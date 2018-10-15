#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

#
# Used by the yakity service to update the yakity resources.
#

# Update the path so that "rpctool" is in it.
PATH=/var/lib/yakity:"${PATH}"

if ! command -v rpctool >/dev/null 2>&1; then
  exit_code="${?}"
  echo "failed to find rpctool command" 1>&2
  exit "${exit_code}"
fi

update() {
  url=$(rpctool get.ovf "${1}" 2>/dev/null) || return 0
  [ -n "${url}" ] || return 0
  curl -sSLo "${2}" "${url}" || return "${?}"
  chmod 0755 "${2}"
}

# Update the program that writes the yakity config from the vSphere GuestInfo.
update YAKITY_GUESTINFO_URL /var/lib/yakity/yakity-guestinfo.sh || \
  echo "failed to update yakity-guestinfo.sh" 1>&2

# Update the main yakity program.
update YAKITY_URL /var/lib/yakity/yakity.sh || \
  echo "failed to update yakity.sh" 1>&2
