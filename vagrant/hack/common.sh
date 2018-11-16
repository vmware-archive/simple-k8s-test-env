#!/bin/sh

# Yakity
#
# Copyright (c) 2018 VMware, Inc. All Rights Reserved.
#
# This product is licensed to you under the Apache 2.0 license (the "License").
# You may not use this product except in compliance with the Apache 2.0 License.
#
# This product may include a number of subcomponents with separate copyright
# notices and license terms. Your use of these subcomponents is subject to the
# terms and conditions of the subcomponent's license, as noted in the LICENSE
# file.

# posix compliant
# verified by https://www.shellcheck.net

#
# A commons library for the Vagrant shell scripts.
#

set -e
set -o pipefail

usage() {
  cat <<EOF
usage: ${0} FLAGS ${PROGRAM}
  This program wraps ${PROGRAM} with some flags specific to yakity. After
  the yakity flags and their arguments are provided, ${PROGRAM} is exec'd
  with the remainder of the command line.

FLAGS
  -k      K8S   The version of Kubernetes to install. Please see the section
                KUBERNETES VERSION for accepted versions.
                The default value is "release/stable".

  -b      BOX   Valid box types include: "photon", "centos", and "ubuntu".
                The default value is "ubuntu".

  -c      CPU   The number of CPUs to assign to each box.
                The default value is "1".

  -m      MEM   The amount of memory (MiB) to assign to each box.
                The default value is "1024".

  -p PROVIDER   Valid providers are: "virtualbox" and "vmware".
                The default value is "virtualbox".

  -v            Enables the vSphere cloud provider and directs it to
                use the vCenter simulator.

  -1            Provision a single-node cluster
                  c01  Controller+Worker

  -2            Provision a two-node cluster
                  c01  Controller
                  w01  Worker

  -3            Provision a three-node cluster
                  c01  Controller
                  c02  Controller+Worker
                  w01  Worker

KUBERNETES VERSION
  The -k flag specifies the version of Kubernetes to install.

  If the value "local" is used, the following local paths are checked
  and replaces "local" as the Kuberentes version if they exist:

    * ${GOPATH}/src/k8s.io/kubernetes
    * ${HOME}/go/src/k8s.io/kubernetes
  
  If the Kubernetes version is set to a filesystem path then this program
  mounts the path into the VM(s) as "/var/lib/kubernetes/install/local" and
  set the Kubernetes version to "file:///var/lib/kubernetes/install/local".
  
  The yakity process executing inside of the VM(s) checks to see if the
  configured Kubernetes version begins with "file://". If it does, yakity
  processes the contents of the directory using the ascribed manner:

    1.  An attempt is made to locate the following release tarballs:

          * kubernetes-client-linux-amd64.tar.gz
          * kubernetes-node-linux-amd64.tar.gz
          * kubernetes-server-linux-amd64.tar.gz
          * kubernetes-test-linux-amd64.tar.gz

    2.  An attempt is made to locate the following binaries:

          * kubectl
          * kube-apiserver
          * kube-controller-manager
          * kube-scheduler
          * kubelet
          * kube-proxy
          * e2e.test

  If multiple copies of the same file are discovered the newest copy is used.
  Files from step two will overwrite their equivalents inside of any tarballs
  discovered in step one as long as the copy from step two is newer.

  Plesae note that only the CentOS and Ubuntu box types support deploying 
  a local Kubernetes build. This is because there is no PhotonOS box in the
  Vagrant registry that includes support for mounting shared folders. If
  someone would like to provide such a box, then PhotonOS could also support
  deploying Kubernetes using local development builds.

  To read more about the valid versions that may be deployed, please see
  https://github.com/akutz/yakity/wiki/Kubernetes-version.

NUMBER OF NODES
  The -1, -2, and -3 flags are used to set the number of nodes in the cluster.
  The flags are mutually exclusive, and only the first of them that appears on
  the command line will be respected.
EOF
}
export usage

[ "${#}" -gt "0" ] || { usage && exit 1; }

fatal() { echo "${@}" 1>&2 && exit 1; }; export fatal

# Change directories to the directory that's a parent of this script.
cd "$(dirname "$(dirname "${0}")")" || fatal "unable to change directories"

while getopts ":k:b:c:m:p:vh123" opt; do
  case "${opt}" in
  k)
    flags=true
    k8s="${OPTARG}"
    ;;
  b)
    flags=true
    box="${OPTARG}"
    ;;
  c)
    flags=true
    cpu="${OPTARG}"
    ;;
  m)
    flags=true
    mem="${OPTARG}"
    ;;
  p)
    flags=true
    provider="${OPTARG}"
    ;;
  v)
    export VCSIM=1
    ;;
  1|2|3)
    flags=true
    [ ! -z "${nodes}" ] || nodes="${opt}"
    ;;
  h)
    usage
    exit 1
    ;;
  :)
    fatal "Option -${OPTARG} requires an argument"
    ;;
  \?)
    # Ignore invalid flags
    ;;
  esac
done

shift $((OPTIND-1))

lcase() { tr '[:upper:]' '[:lower:]'; }
igrep() { a="${1}"; shift; echo "${a}" | grep -i "${@}"; }
is_int() { echo "${1}" | tr -d ',' | grep '^[[:digit:]]\{1,\}$'; }

validate_box() { 
  igrep "${1}" '^\(centos\|photon\|ubuntu\)$' | lcase || \
  fatal "invalid box: ${1}"
}

validate_provider() {
  igrep "${1}" '^\(fusion\|\(vmware\(_\(desktop\|fusion\)\)\{0,1\}\)\|virtualbox\)$' | lcase || \
  fatal "invalid provider: ${1}"
}

vagrant_home="${HOME}/.yakity/vagrant"
instance="${vagrant_home}/instance"
config="${instance}/config.yaml"

if [ "${flags}" = "true" ] || [ ! -e "${config}" ]; then
  k8s="${k8s:-release/stable}"
  if [ "${k8s}" = "local" ]; then
    if [ -n "${GOPATH}" ]; then
      k8s="${GOPATH}/src/k8s.io/kubernetes"
    else
      k8s="${HOME}/go/src/k8s.io/kubernetes"
    fi
    if [ -d "${k8s}" ]; then
      k8s=local
    fi
  fi

  box="$(validate_box "${box:-ubuntu}")"
  case "${box}" in
  centos)
    #box='centos/7'
    box='bento/centos-7.5'
    ;;
  photon)
    box='vmware/photon'
    ;;
  ubuntu)
    #box='ubuntu/xenial64'   # the stock ubuntu box does not support VMware
    box='bento/ubuntu-16.04' # this ubuntu box supports VMware
    ;;
  esac

  provider="$(validate_provider "${provider:-virtualbox}")"
  case "${provider}" in
  fusion|vmware|vmware_desktop|vmware_fusion)
    provider="vmware_fusion"
    ;;
  esac

  cpu="$(is_int "${cpu:-1}")" || fatal "invalid cpu value: ${cpu}"
  mem="$(is_int "${mem:-1024}")" || fatal "invalid mem value: ${mem}"

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
provider:    ${provider}
k8s:         ${k8s}
cpu:         ${cpu}
mem:         ${mem}
nodes:       ${num_nodes}
controllers: ${num_controllers}
both:        ${num_both}
EOF
fi

# If the -i flag was specified then remove the existing instance.
sha7() {
  { shasum -t -a1 2>/dev/null || sha1sum -t; } | awk '{print $1}' | cut -c-7
}

# Configure a custom location for the Vagrant's data directory, .vagrant.
VAGRANT_DOTFILE_PATH="${vagrant_home}/$(sha7 <"${config}")"
export VAGRANT_DOTFILE_PATH && mkdir -p "${VAGRANT_DOTFILE_PATH}"

# Make sure Vagrant sees the path to the config file.
export CONFIG="${VAGRANT_DOTFILE_PATH}/config.yaml"

# If the config file does not already exist, move the file into its
# permanent location.
mv -f "${config}" "${CONFIG}" 2>/dev/null || true

# Create the symlink to the instance.
rm -f "${instance}"; ln -s "${VAGRANT_DOTFILE_PATH}" "${instance}"

# Determine the preferred provider.
provider="$(grep '^provider:' "${CONFIG}" | awk '{print $2}')"

export VAGRANT_DEFAULT_PROVIDER="${provider}"
export KUBECONFIG="${VAGRANT_DOTFILE_PATH}/kubeconfig"
export DNSCONFIG="${VAGRANT_DOTFILE_PATH}/dnsconfig"

print_context() {
  echo "data: ${VAGRANT_DOTFILE_PATH}"
  cat "${CONFIG}"
}
export print_context
