#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

#
# Used by the yakity service to update the yakity resources.
#

# Load the yakity commons library.
# shellcheck disable=SC1090
. "$(pwd)/yakity-common.sh"

_done_file="$(pwd)/.$(basename "${0}").done"
[ ! -f "${_done_file}" ] || exit 0
touch "${_done_file}"

update() {
  url="$(rpc_get "${1}")"
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
