#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

#
# A commons library for the OVA's shell scripts.
#

set -e
set -o pipefail

# echo2 echoes the provided arguments to stderr.
echo2() { echo "${@}" 1>&2; }; export echo2

# printf2 prints the provided format and arguments to stderr.
# shellcheck disable=SC2059
printf2() { _f="${1}"; shift; printf "${_f}" "${@}" 1>&2; }; export printf2

################################################################################
##                                BIN_DIR                                     ##
################################################################################

# Define BIN_DIR and create it if it does not exist.
export BIN_DIR="${BIN_DIR:-/opt/bin}"
mkdir -p "${BIN_DIR}"; chmod 0755 "${BIN_DIR}"

# If not already a member of PATH, add BIN_DIR to PATH.
echo "${PATH}" | grep -qF "${BIN_DIR}" || export PATH="${BIN_DIR}:${PATH}"

require_program() {
  command -v "${1}" 1>/dev/null || \
    { _ec="${?}"; echo2 "failed to find ${1}"; exit "${_ec}"; }
}
export require_program

# Ensure the rpctool program is available.
require_program rpctool

################################################################################
##                                Boolean                                     ##
################################################################################

# Parses the argument and normalizes a truthy value to lower-case "true" or
# a non-truthy value to lower-case "false".
parse_bool() {
  { echo "${1}" | \
    grep -iq '^[[:space:]]\{0,\}\(1\|yes\|true\)[[:space:]]\{0,\}$' && \
    echo true; } || echo false
}
export parse_bool

is_true() { [ "true" = "$(parse_bool "${1}")" ]; }; export is_true
is_false() { ! is_true "${1}"; }; export is_false

################################################################################
##                                Logging                                     ##
################################################################################

# Check for debug mode.
DEBUG="$(rpctool get yakity.DEBUG)" || \
  { xc="${?}"; echo2 "rpctool: get yakity.DEBUG failed"; exit "${xc}"; }
[ -n "${DEBUG}" ] || DEBUG="$(rpctool get.ovf DEBUG)" || \
  { xc="${?}"; echo2 "rpctool: get ovfEnv.DEBUG failed"; exit "${xc}"; }
DEBUG="$(parse_bool "${DEBUG}")"
is_debug() { [ "${DEBUG}" = "true" ]; }
export DEBUG is_debug

# Logging levels
export FATAL_LEVEL=1 \
       ERROR_LEVEL=2 \
        WARN_LEVEL=3 \
        INFO_LEVEL=4 \
       DEBUG_LEVEL=5

# Debug mode enables tracing and sets LOG_LEVEL=DEBUG_LEVEL.
is_debug && { set -x; LOG_LEVEL="${DEBUG_LEVEL}"; }

# LOG_LEVEL may be set to:
#   * 1, FATAL
#   * 2, ERROR
#   * 3, WARN
#   * 4, INFO
#   * 5, DEBUG
if [ -z "${LOG_LEVEL}" ]; then
  LOG_LEVEL="$(rpctool get yakity.LOG_LEVEL)" || \
    { xc="${?}"; echo2 "rpctool: get yakity.LOG_LEVEL failed"; exit "${xc}"; }
  [ -n "${LOG_LEVEL}" ] || LOG_LEVEL="$(rpctool get.ovf LOG_LEVEL)" || \
    { xc="${?}"; echo2 "rpctool: get ovfEnv.LOG_LEVEL failed"; exit "${xc}"; }
  LOG_LEVEL="${LOG_LEVEL:-${INFO_LEVEL}}"
fi

is_log_level() {
  echo "${1}" | \
    grep -iq '^[[:space:]]\{0,\}\('"${2}"'\|'"${3}"'\)[[:space:]]\{0,\}$'
}
export is_log_level

parse_log_level() {
  if is_log_level "${1}" "${FATAL_LEVEL}" fatal; then
    echo "${FATAL_LEVEL}" && return
  elif is_log_level "${1}" "${ERROR_LEVEL}" error; then
    echo "${ERROR_LEVEL}" && return
  elif is_log_level "${1}" "${WARN_LEVEL}" warn || \
       is_log_level "${1}" "${WARN_LEVEL}" warning; then
    echo "${WARN_LEVEL}" && return
  elif is_log_level "${1}" "${INFO_LEVEL}" info; then
    echo "${INFO_LEVEL}" && return
  elif is_log_level "${1}" "${DEBUG_LEVEL}" debug; then
    echo "${DEBUG_LEVEL}" && return
  fi
  return 1
}
export parse_log_level

# Parse the log level that may have been set when this script was executed.
LOG_LEVEL="$(parse_log_level "${LOG_LEVEL}")"
export LOG_LEVEL

# Returns a success if the provided argument is a whole number.
is_whole_num() {
  echo "${1}" | \
    grep -q '^[[:space:]]\{0,\}\([[:digit:]]\{1,\}\)[[:space:]]\{0,\}$'
}
export is_whole_num

# log LEVEL_INT LEVEL_SZ MSG [RETURN_CODE]
log() {
  _lvl_int="${1}"; _lvl_sz="${2}"; _msg="${3}";
  if [ "${LOG_LEVEL}" -ge "${_lvl_int}" ]; then
    printf2 '%s [%s] %s\n' "${_lvl_sz}" "$(date +%s)" "${_msg}"
  fi
  return 0
}
export log

# debug MSG [RETURN_CODE]
#   Prints the supplies message to stderr if LOG_LEVEL >=DEBUG_LEVEL.
debug() { log "${DEBUG_LEVEL}" DEBUG "${@}"; }; export debug

# info MSG [RETURN_CODE]
#   Prints the supplies message to stderr if LOG_LEVEL >=INFO_LEVEL.
info() { log "${INFO_LEVEL}" INFO "${@}"; }; export info

# warn MSG [RETURN_CODE]
#   Prints the supplies message to stderr if LOG_LEVEL >=WARN_LEVEL.
warn() { log "${WARN_LEVEL}" WARN "${@}"; }; export warn

# error MSG [RETURN_CODE]
#   Prints the supplies message to stderr if LOG_LEVEL >=ERROR_LEVEL.
error() {
  _xc="${?}"
  log "${ERROR_LEVEL}" ERROR "${@}"
  return "${_xc}"
}
export error

# fatal MSG [RETURN_CODE]
#   Prints the supplies message to stderr if LOG_LEVEL >=FATAL_LEVEL.
fatal() {
  _xc="${?}"
  log "${FATAL_LEVEL}" FATAL "${@}"
  [ "${_xc}" -eq "0" ] || exit "${_xc}"
}
export fatal

require() {
  while [ -n "${1}" ]; do
    { [ -n "$(eval "echo \${${1}}")" ] && shift; } || fatal "${1} required"
  done
}
export require

################################################################################
##                                 VMware                                     ##
################################################################################

# Gets this VM's UUID.
#
# ex. VMware-42 30 bd 07 d9 68 0c ae-58 61 e9 3c 47 c1 9e d2
get_self_uuid() {
  cut -c8- </sys/class/dmi/id/product_serial | \
  tr -d ' -' | \
  sed 's/^\([[:alnum:]]\{1,8\}\)\([[:alnum:]]\{1,4\}\)\([[:alnum:]]\{1,4\}\)\([[:alnum:]]\{1,4\}\)\([[:alnum:]]\{1,12\}\)$/\1-\2-\3-\4-\5/' || \
  fatal "failed to read VM UUID"
}
export get_self_uuid

# Sets a guestinfo property in the yakity namespace.
rpc_set() {
  rpctool set "yakity.${1}" "${2}" || fatal "rpctool: set yakity.${1} failed"
}
export rpc_set

# Gets a guestinfo property in the yakity namespace or the OVF environment.
rpc_get() {
  _val="$(rpctool get "yakity.${1}")" || fatal "rpctool: get yakity.${1} failed"
  if [ -n "${_val}" ] && [ ! "${_val}" = "null" ]; then
    debug "rpc_get: key=${1} src=guestinfo.yakity"
    echo "${_val}"
    return
  fi
  _val="$(rpctool get.ovf "${1}")" || fatal "rpctool: get.ovf ${1} failed"
  if [ -n "${_val}" ] && [ ! "${_val}" = "null" ]; then
    debug "rpc_get: key=${1} src=guestinfo.ovfEnv"
    echo "${_val}"
  fi
}
export rpc_get

################################################################################
##                                 yakity                                     ##
################################################################################

parse_node_type() {
  if echo "${1}" | grep -iq '^[[:space:]]\{0,\}both[[:space:]]\{0,\}$'; then
    echo both && return
  elif echo "${1}" | grep -iq '^[[:space:]]\{0,\}controller[[:space:]]\{0,\}$'; then
    echo controller && return
  elif echo "${1}" | grep -iq '^[[:space:]]\{0,\}worker[[:space:]]\{0,\}$'; then
    echo worker && return
  fi
  error "invalid node type: ${1}"; return 1
}
export parse_node_type

get_self_node_type() { 
  parse_node_type "$(rpc_get NODE_TYPE)" || \
    fatal "failed to get self node type"
}
export get_self_node_type

is_controller() {
  echo "${1}" | \
    grep -iq '^[[:space:]]\{0,\}\(both\|controller\)[[:space:]]\{0,\}$'
}
export is_controller

get_controller_ipv4_addrs() {
  cluster_name="$(rpc_get CLUSTER_NAME)"
  cluster_name="${cluster_name:-kubernetes}"
  domain_name="$(rpc_get NETWORK_DOMAIN)"
  domain_name="${domain_name:-$(hostname -d)}"
  cluster_fqdn="${cluster_name}.${domain_name}"
  host -t A "${cluster_fqdn}" | awk '{print $4}' | sort -u
}
export get_controller_ipv4_addrs

get_host_name_from_fqdn() {
  echo "${1}" | awk -F. '{print $1}'
}
export get_host_name_from_fqdn

get_domain_name_from_fqdn() {
  echo "${1}" | sed 's~^'"$(get_host_name_from_fqdn "${1}")"'\.\(.\{1,\}\)$~\1~'
}
export get_domain_name_from_fqdn

# Sets the host name and updats all of the files necessary to have the
# hostname command respond with correct information for "hostname -f",
# "hostname -s", and "hostname -d".
#
# Possible return codes include:
#   0 - success
#
#   50 - after setting the host name the command "hostname -f" returns
#        an empty string
#   51 - after setting the host name the command "hostname -f" returns
#        a value that does not match the host FQDN that was set
#
#   52 - after setting the host name the command "hostname -s" returns
#        an empty string
#   53 - after setting the host name the command "hostname -s" returns
#        a value that does not match the host name that was set
#
#   54 - after setting the host name the command "hostname -d" returns
#        an empty string
#   55 - after setting the host name the command "hostname -d" returns
#        a value that does not match the domain name that was set
#
#    ? - any other non-zero exit code indicates failure and comes directly
#        from the "hostname" command. Please see the "hostname" command
#        for a list of its exit codes.
set_host_name() {
  _host_fqdn="${1}"; _host_name="${2}"; _domain_name="${3}"

  # Use the "hostname" command instead of "hostnamectl set-hostname" since
  # the latter relies on the systemd-hostnamed service, which may not be
  # present or active.
  hostname "${_host_fqdn}" || return "${?}"

  # Update the hostname file.
  echo "${_host_fqdn}" >/etc/hostname

  # Update the hosts file so the "hostname" command will respond with
  # the correct values for "hostname -f", "hostname -s", and "hostname -d".
  cat <<EOF >/etc/hosts
::1         ipv6-localhost ipv6-loopback
127.0.0.1   localhost
127.0.0.1   localhost.${_domain_name}
127.0.0.1   ${_host_name}
127.0.0.1   ${_host_fqdn}
EOF

  _act_host_fqdn="$(hostname -f)" || return "${?}"
  [ -n "${_act_host_fqdn}" ] || return 50
  [ "${_host_fqdn}" = "${_act_host_fqdn}" ] || return 51

  _act_host_name="$(hostname -s)" || return "${?}"
  [ -n "${_act_host_name}" ] || return 52
  [ "${_host_name}" = "${_act_host_name}" ] || return 53

  _act_domain_name="$(hostname -d)" || return "${?}"
  [ -n "${_act_domain_name}" ] || return 54
  [ "${_domain_name}" = "${_act_domain_name}" ] || return 55

  # success!
  return 0
}
export set_host_name

get_cluster_access_info() {
  _cluster_id="${1}"
  _vm_uuid="${2}"
  _k8s_version="${3}"
  cat <<EOF
KUBERNETES VERSION
${_k8s_version}

CLUSTER ID
${_cluster_id}

VM ID
${_vm_uuid}

GOVC
The following commands rely on the program "govc", a command line
utility for managing vSphere. Please ensure "govc" is installed and
that it is configured to access the vSphere instance managing this VM.
For more information please see http://bit.ly/govc-readme.

GET KUBECONFIG
curl -sSL http://bit.ly/get-kubeconfig | sh -s -- "${_vm_uuid}"

SSH ACCESS
curl -sSL http://bit.ly/ssh-to-vm | sh -s -- "${_vm_uuid}"

DELETE CLUSTER
If the cluster was created with an AWS load balancer then the AWS CLI
must be installed and configured in order for the following command to
remove any load-balancer-related resources. If the AWS CLI is missing or
unconfigured, the load-balancer-related resources are not removed.

curl -sSL http://bit.ly/delete-cluster | sh -s -- "${_vm_uuid}"
EOF
}

# Get the short version of the cluster ID.
get_cluster_id7() { echo "${1}" | cut -c-7; }; export get_cluster_id7

unmangle_pem() {
  sed -r 's/(-{5}BEGIN [A-Z ]+-{5})/&\n/g; s/(-{5}END [A-Z ]+-{5})/\n&\n/g' | \
    sed -r 's/.{64}/&\n/g; /^\s*$/d' | \
    sed -r '/^$/d'
}
export unmangle_pem
