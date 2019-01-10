#!/bin/sh

# simple-kubernetes-test-environment
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
# A wrapper for vagrant that chooses its data directory from the input flags.
#

export PROGRAM="vagrant"
_0d="$(dirname "${0}")"

# Load the commons library.
# shellcheck disable=SC1090
. "$(dirname "${0}")/common.sh"

box_out() {
  { [ "${box}" = "vmware/photon" ] && tail -n +3 | cat; } || cat
}

get_system_pods() {
  vagrant ssh --no-tty c01 \
    -c "kubectl -n kube-system get pods" 2>/dev/null | box_out
}

get_cluster_status() {
  vagrant ssh --no-tty c01 -c "kubectl get all" | box_out
}

get_component_status() {
  vagrant ssh --no-tty c01 -c "kubectl get cs" | box_out
}

get_nodes() {
  vagrant ssh --no-tty c01 -c "kubectl get nodes" | box_out
}

kube_dns_running() {
  get_system_pods | grep -q 'kube-dns.\{0,\}[[:space:]]Running'
}

wait_until_cluster_is_online() {
  printf '\nwaiting for the cluster to finish coming online...'
  _i=0 && while [ "${_i}" -lt "300" ] && ! kube_dns_running; do
    printf '.'; sleep 1; _i=$((_i+1))
  done
  [ "${_i}" -lt "300" ] || fatal "timed out"
  echo; echo
}

tail_log() {
  vagrant ssh --no-tty c01 -c 'sudo /var/lib/sk8/tail-log.sh' | box_out || \
    fatal "failed to follow cluster deployment progress"
}

vagrant_up_slowly() {
  { vagrant up --provision-with init-guest && \
    vagrant provision --provision-with file,init-sk8 && \
    vagrant provision --provision-with start-sk8; } || \
    fatal "vagrant up failed"
}

print_congrats() {
  echo 'CLUSTER ONLINE'
  echo '=============='
  get_cluster_status && echo
  echo 'COMPONENT STATUS'
  echo '================'
  get_component_status && echo
  echo 'NODES'
  echo '====='
  get_nodes && echo
  echo 'SYSTEM PODS'
  echo '==========='
  get_system_pods && echo
  cat <<EOF
EXAMPLES
========
  get status       ${_0d}/kubectl.sh -- get cs
  get nodes        ${_0d}/kubectl.sh -- get nodes
  get system pods  ${_0d}/kubectl.sh -- get -n kube-system pods
  shell access     ${_0d}/vagrant.sh -- ssh NODE_NAME
  destroy cluster  ${_0d}/vagrant.sh -- destroy -f
EOF
}

case "${1}" in
up)
  print_context

  # Bring up the boxes in a specific manner.
  vagrant_up_slowly

  # Tail the log on the first box until it's no longer being written.
  tail_log

  # Wait until the cluster is finished coming online.
  wait_until_cluster_is_online

  # Inform the user that the cluster is now online.
  print_congrats
  ;;
vup)
  print_context
  exec vagrant up "${@}"
  ;;
down)
  print_context
  exec vagrant destroy -f
  ;;
*)
  exec vagrant "${@}"
  ;;
esac
