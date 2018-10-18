#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

#
# Used by the yakity service to update the yakity resources.
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

update() {
  url=$(rpctool get.ovf "${1}" 2>/dev/null) || return 0
  [ -n "${url}" ] || return 0
  curl -sSLo "${2}" "${url}" || return "${?}"
  chmod 0755 "${2}"
  echo "updated ${2} from ${url}"
}

# Update the program that writes the yakity config from the vSphere GuestInfo.
update YAKITY_GUESTINFO_URL /var/lib/yakity/yakity-guestinfo.sh || \
  fatal "failed to update yakity-guestinfo.sh"

# Update the main yakity program.
update YAKITY_URL /var/lib/yakity/yakity.sh || \
  fatal "failed to update yakity.sh"

exit 0
