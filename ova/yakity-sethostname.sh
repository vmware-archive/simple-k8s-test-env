#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

#
# Used by the yakity service to update the host's name.
#

set -e
set -o pipefail

# Update the path so that "rpctool" is in it.
PATH=/var/lib/yakity:"${PATH}"

# echo2 echoes the provided arguments to file descriptor 2, stderr.
echo2() { echo "${@}" 1>&2; }

# fatal echoes a string to stderr and then exits the program.
fatal() { exit_code="${2:-${?}}"; echo2 "${1}"; exit "${exit_code}"; }

if ! command -v rpctool >/dev/null 2>&1; then
  fatal "failed to find rpctool command"
fi

get_config_val() {
  if val="$(rpctool get "yakity.${1}" 2>/dev/null)" && [ -n "${val}" ]; then
    echo "${val}"
  elif val="$(rpctool get.ovf "${1}" 2>/dev/null)" && [ -n "${val}" ]; then
    echo "${val}"
  fi
}

get_host_name_from_fqdn() {
  echo "${1}" | awk -F. '{print $1}'
}

get_domain_name_from_fqdn() {
  echo "${1}" | sed 's~^'"$(get_host_name_from_fqdn "${1}")"'\.\(.\{1,\}\)$~\1~'
}

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

if ! host_fqdn="$(get_config_val HOST_FQDN)"; then
  fatal "failed to get host name from OVF environment"
fi

# Exit with an error if the host's FQDN is empty.
[ -n "${host_fqdn}" ] || fatal "host name in OVF environment is required" 2

# If the provided FQDN does not include a domain name then append one.
if ! echo "${host_fqdn}" | grep -q '\.'; then
  host_fqdn="${host_fqdn}.localdomain"
fi

# Get the host name and domain name from the host's FQDN.
host_name="$(get_host_name_from_fqdn "${host_fqdn}")"
domain_name="$(get_domain_name_from_fqdn "${host_fqdn}")"

if ! set_host_name "${host_fqdn}" "${host_name}" "${domain_name}"; then
  case "${?}" in
  50)
      fatal "hostname -f returned empty string" 50
      ;;
  51)
      _act_host_fqdn="$(hostname -f)" || true
      fatal "exp_host_fqdn=${host_fqdn} act_host_fqdn=${_act_host_fqdn}" 51
      ;;
  52)
      fatal "hostname -s returned empty string" 52
      ;;
  53)
      _act_host_name="$(hostname -s)" || true
      fatal "exp_host_name=${host_name} act_host_name=${_act_host_name}" 53
      ;;
  54)
      fatal "hostname -d returned empty string" 54
      ;;
  55)
      _act_domain_name="$(hostname -d)" || true
      fatal "exp_domain_name=${domain_name} act_domain_name=${_act_domain_name}" 55
      ;;
  *)
      fatal "set_host_name failed" "${?}"
      ;;
  esac
fi

echo "host name has been updated!"
echo "    host fqdn  = ${host_fqdn}"
echo "    host name  = ${host_name}"
echo "  domain name  = ${domain_name}"

exit 0
