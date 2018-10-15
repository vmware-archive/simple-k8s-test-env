// Copyright 2016-2018 VMware, Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"encoding/json"
	"encoding/xml"
	"flag"
	"fmt"
	"io"
	"io/ioutil"
	"os"
	"strings"

	"github.com/vmware/vmw-guestinfo/rpcvmx"
	"github.com/vmware/vmw-guestinfo/vmcheck"

	"github.com/vmware/govmomi/ovf"
)

func main() {
	// Check if we're running inside a VM
	isVM, err := vmcheck.IsVirtualWorld()
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to discover virtual world: %v\n", err)
		os.Exit(1)
	}
	if !isVM {
		fmt.Fprintln(os.Stderr, "must be run inside a virtual machine")
		os.Exit(1)
	}

	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, `usage: %s [FLAGS] COMMAND [ARGS]
COMMANDS
  get KEY
    	Gets the value for the specified guestinfo key

  set KEY VAL
    	Sets the value for the specified guestinfo key. If VAL is "-" then
    	the program's standard input stream is used as the value.

  get.ovf [KEY]
    	Gets the OVF environment. If a KEY is specified then the value of the
    	OVF envionment property with the matching key will be returned.

  set.ovf [KEY] [VAL]
    	Sets the OVF environment. If VAL is "-" then the program's standard 
    	input stream is used as the value.

    	If a single argument is provided then KEY is treated as VAL and
    	the program treats the argument as the entire OVF environment payload.
    	When two arguments are provided then the OVF environment property
    	with the matching key is updated with the provided value.

FLAGS
`, os.Args[0])
		flag.PrintDefaults()
	}
	flag.String(
		"ovf.format",
		"json",
		"The format of the OVF environment payload when returned by "+
			"\"get.ovf\" or set via \"set.ovf\". The format string may be "+
			" set to \"xml\" or \"json\".")
	flag.Parse()

	if flag.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "COMMAND is required")
		flag.Usage()
		os.Exit(1)
	}

	// Validate the command name.
	cmdName := flag.Arg(0)
	if strings.EqualFold(cmdName, "get") {
		cmdName = "get"
	} else if strings.EqualFold(cmdName, "set") {
		cmdName = "set"
	} else if strings.EqualFold(cmdName, "get.ovf") {
		cmdName = "get.ovf"
	} else if strings.EqualFold(cmdName, "set.ovf") {
		cmdName = "set.ovf"
	} else {
		fmt.Fprintf(os.Stderr, "invalid command: %s\n", cmdName)
		flag.Usage()
		os.Exit(1)
	}

	// Validate the OVF format.
	ovfFormat := flag.Lookup("ovf.format").Value.String()
	if strings.EqualFold(ovfFormat, "json") {
		ovfFormat = "json"
	} else if strings.EqualFold(ovfFormat, "xml") {
		ovfFormat = "xml"
	} else {
		fmt.Fprintf(os.Stderr, "invalid ovf.format: %s\n", ovfFormat)
		flag.Usage()
		os.Exit(1)
	}

	// Get the VMX config.
	config := rpcvmx.NewConfig()

	// Figure out which operation to perform.
	switch cmdName {
	case "get":
		if flag.NArg() < 2 {
			fmt.Fprintf(
				os.Stderr,
				"invalid number of arguments for %s\n",
				cmdName)
			flag.Usage()
			os.Exit(1)
		}
		key := "guestinfo." + flag.Arg(1)
		val, err := config.String(key, "")
		if err != nil {
			fmt.Fprintf(os.Stderr, "failed to get %s: %v\n", key, err)
			os.Exit(1)
		}
		if val != "" {
			fmt.Println(val)
		}
	case "set":
		if flag.NArg() < 3 {
			fmt.Fprintf(
				os.Stderr,
				"invalid number of arguments for %s\n",
				cmdName)
			flag.Usage()
			os.Exit(1)
		}
		key := "guestinfo." + flag.Arg(1)
		val := flag.Arg(2)
		if val == "-" {
			stdin, err := readStdin()
			if err != nil {
				fmt.Fprintln(os.Stderr, err)
				os.Exit(1)
			}
			val = stdin
		}
		if err := config.SetString(key, val); err != nil {
			fmt.Fprintf(os.Stderr, "failed to set %s: %v\n", key, err)
			os.Exit(1)
		}
	case "get.ovf":
		switch flag.NArg() {
		case 1:
			// Print the entire OVF environment payload.
			ovfEnv, err := getOvfEnv(config)
			if err != nil {
				fmt.Fprintln(os.Stderr, err)
				os.Exit(1)
			}
			var enc encoder
			switch ovfFormat {
			case "json":
				jsonEnc := json.NewEncoder(os.Stdout)
				jsonEnc.SetIndent("", "  ")
				enc = jsonEnc
			case "xml":
				xmlEnc := xml.NewEncoder(os.Stdout)
				xmlEnc.Indent("", "  ")
				enc = xmlEnc
			default:
				fmt.Fprintf(os.Stderr, "invalid ovf.format: %s\n", ovfFormat)
				os.Exit(1)
			}
			if err := enc.Encode(ovfEnv); err != nil {
				fmt.Fprintf(
					os.Stderr,
					"failed to encode OVF environment: %v\n",
					err)
				os.Exit(1)
			}
		case 2:
			// Print the OVF property that matches the provided KEY
			key := flag.Arg(1)
			val, err := getValueInOvfEnv(key, config)
			if err != nil {
				fmt.Fprintf(os.Stderr, "failed to get %s: %v\n", key, err)
				os.Exit(1)
			}
			if val != "" {
				fmt.Println(val)
			}
		default:
			fmt.Fprintf(
				os.Stderr,
				"invalid number of arguments for %s\n",
				cmdName)
			flag.Usage()
			os.Exit(1)
		}
	case "set.ovf":
		switch flag.NArg() {
		case 2:
			// Set the entire OVF environment payload.
			val := flag.Arg(1)
			var rdr io.Reader
			if val == "-" {
				rdr = os.Stdin
			} else {
				rdr = strings.NewReader(val)
			}
			var dec decoder
			switch ovfFormat {
			case "json":
				dec = json.NewDecoder(rdr)
			case "xml":
				dec = xml.NewDecoder(rdr)
			default:
				fmt.Fprintf(os.Stderr, "invalid ovf.format: %s\n", ovfFormat)
				os.Exit(1)
			}

			var ovfEnv ovf.Env
			if err := dec.Decode(&ovfEnv); err != nil {
				fmt.Fprintf(
					os.Stderr,
					"failed to decode OVF environment as %s: %v",
					ovfFormat, err)
				os.Exit(1)
			}

			key := "guestinfo.ovfEnv"
			val = ovfEnv.MarshalManual()
			if err := config.SetString(key, val); err != nil {
				fmt.Fprintf(os.Stderr, "failed to set %s: %v\n", key, err)
				os.Exit(1)
			}
		case 3:
			// Sets a property in the OVF environment
			key := flag.Arg(1)
			val := flag.Arg(2)
			if val == "-" {
				stdin, err := readStdin()
				if err != nil {
					fmt.Fprintln(os.Stderr, err)
					os.Exit(1)
				}
				val = stdin
			}
			if err := setValueInOvfEnv(key, val, config); err != nil {
				fmt.Fprintf(os.Stderr, "failed to set %s: %v\n", key, err)
				os.Exit(1)
			}
		default:
			fmt.Fprintf(
				os.Stderr,
				"invalid number of arguments for %s\n",
				cmdName)
			flag.Usage()
			os.Exit(1)
		}
	}
}

type encoder interface {
	Encode(v interface{}) error
}

type decoder interface {
	Decode(v interface{}) error
}

func readStdin() (string, error) {
	buf, err := ioutil.ReadAll(os.Stdin)
	if err != nil {
		return "", fmt.Errorf("error reading stdin: %v", err)
	}
	return string(buf), nil
}

func getOvfEnv(config *rpcvmx.Config) (*ovf.Env, error) {
	ovfEnvSz, err := config.String("guestinfo.ovfEnv", "")
	if err != nil {
		return nil, fmt.Errorf("failed to get guestinfo.ovfEnv: %v", err)
	}

	var ovfEnv ovf.Env
	if err := xml.Unmarshal([]byte(ovfEnvSz), &ovfEnv); err != nil {
		return nil, fmt.Errorf("failed to unmarshall guestinfo.ovfEnv: %v", err)
	}

	return &ovfEnv, nil
}

func getValueInOvfEnv(key string, config *rpcvmx.Config) (string, error) {

	ovfEnv, err := getOvfEnv(config)
	if err != nil {
		return "", err
	}

	if ovfEnv.Property == nil {
		return "", nil
	}

	for _, prop := range ovfEnv.Property.Properties {
		if strings.EqualFold(prop.Key, key) {
			return prop.Value, nil
		}
	}

	return "", nil
}

func setValueInOvfEnv(key, val string, config *rpcvmx.Config) error {

	ovfEnv, err := getOvfEnv(config)
	if err != nil {
		return err
	}

	if ovfEnv.Property == nil {
		return nil
	}

	var props []ovf.EnvProperty

	// Find the property with the matching key name and update its value.
	keyFound := false
	for _, p := range ovfEnv.Property.Properties {
		if strings.EqualFold(p.Key, key) {
			props = append(props, ovf.EnvProperty{
				Key:   p.Key,
				Value: val,
			})
			keyFound = true
		} else {
			props = append(props, p)
		}
	}

	// If the key was not found then add a new property with it and the value.
	if !keyFound {
		props = append(props, ovf.EnvProperty{
			Key:   key,
			Value: val,
		})
	}

	ovfEnv.Property.Properties = props

	// Go ahead and update the OVF environment in the guestinfo
	// since all of the other properties in the OVF environment will
	// remain the same.
	return config.SetString("guestinfo.ovfEnv", ovfEnv.MarshalManual())
}
