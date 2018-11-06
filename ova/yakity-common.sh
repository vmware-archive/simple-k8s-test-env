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
#
# $1 - The value to parse
# $2 - A default value if $1 is undefined
parse_bool() {
  val="${1:-${2}}"
  { echo "${val}" | \
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
  _rc="${?}"
  _lvl_int="${1}"; _lvl_sz="${2}"; _msg="${3}"
  ! is_whole_num "${4}" || _rc="${4}"
  if [ "${LOG_LEVEL}" -ge "${_lvl_int}" ]; then
    printf2 '%s [%s] %s\n' "${_lvl_sz}" "$(date +%s)" "${_msg}"
  fi
  return "${_rc}"
}
export log

# debug MSG [RETURN_CODE]
#   Prints the supplies message to stderr if LOG_LEVEL >=DEBUG_LEVEL.
debug() { log "${DEBUG_LEVEL}" DEBUG "${1}" 0; }; export debug

# info MSG [RETURN_CODE]
#   Prints the supplies message to stderr if LOG_LEVEL >=INFO_LEVEL.
info() { log "${INFO_LEVEL}" INFO "${1}" 0; }; export info

# warn MSG [RETURN_CODE]
#   Prints the supplies message to stderr if LOG_LEVEL >=WARN_LEVEL.
warn() { log "${WARN_LEVEL}" WARN "${1}" 0; }; export warn

# error MSG [RETURN_CODE]
#   Prints the supplies message to stderr if LOG_LEVEL >=ERROR_LEVEL.
error() { log "${ERROR_LEVEL}" ERROR "${1}" 0; }; export error

# fatal MSG [RETURN_CODE]
#   Prints the supplies message to stderr if LOG_LEVEL >=FATAL_LEVEL.
fatal() { log "${FATAL_LEVEL}" FATAL "${@}" || exit "${?}"; }; export fatal

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

# Get the short version of the cluster ID.
get_cluster_id7() { echo "${1}" | cut -c-7; }; export get_cluster_id7

get_cluster_access_info() {
  _cluster_id="${1}"
  _vm_uuid="${2}"
  _k8s_version="${3}"
  _cluster_id7="$(get_cluster_id7 "${_cluster_id}")"

  cat <<EOF
KUBERNETES VERSION
${_k8s_version}

CLUSTER ID
${_cluster_id7}

REMOTE ACCESS
curl -sSL http://bit.ly/yakcess | sh -s -- ${_vm_uuid}
EOF
}

unmangle_pem() {
  sed -r 's/(-{5}BEGIN [A-Z ]+-{5})/&\n/g; s/(-{5}END [A-Z ]+-{5})/\n&\n/g' | \
    sed -r 's/.{64}/&\n/g; /^\s*$/d' | \
    sed -r '/^$/d'
}
export unmangle_pem

# Returns the last argument as an array using a POSIX-compliant method
# for handling arrays.
only_last_arg() {
  _l="${#}" _i=0 _j="$((_l-1))" && while [ "${_i}" -lt "${_l}" ]; do
    if [ "${_i}" -eq "${_j}" ]; then
      printf '%s\n' "${1}" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/' \\\\/"
    fi
    shift; _i="$((_i+1))"
  done
  echo " "
}
export only_last_arg

# Returns all but the last argument as an array using a POSIX-compliant method
# for handling arrays.
trim_last_arg() {
  _l="${#}" _i=0 _j="$((_l-1))" && while [ "${_i}" -lt "${_l}" ]; do
    if [ "${_i}" -lt "${_j}" ]; then
      printf '%s\n' "${1}" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/' \\\\/"
    fi
    shift; _i="$((_i+1))"
  done
  echo " "
}
export trim_last_arg

# "${node_type}:${uuid}:${host_name}"
parse_member_info()      { echo "${2}" | awk -F: '{print $'"${1}"'}'; }
parse_member_node_type() { parse_member_info 1 "${1}"; }
parse_member_id()        { parse_member_info 2 "${1}"; }
parse_member_host_name() { parse_member_info 3 "${1}"; }
export parse_member_info \
       parse_member_node_type \
       parse_member_id \
       parse_member_host_name

is_file_empty() {
  [ ! -e "${1}" ] || \
    wc -l >/dev/null 2>&1 <"${1}" || \
    grep -q '[[:space:]]\{0,\}' "${1}"
}
export is_file_empty
