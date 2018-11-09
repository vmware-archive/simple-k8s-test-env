#!/bin/sh

export PROGRAM="kubectl"

# Load the commons library.
# shellcheck disable=SC1090
. "$(dirname "${0}")/common.sh"

exec kubectl "${@}"
