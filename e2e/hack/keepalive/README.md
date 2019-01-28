# Keepalive
A small command-line utility that writes one or more characters to stdout in
repeating interval after a child process has not written to stdout for a set
amount of time.

## Getting started
The following example illustrates using `keepalive` with the scirpt 
`periodic_writes.sh`. The script:

1. Writes to stdout
2. Sleeps for `6` seconds
3. Writes to stdout
4. Sleeps for `4` seconds
5. Writes to stdout
6. Sleeps for `11` seconds
7. Writes to stdout

The `keepalive` program will ensure that there is data being written
to standard out during the script's quiet periods:

```shell
./keepalive \
  -quiet-tolerance 5s \
  -sleep-for 1s \
  -- \
  $(pwd)/periodic_writes.sh Do some periodic writes
Do
.
some
periodic
.
.
.
.
.
.
writes
```
