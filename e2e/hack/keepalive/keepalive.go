package main

import (
	"flag"
	"os"
	"os/exec"
	"sync"
	"syscall"
	"time"
)

// keepalive is a small command line utility that can be used to start
// a process and pipe its IO to this process. If there is no IO coming
// from the spawned process, and the process isn't dead and hasn't
// written anything to stdout for five minutes, this process
// will write a single "." character to stdout for every 20 seconds the
// spawned process remains quiet. When the spawned process begins writing
// again, the countdown to keepalive is reset.
func main() {
	flag.DurationVar(
		&quietTolerance,
		"quiet-tolerance",
		5*time.Minute,
		"The duration the program waits before writing keep-alive characters to stdout")
	flag.DurationVar(
		&sleepFor,
		"sleep-for",
		20*time.Second,
		"The duration the program sleeps in between writing keep-alive characters")
	flag.StringVar(
		&keepAliveString,
		"keep-alive-chars",
		".\n",
		"The characters that are written to stdout to keep the program alive")

	flag.Parse()

	keepAliveChars = []byte(keepAliveString)
	quietToleranceSecs = quietTolerance.Seconds()

	if flag.NArg() == 0 {
		flag.Usage()
		os.Exit(1)
	}

	cmd := &exec.Cmd{
		Path:   flag.Arg(0),
		Args:   flag.Args()[0:],
		Stdout: &ioKeepAlive{},
		Stderr: os.Stderr,
	}

	go func() {
		for {
			lastWriteMu.RLock()
			secsSinceLastWrite := time.Since(lastWrite).Seconds()
			lastWriteMu.RUnlock()
			if secsSinceLastWrite >= quietToleranceSecs {
				os.Stdout.Write(keepAliveChars)
			}
			time.Sleep(sleepFor)
		}
	}()

	if err := cmd.Run(); err != nil {
		if exitError, ok := err.(*exec.ExitError); ok {
			ws := exitError.Sys().(syscall.WaitStatus)
			os.Exit(ws.ExitStatus())
		}
		os.Exit(1)
	}
}

var (
	quietTolerance  time.Duration
	keepAliveString string
	sleepFor        time.Duration

	quietToleranceSecs float64
	keepAliveChars     []byte

	lastWrite   = time.Now()
	lastWriteMu sync.RWMutex
)

type ioKeepAlive struct {
}

func (k *ioKeepAlive) Write(b []byte) (int, error) {
	lastWriteMu.Lock()
	lastWrite = time.Now()
	lastWriteMu.Unlock()
	return os.Stdout.Write(b)
}
