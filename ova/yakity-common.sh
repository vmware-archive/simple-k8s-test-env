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
  _xc="${?}"
  _lvl_int="${1}"; _lvl_sz="${2}"; _msg="${3}"; _rc="${4}"
  is_whole_num "${_rc}" || _rc="${_xc}"
  if [ "${LOG_LEVEL}" -ge "${_lvl_int}" ]; then
    printf2 '%s [%s] %s\n' "${_lvl_sz}" "$(date +%s)" "${_msg}"
  fi
  return "${_rc}"
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
error() { log "${ERROR_LEVEL}" ERROR "${@}"; }; export error

# fatal MSG [RETURN_CODE]
#   Prints the supplies message to stderr if LOG_LEVEL >=FATAL_LEVEL.
fatal() {
  log "${FATAL_LEVEL}" FATAL "${@}"; _xc="${?}"
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
