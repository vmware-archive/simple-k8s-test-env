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

#
# usage: get-k8s-artifacts-url.sh K8S_VERSION
#
# K8S_VERSION may be set to:
#
#    * release/(latest|stable|<version>)
#      A pattern that matches one of the builds staged in the public
#      GCS bucket kubernetes-release
#
#    * ci/(latest|<version>)
#      A pattern that matches one of the builds staged in the public
#      GCS bucket kubernetes-release-dev
#
#    * https{0,1}://
#      An URL that points to a remote location that follows the rules
#      for staging K8s builds. This option enables yakity to use a custom
#      build staged with "kubetest".
#
# Whether a URL is discerned from K8S_VERSION or it is set to a URL, the
# URL is used to build the paths to the following K8s artifacts:
#
#        1. https://URL/kubernetes.tar.gz
#        2. https://URL/kubernetes-client-OS-ARCH.tar.gz
#        3. https://URL/kubernetes-node-OS-ARCH.tar.gz
#        3. https://URL/kubernetes-server-OS-ARCH.tar.gz
#        4. https://URL/kubernetes-test-OS-ARCH.tar.gz
#
# To see a full list of supported versions use the Google Storage
# utility, gsutil, and execute "gsutil ls gs://kubernetes-release/release"

# Executes a HEAD request against a URL and verfieis the request returns
# the provided HTTP status and optional response message.
http_stat() {
  ${CURL} -sSLI "${3}" | grep -q \
    '^HTTP/[1-2]\(\.[0-9]\)\{0,1\} '"${1}"'[[:space:]]\{0,\}\('"${2}"'\)\{0,1\}[[:space:]]\{0,\}$'
}
http_200() { http_stat 200         "OK" "${1}"; }
http_204() { http_stat 204 "No Content" "${1}"; }

# Parses K8S_VERSION and returns the URL used to access the Kubernetes
# artifacts for the provided version string.
get_k8s_artifacts_url() {
  { [ -z "${1}" ] && return 1; } || ver="${1}"

  # If the version begins with https?:// then the version *is* the
  # artifact prefix.
  echo "${ver}" | grep -iq '^https\{0,1\}://' && echo "${ver}" && return 0

  # Determine if the version points to a release or a CI build.
  url=https://storage.googleapis.com/kubernetes-release

  # If the version does *not* begin with release/ then it's a dev version.
  echo "${ver}" | grep -q '^release/' || url=${url}-dev

  # If the version is ci/latest, release/latest, or release/stable then
  # append .txt to the version string so the next if block gets triggered.
  echo "${ver}" | \
    grep -q '^\(ci/latest\)\|\(\(release/\(latest\|stable\)\)\(-[[:digit:]]\{1,\}\(\.[[:digit:]]\{1,\}\)\{0,1\}\)\{0,1\}\)$' && \
    ver="${ver}.txt"

  # If the version points to a .txt file then its *that* file that contains
  # the actual version information.
  if echo "${ver}" | grep -q '\.txt$'; then
    ver_real="$(curl -sSL "${url}/${ver}")"
    ver_prefix=$(echo "${ver}" | awk -F/ '{print $1}')
    ver="${ver_prefix}/${ver_real}"
  fi

  # Return the artifact URL.
  echo "${url}/${ver}" && return 0
}

get_k8s_artifacts_url "${@}"
