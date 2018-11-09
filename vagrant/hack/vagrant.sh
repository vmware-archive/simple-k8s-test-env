#!/bin/sh

export PROGRAM="vagrant"

# Load the commons library.
# shellcheck disable=SC1090
. "$(dirname "${0}")/common.sh"

print_context

case "${1}" in
up)
  # shellcheck disable=SC1004
  exec /bin/sh -c 'vagrant up \
    --provision-with init-guest,file,init-yakity && \
    vagrant provision --provision-with start-yakity'
  ;;
*)
  exec vagrant "${@}"
  ;;
esac
