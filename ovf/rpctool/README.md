# rpctool
The program `rpctool` allows users on VMs running on vSphere to manipulate the 
VM's GuestInfo and OVF environment data.

```shell
root@photon-machine [ ~ ]# /var/lib/yakity/rpctool
COMMAND is required
usage: /var/lib/yakity/rpctool [FLAGS] COMMAND [ARGS]
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
  -ovf.format string
    	The format of the OVF environment payload when returned by "get.ovf" or set via "set.ovf". The format string may be  set to "xml" or "json". (default "json")
```

## Get a GuestInfo property
```shell
root@photon-machine [ ~ ]# /var/lib/yakity/rpctool get yakity.k8s.version
release/v1.11.2
```

## Set a GuestInfo property
```shell
root@photon-machine [ ~ ]# /var/lib/yakity/rpctool set yakity.url https://raw.githubusercontent.com/akutz/yakity/master/yakity.sh

root@photon-machine [ ~ ]# /var/lib/yakity/rpctool get yakity.url
https://raw.githubusercontent.com/akutz/yakity/master/yakity.sh
```

## Set a GuestInfo property to the contents of `STDIN`
```shell
root@photon-machine [ ~ ]# /var/lib/yakity/rpctool set yakity.service - </var/lib/yakity/yakity.service

root@photon-machine [ ~ ]# /var/lib/yakity/rpctool get yakity.service
[Unit]
Description=Runs yakity.
After=network.target syslog.target cloud-final.service rc-local.service
Wants=cloud-final.service
ConditionPathExists=!/var/lib/yakity/.yakity.sh.done

[Install]
WantedBy=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
TimeoutSec=0
ExecStartPre=/var/lib/yakity/yakity-update.sh
ExecStartPre=/var/lib/yakity/yakity-guestinfo.sh
ExecStart=/var/lib/yakity/yakity.sh
ExecStartPost=/bin/touch /var/lib/yakity/.yakity.sh.done
```

## Print the OVF environment as JSON
```
root@photon-machine [ ~ ]# /var/lib/yakity/rpctool get.ovf
{
  "XMLName": {
    "Space": "",
    "Local": ""
  },
  "ID": "",
  "EsxID": "",
  "Platform": {
    "Kind": "VMware ESXi",
    "Version": "6.8.1",
    "Vendor": "VMware, Inc.",
    "Locale": "en"
  },
  "Property": {
    "Properties": [
      {
        "Key": "ETCD_DISCOVERY_URL",
        "Value": ""
      },
      {
        "Key": "K8S_VERSION",
        "Value": ""
      },
      {
        "Key": "NUM_CONTROLLERS",
        "Value": "0"
      },
      {
        "Key": "NUM_NODES",
        "Value": "0"
      },
      {
        "Key": "VSPHERE_NETWORK",
        "Value": "sddc-cgw-network-3"
      },
      {
        "Key": "VSPHERE_SERVER",
        "Value": "10.2.224.4"
      },
      {
        "Key": "YAKITY_GUESTINFO_URL",
        "Value": ""
      },
      {
        "Key": "YAKITY_URL",
        "Value": ""
      }
    ]
  }
}
```

## Print the OVF environment as XML
```shell
root@photon-machine [ ~ ]# /var/lib/yakity/rpctool -ovf.format xml get.ovf
<Environment xmlns="http://schemas.dmtf.org/ovf/environment/1" id="" xmlns:ovfenv="http://www.vmware.com/schema/ovfenv" ovfenv:esxId="">
  <PlatformSection>
    <Kind>VMware ESXi</Kind>
    <Version>6.8.1</Version>
    <Vendor>VMware, Inc.</Vendor>
    <Locale>en</Locale>
  </PlatformSection>
  <PropertySection>
    <Property key="ETCD_DISCOVERY_URL" value=""></Property>
    <Property key="K8S_VERSION" value=""></Property>
    <Property key="NUM_CONTROLLERS" value="0"></Property>
    <Property key="NUM_NODES" value="0"></Property>
    <Property key="VSPHERE_NETWORK" value="sddc-cgw-network-3"></Property>
    <Property key="VSPHERE_SERVER" value="10.2.224.4"></Property>
    <Property key="YAKITY_GUESTINFO_URL" value=""></Property>
    <Property key="YAKITY_URL" value=""></Property>
  </PropertySection>
</Environment>
```
