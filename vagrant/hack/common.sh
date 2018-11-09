#!/bin/sh

usage() {
  cat <<EOF
usage: ${0} FLAGS ${PROGRAM}
  This program wraps ${PROGRAM} with some flags specific to yakity. After
  the yakity flags and their arguments are provided, ${PROGRAM} is exec'd
  with the remainder of the command line.

FLAGS
  -b    BOX   Valid box types include: "photon", "centos", and "ubuntu".
              The default value is "photon".

  -c    CPU   The number of CPUs to assign to each box.
              The default value is "1".

  -m    MEM   The amount of memory (MiB) to assign to each box.
              The default value is "1024".

  -1          Provision a single-node cluster
                c01  Controller+Worker

  -2          Provision a two-node cluster
                c01  Controller
                w01  Worker

  -3          Provision a three-node cluster
                c01  Controller
                c02  Controller+Worker
                w01  Worker

NUMBER OF NODES
  The -1, -2, and -3 flags are used to set the number of nodes in the cluster.
  The flags are mutually exclusive, and only the first of them that appears on
  the command line will be respected.
EOF
}
export usage

[ "${#}" -gt "0" ] || { usage && exit 1; }

while getopts ":b:c:m:h123" opt; do
  case "${opt}" in
  b)
    box="${OPTARG}"
    ;;
  c)
    cpu="${OPTARG}"
    ;;
  m)
    mem="${OPTARG}"
    ;;
  1|2|3)
    [ ! -z "${nodes}" ] || nodes="${opt}"
    ;;
  h)
    usage
    exit 1
    ;;
  \?)
    echo "Invalid option: -${OPTARG}" >&2
    exit 1
    ;;
  :)
    echo "Option -${OPTARG} requires an argument" >&2
    exit 1
    ;;
  esac
done

shift $((OPTIND-1))

box="${box:-ubuntu}"
if echo "${box}" | grep -iq '^\(centos\|photon\|ubuntu\)$'; then
  box="$(echo "${box}" | tr '[:upper:]' '[:lower:]')"
else
  echo "invalid box type: ${box}" >&2
  exit 1
fi
case "${box}" in
  centos)
    box='centos/7'
    ;;
  photon)
    box='vmware/photon'
    ;;
  ubuntu)
    box='ubuntu/xenial64'
    ;;
esac

is_whole_num() { echo "${1}" | grep -q '^[[:digit:]]\{1,\}$'; }
is_whole_num "${cpu}" || cpu=1
is_whole_num "${mem}" || mem=1024

case "${nodes}" in
1)
  num_nodes=1; num_controllers=1; num_both=1
  ;;
2)
  num_nodes=2; num_controllers=1; num_both=0
  ;;
3)
  num_nodes=3; num_controllers=2; num_both=1
  ;;
*)
  num_nodes="${NUM_NODES:-1}"
  num_controllers="${NUM_CONTROLLERS:-1}"
  num_both="${NUM_BOTH:-1}"
esac

config="$(mktemp)"
cat <<EOF >"${config}"
---
box:         ${box}
cpu:         ${cpu}
mem:         ${mem}
nodes:       ${num_nodes}
controllers: ${num_controllers}
both:        ${num_both}
EOF

config_sha=$({ shasum -t -a1 2>/dev/null || \
  sha1sum -t; } <"${config}" | awk '{print $1}' | cut -c-7)
VAGRANT_DOTFILE_PATH="$(pwd)/.vagrant/${config_sha}"
export VAGRANT_DOTFILE_PATH
mkdir -p "${VAGRANT_DOTFILE_PATH}"

export CONFIG="${VAGRANT_DOTFILE_PATH}/config.yaml"
{ [ -f "${CONFIG}" ] && rm -f "${config}"; } || mv "${config}" "${CONFIG}"

export KUBECONFIG="${VAGRANT_DOTFILE_PATH}/kubeconfig"

print_context() {
  echo "data:       ${VAGRANT_DOTFILE_PATH}"
  echo "kubeconfig: ${KUBECONFIG}"
  cat "${CONFIG}"
}
export print_context
