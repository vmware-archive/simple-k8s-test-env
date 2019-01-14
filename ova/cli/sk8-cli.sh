#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

#
# A command-line interface (CLI) client for Kubernetes clusters turned
# up with the sk8 OVA.
#

set -e
set -o pipefail

# echo2 echoes the provided arguments to stderr.
echo2() { echo "${@}" 1>&2; }; export echo2

# printf2 prints the provided format and arguments to stderr.
# shellcheck disable=SC2059
printf2() { _f="${1}"; shift; printf "${_f}" "${@}" 1>&2; }; export printf2
