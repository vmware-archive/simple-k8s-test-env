#!/bin/sh

# simple-kubernetes-test-environment
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
# Turns up a Kubernetes cluster. Supports single-node, single-master,
# and multi-master deployments.
#
# usage: sk8.sh
#        sk8.sh NODE_TYPE ETCD_DISCOVERY NUM_CONTROLLERS NUM_NODES
#
#   SINGLE NODE CLUSTER
#     To deploy a single node cluster execute "sk8.sh" with no arguments.
#
#   MULTI NODE CLUSTER
#     To deploy a multi-node cluster execute "sk8.sh" with the following
#     arguments on each controller and worker node in the cluster.
#
#       NODE_TYPE        May be set to "controller", "worker", or "both".
#       ETCD_DISCOVERY   The etcd discovery URL returned by a call to
#                        https://discovery.etcd.io/new?size=NUM_CONTROLLERS.
#       NUM_CONTROLLERS  The total number of controller nodes.
#       NUM_NODES        The total number of nodes. Defaults to
#                        NUM_CONTROLLERS.
#

set -o pipefail || echo 'pipefail unsupported' 1>&2

# Parses the argument and normalizes a truthy value to lower-case "true".
parse_bool() {
  { echo "${1}" | grep -oiq 'true\|yes\|1' && echo 'true'; } || echo 'false'
}

# echo2 echos the provided arguments to file descriptor 2, stderr.
echo2() {
  echo "${@}" 1>&2
}

# Logging levels
FATAL_LEVEL=1; ERROR_LEVEL=2; WARN_LEVEL=3; INFO_LEVEL=4; DEBUG_LEVEL=5;

# LOG_LEVEL may be set to:
#   * 1, FATAL
#   * 2, ERROR
#   * 3, WARN
#   * 4, INFO
#   * 5, DEBUG
LOG_LEVEL="${LOG_LEVEL:-${INFO_LEVEL}}"

parse_log_level() {
  if   echo "${1}" | grep -iq "^${FATAL_LEVEL}\\|fatal$"; then
    echo "${FATAL_LEVEL}"
  elif echo "${1}" | grep -iq "^${ERROR_LEVEL}\\|error$"; then
    echo "${ERROR_LEVEL}"
  elif echo "${1}" | grep -iq "^${WARN_LEVEL}\\|warn\\(ing\\)\\{0,1\\}$"; then
    echo "${WARN_LEVEL}"
  elif echo "${1}" | grep -iq "^${INFO_LEVEL}\\|info$"; then
    echo "${INFO_LEVEL}"
  elif echo "${1}" | grep -iq "^${DEBUG_LEVEL}\\|debug$"; then
    echo "${DEBUG_LEVEL}"
  else
    echo "${INFO_LEVEL}"
  fi
}

# Parse the log level that may have been set when this script was executed.
LOG_LEVEL="$(parse_log_level "${LOG_LEVEL}")"

# Normalize the possible truthy value of DEBUG to lower-case "true".
DEBUG=$(parse_bool "${DEBUG}")
is_debug() { [ "${DEBUG}" = "true" ]; }

# Debug mode enables tracing and sets LOG_LEVEL=DEBUG_LEVEL.
is_debug && { set -x; LOG_LEVEL="${DEBUG_LEVEL}"; }

# Returns a success if the provided argument is a whole number.
is_whole_num() { echo "${1}" | grep -q '^[[:digit:]]\{1,\}$'; }

# log LEVEL_INT LEVEL_SZ MSG [RETURN_CODE]
log() {
  exit_code="${?}"
  lvl_int="${1}"; lvl_sz="${2}"; msg="${3}"; ret_code="${4}"
  is_whole_num "${ret_code}" || ret_code="${exit_code}"
  if [ "${LOG_LEVEL}" -ge "${lvl_int}" ]; then
    printf "%s [%s] " "${lvl_sz}" "$(date +%s)" 1>&2; echo2 "${msg}"
  fi
  return "${ret_code}"
}

# debug MSG [RETURN_CODE]
#   Prints the supplies message to stderr if LOG_LEVEL >=DEBUG_LEVEL.
debug() { log "${DEBUG_LEVEL}" DEBUG "${@}"; }

# info MSG [RETURN_CODE]
#   Prints the supplies message to stderr if LOG_LEVEL >=INFO_LEVEL.
info() { log "${INFO_LEVEL}" INFO "${@}"; }

# warn MSG [RETURN_CODE]
#   Prints the supplies message to stderr if LOG_LEVEL >=WARN_LEVEL.
warn() { log "${WARN_LEVEL}" WARN "${@}"; }

# error MSG [RETURN_CODE]
#   Prints the supplies message to stderr if LOG_LEVEL >=ERROR_LEVEL.
error() { log "${ERROR_LEVEL}" ERROR "${@}"; }

# fatal MSG [RETURN_CODE]
#   Prints the supplies message to stderr if LOG_LEVEL >=FATAL_LEVEL.
fatal() {
  log "${FATAL_LEVEL}" FATAL "${@}"; ret_code="${?}"
  [ "${ret_code}" -eq "0" ] || exit "${ret_code}"
}

# If the sk8 defaults file is present then load it.
SK8_DEFAULTS=${SK8_DEFAULTS:-/etc/default/sk8}
if [ -e "${SK8_DEFAULTS}" ]; then
  info "loading defaults = ${SK8_DEFAULTS}"
  # shellcheck disable=SC1090
  . "${SK8_DEFAULTS}" || fatal "failed to load defaults = ${SK8_DEFAULTS}"
fi

# Add ${BIN_DIR} to the path
BIN_DIR="${BIN_DIR:-/opt/bin}"; mkdir -p "${BIN_DIR}"; chmod 0755 "${BIN_DIR}"
echo "${PATH}" | grep -qF "${BIN_DIR}" || export PATH="${BIN_DIR}:${PATH}"

# Parse the log level a second time in case the defaults file set the
# log level to a new value.
LOG_LEVEL="$(parse_log_level "${LOG_LEVEL}")"

# Warn the user if certain, expected directories do not exist.
warn_and_mkdir_sysdir() {
  [ ! -d "${1}" ] && \
    warn "${1} does not exist, system may be unsupported" && \
    mkdir -p "${1}"
}
warn_and_mkdir_sysdir /etc/default
warn_and_mkdir_sysdir /etc/profile.d
warn_and_mkdir_sysdir /etc/systemd/system
warn_and_mkdir_sysdir /etc/sysconfig
warn_and_mkdir_sysdir /etc/modules-load.d
warn_and_mkdir_sysdir /etc/sysctl.d

# NODE_TYPE is first assgined to the value of the first argument, $1. 
# If unset, NODE_TYPE is assigned the value of the environment variable
# NODE_TYPE. If unset, NODE_TYPE defaults to "both".
NODE_TYPE="${1:-${NODE_TYPE}}"; NODE_TYPE="${NODE_TYPE:-both}"

# ETCD_DISCOVERY is first assgined to the value of the second argument, $2. 
# If unset, ETCD_DISCOVERY is assigned the value of the environment variable
# ETCD_DISCOVERY.
ETCD_DISCOVERY="${2:-${ETCD_DISCOVERY}}"

# NUM_CONTROLLERS is first assgined to the value of the third argument, $3. 
# If unset, NUM_CONTROLLERS is assigned the value of the environment variable
# NUM_CONTROLLERS. If unset, NUM_CONTROLLERS defaults to "1".
NUM_CONTROLLERS="${3:-${NUM_CONTROLLERS}}"
NUM_CONTROLLERS="${NUM_CONTROLLERS:-1}"

# NUM_NODES is first assgined to the value of the fourth argument, $4. 
# If unset, NUM_NODES is assigned the value of the environment variable
# NUM_NODES. If unset, NUM_NODES defaults to the value of the environment
# variable NUM_CONTROLLERS.
NUM_NODES="${4:-${NUM_NODES}}"; NUM_NODES="${NUM_NODES:-${NUM_CONTROLLERS}}"

debug "pre-processed input"
debug "  NODE_TYPE       = ${NODE_TYPE}"
debug "  ETCD_DISCOVERY  = ${ETCD_DISCOVERY}"
debug "  NUM_CONTROLLERS = ${NUM_CONTROLLERS}"
debug "  NUM_NODES       = ${NUM_NODES}"

# A quick var and function that indicates whether this is a single
# node cluster.
is_single() { [ -z "${ETCD_DISCOVERY}" ]; }

if is_single; then
  info "deploying single node cluster"
  NODE_TYPE=both; NUM_CONTROLLERS=1; NUM_NODES=1
else
  info "deploying multi-node cluster"

  [ -z "${NODE_TYPE}" ] && fatal "missing NODE_TYPE"
  [ -z "${NUM_CONTROLLERS}" ] && fatal "missing NUM_CONTROLLERS"
  [ -z "${NUM_NODES}" ] && fatal "missing NUM_NODES"

  # Normalize NODE_TYPE to "controller", "worker", or "both". If NODE_TYPE
  # is none of these then the script exits with an error.
  NODE_TYPE=$(echo "${NODE_TYPE}" | \
    grep -io '^both\|controller\|worker$' | \
    tr '[:upper:]' '[:lower:]') || \
    fatal "invalid NODE_TYPE=${NODE_TYPE}"

  # Ensure NUM_CONTROLLERS and NUM_NODES are both set to whole numbers.
  # If either is not set to a whole number then the script exits with
  # an error.
  ! is_whole_num "${NUM_CONTROLLERS}" && \
    fatal "invalid NUM_CONTROLLERS=${NUM_CONTROLLERS}"
  ! is_whole_num "${NUM_NODES}" && \
    fatal "invalid NUM_NODES=${NUM_NODES}"
fi

info "deployment config"
info "  NODE_TYPE       = ${NODE_TYPE}"
info "  ETCD_DISCOVERY  = ${ETCD_DISCOVERY}"
info "  NUM_CONTROLLERS = ${NUM_CONTROLLERS}"
info "  NUM_NODES       = ${NUM_NODES}"

################################################################################
##                               Networking                                   ##
################################################################################
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

HOST_FQDN=$(hostname -f) || fatal "failed to get host fqdn"
HOST_NAME=$(hostname -s) || fatal "failed to get host name"

# If the host's FQDN is the same as the host's name, then it's likely the
# host doesn't have a domain part set for its host name. This program requires
# the host to have a valid FQDN. This logic ensures that the host has a valid
# FQDN by appending ".localdomain" to the host's name.
if [ "${HOST_FQDN}" = "${HOST_NAME}" ]; then
  host_fqdn="${HOST_NAME}.${NETWORK_DOMAIN:-localdomain}"
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
  HOST_FQDN=$(hostname -f) || fatal "failed to get host fqdn"
  HOST_NAME=$(hostname -s) || fatal "failed to get host name"
fi

if [ -z "${IPV4_ADDRESS}" ]; then
  if [ -n "${IPV4_DEVICE}" ]; then
    ip_route_dev="dev ${IPV4_DEVICE}"
  fi
  # shellcheck disable=SC2086
  IPV4_ADDRESS=$(ip route get ${ip_route_dev} 1 | awk '{print $NF;exit}') || \
    fatal "failed to get ipv4 address"
fi

if [ -z "${MAC_ADDRESS}" ]; then
  # shellcheck disable=SC2086
  MAC_ADDRESS=$(ip a | \
    grep -F "${IPV4_ADDRESS}" -B 1 | head -n 1 | awk '{print $2}') || \
    fatal "failed to get mac address"
fi

################################################################################
##                                 Config                                     ##
################################################################################

# Network information about the host.
NETWORK_DOMAIN="${NETWORK_DOMAIN:-$(hostname -d)}" || \
  fatal "failed to get host domain"
NETWORK_DNS_1="${NETWORK_DNS_1:-8.8.8.8}"
NETWORK_DNS_2="${NETWORK_DNS_2:-8.8.4.4}"
NETWORK_DNS_SEARCH="${NETWORK_DNS_SEARCH:-${NETWORK_DOMAIN}}"

info "HOST_FQDN=${HOST_FQDN}"
info "HOST_NAME=${HOST_NAME}"
info "IPV4_ADDRESS=${IPV4_ADDRESS}"
info "NETWORK_DOMAIN=${NETWORK_DOMAIN}"

# The number of seconds the keys associated with sk8 will exist
# before being removed by the etcd server.
#
# The default value is 15 minutes.
ETCD_LEASE_TTL=${ETCD_LEASE_TTL:-900}

# Set to "true" to configure IP tables to allow all 
# inbound and outbond connections.
IPTABLES_ALLOW_ALL=true
{ is_debug && IPTABLES_ALLOW_ALL=true; } || \
IPTABLES_ALLOW_ALL=$(parse_bool "${IPTABLES_ALLOW_ALL}")

# Setting this to true causes all of the temporary content stored
# in etcd for sharing assets to NOT be removed once the deploy process
# has completed.
CLEANUP_DISABLED=true
{ is_debug && CLEANUP_DISABLED=true; } || \
CLEANUP_DISABLED=$(parse_bool "${CLEANUP_DISABLED}")

# The directory in which the CNI plug-in binaries are located.
# The plug-ins are downloaded to CNI_BIN_DIR and then symlinked to
# /opt/cni/bin because Kubernetes --cni-bin-dir flag does not seem
# to work, and so the plug-ins need to be accessible in the default
# location.
CNI_BIN_DIR="${CNI_BIN_DIR:-/opt/bin/cni}"

# The default curl command to use instead of invoking curl directly.
CURL="curl --retry 5 --retry-delay 1 --retry-max-time 120"

# Setting CURL_DEBUG to a truthy value causes the default curl command
# to use verbose mode. Please keep in mind that this can negatively
# affect pattern matching that may be applied to curl output.
CURL_DEBUG=$(parse_bool "${CURL_DEBUG}")
[ "${CURL_DEBUG}" = "true" ] && CURL="${CURL} -v"

# The log levels for the various kubernetes components.
LOG_LEVEL_KUBERNETES="${LOG_LEVEL_KUBERNETES:-2}"
LOG_LEVEL_KUBE_APISERVER="${LOG_LEVEL_KUBE_APISERVER:-${LOG_LEVEL_KUBERNETES}}"
LOG_LEVEL_KUBE_SCHEDULER="${LOG_LEVEL_KUBE_SCHEDULER:-${LOG_LEVEL_KUBERNETES}}"
LOG_LEVEL_KUBE_CONTROLLER_MANAGER="${LOG_LEVEL_KUBE_CONTROLLER_MANAGER:-${LOG_LEVEL_KUBERNETES}}"
LOG_LEVEL_KUBELET="${LOG_LEVEL_KUBELET:-${LOG_LEVEL_KUBERNETES}}"
LOG_LEVEL_KUBE_PROXY="${LOG_LEVEL_KUBE_PROXY:-${LOG_LEVEL_KUBERNETES}}"
LOG_LEVEL_CLOUD_CONTROLLER_MANAGER="${LOG_LEVEL_CLOUD_CONTROLLER_MANAGER:-${LOG_LEVEL_KUBERNETES}}"

# Set to true to install the kubernetes e2e conformance test dependencies:
#
#   * Downloads this cluster's kubernetes-test.tar.gz to each worker
#     node and inflates the archive to /var/lib.
#
#   * Creates the "e2e" namespace.
#
#   * Creates a secret named "kubeconfig" in the "e2e" namespace. This
#     secret may be mounted as a volume to /etc/kubernetes to the image
#     gcr.io/kubernetes-conformance-testing/sk8e2e-job in order
#     to provide the container with a kubeconfig that can be used to
#     run the e2e tests.
INSTALL_CONFORMANCE_TESTS="${INSTALL_CONFORMANCE_TESTS:-true}"
INSTALL_CONFORMANCE_TESTS=$(parse_bool "${INSTALL_CONFORMANCE_TESTS}")

# Set to true to run the kubernetes e2e conformance test suite.
RUN_CONFORMANCE_TESTS=$(parse_bool "${RUN_CONFORMANCE_TESTS}")

# If defined, each of the following MANIFEST_YAML environment variables
# are applied from a control plane node with 
# "echo VAL | kubectl create -f -- -" using the order specified by the 
# environment variable's name. The manifests are applied exactly once, 
# no matter the number of control plane nodes.
#
# The reason for AFTER_RBAC_1 and AFTER_RBAC_2 is so systems like
# Terraform that may generate manifests can still participate while
# not overriding the end-user's values.
#
# Each of the values should be gzip'd and base64-encoded.
#MANIFEST_YAML_BEFORE_RBAC=
#MANIFEST_YAML_AFTER_RBAC_1=
#MANIFEST_YAML_AFTER_RBAC_2=
#MANIFEST_YAML_AFTER_ALL=

# Can be generated with:
#  head -c 32 /dev/urandom | base64
ENCRYPTION_KEY="${ENCRYPTION_KEY:-$(head -c 32 /dev/urandom | base64)}" || \
  fatal "error generating encryption key"

# The K8s cluster admin.
CLUSTER_ADMIN="${CLUSTER_ADMIN:-kubernetes}"

# The name of the K8s cluster.
CLUSTER_NAME="${CLUSTER_NAME:-kubernetes}"

# The FQDN of the K8s cluster.
CLUSTER_FQDN="${CLUSTER_NAME}.${NETWORK_DOMAIN}"

# The FQDN used to access the K8s cluster externally.
#EXTERNAL_FQDN=

# The K8s cluster CIDR.
CLUSTER_CIDR="${CLUSTER_CIDR:-10.200.0.0/16}"

# The format of K8s pod CIDR. The format should include a %d to be
# replaced by the index of this host in the cluster as discovered 
# via etcd. The result is assigned to POD_CIDR. If this is a single-node
# cluster then POD_CIDR will be set to 10.200.0.0/24 (per the default
# pattern below).
POD_CIDR_FORMAT="${POD_CIDR_FORMAT:-10.200.%d.0/24}"

# The secure port on which the K8s API server is advertised.
SECURE_PORT="${SECURE_PORT:-443}"

# The K8s cluster's service CIDR.
SERVICE_CIDR="${SERVICE_CIDR:-10.32.0.0/24}"

# The IP address used to access the K8s API server on the service network.
SERVICE_IPV4_ADDRESS="${SERVICE_IPV4_ADDRESS:-10.32.0.1}"

# The name of the service DNS provider. Valid values include "coredns".
# Any other value results in kube-dns being used.
SERVICE_DNS_PROVIDER="${SERVICE_DNS_PROVIDER:-kube-dns}"

# The IP address of the DNS server for the service network.
SERVICE_DNS_IPV4_ADDRESS="${SERVICE_DNS_IPV4_ADDRESS:-10.32.0.10}"

# The domain name used by the K8s service network.
SERVICE_DOMAIN="${SERVICE_DOMAIN:-cluster.local}"

# The name of the service record that points to the K8s API server on
# the service network.
SERVICE_NAME="${SERVICE_NAME:-${CLUSTER_NAME}}"

# The FQDN used to access the K8s API server on the service network.
SERVICE_FQDN="${SERVICE_NAME}.default.svc.${SERVICE_DOMAIN}"

# Set to a truthy value to override the host name in the kubelet with
# the FQDN of this host.
HOST_NAME_OVERRIDE="${HOST_NAME_OVERRIDE:-false}"
HOST_NAME_OVERRIDE=$(parse_bool "${HOST_NAME_OVERRIDE}")

# Set to "false" to disable failing the kubelet if swap space is enabled.
if [ -n "${FAIL_SWAP_ON}" ]; then
  FAIL_SWAP_ON="$(parse_bool "${FAIL_SWAP_ON}")"
fi

# The name of the cloud provider to use.
#CLOUD_PROVIDER=

# The gzip'd, base-64 encoded cloud provider configuration to use.
#CLOUD_CONFIG=

# If CLOUD_PROVIDER=external then this value is inspected to
# determine whiche external cloud-provider to use.
CLOUD_PROVIDER_EXTERNAL="${CLOUD_PROVIDER_EXTERNAL:-vsphere}"

# Used only when CLOUD_PROVIDER is set to "external". Please
# note that CLOUD_PROVIDER_EXTERNAL must also be set to the
# provider contained in the image specified by
# CLOUD_PROVIDER_IMAGE. There is no attempt to ensure the
# specified image is related to the specified provider.
CLOUD_PROVIDER_IMAGE=${CLOUD_PROVIDER_IMAGE:-gcr.io/cloud-provider-vsphere/vsphere-cloud-controller-manager:latest}

# Used only when CLOUD_PROVIDER is set to "external". The
# podspec for the external CCM is amended with an
# imagePullSecrets section. This value is a space-delimited
# series of secret references added to that section.
#CLOUD_PROVIDER_IMAGE_SECRETS=

# Set to a truthy value to enable the vCenter simulator. The simulator
# is only used if CLOUD_PROVIDER or CLOUD_PROVIDER_EXTERNAL is set to
# "vsphere".
VCSIM="${VCSIM:-false}"
VCSIM=$(parse_bool "${VCSIM}")

# The port on which the vCenter simulator listens for incoming connections.
VCSIM_PORT="${VCSIM_PORT:-8989}"

# Versions of the software packages installed on the controller and
# worker nodes. Please note that not all the software packages listed
# below are installed on both controllers and workers. Some is intalled
# on one, and some the other. Some software, such as jq, is installed
# on both controllers and workers.

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
#      for staging K8s builds. This option enables sk8 to use a custom
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
# for GA releases or "gsutil ls gs://kubernetes-release-dev" for dev
# releases.
K8S_VERSION="${K8S_VERSION:-release/stable}"

CNI_PLUGINS_VERSION="${CNI_PLUGINS_VERSION:-0.7.1}"
CONTAINERD_VERSION="${CONTAINERD_VERSION:-1.1.4}"
COREDNS_VERSION="${COREDNS_VERSION:-1.2.2}"
CRICTL_VERSION="${CRICTL_VERSION:-1.11.1}"
ETCD_VERSION="${ETCD_VERSION:-3.3.9}"
JQ_VERSION="${JQ_VERSION:-1.5}"
NGINX_VERSION="${NGINX_VERSION:-1.14.0}"
RUNC_VERSION="${RUNC_VERSION:-1.0.0-rc5}"
RUNSC_VERSION="${RUNSC_VERSION:-2018-09-01}"

# The paths to the TLS CA crt and key files used to sign the
# generated certificate signing request (CSR).
TLS_CA_CRT=${TLS_CA_CRT:-/etc/ssl/ca.crt}
TLS_CA_KEY=${TLS_CA_KEY:-/etc/ssl/ca.key}

# The paths to the generated key and certificate files.
# If TLS_KEY_OUT, TLS_CRT_OUT, and TLS_PEM_OUT are all unset then
# the generated key and certificate are printed to STDOUT.
#TLS_KEY_OUT=
#TLS_CRT_OUT=

# The strength of the generated certificate
TLS_DEFAULT_BITS=${TLS_DEFAULT_BITS:-2048}

# The number of days until the certificate expires. The default
# value is 100 years.
TLS_DEFAULT_DAYS=${TLS_DEFAULT_DAYS:-36500}

# The components that make up the certificate's distinguished name.
TLS_COUNTRY_NAME=${TLS_COUNTRY_NAME:-US}
TLS_STATE_OR_PROVINCE_NAME=${TLS_STATE_OR_PROVINCE_NAME:-California}
TLS_LOCALITY_NAME=${TLS_LOCALITY_NAME:-Palo Alto}
TLS_ORG_NAME=${TLS_ORG_NAME:-VMware}
TLS_OU_NAME=${TLS_OU_NAME:-CNX}
TLS_COMMON_NAME=${TLS_COMMON_NAME:-${1}}
TLS_EMAIL=${TLS_EMAIL:-cnx@vmware.com}

# Set to true to indicate the certificate is a CA.
TLS_IS_CA="${TLS_IS_CA:-FALSE}"

# The certificate's key usage.
TLS_KEY_USAGE="${TLS_KEY_USAGE:-digitalSignature, keyEncipherment}"

# The certificate's extended key usage string.
TLS_EXT_KEY_USAGE="${TLS_EXT_KEY_USAGE:-clientAuth, serverAuth}"

# Set to false to disable subject alternative names (SANs).
TLS_SAN="${TLS_SAN:-true}"

# A space-delimited list of FQDNs to use as SANs.
TLS_SAN_DNS="${TLS_SAN_DNS:-localhost ${HOST_NAME} ${HOST_FQDN}}"

# A space-delimited list of IP addresses to use as SANs.
TLS_SAN_IP="${TLS_SAN_IP:-127.0.0.1 ${IPV4_ADDRESS}}"

# The deafult owner and perms for generated TLS key and certs.
TLS_KEY_UID=0
TLS_KEY_GID=0
TLS_KEY_PERM=0400
TLS_CRT_UID=0
TLS_CRT_GID=0
TLS_CRT_PERM=0644

################################################################################
##                         K8S API Version Strings                            ##
################################################################################

KUBE_SCHEDULER_API_VERSION_OLD_PREFIX="componentconfig/v1alpha1"
KUBE_SCHEDULER_API_VERSION_NEW_PREFIX="kubescheduler.config.k8s.io/v1alpha1"

# If deploying a CI build or a release 1.12 or newer, use the new
# kube-scheduler API version prefix. Otherwise use the old one.
if echo "${K8S_VERSION}" | grep -q '^ci/' || \
   echo "${K8S_VERSION}" | grep -q '1\.1[2-9]'; then
  KUBE_SCHEDULER_API_VERSION="${KUBE_SCHEDULER_API_VERSION:-${KUBE_SCHEDULER_API_VERSION_NEW_PREFIX}}"
else
  KUBE_SCHEDULER_API_VERSION="${KUBE_SCHEDULER_API_VERSION:-${KUBE_SCHEDULER_API_VERSION_OLD_PREFIX}}"
fi
debug "KUBE_SCHEDULER_API_VERSION=${KUBE_SCHEDULER_API_VERSION}"

################################################################################
##                                Functions                                   ##
################################################################################

# The lock file used when obtaining a distributed lock with etcd.
LOCK_FILE="$(basename "${0}").lock"

# The name of the distributed lock.
LOCK_KEY="$(basename "${0}").lock"

# The process ID of the "etcdctl lock" command used to obtain the
# distributed lock.
LOCK_PID=

# Releases a distributed lock obtained from the etcd server. This function will
# not work until the etcd server is online and etcdctl has been configured.
release_lock() {
  kill "${LOCK_PID}" 2>/dev/null
  wait "${LOCK_PID}" 2>/dev/null || true
  rm -f "${LOCK_FILE}"
  debug "released lock ${LOCK_KEY}"
}

# Obtains a distributed lock from the etcd server. This function will
# not work until the etcd server is online and etcdctl has been configured.
obtain_lock() {
  debug "create lock file=${LOCK_FILE}"
  mkfifo "${LOCK_FILE}" || { error "failed to create fifo lock file"; return; }

  debug "obtaining distributed lock=${LOCK_KEY}"
  etcdctl lock "${LOCK_KEY}" >"${LOCK_FILE}" &
  LOCK_PID="${!}"
  debug "distributed lock process pid=${LOCK_PID}"

  if ! read -r lock_name <"${LOCK_FILE}"; then
    exit_code="${?}"
    error "failed to obtain distributed lock: ${lock_name}"
    release_lock "${LOCK_KEY}" "${LOCK_PID}" "${LOCK_FILE}"
    return "${exit_code}"
  fi

  debug "obtained distributed lock: ${lock_name}"
}

# Evaluates the first argument as the name of a function to execute 
# while holding a distributed lock. Regardless of the evaluated function's
# exit code, the lock is always released. This function then exits with
# the exit code of the evaluated function.
do_with_lock() {
  debug "obtaining distributed lock to safely execute ${1}"
  obtain_lock || { error "failed to obtain lock for ${1}"; return; }
  eval "${1}"; exit_code="${?}"
  release_lock
  debug "released lock used to safeley execute ${1}"
  return "${exit_code}"
}

# The ID of the lease associated with all keys added to etcd by this
# script.
#ETCD_LEASE_ID=

# grant_etcd_lease defines PUT_WITH_LEASE as a shortcut means of invoking
# "etcdctl put --lease=ETCD_LEASE_ID"
#PUT_WITH_LEASE=

# Grants a lease used to store all the keys added to etcd by sk8.
grant_etcd_lease() {
  lease_id_key="/sk8/lease/id"
  lease_ttl_key="/sk8/lease/ttl"
  lease_grantor_key="/sk8/lease/grantor"

  ETCD_LEASE_ID=$(etcdctl get "${lease_id_key}" --print-value-only) || \
    { error "failed to get lease id"; return; }

  if [ -n "${ETCD_LEASE_ID}" ]; then
    lease_ttl=$(etcdctl get "${lease_ttl_key}" --print-value-only) || \
      { error "failed to get lease ttl"; return; }
    lease_grantor=$(etcdctl get "${lease_grantor_key}" --print-value-only) || \
      { error "failed to get lease grantor"; return; }

    # Create a shortcut way to invoke 'etcdctl put' with the lease attached.
    PUT_WITH_LEASE="etcdctl put --lease=${ETCD_LEASE_ID}"

    info "lease already exists: id=${ETCD_LEASE_ID} ttl=${lease_ttl} grantor=${lease_grantor}"
  fi

  # Grant a new lease.
  ETCD_LEASE_ID=$(etcdctl lease grant "${ETCD_LEASE_TTL}" | \
    awk '{print $2}') || { error "error granting etcd lease"; return; }

  # Create a shortcut way to invoke 'etcdctl put' with the lease attached.
  PUT_WITH_LEASE="etcdctl put --lease=${ETCD_LEASE_ID}"

  # Save the lease ID, TTL, and this host's name as the grantor.
  ${PUT_WITH_LEASE} "${lease_id_key}" "${ETCD_LEASE_ID}" || \
    { error "error storing etcd lease id"; return; }
  ${PUT_WITH_LEASE} "${lease_ttl_key}" "${ETCD_LEASE_TTL}" || \
    { error "error storing etcd lease TTL"; return; }
  ${PUT_WITH_LEASE} "${lease_grantor_key}" "${HOST_FQDN}" || \
    { error "error storing etcd lease grantor"; return; }

  info "lease id=${ETCD_LEASE_ID} granted"
}

put_string() {
  debug "putting '${2}' into etcd key '${1}'"
  ${PUT_WITH_LEASE} "${1}" "${2}" || \
    { error "failed to put '${2}' into etcd key '${1}'"; return; }
}

put_file() {
  debug "putting contents of '${2}' into etcd key '${1}'"
  ${PUT_WITH_LEASE} "${1}" -- <"${2}" || \
    { error "failed to put contents of '${2}' to etcd key '${1}'"; return; }
}

put_stdin() {
  old_ifs="${IFS}"; IFS=''; stdin="$(cat)"; IFS="${old_ifs}"
  debug "putting contents of STDIN into etcd key '${1}'"
  echo "${stdin}" | ${PUT_WITH_LEASE} "${1}" || \
    { error "failed to put contents of STDIN to etcd key '${1}'"; return; }
}

# Executes the supplied command until it succeeds or until 100 attempts
# have occurred over five minutes. If the command has not succeeded
# by that time, an error will be returned.
retry_until_0() {
  msg="${1}"; shift; is_debug || printf "%s" "${msg}"
  i=1 && while true; do
    [ "${i}" -gt 100 ] && { error "timed out: ${msg}" 1; return; }
    if is_debug; then
      debug "${1}: attempt ${i}" && "${@}" && break
    else
      printf "." && "${@}" >/dev/null 2>&1 && break
    fi
    sleep 3; i=$((i+1))
  done
  { is_debug && debug "${msg}: success"; } || echo "✓"
}

get_product_uuid() {
  tr '[:upper:]' '[:lower:]' </sys/class/dmi/id/product_uuid || \
    { error "failed to read product uuid"; return; }
}

get_product_serial() {
  tr '[:upper:]' '[:lower:]' </sys/class/dmi/id/product_serial | \
    cut -c8- | tr -d ' -' | \
    sed 's/^\([[:alnum:]]\{1,8\}\)\([[:alnum:]]\{1,4\}\)\([[:alnum:]]\{1,4\}\)\([[:alnum:]]\{1,4\}\)\([[:alnum:]]\{1,12\}\)$/\1-\2-\3-\4-\5/' || \
    { error "failed to read product serial"; return; }
}

# Parses K8S_VERSION and returns the URL used to access the Kubernetes
# artifacts for the provided version string.
get_k8s_artifacts_url() {
  { [ -z "${1}" ] && return 1; } || ver="${1}"

  # If the version begins with https?:// then the version *is* the
  # artifact prefix.
  echo "${ver}" | grep -iq '^https\{0,1\}://' && echo "${ver}" && return 0

  # If the version begins with file:// then the version *is* the
  # artifact prefix.
  echo "${ver}" | grep -iq '^file://' && echo "${ver}" && return 0

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

# Reverses an FQDN and substitutes slash characters for periods.
# For example, k8s.vmware.ci becomes ci/vmware/k8s.
reverse_fqdn() {
  echo "${1}" | tr '.' '\n' | \
    sed '1!x;H;1h;$!d;g' | tr '\n' '.' | \
    sed 's/.$//' | tr '.' '/'
}

# Reverses and IP address and removes a trailing subnet notation. 
# For example, 10.32.0.0/24 becomes 0.0.32.10.
reverse_ipv4_address() {
  echo "${1}" | sed 's~\(.\{1,\}\)/[[:digit:]]\{1,\}~\1~g' | \
    tr '.' '\n' | sed '1!x;H;1h;$!d;g' | \
    tr '\n' '.' | sed 's/.$//'
}

# Executes a HEAD request against a URL and verifies the request returns
# the provided HTTP status and optional response message.
http_stat() {
  if echo "${3}" | grep -q '^file://'; then
    [ -f "$(echo "${3}" | sed 's~^file://~~')" ]
  else
    ${CURL} -sSI "${3}" | grep -q \
      '^HTTP/[1-2]\(\.[0-9]\)\{0,1\} '"${1}"'[[:space:]]\{0,\}\('"${2}"'\)\{0,1\}[[:space:]]\{0,\}$'
  fi
}
http_200() { http_stat 200                "OK" "${1}"; }
http_204() { http_stat 204        "No Content" "${1}"; }
http_301() { http_stat 301 "Moved Permanently" "${1}"; }
http_302() { http_stat 302             "Found" "${1}"; }

# This function assumes a resource is available if it returns 200, 301, or 302.
# The issue is GitHub downloads use S3 as the backing store. It's not possible
# to simply issue a HEAD request against a GitHub download URL as the URL points
# to an S3 resource using a signature for a GET operation, not a HEAD operation.
# The S3 service rejects the HEAD request since it is sent with a signature for
# a GET operation.
http_ok() { http_200 "${1}" || http_301 "${1}" || http_302 "${1}"; }

# Returns a successful exit code if the provided argument begins with http://
# or https://.
is_url() {
  echo "${1}" | grep -iq '^https\{0,1\}://'
}

is_cloud_provider_internal_vsphere() {
  [ "${CLOUD_PROVIDER}" = "vsphere" ]
}

is_cloud_provider_external() {
  [ "${CLOUD_PROVIDER}" = "external" ]
}

is_cloud_provider_external_vsphere() {
  is_cloud_provider_external && [ "${CLOUD_PROVIDER_EXTERNAL}" = "vsphere" ]
}

is_cloud_provider_vsphere() {
  is_cloud_provider_internal_vsphere || is_cloud_provider_external_vsphere
}

# Returns a successful exit code if the vCenter simulator is enabled
# and the in-tree or external cloud provider is set to vSphere.
is_vcsim() {
  [ "${VCSIM}" = "true" ] && is_cloud_provider_vsphere
}

# Creates a new X509 certificate/key pair.
new_cert() {
  # Make a temporary directory and switch to it.
  OLDDIR=$(pwd) || return
  { MYTEMP=$(mktemp -d) && cd "${MYTEMP}"; } || return

  # Write the SSL config file to disk.
  cat > ssl.conf <<EOF
[ req ]
default_bits           = ${TLS_DEFAULT_BITS}
default_days           = ${TLS_DEFAULT_DAYS}
encrypt_key            = no
default_md             = sha1
prompt                 = no
utf8                   = yes
distinguished_name     = dn
req_extensions         = ext
x509_extensions        = ext

[ dn ]
countryName            = ${TLS_COUNTRY_NAME}
stateOrProvinceName    = ${TLS_STATE_OR_PROVINCE_NAME}
localityName           = ${TLS_LOCALITY_NAME}
organizationName       = ${TLS_ORG_NAME}
organizationalUnitName = ${TLS_OU_NAME}
commonName             = ${TLS_COMMON_NAME}
emailAddress           = ${TLS_EMAIL}

[ ext ]
basicConstraints       = CA:$(echo "${TLS_IS_CA}" | tr '[:lower:]' '[:upper:]')
keyUsage               = ${TLS_KEY_USAGE}
extendedKeyUsage       = ${TLS_EXT_KEY_USAGE}
subjectKeyIdentifier   = hash
EOF

  if [ "${TLS_SAN}" = "true" ] && \
    { [ -n "${TLS_SAN_DNS}" ] || [ -n "${TLS_SAN_IP}" ]; }; then
    cat >> ssl.conf <<EOF
subjectAltName         = @sans

# DNS.1-n-1 are additional DNS SANs parsed from TLS_SAN_DNS
# IP.1-n-1  are additional IP SANs parsed from TLS_SAN_IP
[ sans ]
EOF

    # Append any DNS SANs to the SSL config file.
    i=1 && for j in $TLS_SAN_DNS; do
      echo "DNS.${i}                  = $j" >> ssl.conf && i="$(( i+1 ))"
    done

    # Append any IP SANs to the SSL config file.
    i=1 && for j in $TLS_SAN_IP; do
      echo "IP.${i}                   = $j" >> ssl.conf && i="$(( i+1 ))"
    done
  fi

  info "generating x509 certificate for ${TLS_COMMON_NAME}"
  debug "  TLS_CA_CRT                 = ${TLS_CA_CRT}"
  debug "  TLS_CA_KEY                 = ${TLS_CA_KEY}"
  debug "  TLS_KEY_OUT                = ${TLS_KEY_OUT}"
  debug "  TLS_KEY_UID                = ${TLS_KEY_UID}"
  debug "  TLS_KEY_GID                = ${TLS_KEY_GID}"
  debug "  TLS_KEY_PERM               = ${TLS_KEY_PERM}"
  debug "  TLS_CRT_OUT                = ${TLS_CRT_OUT}"
  debug "  TLS_CRT_UID                = ${TLS_CRT_UID}"
  debug "  TLS_CRT_GID                = ${TLS_CRT_GID}"
  debug "  TLS_CRT_PERM               = ${TLS_CRT_PERM}"
  debug "  TLS_DEFAULT_BITS           = ${TLS_DEFAULT_BITS}"
  debug "  TLS_DEFAULT_DAYS           = ${TLS_DEFAULT_DAYS}"
  debug "  TLS_COUNTRY_NAME           = ${TLS_COUNTRY_NAME}"
  debug "  TLS_STATE_OR_PROVINCE_NAME = ${TLS_STATE_OR_PROVINCE_NAME}"
  debug "  TLS_LOCALITY_NAME          = ${TLS_LOCALITY_NAME}"
  debug "  TLS_ORG_NAME               = ${TLS_ORG_NAME}"
  debug "  TLS_OU_NAME                = ${TLS_OU_NAME}"
  debug "  TLS_COMMON_NAME            = ${TLS_COMMON_NAME}"
  debug "  TLS_EMAIL                  = ${TLS_EMAIL}"
  debug "  TLS_IS_CA                  = ${TLS_IS_CA}"
  debug "  TLS_KEY_USAGE              = ${TLS_KEY_USAGE}"
  debug "  TLS_EXT_KEY_USAGE          = ${TLS_EXT_KEY_USAGE}"
  debug "  TLS_SAN                    = ${TLS_SAN}"
  debug "  TLS_SAN_DNS                = ${TLS_SAN_DNS}"
  debug "  TLS_SAN_IP                 = ${TLS_SAN_IP}"

  # Generate a private key file.
  openssl genrsa -out "${TLS_KEY_OUT}" "${TLS_DEFAULT_BITS}" || \
    { error "failed to generate a new private key"; return; }

  # Generate a certificate CSR.
  openssl req -config ssl.conf \
              -new \
              -key "${TLS_KEY_OUT}" \
              -days "${TLS_DEFAULT_DAYS}" \
              -out csr.pem || \
    { error "failed to generate a csr"; return; }

  # Sign the CSR with the provided CA.
  openssl x509 -extfile ssl.conf \
               -extensions ext \
               -days "${TLS_DEFAULT_DAYS}" \
               -req \
               -in csr.pem \
               -CA "${TLS_CA_CRT}" \
               -CAkey "${TLS_CA_KEY}" \
               -CAcreateserial \
               -out "${TLS_CRT_OUT}" || \
    { error "failed to sign csr with ca"; return; }

  [ -n "${TLS_KEY_UID}" ] && chown "${TLS_KEY_UID}" "${TLS_KEY_OUT}"
  [ -n "${TLS_KEY_GID}" ] && chgrp "${TLS_KEY_GID}" "${TLS_KEY_OUT}"
  [ -n "${TLS_KEY_PERM}" ] && chmod "${TLS_KEY_PERM}" "${TLS_KEY_OUT}"

  [ -n "${TLS_CRT_UID}" ] && chown "${TLS_CRT_UID}" "${TLS_CRT_OUT}"
  [ -n "${TLS_CRT_GID}" ] && chgrp "${TLS_CRT_GID}" "${TLS_CRT_OUT}"
  [ -n "${TLS_CRT_PERM}" ] && chmod "${TLS_CRT_PERM}" "${TLS_CRT_OUT}"

  # Print the certificate's information if requested.
  if is_debug; then 
    openssl x509 -noout -text <"${TLS_CRT_OUT}" || \
      { error "failed to print certificate"; return; }
  fi

  # Print the certificate's subject.
  if cert_subj=$(openssl x509 -noout -subject <"${TLS_CRT_OUT}" | \
                 awk '{print $2}'); then
    info "generated x509 certificate: ${cert_subj}"
  else
    error "failed to print certificate subject"; return;
  fi

  cd "${OLDDIR}" || { error "failed to cd to ${OLDDIR}"; return; }
}

# Creates a new kubeconfig file.
new_kubeconfig() {
  [ -z "${KFG_FILE_PATH}" ] && { error "missing KFG_FILE_PATH"; return; }
  [ -z "${KFG_USER}" ] && { error "missing KFG_USER"; return; }
  [ -z "${KFG_TLS_CRT}" ] && { error "missing KFG_TLS_CRT"; return; }
  [ -z "${KFG_TLS_KEY}" ] && { error "missing KFG_TLS_KEY"; return; }

  kfg_cluster="${KCFG_CLUSTER:-${CLUSTER_FQDN}}"
  kfg_tls_ca_crt="${KFG_TLS_CA_CRT:-${TLS_CA_CRT}}"
  kfg_server="${KFG_SERVER:-https://${CLUSTER_FQDN}:${SECURE_PORT}}"
  kfg_context="${KFG_CONTEXT:-default}"
  kfg_uid="${KFG_UID:-root}"
  kfg_gid="${KFG_GID:-root}"
  kfg_perm="${KFG_PERM:-0400}"

  info "generating kubeconfig for ${KFG_USER}"
  debug "  KFG_FILE_PATH  = ${KFG_FILE_PATH}"
  debug "  KFG_TLS_CA_CRT = ${kfg_tls_ca_crt}"
  debug "  KFG_TLS_CRT    = ${KFG_TLS_CRT}"
  debug "  KFG_TLS_KEY    = ${KFG_TLS_KEY}"
  debug "  KFG_CLUSTER    = ${kfg_cluster}"
  debug "  KFG_SERVER     = ${kfg_server}"
  debug "  KFG_CONTEXT    = ${kfg_context}"
  debug "  KFG_USER       = ${KFG_USER}"
  debug "  KFG_UID        = ${kfg_uid}"
  debug "  KFG_GID        = ${kfg_gid}"
  debug "  KFG_PERM       = ${kfg_perm}"

  kubectl config set-cluster "${kfg_cluster}" \
    --certificate-authority="${kfg_tls_ca_crt}" \
    --embed-certs=true \
    --server="${kfg_server}" \
    --kubeconfig="${KFG_FILE_PATH}" || \
    { error "failed to kubectl config set-cluster"; return; }

  kubectl config set-credentials "${KFG_USER}" \
    --client-certificate="${KFG_TLS_CRT}" \
    --client-key="${KFG_TLS_KEY}" \
    --embed-certs=true \
    --kubeconfig="${KFG_FILE_PATH}" || \
    { error "failed to kubectl config set-credentials"; return; }

  kubectl config set-context "${kfg_context}" \
    --cluster="${kfg_cluster}" \
    --user="${KFG_USER}" \
    --kubeconfig="${KFG_FILE_PATH}" || \
    { error "failed to kubectl config set-context"; return; }

  kubectl config use-context "${kfg_context}" \
    --kubeconfig="${KFG_FILE_PATH}" || \
    { error "failed to kubectl config use-context"; return; }

  chown "${kfg_uid}"  "${KFG_FILE_PATH}" || return
  chgrp "${kfg_gid}"  "${KFG_FILE_PATH}" || return
  chmod "${kfg_perm}" "${KFG_FILE_PATH}" || return
}

# Configures iptables.
configure_iptables() {
  info "installing iptables"

  # Tell iptables to allow all incoming and outgoing connections.
  if [ "${IPTABLES_ALLOW_ALL}" = "true" ]; then
    warn "iptables allow all"
    cat <<EOF >/etc/sysconfig/iptables
*filter
:INPUT DROP [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
# Allow all outgoing packets.
-P OUTPUT ACCEPT
# Allow packet fowarding.
-P FORWARD ACCEPT
# Allow all incoming packets.
-A INPUT -j ACCEPT
# Enable the rules.
COMMIT
EOF

  # Configure iptables for controller nodes.
  elif [ "${NODE_TYPE}" = "controller" ]; then
    info "iptables enabled for controller node"
    cat <<EOF >/etc/sysconfig/iptables
*filter
:INPUT DROP [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]

# Block all null packets.
-A INPUT -p tcp --tcp-flags ALL NONE -j DROP

# Reject a syn-flood attack.
-A INPUT -p tcp ! --syn -m state --state NEW -j DROP

# Block XMAS/recon packets.
-A INPUT -p tcp --tcp-flags ALL ALL -j DROP

# Allow all incoming packets on the loopback interface.
-A INPUT -i lo -j ACCEPT

# Allow incoming packets for SSH.
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT

# Allow incoming packets for the etcd client and peer endpoints.
-A INPUT -p tcp -m tcp --dport 2379 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 2380 -j ACCEPT

# Allow incoming packets for DNS.
-A INPUT -p tcp -m tcp --dport 53 -j ACCEPT
-A INPUT -p udp -m udp --dport 53 -j ACCEPT

# Allow incoming packets for HTTP/HTTPS.
-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 443 -j ACCEPT

# Allow incoming packets for established connections.
-I INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow all outgoing packets.
-P OUTPUT ACCEPT

# Allow packet fowarding.
-P FORWARD ACCEPT

# Drop everything else.
-P INPUT DROP

# Enable the rules.
COMMIT
EOF

  # Configure iptables for worker nodes.
  elif [ "${NODE_TYPE}" = "worker" ]; then
    info "iptables enabled for worker node"
    cat <<EOF >/etc/sysconfig/iptables
*filter
:INPUT DROP [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]

# Block all null packets.
-A INPUT -p tcp --tcp-flags ALL NONE -j DROP

# Reject a syn-flood attack.
-A INPUT -p tcp ! --syn -m state --state NEW -j DROP

# Block XMAS/recon packets.
-A INPUT -p tcp --tcp-flags ALL ALL -j DROP

# Allow all incoming packets on the loopback interface.
-A INPUT -i lo -j ACCEPT

# Allow incoming packets for SSH.
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT

# Allow incoming packets for cAdvisor, used to query container metrics.
-A INPUT -p tcp -m tcp --dport 4149 -j ACCEPT

# Allow incoming packets for the unrestricted kubelet API.
-A INPUT -p tcp -m tcp --dport 10250 -j ACCEPT

# Allow incoming packets for the unauthenticated, read-only port used
# to query the node state.
-A INPUT -p tcp -m tcp --dport 10255 -j ACCEPT

# Allow incoming packets for kube-proxy's health check server.
-A INPUT -p tcp -m tcp --dport 10256 -j ACCEPT

# Allow incoming packets for Calico's health check server.
-A INPUT -p tcp -m tcp --dport 9099 -j ACCEPT

# Allow incoming packets for NodePort services.
# https://kubernetes.io/docs/setup/independent/install-kubeadm/
-A INPUT -p tcp -m multiport --dports 30000:32767 -j ACCEPT

# Allow incoming packets for established connections.
-I INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow all outgoing packets.
-P OUTPUT ACCEPT

# Allow packet fowarding.
-P FORWARD ACCEPT

# Drop everything else.
-P INPUT DROP

# Enable the rules.
COMMIT
EOF

  # Configure iptables for hosts that are simultaneously controller and
  # worker nodes in a multi-node cluster.
  elif ! is_single; then
    info "iptables enabled for controller/worker node"
    cat <<EOF >/etc/sysconfig/iptables
*filter
:INPUT DROP [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]

# Block all null packets.
-A INPUT -p tcp --tcp-flags ALL NONE -j DROP

# Reject a syn-flood attack.
-A INPUT -p tcp ! --syn -m state --state NEW -j DROP

# Block XMAS/recon packets.
-A INPUT -p tcp --tcp-flags ALL ALL -j DROP

# Allow all incoming packets on the loopback interface.
-A INPUT -i lo -j ACCEPT

# Allow incoming packets for SSH.
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT

# Allow incoming packets for the etcd client and peer endpoints.
-A INPUT -p tcp -m tcp --dport 2379 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 2380 -j ACCEPT

# Allow incoming packets for DNS.
-A INPUT -p tcp -m tcp --dport 53 -j ACCEPT
-A INPUT -p udp -m udp --dport 53 -j ACCEPT

# Allow incoming packets for HTTP/HTTPS.
-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 443 -j ACCEPT

# Allow incoming packets for cAdvisor, used to query container metrics.
-A INPUT -p tcp -m tcp --dport 4149 -j ACCEPT

# Allow incoming packets for the unrestricted kubelet API.
-A INPUT -p tcp -m tcp --dport 10250 -j ACCEPT

# Allow incoming packets for the unauthenticated, read-only port used
# to query the node state.
-A INPUT -p tcp -m tcp --dport 10255 -j ACCEPT

# Allow incoming packets for kube-proxy's health check server.
-A INPUT -p tcp -m tcp --dport 10256 -j ACCEPT

# Allow incoming packets for Calico's health check server.
-A INPUT -p tcp -m tcp --dport 9099 -j ACCEPT

# Allow incoming packets for NodePort services.
# https://kubernetes.io/docs/setup/independent/install-kubeadm/
-A INPUT -p tcp -m multiport --dports 30000:32767 -j ACCEPT

# Allow incoming packets for established connections.
-I INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow all outgoing packets.
-P OUTPUT ACCEPT

# Allow packet fowarding.
-P FORWARD ACCEPT

# Drop everything else.
-P INPUT DROP

# Enable the rules.
COMMIT
EOF

  # Configure iptables for a single-node cluster.
  else
    info "iptables enabled for single node cluster"
    cat <<EOF >/etc/sysconfig/iptables
*filter
:INPUT DROP [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]

# Block all null packets.
-A INPUT -p tcp --tcp-flags ALL NONE -j DROP

# Reject a syn-flood attack.
-A INPUT -p tcp ! --syn -m state --state NEW -j DROP

# Block XMAS/recon packets.
-A INPUT -p tcp --tcp-flags ALL ALL -j DROP

# Allow all incoming packets on the loopback interface.
-A INPUT -i lo -j ACCEPT

# Allow incoming packets for SSH.
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT

# Allow incoming packets for HTTP/HTTPS.
-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 443 -j ACCEPT

# Allow incoming packets for established connections.
-I INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow all outgoing packets.
-P OUTPUT ACCEPT

# Allow packet fowarding.
-P FORWARD ACCEPT

# Drop everything else.
-P INPUT DROP

# Enable the rules.
COMMIT
EOF
  fi

  cp -f /etc/sysconfig/iptables /etc/sysconfig/ip6tables
  if [ -d /etc/systemd/scripts ]; then
    cp -f /etc/sysconfig/iptables /etc/systemd/scripts/ip4save
    cp -f /etc/sysconfig/iptables /etc/systemd/scripts/ip6save
  fi
  if systemctl is-enabled iptables.service >/dev/null 2>&1; then
    debug "restarting iptables.service"
    systemctl -l restart iptables.service || \
      { error "failed to restart iptables.service"; return; }
  fi
  if systemctl is-enabled ip6tables.service >/dev/null 2>&1; then
    debug "restarting ip6tables.service"
    systemctl -l restart ip6tables.service || \
      { error "failed to restart ip6tables.service"; return; }
  fi

  debug "installed iptables"
}

# Enables the bridge module. This function is used by worker nodes.
enable_bridge_module() {
  # Do not enable the bridge module on controller nodes.
  [ "${NODE_TYPE}" = "controller" ] && return

  info "installing bridge kernel module"
  echo br_netfilter > /etc/modules-load.d/br_netfilter.conf
  if systemctl is-enabled systemd-modules-load.service >/dev/null 2>&1; then
    systemctl -l restart systemd-modules-load.service || \
      { error "failed to restart systemd-modules-load.service"; return; }
  fi
  cat <<EOF >/etc/sysctl.d/k8s-bridge.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
  sysctl --system || { error "failed to sysctl --system"; return; }

  debug "installed bridge kernel module"
}

# Enables IP forwarding.
enable_ip_forwarding() {
  info "enabling ip forwarding"
  echo "net.ipv4.ip_forward = 1" >/etc/sysctl.d/k8s-ip-forward.conf
  sysctl --system || { error "failed to sysctl --system"; return; }
}

# Reads the CA cert/key pair from TLS_CA_CRT_GZ and TLS_CA_KEY_GZ and
# writes them to TLS_CA_CRT and TLS_CA_KEY.
install_ca_files() {
  info "installing CAs"
  if [ -e "${TLS_CA_CRT}" ]; then
    debug "using existing CA crt at ${TLS_CA_CRT}"
  else
    [ -z "${TLS_CA_CRT_GZ}" ] && { error "missing TLS_CA_CRT_GZ"; return; }
    debug "writing CA crt file ${TLS_CA_CRT}"
    echo "${TLS_CA_CRT_GZ}" | base64 -d | gzip -d > "${TLS_CA_CRT}" || \
      { error "failed to write CA crt"; return; }
  fi
  if [ -e "${TLS_CA_KEY}" ]; then
    debug "using existing CA key at ${TLS_CA_KEY}"
  else
    [ -z "${TLS_CA_KEY_GZ}" ] && { error "missing TLS_CA_KEY_GZ"; return; }
    debug "writing CA key file ${TLS_CA_KEY}"
    echo "${TLS_CA_KEY_GZ}" | base64 -d | gzip -d > "${TLS_CA_KEY}" || \
      { error "failed to write CA key"; return; }
  fi

  mkdir -p /etc/ssl/certs; chmod 0755 /etc/ssl/certs;
  rm -f /etc/ssl/certs/sk8-ca.crt
  ln -s "${TLS_CA_CRT}" /etc/ssl/certs/sk8-ca.crt
  debug "linked ${TLS_CA_CRT} to /etc/ssl/certs/sk8-ca.crt"

  debug "installed CAs"
}

install_etcd() {
  # Do not install etcd on worker nodes.
  [ "${NODE_TYPE}" = "worker" ] && return

  info "installing etcd"

  # Create the etcd user if it doesn't exist.
  if ! getent passwd etcd >/dev/null 2>&1; then 
    debug "creating etcd user"
    useradd etcd --home /var/lib/etcd --no-user-group --system -M || \
      { error "failed to create etcd user"; return; }
  fi

  # Create the etcd directories and set their owner to etcd.
  debug "creating directories for etcd server"
  mkdir -p /var/lib/etcd/data
  chown etcd /var/lib/etcd /var/lib/etcd/data || return

  debug "generating cert for etcd client and peer endpoints"
  (TLS_KEY_OUT=/etc/ssl/etcd.key \
    TLS_CRT_OUT=/etc/ssl/etcd.crt \
    TLS_KEY_UID=etcd \
    TLS_CRT_UID=etcd \
    TLS_SAN_DNS="localhost ${HOST_NAME} ${HOST_FQDN} ${CLUSTER_FQDN}" \
    TLS_SAN_IP="127.0.0.1 ${IPV4_ADDRESS}" \
    TLS_COMMON_NAME="${HOST_FQDN}" new_cert) || \
    { error "failed to generate certs for etcd"; return; }

  debug "writing etcd defaults file=/etc/default/etcd"
  # Create the etcd environment file.
cat <<EOF > /etc/default/etcd
ETCD_DEBUG=${DEBUG}
ETCD_NAME=${HOST_NAME}
ETCD_DATA_DIR=/var/lib/etcd/data
ETCD_LISTEN_PEER_URLS=https://${IPV4_ADDRESS}:2380
ETCD_LISTEN_CLIENT_URLS=https://0.0.0.0:2379
ETCD_INITIAL_ADVERTISE_PEER_URLS=https://${IPV4_ADDRESS}:2380
ETCD_ADVERTISE_CLIENT_URLS=https://${IPV4_ADDRESS}:2379

ETCD_CERT_FILE=/etc/ssl/etcd.crt
ETCD_KEY_FILE=/etc/ssl/etcd.key
ETCD_CLIENT_CERT_AUTH=true
ETCD_TRUSTED_CA_FILE=${TLS_CA_CRT}
ETCD_PEER_CERT_FILE=/etc/ssl/etcd.crt
ETCD_PEER_KEY_FILE=/etc/ssl/etcd.key
ETCD_PEER_CLIENT_CERT_AUTH=true
ETCD_PEER_TRUSTED_CA_FILE=${TLS_CA_CRT}
EOF

  # If ETCD_DISCOVERY is set then add it to the etcd environment file.
  if [ -n "${ETCD_DISCOVERY}" ]; then
    debug "using etcd discovery url: ${ETCD_DISCOVERY}"
    echo "ETCD_DISCOVERY=${ETCD_DISCOVERY}" >> /etc/default/etcd
  fi

  # Create the etcd systemd service.
  debug "writing etcd service file=/etc/systemd/system/etcd.service"
  cat <<EOF > /etc/systemd/system/etcd.service
[Unit]
Description=etcd.service
Documentation=https://github.com/etcd-io/etcd
After=network-online.target
Wants=network-online.target

[Install]
WantedBy=multi-user.target

[Service]
Type=notify
Restart=always
RestartSec=10s
LimitNOFILE=40000
TimeoutStartSec=0
NoNewPrivileges=true
PermissionsStartOnly=true
User=etcd
WorkingDirectory=/var/lib/etcd
EnvironmentFile=/etc/default/etcd
ExecStart=/opt/bin/etcd
EOF

  debug "enabling etcd service"
  systemctl -l enable etcd.service || \
    { error "failed to enable etcd.service"; return; }

  debug "starting etcd service"
  systemctl -l start etcd.service || \
    { error "failed to start etcd.service"; return; }

  debug "installed etcd"
}

get_etcd_members_from_discovery_url() {
  info "getting etcd members from discovery url"
  [ -z "${ETCD_DISCOVERY}" ] && return
  members=$(${CURL} -sSL "${ETCD_DISCOVERY}" | \
    grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | \
    tr '\n' ' ' | \
    sed 's/\(.\{1,\}\).$/\1/') || return
  num_members=$(echo "${members}" | wc -w | awk '{print $1}') || return
  debug "discovered ${num_members}"
  [ "${num_members}" -eq "${NUM_CONTROLLERS}" ] || return
  debug "got etcd members from discovery url"
}

# Polls the etcd discovery URL until the number of expected members
# have joined the cluster
discover_etcd_cluster_members() {
  info "discovering etcd cluster members"

  # If this is a single-node cluster then there is no need for discovery.
  if is_single; then
    CONTROLLER_IPV4_ADDRESSES="${IPV4_ADDRESS}"
    info "discovered etcd cluster members: ${CONTROLLER_IPV4_ADDRESSES}"
    return
  fi

  # Poll the etcd discovery URL until the number of members matches the
  # number of controller nodes.
  #
  # After 100 failed attempts over 5 minutes the function will exit with 
  # an error.
  info "waiting for etcd members to join cluster"
  i=1 && while true; do
    if [ "${i}" -gt 100 ]; then
      error "timed out waiting for etcd members to join cluster" 1; return
    fi

    debug "waiting for etcd members to join cluster: poll attempt ${i}"
    printf "."
    members=$(${CURL} -sSL "${ETCD_DISCOVERY}" | \
      grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | \
      tr '\n' ' ' | \
      sed 's/\(.\{1,\}\).$/\1/')

    # Break out of the loop if the number of members that have joined
    # the etcd cluster matches the expected number of controller nodes.
    if num_members=$(echo "${members}" | wc -w | awk '{print $1}'); then
      debug "discovered ${num_members}"
      if [ "${num_members}" -eq "${NUM_CONTROLLERS}" ]; then
        debug "discovery complete" && break
      fi
    fi

    sleep 3
    i=$((i+1))
  done

  # Assign the IPv4 addresses of the discovered etcd cluster members to
  # the environment variable that contains the IPv4 addresses of the
  # controller nodes. All controller nodes should be a member of the
  # etcd cluster.
  #
  # The sort command is used to ensure the order of the IP addresses
  # is consistent across all of the nodes.
  CONTROLLER_IPV4_ADDRESSES=$(echo "${members}" | \
    tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/\(.\{1,\}\).$/\1/')
  info "discovered etcd cluster members: ${CONTROLLER_IPV4_ADDRESSES}"
}

configure_etcdctl() {
  info "generating cert for etcdctl"
  (TLS_KEY_OUT=/etc/ssl/etcdctl.key \
    TLS_CRT_OUT=/etc/ssl/etcdctl.crt \
    TLS_KEY_GID=k8s-admin \
    TLS_CRT_GID=k8s-admin \
    TLS_KEY_PERM=0440 \
    TLS_SAN=false \
    TLS_COMMON_NAME="etcdctl@${HOST_FQDN}" new_cert) || \
    { error "failed to generate certs for etcdctl"; return; }

  # Create a comma-separated list of the etcd client endpoints.
  for e in ${CONTROLLER_IPV4_ADDRESSES}; do
    if [ -z "${ETCD_CLIENT_ENDPOINTS}" ]; then
      ETCD_CLIENT_ENDPOINTS="https://${e}:2379"
    else
      ETCD_CLIENT_ENDPOINTS="${ETCD_CLIENT_ENDPOINTS},https://${e}:2379"
    fi
  done

  debug "writing etcdctl defaults file=/etc/default/etcdctl"
  cat <<EOF > /etc/default/etcdctl
ETCDCTL_API=3
ETCDCTL_CERT=/etc/ssl/etcdctl.crt
ETCDCTL_KEY=/etc/ssl/etcdctl.key
ETCDCTL_CACERT=${TLS_CA_CRT}
EOF

  if [ "${NODE_TYPE}" = "worker" ]; then
    echo "ETCDCTL_ENDPOINTS=${ETCD_CLIENT_ENDPOINTS}" >> /etc/default/etcdctl
  else
    echo "ETCDCTL_ENDPOINTS=https://127.0.0.1:2379" >> /etc/default/etcdctl
  fi

  # Load the etcdctl config into this script's process
  # shellcheck disable=SC1091
  set -o allexport && . /etc/default/etcdctl && set +o allexport

  # Make it so others can use the etcdctl config as well.
  debug "writing etcdctl profile.d file=/etc/profile.d/etcdctl.sh"
  cat <<EOF > /etc/profile.d/etcdctl.sh
#!/bin/sh
set -o allexport && . /etc/default/etcdctl && set +o allexport
EOF

  debug "configured etcdctl"
}

# Creates DNS entries on the etcd server for this node and an A-record
# for the public cluster FQDN.
create_dns_entries() {
  info "creating DNS entries"

  # Create the round-robin A record for the cluster's public FQDN.
  # This will be executed on each node, and that's okay since it's 
  # no issue to overwrite an existing etcd key.
  debug "creating round-robin DNS A-record for public cluster FQDN"
  cluster_fqdn_rev=$(reverse_fqdn "${CLUSTER_FQDN}")
  i=0 && for a in ${CONTROLLER_IPV4_ADDRESSES}; do
    # Create the A-Record
    etcdctl put "/skydns/${cluster_fqdn_rev}/${i}" '{"host":"'"${a}"'"}'
    debug "created cluster FQDN DNS A-record"
    etcdctl get "/skydns/${cluster_fqdn_rev}/${i}"
    # Increment the address index.
    i=$((i+1))
  done

  fqdn_rev=$(reverse_fqdn "${HOST_FQDN}")
  addr_slashes=$(echo "${IPV4_ADDRESS}" | tr '.' '/')

  # Create the A-Record for this host.
  debug "creating DNS A-record for this host"
  etcdctl put "/skydns/${fqdn_rev}" '{"host":"'"${IPV4_ADDRESS}"'"}' || \
    { error "failed to create DNS A-record"; return; }
  etcdctl get "/skydns/${fqdn_rev}"

  # Create the TXT record for this host that returns the node type.
  #etcdctl put "/skydns/${fqdn_rev}/txt/node-type" \
  #  '{"text":"'"${NODE_TYPE}"'"}' || \
  #  { error "failed to create DNS TXT-record for node type"; return; }
  #etcdctl get "/skydns/${fqdn_rev}/txt/node-type"

  # Create the reverse lookup record for this host.
  debug "creating DNS reverse lookup record for this host"
  etcdctl put "/skydns/arpa/in-addr/${addr_slashes}" '{"host":"'"${HOST_FQDN}"'"}' || \
    { error "failed to create DNS reverse lookup record"; return; }
  etcdctl get "/skydns/arpa/in-addr/${addr_slashes}"

  # If EXTERNAL_FQDN is defined then create a CNAME record for it
  # that points to CLUSTER_FQDN.
  if [ -n "${EXTERNAL_FQDN}" ]; then
    debug "creating DNS CNAME record for external cluster FQDN"
    external_fqdn_rev=$(reverse_fqdn "${EXTERNAL_FQDN}")
    etcdctl put "/skydns/${external_fqdn_rev}" '{"host":"'"${CLUSTER_FQDN}"'"}'
    debug "created external FQDN DNS CNAME record"
    etcdctl get "/skydns/${external_fqdn_rev}"
  fi

  # Create a text record at the root of the cluster that contains the
  # host name of all of the members of the cluster.
  #_rev_domain_fqdn="$(reverse_fqdn "${NETWORK_DOMAIN}")"
  #etcdctl put "/skydns/${_rev_domain_fqdn}/txt/cluster/num-nodes" \
  #  '{"text":"'"${NUM_NODES}"'"}' || \
  #  { error "failed to create DNS TXT-record for NUM_NODES"; return; }
  #etcdctl get "/skydns/${_rev_domain_fqdn}/txt/cluster/num-nodes"
  #etcdctl put "/skydns/${_rev_domain_fqdn}/txt/cluster/num-controllers" \
  #  '{"text":"'"${NUM_CONTROLLERS}"'"}' || \
  #  { error "failed to create DNS TXT-record for NUM_CONTROLLERS"; return; }
  #etcdctl get "/skydns/${_rev_domain_fqdn}/txt/cluster/num-controllers"

  debug "created DNS entries"
}

install_nginx() {
  info "installing nginx"

  # Do not install nginx on worker nodes.
  [ "${NODE_TYPE}" = "worker" ] && return

  # Create the nginx user if it doesn't exist.
  if ! getent passwd nginx >/dev/null 2>&1; then 
    debug "creating nginx user"
    useradd nginx --home /var/lib/nginx --no-user-group --system -M || \
      { error "failed to create nginx user"; return; }
  fi

  debug "creating directories for nginx"
  mkdir -p  /etc/nginx \
            /var/lib/nginx \
            /var/log/nginx

  nogroup_name=nobody
  id nobody | grep -q nogroup && nogroup_name=nogroup

  debug "writing nginx config file=/etc/nginx/nginx.conf"
  cat <<EOF > /etc/nginx/nginx.conf
user                   nginx ${nogroup_name};
pid                    /var/run/nginx.pid;
error_log              syslog:server=unix:/dev/log;
worker_processes       1;

events {
  worker_connections   1024;
}

http {
  default_type         application/octet-stream;
  log_format           main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                             '\$status \$body_bytes_sent "\$http_referer" '
                             '"\$http_user_agent" "\$http_x_forwarded_for"';
  access_log           syslog:server=unix:/dev/log main;
  sendfile             on;
  keepalive_timeout    65;
  gzip                 on;

  server {
    listen      80;
    server_name ${CLUSTER_FQDN};

    location = /healthz {
      proxy_pass                    https://127.0.0.1:443/healthz;
      proxy_ssl_trusted_certificate ${TLS_CA_CRT};
      proxy_set_header Host         \$host;
      proxy_set_header X-Real-IP    \$remote_addr;
    }

    location = /artifactz {
      return 200 '${K8S_ARTIFACT_PREFIX}';
      add_header Content-Type text/plain;
    }

    location = /e2e/job.yaml {
      alias /var/lib/kubernetes/e2e-job.yaml;
      add_header Content-Type text/plain;
    }
  }
}
EOF

  debug "writing nginx service=/etc/systemd/system/nginx.service"
  cat <<EOF > /etc/systemd/system/nginx.service
[Unit]
Description=nginx.service
Documentation=http://bit.ly/howto-build-nginx-for-container-linux
After=syslog.target nss-lookup.target

[Install]
WantedBy=multi-user.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid

ExecStartPre=/opt/bin/nginx -t
ExecStart=/opt/bin/nginx
ExecReload=/opt/bin/nginx -s reload
ExecStop=/bin/kill -s QUIT \$MAINPID
PrivateTmp=true
EOF

  debug "enabling nginx.service"
  systemctl -l enable nginx.service || \
    { error "failed to enable nginx.service"; return; }

  debug "starting nginx.service"
  systemctl -l start nginx.service || \
    { error "failed to start nginx.service"; return; }

  debug "installed nginx"
}

install_coredns() {
  info "installing coredns"

  # Do not install CoreDNS on worker nodes.
  [ "${NODE_TYPE}" = "worker" ] && return

  # Create the coredns user if it doesn't exist.
  if ! getent passwd coredns >/dev/null 2>&1; then 
    debug "creating coredns user"
    useradd coredns --home /var/lib/coredns --no-user-group --system -M || \
      { error "failed to create coredns user"; return; }
  fi

  debug "creating directories for CoreDNS"
  mkdir -p /etc/coredns /var/lib/coredns
  chown coredns /var/lib/coredns || \
    { error "failed to chown /var/lib/coredns"; return; }

  debug "generating certs for coredns"
  (TLS_KEY_OUT=/etc/ssl/coredns.key \
    TLS_CRT_OUT=/etc/ssl/coredns.crt \
    TLS_KEY_UID=coredns TLS_CRT_UID=coredns \
    TLS_COMMON_NAME="coredns@${HOST_FQDN}" \
    new_cert) || \
    { error "failed to generate x509 cert/key pair for CoreDNS"; return; }

  dns_zones="${NETWORK_DOMAIN} 0.0.0.0/0"
  [ -n "${EXTERNAL_FQDN}" ] && dns_zones="${EXTERNAL_FQDN}. ${dns_zones}"

  debug "writing /etc/coredns/Corefile"
  cat <<EOF > /etc/coredns/Corefile
. {
    log
    errors
    etcd ${dns_zones} {
        stubzones
        path /skydns
        endpoint https://127.0.0.1:2379
        upstream 127.0.0.1:53
        tls /etc/ssl/coredns.crt /etc/ssl/coredns.key ${TLS_CA_CRT}
    }
    prometheus
    cache 160 ${NETWORK_DOMAIN}
    loadbalance
    proxy . ${NETWORK_DNS_1}:53 ${NETWORK_DNS_2}:53
}
EOF

  debug "writing /etc/systemd/system/coredns.service"
  cat <<EOF > /etc/systemd/system/coredns.service
[Unit]
Description=coredns.service
Documentation=https://github.com/akutz/skydns/releases/tag/15f42ac
After=etcd.service
Requires=etcd.service

[Install]
WantedBy=multi-user.target

# Copied from http://bit.ly/systemd-coredns-service
[Service]
PermissionsStartOnly=true
LimitNOFILE=1048576
LimitNPROC=512
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
User=coredns
WorkingDirectory=/var/lib/coredns
ExecReload=/bin/kill -SIGUSR1 \$MAINPID
Restart=on-failure
ExecStart=/opt/bin/coredns -conf /etc/coredns/Corefile
EOF

  debug "enabling coredns.service"
  systemctl -l enable coredns.service || \
    { error "failed to enable coredns.service"; return; }

  debug "starting coredns.service"
  systemctl -l start coredns.service || \
    { error "failed to start coredns.service"; return; }

  debug "installed coredns"
}

resolve_via_coredns() {
  info "configuring DNS resolution against the control plane"

  # Even on worker nodes the custom resolv.conf is located in /var/lib/coredns.
  mkdir -p /var/lib/coredns

  # Remove the symlink for system's resolv.conf
  rm -f /etc/resolv.conf /var/lib/coredns/resolv.conf

  # Create a resolv.conf that points to the local CoreDNS server.
  if [ "${NODE_TYPE}" = "worker" ]; then
    i=1 && for e in ${CONTROLLER_IPV4_ADDRESSES}; do
      [ "${i}" -gt "3" ] && break
      echo "nameserver ${e}" >> /var/lib/coredns/resolv.conf
      i=$((i+1))
    done
  else
    echo "nameserver 127.0.0.1" >> /var/lib/coredns/resolv.conf
  fi

  # Add a search directive to the file.
  if [ -n "${NETWORK_DNS_SEARCH}" ]; then
    echo "search ${NETWORK_DNS_SEARCH}" >> /var/lib/coredns/resolv.conf
  fi

  # Link the CoreDNS resolv.conf to /etc/resolv.conf
  ln -s /var/lib/coredns/resolv.conf /etc/resolv.conf

  debug "using control plane for DNS resolution"
}

# Waits until all of the nodes can be resolved by their IP addresses 
# via reverse lookup.
wait_on_reverse_lookup() {
  info "waiting on all nodes to be resolvable via reverse DNS loopup"

  node_ipv4_addresses=$(get_all_node_ipv4_addresses) || \
    { error "failed to get ipv4 addresses for all nodes"; return; }

  debug "waiting on reverse lookup w node ipv4 addresses=${node_ipv4_addresses}"

  # After 100 failed attempts over 5 minutes the function will exit with 
  # an error.
  i=1 && while true; do
    if [ "${i}" -gt 100 ]; then
      error "timed out waiting for reverse lookup" 1; return
    fi

    debug "waiting for reverse lookup: attempt ${i}"
    printf "."

    all_resolve=true
    for a in ${node_ipv4_addresses}; do
       host "${a}" || { all_resolve=false && break; }
    done

    if [ "${all_resolve}" = "true" ]; then
      debug "all nodes resolved via reverse lookup" && break
    fi

    sleep 3
    i=$((i+1))
  done

  info "all nodes resolving"
}

# If NetworkManager is present, this function causes NetworkManager to
# stop trying to manage DNS so that the custom resolv.conf file created
# by this script will not be overriden.
disable_net_man_dns() {
  [ -d "/etc/NetworkManager/conf.d" ] || return 0
  info "disabling network manager dns"
  cat <<EOF > /etc/NetworkManager/conf.d/00-do-not-manage-dns.conf
[main]
dns=none
rc-manager=unmanaged
EOF
}

# If resolved is present then disable it so it does not interfere with
# CoreDNS.
disable_resolved() {
  systemctl is-enabled systemd-resolved >/dev/null 2>&1 || return 0
  info "diabling systemd-resolved"
  systemctl stop systemd-resolved >/dev/null 2>&1 || \
    { error "failed to stop systemd-resolved"; return; }
  systemctl disable systemd-resolved >/dev/null 2>&1 || \
    { error "failed to disable systemd-resolved"; return; }
  systemctl mask systemd-resolved >/dev/null 2>&1 || \
    { error "failed to mask systemd-resolved"; return; }
  debug "disabled systemd-resolved"
}

# Creates a sane shell prompt for logged-in users that includes the 
# last exit code.
configure_prompt() {
  info "configuring prompt"
  echo '#!/bin/sh' > /etc/profile.d/prompt.sh
  echo 'export PS1="[\$?]\[\e[32;1m\]\u\[\e[0m\]@\[\e[32;1m\]\h\[\e[0m\]:\W$ \[\e[0m\]"' >> /etc/profile.d/prompt.sh
}

# Creates a small command for printing the node type.
create_node_type_cmd() {
  info "creating node-type command"
  printf '#!/bin/sh\necho "%s"\n' "${NODE_TYPE}" >/opt/bin/node-type || return
  chmod 0755 /opt/bin/node-type
}

# Adds ${BIN_DIR} to the PATH for logged-in users.
configure_path() {
  info "configuring path"
  cat <<EOF > /etc/default/path
PATH=${BIN_DIR}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF
  cat <<EOF > /etc/profile.d/path.sh
#!/bin/sh
set -o allexport && . /etc/default/path && set +o allexport
EOF
}

# Uploads information about this node to the etcd server.
put_node_info() {
  # Get the number of nodes that have already stored their information.
  # This becomes the node's index, which is important as it forms
  # the node's pod-cidr.
  NODE_INDEX=$(etcdctl get '/sk8/nodes/' --prefix --keys-only | grep -cv '^$')

  # Build this node's pod cidr.
  # shellcheck disable=SC2059
  if [ -z "${POD_CIDR}" ]; then
    POD_CIDR=$(printf "${POD_CIDR_FORMAT}" "${NODE_INDEX}")
  fi
  
  node_info_key="/sk8/nodes/${NODE_INDEX}"
  debug "node info key=${node_info_key}"
  
  _uuid=$(get_product_uuid) || return "${?}"
  _serial=$(get_product_serial) || return "${?}"

  cat <<EOF | put_stdin "${node_info_key}" || \
    { error "failed to put node info"; return; }
{
  "host_fqdn": "${HOST_FQDN}",
  "host_name": "${HOST_NAME}",
  "ipv4_address": "${IPV4_ADDRESS}",
  "mac_address": "${MAC_ADDRESS}",
  "node_type": "${NODE_TYPE}",
  "node_index": ${NODE_INDEX},
  "pod_cidr": "${POD_CIDR}",
  "uuid": "${_uuid}",
  "serial": "${_serial}"
}
EOF

  debug "put node info at ${node_info_key}"
}

get_all_node_info() {
  etcdctl get /sk8/nodes --sort-by=KEY --prefix
}

#get_all_node_ipv4_addresses() {
#  get_all_node_info | grep ipv4_address | awk '{print $2}' | tr -d '",'
#}

get_all_node_ipv4_addresses() {
  etcdctl get /sk8/nodes --sort-by=KEY --prefix \
    --print-value-only | jq -rs '.[] | .ipv4_address'
}

# Polls etcd until all nodes have uploaded their information.
wait_on_all_node_info() {
  info "waiting on all nodes to join the cluster"
  # After 100 failed attempts over 5 minutes the function will exit with 
  # an error.
  i=0 && while true; do
    [ "${i}" -gt 100 ] && { error "timed out waiting for node info" 1; return; }
    debug "waiting for all node info: poll attempt ${i}"
    printf "."
    
    # Break out of the loop if the number of nodes that have stored
    # their info matches the number of expected nodes.
    num_nodes=$(etcdctl get '/sk8/nodes/' --prefix --keys-only | grep -cv '^$')
    [ "${num_nodes}" -eq "${NUM_NODES}" ] && break

    sleep 3
    i=$((i+1))
  done
  info "all nodes have joined the cluster"
}

# Prints the information each node uploaded about itself to the etcd server.
print_all_node_info() {
  i=0 && while true; do
    node_info_key="/sk8/nodes/${i}"
    node_info=$(etcdctl get "${node_info_key}" --print-value-only) || break
    [ -z "${node_info}" ] && break
    if ! node_info_val=$(echo "${node_info}" | jq ''); then
      error "problem printing node info for ${node_info_key}"; return
    fi
    info "  ${node_info_key}=${node_info_val}"
    i=$((i+1))
  done
}

install_cni_plugins() {
  info "installing CNI plug-ins"

  # Symlink CNI_BIN_DIR to /opt/cni/bin since Kubernetes --cni-bin-dir
  # flag does not seem to work, and containers fail if the CNI plug-ins
  # are not accessible in the default location.
  mkdir -p /opt/cni
  ln -s "${CNI_BIN_DIR}" /opt/cni/bin || \
    { error "failed to symlink ${CNI_BIN_DIR} to /opt/cni/bin"; return; }

  mkdir -p /etc/cni/net.d/

  debug "writing /etc/cni/net.d/10-bridge.conf"
  cat <<EOF > /etc/cni/net.d/10-bridge.conf
{
  "cniVersion": "0.3.1",
  "name": "bridge",
  "type": "bridge",
  "bridge": "cnio0",
  "isGateway": true,
  "ipMasq": true,
  "ipam": {
    "type": "host-local",
    "ranges": [
      [
        {
          "subnet": "${POD_CIDR}"
        }
      ]
    ],
    "routes": [
      {
        "dst": "0.0.0.0/0"
      }
    ]
  }
}
EOF

  debug "writing /etc/cni/net.d/99-loopback.conf"
  cat <<EOF >/etc/cni/net.d/99-loopback.conf
{
  "cniVersion": "0.3.1",
  "type": "loopback"
}
EOF

  debug "installed CNI plug-ins"
}

install_containerd() {
  info "installing containerd"

  debug "creating directories for containerd"
  mkdir -p  /etc/containerd \
            /opt/containerd \
            /var/lib/containerd \
            /var/run/containerd

  if echo "${CONTAINERD_VERSION}" | grep -q '^1.1'; then
    debug "writing 1.1.x /etc/containerd/config.toml"
    cat <<EOF >/etc/containerd/config.toml
[plugins]
  [plugins.cri.containerd]
    snapshotter = "overlayfs"
    [plugins.cri.containerd.default_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/opt/bin/runc"
      runtime_root = ""
    [plugins.cri.containerd.untrusted_workload_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/opt/bin/runsc"
      runtime_root = "/var/run/containerd/runsc"
EOF
  else
    debug "writing 1.2.x /etc/containerd/config.toml"
    cat <<EOF >/etc/containerd/config.toml
root = "/var/lib/containerd"
state = "/var/run/containerd"
subreaper = true

[grpc]
  address = "/var/run/containerd/containerd.sock"
  uid = 0
  gid = 0

[plugins]
  [plugins.opt]
    path = "/opt/containerd"
  [plugins.cri.containerd]
    snapshotter = "overlayfs"
    [plugins.cri.containerd.default_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/opt/bin/runc"
      runtime_root = ""
    [plugins.cri.containerd.untrusted_workload_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/opt/bin/runsc"
      runtime_root = "/var/run/containerd/runsc"
EOF
fi

  debug "writing /etc/systemd/system/containerd.service"
  cat <<EOF >/etc/systemd/system/containerd.service
[Unit]
Description=containerd.service
Documentation=https://containerd.io
After=network-online.target
Wants=network-online.target

[Install]
WantedBy=multi-user.target

[Service]
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
WorkingDirectory=/var/lib/containerd
EnvironmentFile=/etc/default/path
ExecStartPre=/bin/sh -c '/usr/sbin/modprobe overlay || /sbin/modprobe overlay'
ExecStart=/opt/bin/containerd
EOF

  debug "enabling containerd service"
  systemctl -l enable containerd.service || \
    { error "failed to enable containerd.service"; return; }

  debug "starting containerd service"
  systemctl -l start containerd.service || \
    { error "failed to start containerd.service"; return; }

  debug "installed containerd"
}

install_cloud_provider() {
  { [ -z "${CLOUD_PROVIDER}" ] || [ -z "${CLOUD_CONFIG}" ]; } && return

  info "installing cloud provider ${CLOUD_PROVIDER}"

  mkdir -p /var/lib/kubernetes/
  EXT_CLOUD_PROVIDER_OPTS=" --cloud-provider='${CLOUD_PROVIDER}'"
  if [ ! "${CLOUD_PROVIDER}" = "external" ]; then
    echo "${CLOUD_CONFIG}" | base64 -d | gzip -d >/var/lib/kubernetes/cloud-provider.conf
    EXT_CLOUD_PROVIDER_OPTS="${EXT_CLOUD_PROVIDER_OPTS} --cloud-config=/var/lib/kubernetes/cloud-provider.conf"
    CLOUD_PROVIDER_OPTS="${EXT_CLOUD_PROVIDER_OPTS}"
  fi
}

install_kube_apiserver() {
  info "installing kube-apiserver"

  cat <<EOF > /etc/default/kube-apiserver
# Copied from http://bit.ly/2niZlvx

APISERVER_OPTS="--advertise-address=${IPV4_ADDRESS} \\
--allow-privileged=true \\
--apiserver-count=${NUM_CONTROLLERS} \\
--audit-log-maxage=30 \\
--audit-log-maxbackup=3 \\
--audit-log-maxsize=100 \\
--audit-log-path=/var/log/audit.log \\
--authorization-mode=Node,RBAC \\
--bind-address=0.0.0.0${CLOUD_PROVIDER_OPTS} \\
--client-ca-file='${TLS_CA_CRT}' \\
--enable-admission-plugins='Initializers,NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota' \\
--enable-swagger-ui=true \\
--etcd-cafile='${TLS_CA_CRT}' \\
--etcd-certfile=/etc/ssl/etcd.crt \
--etcd-keyfile=/etc/ssl/etcd.key \\
--etcd-servers='${ETCD_CLIENT_ENDPOINTS}' \\
--event-ttl=1h \\
--experimental-encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
--kubelet-certificate-authority='${TLS_CA_CRT}' \\
--kubelet-client-certificate=/etc/ssl/kube-apiserver.crt \\
--kubelet-client-key=/etc/ssl/kube-apiserver.key \\
--kubelet-https=true \\
--runtime-config=api/all \\
--secure-port=${SECURE_PORT} \\
--service-account-key-file=/etc/ssl/k8s-service-accounts.key \\
--service-cluster-ip-range='${SERVICE_CIDR}' \\
--service-node-port-range=30000-32767 \\
--tls-cert-file=/etc/ssl/kube-apiserver.crt \\
--tls-private-key-file=/etc/ssl/kube-apiserver.key \\
--v=${LOG_LEVEL_KUBE_APISERVER}"
EOF

  cat <<EOF > /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes
After=etcd.service
Requires=etcd.service

[Install]
WantedBy=multi-user.target

[Service]
Restart=on-failure
RestartSec=5
WorkingDirectory=/var/lib/kube-apiserver
EnvironmentFile=/etc/default/kube-apiserver
ExecStart=/opt/bin/kube-apiserver \$APISERVER_OPTS
EOF

  debug "enabling kube-apiserver.service"
  systemctl -l enable kube-apiserver.service || \
    { error "failed to enable kube-apiserver.service"; return; }

  debug "starting kube-apiserver.service"
  systemctl -l start kube-apiserver.service || \
    { error "failed to start kube-apiserver.service"; return; }

  debug "installed kube-apiserver"
}

install_kube_controller_manager() {
  info "installing kube-controller-manager"

  cat <<EOF >/etc/default/kube-controller-manager
CONTROLLER_OPTS="--address=0.0.0.0${CLOUD_PROVIDER_OPTS} \\
--cluster-cidr='${CLUSTER_CIDR}' \\
--cluster-name='${SERVICE_NAME}' \\
--cluster-signing-cert-file='${TLS_CA_CRT}' \\
--cluster-signing-key-file='${TLS_CA_KEY}' \\
--kubeconfig=/var/lib/kube-controller-manager/kubeconfig \\
--leader-elect=true \\
--root-ca-file='${TLS_CA_CRT}' \\
--service-account-private-key-file=/etc/ssl/k8s-service-accounts.key \\
--service-cluster-ip-range='${SERVICE_CIDR}' \\
--use-service-account-credentials=true \\
--v=${LOG_LEVEL_KUBE_CONTROLLER_MANAGER}"
EOF

  cat <<EOF >/etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes
After=kube-apiserver.service
Requires=kube-apiserver.service

[Install]
WantedBy=multi-user.target

[Service]
Restart=on-failure
RestartSec=5
WorkingDirectory=/var/lib/kube-controller-manager
EnvironmentFile=/etc/default/kube-controller-manager
ExecStart=/opt/bin/kube-controller-manager \$CONTROLLER_OPTS
EOF

  debug "enabling kube-controller-manager.service"
  systemctl -l enable kube-controller-manager.service || \
    { error "failed to enable kube-controller-manager.service"; return; }

  debug "starting kube-controller-manager.service"
  systemctl -l start kube-controller-manager.service || \
    { error "failed to start kube-controller-manager.service"; return; }

  debug "installed kube-controller-manager"
}

install_kube_scheduler() {
  info "installing kube-scheduler"

#  cat <<EOF > /var/lib/kube-scheduler/kube-scheduler-config.yaml
#apiVersion: ${KUBE_SCHEDULER_API_VERSION}
#kind: KubeSchedulerConfiguration
#clientConnection:
#  kubeconfig: /var/lib/kube-scheduler/kubeconfig
#leaderElection:
#  leaderElect: true
#EOF

  cat <<EOF > /etc/default/kube-scheduler
SCHEDULER_OPTS="--kubeconfig=/var/lib/kube-scheduler/kubeconfig \\
--leader-elect=true \\
--v=${LOG_LEVEL_KUBE_SCHEDULER}"
EOF

  cat <<EOF > /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes
After=kube-apiserver.service
Requires=kube-apiserver.service

[Install]
WantedBy=multi-user.target

[Service]
Restart=on-failure
RestartSec=5
WorkingDirectory=/var/lib/kube-scheduler
EnvironmentFile=/etc/default/kube-scheduler
ExecStart=/opt/bin/kube-scheduler \$SCHEDULER_OPTS
EOF

  debug "enabling kube-scheduler.service"
  systemctl -l enable kube-scheduler.service || \
    { error "failed to enable kube-scheduler.service"; return; }

  debug "starting kube-scheduler.service"
  systemctl -l start kube-scheduler.service || \
    { error "failed to start kube-scheduler.service"; return; }

  debug "installed kube-scheduler"
}

install_kubelet() {
  info "installing kubelet"

  cat <<EOF > /var/lib/kubelet/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: ${TLS_CA_CRT}
authorization:
  mode: Webhook
clusterDomain: ${SERVICE_DOMAIN}
clusterDNS:
  - ${SERVICE_DNS_IPV4_ADDRESS}
podCIDR: ${POD_CIDR}
runtimeRequestTimeout: 15m
tlsCertFile: /etc/ssl/kubelet.crt
tlsPrivateKeyFile: /etc/ssl/kubelet.key
EOF

  if [ -n "${FAIL_SWAP_ON}" ]; then
    _kubelet_opts="--fail-swap-on='${FAIL_SWAP_ON}'"
  fi
  if [ "${HOST_NAME_OVERRIDE}" = "true" ]; then
    _kubelet_opts="${_kubelet_opts} --hostname-override='${HOST_FQDN}'"
  fi

  cat <<EOF >/etc/default/kubelet
KUBELET_OPTS="--allow-privileged \\
--client-ca-file='${TLS_CA_CRT}'${EXT_CLOUD_PROVIDER_OPTS} \\
--cni-bin-dir=/opt/bin/cni \\
--config=/var/lib/kubelet/kubelet-config.yaml \\
--container-runtime=remote \
--container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
--image-pull-progress-deadline=2m \\
--kubeconfig=/var/lib/kubelet/kubeconfig \\
--network-plugin=cni \\
--node-ip=${IPV4_ADDRESS} \\
--register-node=true \\
--v=${LOG_LEVEL_KUBELET} ${_kubelet_opts}"
EOF

  cat <<EOF >/etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Install]
WantedBy=multi-user.target

[Service]
Restart=on-failure
RestartSec=5
WorkingDirectory=/var/lib/kubelet
EnvironmentFile=/etc/default/path
EnvironmentFile=/etc/default/kubelet
ExecStart=/opt/bin/kubelet \$KUBELET_OPTS
EOF

  debug "enabling kubelet.service"
  systemctl -l enable kubelet.service || \
    { error "failed to enable kubelet.service"; return; }

  debug "starting kubelet.service"
  systemctl -l start kubelet.service || \
    { error "failed to start kubelet.service"; return; }

  debug "installed kubelet"
}

install_kube_proxy() {
  info "installing kube-proxy"

#  cat <<EOF > /var/lib/kube-proxy/kube-proxy-config.yaml
#kind: KubeProxyConfiguration
#apiVersion: kubeproxy.config.k8s.io/v1alpha1
#clientConnection:
#  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
#mode: "iptables"
#clusterCIDR: "${CLUSTER_CIDR}"
#EOF

  cat <<EOF >/etc/default/kube-proxy
KUBE_PROXY_OPTS="--cluster-cidr='${CLUSTER_CIDR}' \\
--kubeconfig='/var/lib/kube-proxy/kubeconfig' \\
--proxy-mode='iptables' \\
--v=${LOG_LEVEL_KUBE_PROXY}"
EOF

  cat <<EOF >/etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes
After=kubelet.service
Requires=kubelet.service

[Install]
WantedBy=multi-user.target

[Service]
Restart=on-failure
RestartSec=5
WorkingDirectory=/var/lib/kube-proxy
EnvironmentFile=/etc/default/kube-proxy
ExecStart=/opt/bin/kube-proxy \$KUBE_PROXY_OPTS
EOF

  debug "enabling kube-proxy.service"
  systemctl -l enable kube-proxy.service || \
    { error "failed to enable kube-proxy.service"; return; }

  debug "starting kube-proxy.service"
  systemctl -l start kube-proxy.service || \
    { error "failed to start kube-proxy.service"; return; }

  debug "installed kube-proxy"
}

fetch_tls() {
  etcdctl get --print-value-only "${1}" >"${3}" || \
    { error "failed to write '${1}' to '${3}'"; return; }
  etcdctl get --print-value-only "${2}" >"${4}" || \
    { error "failed to write '${2}' to '${4}'"; return; }
  { chmod 0444 "${3}" && chmod 0400 "${4}"; } || \
    { error "failed to chmod '${3}' & '${4}'"; return; }
  { chown root:root "${3}" "${4}"; } || \
    { error "failed to chown '${3}' & '${4}'"; return; }
}

fetch_kubeconfig() {
  etcdctl get --print-value-only "${1}" >"${2}" || \
    { error "failed to write '${1}' to '${2}'"; return; }
  chmod 0400 "${2}" || { error "failed to chmod '${2}'"; return; } 
  chown root:root "${2}" || { error "failed to chown '${2}'"; return; } 
}

# Generates or fetches assets that are shared between multiple 
# controller/worker nodes.
generate_or_fetch_shared_kubernetes_assets() {
  # The key prefix for shared assets.
  shared_assets_prefix="/sk8/shared"

  # Stores the name of the node that generates the shared assets.
  init_node_key="${shared_assets_prefix}/init-node"

  # The keys for the cert/key pairs.
  shared_tls_prefix="${shared_assets_prefix}/tls"
  shared_tls_apiserver_crt_key="${shared_tls_prefix}/kube-apiserver.crt"
  shared_tls_apiserver_key_key="${shared_tls_prefix}/kube-apiserver.key"
  shared_tls_svc_accts_crt_key="${shared_tls_prefix}/service-accounts.crt"
  shared_tls_svc_accts_key_key="${shared_tls_prefix}/service-accounts.key"
  shared_tls_kube_proxy_crt_key="${shared_tls_prefix}/kube-proxy.crt"
  shared_tls_kube_proxy_key_key="${shared_tls_prefix}/kube-proxy.key"

  # The key for the encryption key.
  shared_enc_key_key="${shared_assets_prefix}/encryption.key"

  # The keys for the kubeconfigs.
  shared_kfg_prefix="${shared_assets_prefix}/kfg"
  shared_kfg_admin_key="${shared_kfg_prefix}/k8s-admin"
  shared_kfg_public_admin_key="${shared_kfg_prefix}/public-k8s-admin"
  shared_kfg_controller_manager_key="${shared_kfg_prefix}/kube-controller-manager"
  shared_kfg_scheduler_key="${shared_kfg_prefix}/kube-scheduler"
  shared_kfg_kube_proxy_key="${shared_kfg_prefix}/kube-proxy"

  # Create the directories where the shared assets are generated or into
  # which the shared assets are fetched.
  mkdir -p /var/lib/kubernetes \
           /var/lib/kube-apiserver \
           /var/lib/kube-controller-manager \
           /var/lib/kube-scheduler \
           /var/lib/kube-proxy

  # Check to see if the init routine has already run on another node.
  name_of_init_node=$(etcdctl get --print-value-only "${init_node_key}") || \
    { error "failed to get name of init node"; return; }

  if [ -n "${name_of_init_node}" ]; then
    info "shared assets already generated on ${name_of_init_node}"

    # Fetch shared controller assets.
    if [ ! "${NODE_TYPE}" = "worker" ]; then
      debug "fetching shared kube-apiserver cert/key pair"
      fetch_tls "${shared_tls_apiserver_crt_key}" \
                "${shared_tls_apiserver_key_key}" \
                /etc/ssl/kube-apiserver.crt \
                /etc/ssl/kube-apiserver.key || \
        { error "failed to fetch shared kube-apiserver cert/key pair"; return; }

      debug "fetching shared service accounts cert/key pair"
      fetch_tls "${shared_tls_svc_accts_crt_key}" \
                "${shared_tls_svc_accts_key_key}" \
                /etc/ssl/k8s-service-accounts.crt \
                /etc/ssl/k8s-service-accounts.key || \
        { error "failed to fetch shared service accounts cert/key pair"; return; }

      debug "fetching shared k8s-admin kubeconfig"
      fetch_kubeconfig "${shared_kfg_admin_key}" \
                       /var/lib/kubernetes/kubeconfig || \
        { error "failed to fetch shared k8s-admin kubeconfig"; return; }

      # Grant access to the admin kubeconfig to users belonging to the
      # "k8s-admin" group.
      chmod 0440 /var/lib/kubernetes/kubeconfig || \
        { error "failed to chmod /var/lib/kubernetes/kubeconfig"; return; }
      chown root:k8s-admin /var/lib/kubernetes/kubeconfig || \
        { error "failed to chown /var/lib/kubernetes/kubeconfig"; return; }

      debug "fetching shared kube-controller-manager kubeconfig"
      fetch_kubeconfig "${shared_kfg_controller_manager_key}" \
                       /var/lib/kube-controller-manager/kubeconfig || \
        { error "failed to fetch shared kube-controller-manager kubeconfig"; return; }

      debug "fetching shared kube-scheduler kubeconfig"
      fetch_kubeconfig "${shared_kfg_scheduler_key}" \
                       /var/lib/kube-scheduler/kubeconfig || \
        { error "failed to fetch shared kube-scheduler kubeconfig"; return; }

      debug "fetching shared encryption key"
      etcdctl get "${shared_enc_key_key}" --print-value-only > \
        /var/lib/kubernetes/encryption-config.yaml || \
        { error "failed to fetch shared encryption key"; return; }
    fi

    # Fetch shared worker assets.
    if [ ! "${NODE_TYPE}" = "controller" ]; then
      debug "fetching shared kube-proxy cert/key pair"
      fetch_tls "${shared_tls_kube_proxy_crt_key}" \
                "${shared_tls_kube_proxy_key_key}" \
                /etc/ssl/kube-proxy.crt \
                /etc/ssl/kube-proxy.key || \
        { error "failed to fetch shared kube-proxy cert/key pair"; return; }

      debug "fetching shared kube-proxy kubeconfig"
      fetch_kubeconfig "${shared_kfg_kube_proxy_key}" \
                       /var/lib/kube-proxy/kubeconfig || \
        { error "failed to fetch shared kube-proxy kubeconfig"; return; }
    fi

    info "fetched all shared assets from ${name_of_init_node}" && return
  fi

  # At this point the lock has been obtained and it's known that no other
  # node has run the initialization routine.
  info "generating shared asssets"

  # Indicate that the init process is running on this node.
  put_string "${init_node_key}" "${HOST_FQDN}" || \
    { error "failed to put ${init_node_key}=${HOST_FQDN}"; return; }

  debug "generating shared kube-apiserver x509 cert/key pair"
  kube_apiserver_san_ip="127.0.0.1 ${SERVICE_IPV4_ADDRESS} ${CONTROLLER_IPV4_ADDRESSES}"
  kube_apiserver_san_dns="localhost ${CLUSTER_FQDN} ${SERVICE_FQDN} ${SERVICE_NAME}.default"
  if [ -n "${EXTERNAL_FQDN}" ]; then
    # TODO Figure out how to parse "host EXTERNAL_FQDN" in case it returns
    #      multiple IP addresses.
    kube_apiserver_san_ip="${kube_apiserver_san_ip}"
    kube_apiserver_san_dns="${kube_apiserver_san_dns} ${EXTERNAL_FQDN}"
  fi
  (TLS_KEY_OUT=/etc/ssl/kube-apiserver.key \
    TLS_CRT_OUT=/etc/ssl/kube-apiserver.crt \
    TLS_SAN_IP="${kube_apiserver_san_ip}" \
    TLS_SAN_DNS="${kube_apiserver_san_dns}" \
    TLS_COMMON_NAME="${CLUSTER_ADMIN}" \
    new_cert) || \
    { error "failed to generate shared kube-apiserver x509 cert/key pair"; return; }

  debug "generating shared k8s-admin x509 cert/key pair"
  (TLS_KEY_OUT=/etc/ssl/k8s-admin.key \
    TLS_CRT_OUT=/etc/ssl/k8s-admin.crt \
    TLS_SAN=false \
    TLS_ORG_NAME="system:masters" \
    TLS_COMMON_NAME="admin" \
    new_cert) || \
    { error "failed to generate shared k8s-admin x509 cert/key pair"; return; }

  debug "generating shared kube-controller-manager x509 cert/key pair"
  (TLS_KEY_OUT=/etc/ssl/kube-controller-manager.key \
    TLS_CRT_OUT=/etc/ssl/kube-controller-manager.crt \
    TLS_SAN=false \
    TLS_ORG_NAME="system:kube-controller-manager" \
    TLS_COMMON_NAME="system:kube-controller-manager" \
    new_cert) || \
    { error "failed to generate shared kube-controller-manager x509 cert/key pair"; return; }

  debug "generating shared kube-scheduler x509 cert/key pair"
  (TLS_KEY_OUT=/etc/ssl/kube-scheduler.key \
    TLS_CRT_OUT=/etc/ssl/kube-scheduler.crt \
    TLS_SAN=false \
    TLS_ORG_NAME="system:kube-scheduler" \
    TLS_COMMON_NAME="system:kube-scheduler" \
    new_cert) || \
    { error "failed to generate shared kube-scheduler x509 cert/key pair"; return; }

  debug "generating shared k8s-service-accounts x509 cert/key pair"
  (TLS_KEY_OUT=/etc/ssl/k8s-service-accounts.key \
    TLS_CRT_OUT=/etc/ssl/k8s-service-accounts.crt \
    TLS_SAN=false \
    TLS_COMMON_NAME="service-accounts" \
    new_cert) || \
    { error "failed to generate shared k8s-service-accounts x509 cert/key pair"; return; }

  debug "generating shared kube-proxy x509 cert/key pair"
  (TLS_KEY_OUT=/etc/ssl/kube-proxy.key \
    TLS_CRT_OUT=/etc/ssl/kube-proxy.crt \
    TLS_SAN=false \
    TLS_ORG_NAME="system:node-proxier" \
    TLS_COMMON_NAME="system:kube-proxy" \
    new_cert) || \
    { error "failed to generate shared kube-proxy x509 cert/key pair"; return; }

  debug "generating shared k8s-admin kubeconfig"
  (KFG_FILE_PATH=/var/lib/kubernetes/kubeconfig \
    KFG_USER=admin \
    KFG_TLS_CRT=/etc/ssl/k8s-admin.crt \
    KFG_TLS_KEY=/etc/ssl/k8s-admin.key \
    KFG_GID=k8s-admin \
    KFG_PERM=0440 \
    KFG_SERVER="https://127.0.0.1:${SECURE_PORT}" \
    new_kubeconfig) || \
    { error "failed to generate shared k8s-admin kubeconfig"; return; }

  debug "generating shared public k8s-admin kubeconfig"
  (KFG_FILE_PATH=/var/lib/kubernetes/public.kubeconfig \
    KFG_USER=admin \
    KFG_TLS_CRT=/etc/ssl/k8s-admin.crt \
    KFG_TLS_KEY=/etc/ssl/k8s-admin.key \
    new_kubeconfig) || \
    { error "failed to generate shared public k8s-admin kubeconfig"; return; }

  debug "generating shared kube-scheduler kubeconfig"
  (KFG_FILE_PATH=/var/lib/kube-scheduler/kubeconfig \
    KFG_USER="system:kube-scheduler" \
    KFG_TLS_CRT=/etc/ssl/kube-scheduler.crt \
    KFG_TLS_KEY=/etc/ssl/kube-scheduler.key \
    KFG_SERVER="https://127.0.0.1:${SECURE_PORT}" \
    new_kubeconfig) || \
    { error "failed to generate shared kube-scheduler kubeconfig"; return; }

  debug "generating shared kube-controller-manager kubeconfig"
  (KFG_FILE_PATH=/var/lib/kube-controller-manager/kubeconfig \
    KFG_USER="system:kube-controller-manager" \
    KFG_TLS_CRT=/etc/ssl/kube-controller-manager.crt \
    KFG_TLS_KEY=/etc/ssl/kube-controller-manager.key \
    KFG_SERVER="https://127.0.0.1:${SECURE_PORT}" \
    KFG_PERM=0644 \
    new_kubeconfig) || \
    { error "failed to generate shared kube-controller-manager kubeconfig"; return; }

  debug "generating shared kube-proxy kubeconfig"
  (KFG_FILE_PATH=/var/lib/kube-proxy/kubeconfig \
    KFG_USER="system:kube-proxy" \
    KFG_TLS_CRT=/etc/ssl/kube-proxy.crt \
    KFG_TLS_KEY=/etc/ssl/kube-proxy.key \
    new_kubeconfig) || \
    { error "failed to generate shared kube-proxy kubeconfig"; return; }

  debug "generating shared encryption-config"
  cat <<EOF >/var/lib/kubernetes/encryption-config.yaml
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF

  # Store the cert/key pairs on the etcd server.
  put_file "${shared_tls_apiserver_crt_key}"  /etc/ssl/kube-apiserver.crt || return
  put_file "${shared_tls_apiserver_key_key}"  /etc/ssl/kube-apiserver.key || return
  put_file "${shared_tls_svc_accts_crt_key}"  /etc/ssl/k8s-service-accounts.crt || return
  put_file "${shared_tls_svc_accts_key_key}"  /etc/ssl/k8s-service-accounts.key || return
  put_file "${shared_tls_kube_proxy_crt_key}" /etc/ssl/kube-proxy.crt || return
  put_file "${shared_tls_kube_proxy_key_key}" /etc/ssl/kube-proxy.key || return

  # Store the kubeconfigs on the etcd server.
  put_file "${shared_kfg_admin_key}"              /var/lib/kubernetes/kubeconfig || return
  put_file "${shared_kfg_public_admin_key}"       /var/lib/kubernetes/public.kubeconfig || return
  put_file "${shared_kfg_controller_manager_key}" /var/lib/kube-controller-manager/kubeconfig || return
  put_file "${shared_kfg_scheduler_key}"          /var/lib/kube-scheduler/kubeconfig || return
  put_file "${shared_kfg_kube_proxy_key}"         /var/lib/kube-proxy/kubeconfig || return

  # Store the encryption key on the etcd server.
  put_file "${shared_enc_key_key}" /var/lib/kubernetes/encryption-config.yaml || return

  # Remove the certificates that are no longer needed once the kubeconfigs
  # have been generated.
  if [ "${NODE_TYPE}" = "controller" ]; then
    rm -fr /var/lib/kube-proxy
    rm -f  /etc/ssl/kube-proxy.*
  elif [ "${NODE_TYPE}" = "worker" ]; then
    rm -fr /var/lib/kube-apiserver
    rm -fr /var/lib/kube-controller-manager
    rm -fr /var/lib/kube-scheduler
    rm -f  /var/lib/kubernetes/kubeconfig
    rm -f  /var/lib/kubernetes/encryption-config.yaml
  fi
  rm -f /var/lib/kubernetes/public.kubeconfig
  rm -f /etc/ssl/k8s-admin.*
  rm -f /etc/ssl/kube-controller-manager.*
  rm -f /etc/ssl/kube-scheduler.*
}

wait_until_kube_apiserver_is_online() {
  retry_until_0 \
    "try to connect to cluster with kubectl" \
    kubectl get cs || return
  retry_until_0 \
    "ensure that the kube-system namespaces exists" \
    kubectl get namespace kube-system || return
  retry_until_0 \
    "ensure that ClusterRoles are available" \
    kubectl get ClusterRole.v1.rbac.authorization.k8s.io || return
  retry_until_0 \
    "ensure that ClusterRoleBindings are available" \
    kubectl get ClusterRoleBinding.v1.rbac.authorization.k8s.io || return
}

# Configures kubernetes to use RBAC.
apply_rbac() {
  [ "${NODE_TYPE}" = "worker" ] && return

  info "configuring kubernetes RBAC"

  # Stores the name of the node that configures rbac.
  init_rbac_key="/sk8/init-rbac"

  # Check to see if the init routine has already run on another node.
  name_of_init_node=$(etcdctl get --print-value-only "${init_rbac_key}") || \
    { error "failed to get name of init node for kubernetes RBAC"; return; }

  if [ -n "${name_of_init_node}" ]; then
    info "kubernetes RBAC has already been configured from node ${name_of_init_node}"
    return
  fi

  # Let other nodes know that this node has configured RBAC.
  put_string "${init_rbac_key}" "${HOST_FQDN}" || \
    { error "error configuring kubernetes RBAC"; return; }

  # Create the system:kube-apiserver-to-kubelet ClusterRole with 
  # permissions to access the Kubelet API and perform most common tasks 
  # associated with managing pods.
  cat <<EOF >/var/lib/kubernetes/create-cluster-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
EOF

  debug "configure kubernetes RBAC - creating ClusterRole"
  kubectl apply -f /var/lib/kubernetes/create-cluster-role.yaml || \
    { error "failed to configure kubernetes RBAC - create ClusterRole"; return; }

  # Bind the system:kube-apiserver-to-kubelet ClusterRole to the 
  # kubernetes user:
cat <<EOF >/var/lib/kubernetes/bind-cluster-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: ${CLUSTER_ADMIN}
EOF

  debug "configure kubernetes RBAC - binding ClusterRole"
  kubectl apply -f /var/lib/kubernetes/bind-cluster-role.yaml || \
    { error "failed to configure kubernetes RBAC - bind ClusterRole"; return; }

  debug "kubernetes RBAC has been configured"
}

# Configures kubernetes to use CoreDNS for service DNS resolution.
apply_service_dns_with_coredns() {
  info "configuring kubernetes service DNS with CoreDNS"

  # Reverse the service CIDR and remove the subnet notation so the
  # value can be used as for reverse DNS lookup.
  rev_service_cidr="$(reverse_ipv4_address "${SERVICE_CIDR}")"
  ipv4_inaddr_arpa="${rev_service_cidr}.in-addr.arpa"
  debug "service dns ipv4 inaddr arpa=${ipv4_inaddr_arpa}"

  # Write the podspec to disk.
  debug "writing service DNS podspec"
  cat <<EOF >/var/lib/kubernetes/kube-dns-podspec.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: coredns
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:coredns
rules:
- apiGroups:
  - ""
  resources:
  - endpoints
  - services
  - pods
  - namespaces
  verbs:
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:coredns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:coredns
subjects:
- kind: ServiceAccount
  name: coredns
  namespace: kube-system
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health
        kubernetes ${SERVICE_DOMAIN} ${ipv4_inaddr_arpa} ip6.arpa {
          pods insecure
          upstream
          fallthrough ${ipv4_inaddr_arpa} ip6.arpa
        }
        prometheus :9153
        proxy . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: coredns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    kubernetes.io/name: "CoreDNS"
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  selector:
    matchLabels:
      k8s-app: kube-dns
  template:
    metadata:
      labels:
        k8s-app: kube-dns
    spec:
      serviceAccountName: coredns
      tolerations:
        - key: node-role.kubernetes.io/master
          effect: NoSchedule
        - key: "CriticalAddonsOnly"
          operator: "Exists"
      containers:
      - name: coredns
        image: coredns/coredns:1.2.2
        imagePullPolicy: IfNotPresent
        resources:
          limits:
            memory: 170Mi
          requests:
            cpu: 100m
            memory: 70Mi
        args: [ "-conf", "/etc/coredns/Corefile" ]
        volumeMounts:
        - name: config-volume
          mountPath: /etc/coredns
          readOnly: true
        ports:
        - containerPort: 53
          name: dns
          protocol: UDP
        - containerPort: 53
          name: dns-tcp
          protocol: TCP
        - containerPort: 9153
          name: metrics
          protocol: TCP
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            add:
            - NET_BIND_SERVICE
            drop:
            - all
          readOnlyRootFilesystem: true
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
      dnsPolicy: Default
      volumes:
        - name: config-volume
          configMap:
            name: coredns
            items:
            - key: Corefile
              path: Corefile
---
apiVersion: v1
kind: Service
metadata:
  name: kube-dns
  namespace: kube-system
  annotations:
    prometheus.io/port: "9153"
    prometheus.io/scrape: "true"
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    kubernetes.io/name: "CoreDNS"
spec:
  selector:
    k8s-app: kube-dns
  clusterIP: ${SERVICE_DNS_IPV4_ADDRESS}
  ports:
  - name: dns
    port: 53
    protocol: UDP
  - name: dns-tcp
    port: 53
    protocol: TCP
EOF

  debug "configured kubernetes service DNS with CoreDNS"
}

# Configures kubernetes to use kube-dns for service DNS resolution.
apply_service_dns_with_kube_dns() {
  info "configuring kubernetes service DNS with kube-dns"

  cat <<EOF >/var/lib/kubernetes/kube-dns-podspec.yaml
# Copyright 2016 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
apiVersion: v1
kind: Service
metadata:
  name: kube-dns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
    kubernetes.io/name: "KubeDNS"
spec:
  selector:
    k8s-app: kube-dns
  clusterIP: ${SERVICE_DNS_IPV4_ADDRESS}
  ports:
  - name: dns
    port: 53
    protocol: UDP
  - name: dns-tcp
    port: 53
    protocol: TCP
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kube-dns
  namespace: kube-system
  labels:
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-dns
  namespace: kube-system
  labels:
    addonmanager.kubernetes.io/mode: EnsureExists
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: kube-dns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
spec:
  # replicas: not specified here:
  # 1. In order to make Addon Manager do not reconcile this replicas parameter.
  # 2. Default is 1.
  # 3. Will be tuned in real time if DNS horizontal auto-scaling is turned on.
  strategy:
    rollingUpdate:
      maxSurge: 10%
      maxUnavailable: 0
  selector:
    matchLabels:
      k8s-app: kube-dns
  template:
    metadata:
      labels:
        k8s-app: kube-dns
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ''
    spec:
      tolerations:
      - key: "CriticalAddonsOnly"
        operator: "Exists"
      volumes:
      - name: kube-dns-config
        configMap:
          name: kube-dns
          optional: true
      containers:
      - name: kubedns
        image: gcr.io/google_containers/k8s-dns-kube-dns-amd64:1.14.7
        resources:
          # TODO: Set memory limits when we've profiled the container for large
          # clusters, then set request = limit to keep this container in
          # guaranteed class. Currently, this container falls into the
          # "burstable" category so the kubelet doesn't backoff from restarting it.
          limits:
            memory: 170Mi
          requests:
            cpu: 100m
            memory: 70Mi
        livenessProbe:
          httpGet:
            path: /healthcheck/kubedns
            port: 10054
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
        readinessProbe:
          httpGet:
            path: /readiness
            port: 8081
            scheme: HTTP
          # we poll on pod startup for the Kubernetes master service and
          # only setup the /readiness HTTP server once that's available.
          initialDelaySeconds: 3
          timeoutSeconds: 5
        args:
        - --domain=${SERVICE_DOMAIN}.
        - --dns-port=10053
        - --config-dir=/kube-dns-config
        - --v=2
        env:
        - name: PROMETHEUS_PORT
          value: "10055"
        ports:
        - containerPort: 10053
          name: dns-local
          protocol: UDP
        - containerPort: 10053
          name: dns-tcp-local
          protocol: TCP
        - containerPort: 10055
          name: metrics
          protocol: TCP
        volumeMounts:
        - name: kube-dns-config
          mountPath: /kube-dns-config
      - name: dnsmasq
        image: gcr.io/google_containers/k8s-dns-dnsmasq-nanny-amd64:1.14.7
        livenessProbe:
          httpGet:
            path: /healthcheck/dnsmasq
            port: 10054
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
        args:
        - -v=2
        - -logtostderr
        - -configDir=/etc/k8s/dns/dnsmasq-nanny
        - -restartDnsmasq=true
        - --
        - -k
        - --cache-size=1000
        - --no-negcache
        - --log-facility=-
        - --server=/${SERVICE_DOMAIN}/127.0.0.1#10053
        - --server=/in-addr.arpa/127.0.0.1#10053
        - --server=/ip6.arpa/127.0.0.1#10053
        ports:
        - containerPort: 53
          name: dns
          protocol: UDP
        - containerPort: 53
          name: dns-tcp
          protocol: TCP
        # see: https://github.com/kubernetes/kubernetes/issues/29055 for details
        resources:
          requests:
            cpu: 150m
            memory: 20Mi
        volumeMounts:
        - name: kube-dns-config
          mountPath: /etc/k8s/dns/dnsmasq-nanny
      - name: sidecar
        image: gcr.io/google_containers/k8s-dns-sidecar-amd64:1.14.7
        livenessProbe:
          httpGet:
            path: /metrics
            port: 10054
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
        args:
        - --v=2
        - --logtostderr
        - --probe=kubedns,127.0.0.1:10053,${SERVICE_NAME}.default.svc.${SERVICE_DOMAIN},5,SRV
        - --probe=dnsmasq,127.0.0.1:53,${SERVICE_NAME}.default.svc.${SERVICE_DOMAIN},5,SRV
        ports:
        - containerPort: 10054
          name: metrics
          protocol: TCP
        resources:
          requests:
            memory: 20Mi
            cpu: 10m
      dnsPolicy: Default  # Don't use cluster DNS.
      serviceAccountName: kube-dns
EOF

  debug "configured kubernetes service DNS with kube-dns"
}

# Configures kubernetes to use CoreDNS for service DNS resolution.
apply_service_dns() {
  [ "${NODE_TYPE}" = "worker" ] && return

  info "configuring kubernetes service DNS"

  # Stores the name of the node that configures service DNS.
  init_svc_dns_key="/sk8/init-service-dns"

  # Check to see if the init routine has already run on another node.
  name_of_init_node=$(etcdctl get --print-value-only "${init_svc_dns_key}") || \
    { error "failed to get name of init node for kubernetes service DNS"; return; }

  if [ -n "${name_of_init_node}" ]; then
    info "kubernetes service DNS has already been configured from node ${name_of_init_node}"
    return
  fi

  # Let other nodes know that this node has configured service DNS.
  put_string "${init_svc_dns_key}" "${HOST_FQDN}" || 
    { error "error configuring kubernetes service DNS"; return; }

  if [ "${SERVICE_DNS_PROVIDER}" = "coredns" ]; then
    apply_service_dns_with_coredns || \
      { error "failed to write CoreDNS podspec"; return; }
  else
    apply_service_dns_with_kube_dns || \
      { error "failed to write kube-dns podspec"; return; }
  fi

  # Deploy the service DNS podspec.
  kubectl create -f /var/lib/kubernetes/kube-dns-podspec.yaml || \
    { error "failed to configure kubernetes service DNS"; return; }

  debug "configured kubernetes service DNS"
}

apply_ccm_vsphere() {
  cat <<EOF >/var/lib/kubernetes/ccm-vsphere.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cloud-controller-manager
  namespace: kube-system
---
apiVersion: v1
kind: Pod
metadata:
  annotations:
    scheduler.alpha.kubernetes.io/critical-pod: ""
  labels:
    component: cloud-controller-manager
    tier: control-plane
  name: vsphere-cloud-controller-manager
  namespace: kube-system
spec:
  tolerations:
  - key: node.cloudprovider.kubernetes.io/uninitialized
    value: "true"
    effect: NoSchedule
  - key: node-role.kubernetes.io/master
    effect: NoSchedule
  containers:
    - name: vsphere-cloud-controller-manager
      image: ${CLOUD_PROVIDER_IMAGE}
      args:
        - /bin/vsphere-cloud-controller-manager
        - --cloud-config=/etc/cloud/cloud-provider.conf
        - --cloud-provider=vsphere
        - --use-service-account-credentials=true
        - --address=127.0.0.1
        - --leader-elect=false
        - --kubeconfig=/etc/cloud/kubeconfig
        - --v=${LOG_LEVEL_CLOUD_CONTROLLER_MANAGER}
      volumeMounts:
        - mountPath: /etc/ssl/certs
          name: ca-certs-volume
          readOnly: true
        - mountPath: /etc/cloud
          name: cloud-config-volume
          readOnly: true
      resources:
        requests:
          cpu: 200m
  hostNetwork: true
  securityContext:
    runAsUser: 1001
  serviceAccountName: cloud-controller-manager
  volumes:
  - name: ca-certs-volume
    configMap:
      name: ca-certs
  - name: cloud-config-volume
    configMap:
      name: cloud-config
EOF

  # If there are secrets defined and used to pull the
  # cloud provider image then add them to the podspec.
  if [ -n "${CLOUD_PROVIDER_IMAGE_SECRETS}" ]; then
      cat <<EOF >>/var/lib/kubernetes/ccm-vsphere.yaml
  imagePullSecrets:
EOF
    for key in ${CLOUD_PROVIDER_IMAGE_SECRETS}; do
      cat <<EOF >>/var/lib/kubernetes/ccm-vsphere.yaml
    - name: ${key}
EOF
    done
  fi

  # Deploy the podspec.
  kubectl create -f /var/lib/kubernetes/ccm-vsphere.yaml || \
    { error "failed to configure CCM for vSphere"; return; }

  debug "configured CCM for vSphere"
}

apply_ccm_rbac() {
  info "applying CCM RBAC"

  cat <<EOF >/var/lib/kubernetes/ccm-roles.yaml
apiVersion: v1
items:
- apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRole
  metadata:
    name: system:cloud-controller-manager
  rules:
  - apiGroups:
    - ""
    resources:
    - events
    verbs:
    - create
    - patch
    - update
  - apiGroups:
    - ""
    resources:
    - nodes
    verbs:
    - '*'
  - apiGroups:
    - ""
    resources:
    - nodes/status
    verbs:
    - patch
  - apiGroups:
    - ""
    resources:
    - services
    verbs:
    - list
    - patch
    - update
    - watch
  - apiGroups:
    - ""
    resources:
    - serviceaccounts
    verbs:
    - create
    - get
    - list
    - watch
    - update
  - apiGroups:
    - ""
    resources:
    - persistentvolumes
    verbs:
    - get
    - list
    - update
    - watch
  - apiGroups:
    - ""
    resources:
    - endpoints
    verbs:
    - create
    - get
    - list
    - watch
    - update
  - apiGroups:
    - ""
    resources:
    - secrets
    verbs:
    - get
    - list
    - watch
- apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRole
  metadata:
    name: system:cloud-node-controller
  rules:
  - apiGroups:
    - ""
    resources:
    - nodes
    verbs:
    - delete
    - get
    - patch
    - update
    - list
  - apiGroups:
    - ""
    resources:
    - nodes/status
    verbs:
    - patch
  - apiGroups:
    - ""
    resources:
    - events
    verbs:
    - create
    - patch
    - update
- apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRole
  metadata:
    name: system:pvl-controller
  rules:
  - apiGroups:
    - ""
    resources:
    - persistentvolumes
    verbs:
    - get
    - list
    - watch
  - apiGroups:
    - ""
    resources:
    - events
    verbs:
    - create
    - patch
    - update
kind: List
metadata: {}
EOF

  cat <<EOF >/var/lib/kubernetes/ccm-role-bindings.yaml
apiVersion: v1
items:
- apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRoleBinding
  metadata:
    name: system:cloud-node-controller
  roleRef:
    apiGroup: rbac.authorization.k8s.io
    kind: ClusterRole
    name: system:cloud-node-controller
  subjects:
  - kind: ServiceAccount
    name: cloud-node-controller
    namespace: kube-system
- apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRoleBinding
  metadata:
    name: system:pvl-controller
  roleRef:
    apiGroup: rbac.authorization.k8s.io
    kind: ClusterRole
    name: system:pvl-controller
  subjects:
  - kind: ServiceAccount
    name: pvl-controller
    namespace: kube-system
- apiVersion: rbac.authorization.k8s.io/v1
  kind: ClusterRoleBinding
  metadata:
    name: system:cloud-controller-manager
  roleRef:
    apiGroup: rbac.authorization.k8s.io
    kind: ClusterRole
    name: system:cloud-controller-manager
  subjects:
  - kind: ServiceAccount
    name: cloud-controller-manager
    namespace: kube-system
  - kind: User
    name: cloud-controller-manager
kind: List
metadata: {}
EOF

  # Create the CCM roles.
  kubectl create -f /var/lib/kubernetes/ccm-roles.yaml || \
    { error "failed to configure CCM roles"; return; }

  # Create the CCM role bindings.
  kubectl create -f /var/lib/kubernetes/ccm-role-bindings.yaml || \
    { error "failed to configure CCM role bindings"; return; }

  debug "configured CCM RBAC"
}

apply_ccm_configmaps() {
  info "creating CCM configmaps"

  # Create a directory to generate files for the CCM.
  mkdir -p /var/lib/kubernetes/.ccm

  # Copy all of the crt files in the /etc/ssl/certs directory
  # into the CCM directory in order to create a ca-certs
  # config map.
  for f in /etc/ssl/certs/*.crt; do
    rf=$(readlink "${f}") || rf="${f}"
    cp -f "${rf}" /var/lib/kubernetes/.ccm
    debug "adding '${rf}' to ca-certs"
  done

  # Create a config map with all of the host's trusted certs.
  kubectl create configmap ca-certs \
    --from-file=/var/lib/kubernetes/.ccm/ \
    --namespace=kube-system || \
  { error "failed to create ca-certs configmap"; return; }
  debug "created ca-certs configmap"

  # Remove the certs from the CCM directory.
  rm -f /var/lib/kubernetes/.ccm/*.crt

  debug "generating CCM x509 cert/key pair"
  (TLS_KEY_OUT=/var/lib/kubernetes/.ccm/key.pem \
    TLS_CRT_OUT=/var/lib/kubernetes/.ccm/crt.pem \
    TLS_SAN=false \
    TLS_ORG_NAME="system:cloud-controller-manager" \
    TLS_COMMON_NAME="cloud-controller-manager" \
    new_cert) || \
    { error "failed to generate CCM x509 cert/key pair"; return; }

  # Generate the CCM's kubeconfig.
  debug "generating CCM kubeconfig"
  (KFG_FILE_PATH=/var/lib/kubernetes/.ccm/kubeconfig \
    KFG_USER="cloud-controller-manager" \
    KFG_TLS_CRT=/var/lib/kubernetes/.ccm/crt.pem \
    KFG_TLS_KEY=/var/lib/kubernetes/.ccm/key.pem \
    KFG_SERVER="https://${CLUSTER_FQDN}:${SECURE_PORT}" \
    KFG_PERM=0644 \
    new_kubeconfig) || \
    { error "failed to generate CCM kubeconfig"; return; }

  # Remove the CCM's pem files once they've been added to the kubeconfig.
  rm -f /var/lib/kubernetes/.ccm/*.pem

  # Write the cloud-provider config file to disk in order to load
  # it into a configmap.
  if [ -n "${CLOUD_CONFIG}" ]; then
    echo "${CLOUD_CONFIG}" | \
      base64 -d | \
      gzip -d >/var/lib/kubernetes/.ccm/cloud-provider.conf
    debug "created cloud-provider.conf for CCM"
  fi

  # Create a configmap with the CCM's kubeconfig and cloud-provider
  # configuration file.
  kubectl create configmap cloud-config \
    --from-file=/var/lib/kubernetes/.ccm/ \
    --namespace=kube-system || \
  { error "failed to create cloud-config configmap"; return; }
  debug "created cloud-config configmap"

  # Remove the CCM directory.
  rm -fr /var/lib/kubernetes/.ccm

  debug "created config maps for CCM"
}

apply_ccm() {
  [ "${CLOUD_PROVIDER}" = "external" ] || return
  [ "${NODE_TYPE}" = "worker" ] && return

  info "configuring CCM"

  # Stores the name of the node that configures the cloud-provider.
  init_ccm_key="/sk8/init-cloud-provider"

  # Check to see if the init routine has already run on another node.
  name_of_init_node=$(etcdctl get --print-value-only "${init_ccm_key}") || \
    { error "failed to get name of init node for CCM"; return; }

  if [ -n "${name_of_init_node}" ]; then
    info "CCM has already been configured from node ${name_of_init_node}"
    return
  fi

  # Let other nodes know that this node has configured the cloud-provider.
  put_string "${init_ccm_key}" "${HOST_FQDN}" || \
    { error "error configuring CCM"; return; }

  apply_ccm_configmaps || return
  apply_ccm_rbac || return

  # Select the cloud provider.
  case "${CLOUD_PROVIDER_EXTERNAL}" in
    vsphere) apply_ccm_vsphere || return;;
    *) { error "invalid cloud provider=${CLOUD_PROVIDER_EXTERNAL}" 1; return; }
  esac

  debug "configured CCM"
}

apply_manifest() {
  [ "${NODE_TYPE}" = "worker" ] && return

  op_name="manifest-${1}"
  info "applying ${op_name}"

  # Stores the name of the node that applies the manifest.
  init_node_key="/sk8/apply-${op_name}"

  # Check to see if the init routine has already run on another node.
  name_of_init_node=$(etcdctl get --print-value-only "${init_node_key}") || \
    { error "failed to get name of init node for ${op_name}"; return; }

  if [ -n "${name_of_init_node}" ]; then
    info "${op_name} has already been applied on ${name_of_init_node}"
    return
  fi

  # Let other nodes know that this node has run the init routine.
  put_string "${init_node_key}" "${HOST_FQDN}" || \
    { error "error applying ${op_name}"; return; }

  echo "${2}" | base64 -d | gzip -d | kubectl create -f - || \
    { error "error applying ${op_name}"; return; }

  debug "applied ${op_name}"
}

apply_manifest_before_rbac() {
  [ -z "${MANIFEST_YAML_BEFORE_RBAC}" ] || \
    apply_manifest "before-rbac" "${MANIFEST_YAML_BEFORE_RBAC}"
}

apply_manifest_after_rbac_1() {
  [ -z "${MANIFEST_YAML_AFTER_RBAC_1}" ] || \
    apply_manifest "after-rbac-1" "${MANIFEST_YAML_AFTER_RBAC_1}"
}

apply_manifest_after_rbac_2() {
  [ -z "${MANIFEST_YAML_AFTER_RBAC_2}" ] || \
    apply_manifest "after-rbac-2" "${MANIFEST_YAML_AFTER_RBAC_2}"
}

apply_manifest_after_all() {
  [ -z "${MANIFEST_YAML_AFTER_ALL}" ] || \
    apply_manifest "after-all" "${MANIFEST_YAML_AFTER_ALL}"
}

create_k8s_admin_group() {
  getent group k8s-admin >/dev/null 2>&1 || groupadd k8s-admin
}

wait_for_healthy_kubernetes_cluster() {
  info "waiting until the kubernetes control plane is online"
  # Wait until the kubernetes health check reports "ok". After 100 failed 
  # attempts over 5 minutes the script will exit with an error.
  i=1 && while true; do
    if [ "${i}" -gt 100 ]; then
      error "timed out waiting for a healthy kubernetes cluster" 1; return
    fi
    debug "control plane health check attempt: ${i}"
    response=$(${CURL} -sSL "http://${CLUSTER_FQDN}/healthz")
    [ "${response}" = "ok" ] && break
    sleep 3
    i=$((i+1))
  done
  info "kubernetes cluster is healthy"
}

install_kube_apiserver_and_wait_until_its_online() {
  install_kube_apiserver || \
    { error "failed to install kube-apiserver"; return; }

  wait_until_kube_apiserver_is_online || \
    { error "error waiting until kube-apiserver is online"; return; }
}

apply_rbac_and_manifests() {
  apply_manifest_before_rbac || \
    { error "failed to apply manifest-before-rbac"; return; }

  apply_rbac || \
    { error "failed to configure rbac for kubernetes"; return; }

  apply_manifest_after_rbac_1 || \
    { error "failed to apply manifest-after-rbac-1"; return; }

   apply_manifest_after_rbac_2 || \
    { error "failed to apply manifest-after-rbac-2"; return; }
}

install_kubernetes_test() {
  [ "${INSTALL_CONFORMANCE_TESTS}" = "true" ] || return 0

  info "installing e2e conformance tests"

  debug "creating e2e job yaml"
  cat <<EOF >/var/lib/kubernetes/e2e-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: e2e
  namespace: e2e
  labels:
    name: e2e
spec:
  template:
    spec:
      volumes:
      - name: kubectl
        hostPath:
          path: /opt/bin/kubectl
          type: File
      - name: kubeconfig
        secret:
          secretName: kubeconfig
      - name: e2e
        hostPath:
          path: /var/lib/kubernetes/e2e
          type: Directory
      - name: artifacts
        emptyDir: {}
      containers:
      - name: run
        image: gcr.io/kubernetes-conformance-testing/sk8e2e-job
        args:
        - run
        volumeMounts:
        - name: kubectl
          mountPath: /usr/local/bin/kubectl
          readOnly: true
        - name: kubeconfig
          mountPath: /etc/kubernetes
          readOnly: true
        - name: e2e
          mountPath: /var/lib/kubernetes
          readOnly: true
        - name: artifacts
          mountPath: /var/log/kubernetes/e2e
          readOnly: false
      - name: tgz
        image: gcr.io/kubernetes-conformance-testing/sk8e2e-job
        args:
        - tgz
        volumeMounts:
        - name: artifacts
          mountPath: /var/log/kubernetes/e2e
          readOnly: false
      restartPolicy: Never
  backoffLimit: 4
EOF

  # Make sure everyone can read the file.
  chmod 0644 /var/lib/kubernetes/e2e-job.yaml

  # Stores the name of the init node.
  init_node_key="/sk8/e2e"

  # Check to see if the init routine has already run on another node.
  name_of_init_node=$(etcdctl get --print-value-only "${init_node_key}") || \
    { error "failed to get name of init node for e2e"; return; }

  if [ -n "${name_of_init_node}" ]; then
    info "e2e has already been applied on ${name_of_init_node}"
    return
  fi

  # Let other nodes know that this node has run the init routine.
  put_string "${init_node_key}" "${HOST_FQDN}" || \
    { error "error applying e2e"; return; }

  cat <<EOF >/var/lib/kubernetes/e2e-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: e2e
  labels:
    name: e2e
EOF

  # Create the e2e namespace.
  debug "creating e2e namespace"
  kubectl create -f /var/lib/kubernetes/e2e-namespace.yaml || \
    { error "failed to create e2e namespace"; return; }

  debug "fetching shared public k8s-admin kubeconfig"
  fetch_kubeconfig "${shared_kfg_public_admin_key}" \
                   /var/lib/kubernetes/e2e.kubeconfig || \
    { error "failed to fetch e2e kubeconfig"; return; }

  debug "creating e2e secret kubeconfig"
  kubectl create -n e2e secret generic kubeconfig \
    --from-file=kubeconfig=/var/lib/kubernetes/e2e.kubeconfig || \
    { error "failed to create e2e kubeconfig"; return; }
  rm -f /var/lib/kubernetes/e2e.kubeconfig

  debug "installed e2e conformance tests"

  if [ "${RUN_CONFORMANCE_TESTS}" = "true" ]; then
    info "scheduling e2e conformance test job spec"
    kubectl -n e2e create -f /var/lib/kubernetes/e2e-job.yaml || \
      { error "failed to start e2e job"; return; }
    debug "scheduled e2e conformance test job spec"
  fi
}

install_kubernetes() {
  info "installing kubernetes"

  debug "installing the cloud provider"
  install_cloud_provider || \
    { error "failed to install cloud provider"; return; }

  debug "generating or fetching shared kubernetes assets"
  do_with_lock generate_or_fetch_shared_kubernetes_assets || \
    { error "failed to generate or fetch shared kubernetes assets"; return; }

  # If the node isn't explicitly a worker then install the controller bits.
  if [ ! "${NODE_TYPE}" = "worker" ]; then
    info "installing kubernetes control plane components"

    # The rest of this process will be able to use the exported KUBECONFIG.
    export KUBECONFIG=/var/lib/kubernetes/kubeconfig

    # Create a shell profile script so that logged-in users will have
    # KUBECONFIG set to /var/lib/kubernetes/kubeconfig if the user is
    # root or belongs to the k8s-admin group.
    cat <<EOF >/etc/profile.d/k8s-admin.sh
#!/bin/sh
# Set the KUBECONFIG environment variable to point to the admin
# kubeconfig file if the current user is root or belongs to the 
# k8s-admin group.
id | grep -q 'uid=0\\|k8s-admin' && \\
  export KUBECONFIG=/var/lib/kubernetes/kubeconfig
EOF

    debug "creating directories for kubernetes control plane"
    mkdir -p  /var/lib/kubernetes \
              /var/lib/kube-apiserver \
              /var/lib/kube-controller-manager \
              /var/lib/kube-scheduler

    # Installation of the kube-apiserver and waiting until it's online
    # is synchronized in order to keep two control plane nodes from trying
    # to write to etcd at once. When this happens, sometimes one or more
    # of the kube-apiserver processes crash.
    #
    # Please see https://github.com/kubernetes/kubernetes/issues/67367
    # for more information.
    do_with_lock install_kube_apiserver_and_wait_until_its_online || return

    do_with_lock apply_rbac_and_manifests || return

    # Wait until RBAC is configured to install kube-controller-manager,
    # kube-scheduler, and kubernetes-test.
    install_kube_controller_manager || \
      { error "failed to install kube-controller-manager"; return; }
    install_kube_scheduler || \
      { error "failed to install kube-scheduler"; return; }
    do_with_lock install_kubernetes_test || \
      { error "failed to install kubernetes-test"; return; }

    # Deploy CoreDNS to kubernetes for kubernetes service DNS resolution.
    do_with_lock apply_service_dns || \
      { error "failed to configure CoreDNS for kubernetes"; return; }

    if [ "${CLOUD_PROVIDER}" = "external" ]; then
      # Deploy the out-of-tree cloud provider.
      do_with_lock apply_ccm ||
        { error "failed to configure CCM"; return; }
    fi

    do_with_lock apply_manifest_after_all || \
      { error "failed to apply manifest-after-all"; return; }

    debug "installed kubernetes control plane components"
  fi

  # If the node isn't explicitly a controller then install the worker bits.
  if [ ! "${NODE_TYPE}" = "controller" ]; then
    info "installing kubernetes worker components"

    debug "creating directories for kubernetes worker"
    mkdir -p  /var/lib/kubernetes \
              /var/lib/kubelet \
              /var/lib/kube-proxy

    debug "generating kubelet x509 cert/key pair"
    (TLS_KEY_OUT=/etc/ssl/kubelet.key \
      TLS_CRT_OUT=/etc/ssl/kubelet.crt \
      TLS_ORG_NAME="system:nodes" \
      TLS_COMMON_NAME="system:node:${HOST_FQDN}" \
      new_cert) || \
      { error "failed to generate kubelet x509 cert/key pair"; return; }

    debug "generating kubelet kubeconfig"
    (KFG_FILE_PATH=/var/lib/kubelet/kubeconfig \
      KFG_USER="system:node:${HOST_FQDN}" \
      KFG_TLS_CRT=/etc/ssl/kubelet.crt \
      KFG_TLS_KEY=/etc/ssl/kubelet.key \
      new_kubeconfig) || \
      { error "failed to generate kubelet kubeconfig"; return; }

    # Do not start the kubelet until the kubernetes cluster is reporting
    # as healthy.
    wait_for_healthy_kubernetes_cluster || \
      { error "failed while waiting for healthy kubernetes cluster"; return; }

    install_kubelet || \
      { error "failed to install kubelet"; return; }
    install_kube_proxy || \
      { error "failed to install kube-proxy"; return; }

    debug "installed kubernetes worker components"
  fi

  debug "installed kubernetes"
}

create_pod_net_routes() {
  info "creating routes to pod nets on other nodes"

  # Create a jq expression that transforms the node info for
  # all nodes but this one into one or more "ip route add"
  # calls to add routes for pod networks on other nodes.
  jqq='.[] | select (.ipv4_address != "'"${IPV4_ADDRESS}"'") | '
  jqq="${jqq}"'"ip route add \(.pod_cidr) via \(.ipv4_address)"'

  exit_code=0

  # Save the old IFS value
  OLD_IFS="${IFS}"

  # Split on newlines so to parse the output of jq correctly.
  IFS="$(printf '%b_' '\n')"; a="${a%_}"

  # Create and execute one or several commands to add routes to
  # pod networks on other nodes.
  for r in $(etcdctl get /sk8/nodes \
            --print-value-only --prefix | \
            jq -rs "${jqq}"); do
    debug "${r}"
    /bin/sh -c "${r}" || { exit_code="${?}" && break; }
  done
  IFS="${OLD_IFS}"
  if [ "${exit_code}" -ne "0" ]; then
    error "failed to add routes for pod network" "${exit_code}"; return
  fi
  debug "created routes to pod nets on other nodes"
}

install_vcsim_service() {
  # Stores the name of the node on which vcsim is running.
  init_vcsim_key="/sk8/init-vcsim"

  # Check to see if the init routine has already run on another node.
  name_of_init_node=$(etcdctl get --print-value-only "${init_vcsim_key}") || \
    { error "failed to get name of init node for vcsim"; return; }

  if [ -n "${name_of_init_node}" ]; then
    info "vcsim has already been configured from node ${name_of_init_node}"
    VCSIM_FQDN="${name_of_init_node}"
    export GOVC_URL="https://${VCSIM_FQDN}:${VCSIM_PORT}/sdk"
    rm -f "${BIN_DIR}/vcsim"
    return
  fi

  VCSIM_FQDN="${HOST_FQDN}"
  export GOVC_URL="https://${VCSIM_FQDN}:${VCSIM_PORT}/sdk"

  # Let other nodes know that this node us running vcsim.
  put_string "${init_vcsim_key}" "${HOST_FQDN}" || \
    { error "error configuring vcsim"; return; }

  # Create the vcsim user if it doesn't exist.
  if ! getent passwd vcsim >/dev/null 2>&1; then
    debug "creating vcsim user"
    useradd vcsim --home /var/lib/vcsim --no-user-group --system -M || \
      { error "failed to create vcsim user"; return; }
  fi

  # Create the vcsim directories and set their owner to vcsim.
  debug "creating directories for vcsim server"
  mkdir -p /var/lib/vcsim
  chown vcsim /var/lib/vcsim || return

  cat <<EOF >/etc/default/vcsim
VCSIM_OPTS="-vm 0 \\
-httptest.serve 0.0.0.0:${VCSIM_PORT}"

VM_FILE="/var/lib/vcsim/vms"
EOF

  # Create the vcsim systemd service.
  debug "writing vcsim service file=/etc/systemd/system/vcsim.service"
  cat <<EOF > /etc/systemd/system/vcsim.service
[Unit]
Description=vcsim.service
Documentation=https://github.com/vmware/govmomi/tree/master/vcsim
After=network-online.target
Wants=network-online.target

[Install]
WantedBy=multi-user.target

[Service]
Restart=always
RestartSec=10s
LimitNOFILE=40000
TimeoutStartSec=0
NoNewPrivileges=true
PermissionsStartOnly=true
User=vcsim
WorkingDirectory=/var/lib/vcsim
EnvironmentFile=/etc/default/govc
EnvironmentFile=/etc/default/vcsim
ExecStart=/opt/bin/vcsim \$VCSIM_OPTS
ExecStartPost=/var/lib/vcsim/create-vms.sh
EOF

  debug "enabling vcsim service"
  systemctl -l enable vcsim.service || \
    { error "failed to enable vcsim.service"; return; }

  debug "created vcsim service"
}

start_vcsim_service() {
  debug "starting vcsim service"
  systemctl -l start vcsim.service || \
    { error "failed to start vcsim.service"; return; }
}

create_govc_config() {
  # Write the govc configuration.
  cat <<EOF >/etc/default/govc
GOVC_URL="${GOVC_URL}"
GOVC_INSECURE="true"
GOVC_USERNAME="user"
GOVC_PASSWORD="pass"
GOVC_DATACENTER="/DC0"
GOVC_RESOURCE_POOL="/DC0/host/DC0_C0/Resources"
GOVC_DATASTORE="/DC0/datastore/LocalDS_0"
GOVC_FOLDER="/DC0/vm"
GOVC_NETWORK="/DC0/network/VM Network"
EOF
  cat <<EOF > /etc/profile.d/govc.sh
#!/bin/sh
set -o allexport && . /etc/default/govc && set +o allexport
EOF
  # shellcheck disable=SC1091
  set -o allexport && . /etc/default/govc && set +o allexport
}

config_vcsim_as_ccm() {
  if [ "${CLOUD_PROVIDER}" = "vsphere" ]; then
    CLOUD_CONFIG=$(cat <<EOF | gzip -9c | base64 -w0
[Global]
  user               = "user""
  password           = "pass"
  port               = "${VCSIM_PORT}"
  insecure-flag      = "true"
  datacenters        = "DC0"

[VirtualCenter "${VCSIM_FQDN}"]

[Workspace]
  server             = "${VCSIM_FQDN}"
  datacenter         = "DC0"
  folder             = "vm"
  default-datastore  = "LocalDS_0"
  resourcepool-path  = "Resources"

[Disk]
  scsicontrollertype = pvscsi

[Network]
  public-network     = "VM Network"
EOF
)
  else
    CLOUD_CONFIG=$(cat <<EOF | gzip -9c | base64 -w0
[Global]
  secret-name        = "cloud-provider-vsphere-credentials"
  secret-namespace   = "kube-system"
  service-account    = "cloud-controller-manager"
  port               = "${VCSIM_PORT}"
  insecure-flag      = "true"
  datacenters        = "DC0"

[VirtualCenter "${VCSIM_FQDN}"]
EOF
)

    MANIFEST_YAML_AFTER_RBAC_2=$(cat <<EOF | gzip -9c | base64 -w0
apiVersion: v1
kind: Secret
metadata:
  name: cloud-provider-vsphere-credentials
  namespace: kube-system
data:
  ${VCSIM_FQDN}.username: "$(printf '%s' "user" | base64 -w0)"
  ${VCSIM_FQDN}.password: "$(printf '%s' "pass" | base64 -w0)"
EOF
)
    export MANIFEST_YAML_AFTER_RBAC_2
  fi

  export CLOUD_CONFIG
}

config_vcsim_service() {
  info "configuring vcsim service"

  # Use jq to get all of the information about the nodes needed to create the
  # VMs in vcsim.
  etcdctl get /sk8/nodes --sort-by=KEY --prefix --print-value-only | \
    jq -rs '.[] | "\(.host_name),\(.host_fqdn),\(.ipv4_address),\(.mac_address),\(.uuid),\(.serial)"' \
    >/var/lib/vcsim/vms

  cat <<EOF >/var/lib/vcsim/create-vms.sh
#!/bin/sh

set -e
! /bin/sh -c 'set -o pipefail' >/dev/null 2>&1 || set -o pipefail

[ -f "\${VM_FILE}" ] || exit 1

# Wait until the simulator is responding to create the VMs.
while ! ${BIN_DIR}/govc ls >/dev/null 2>&1; do sleep 1; done

while IFS='' read -r vm || [ -n "\${vm}" ]; do
  host_name=\$(echo "\${vm}" | awk -F, '{print \$1}')
  host_fqdn=\$(echo "\${vm}" | awk -F, '{print \$2}')
  ipv4_address=\$(echo "\${vm}" | awk -F, '{print \$3}')
  mac_address=\$(echo "\${vm}" | awk -F, '{print \$4}')
  serial=\$(echo "\${vm}" | awk -F, '{print \$5}')
  uuid=\$(echo "\${vm}" | awk -F, '{print \$6}')

  echo "creating vcsim vm Name=\${host_name} FQDN=\${host_fqdn} IPv4=\${ipv4_address} MAC=\${mac_address} ID=\${uuid} Serial=\${serial}"
  ${BIN_DIR}/govc vm.create -net.address "\${mac_address}" "\${host_name}"
  ${BIN_DIR}/govc vm.change -vm "${GOVC_FOLDER}/\${host_name}" \\
    -e "SET.config.uuid=\${serial}" \\
    -e "SET.summary.config.uuid=\${serial}" \\
    -e "SET.config.instanceUuid=\${uuid}" \\
    -e "SET.summary.config.instanceUuid=\${uuid}" \\
    -e "SET.guest.hostName=\${host_fqdn}" \\
    -e "SET.summary.guest.hostName=\${host_fqdn}" \\
    -e "SET.guest.ipAddress=\${ipv4_address}" \\
    -e "SET.summary.guest.ipAddress=\${ipv4_address}"
done <"\${VM_FILE}"
EOF
  chmod 0755 /var/lib/vcsim/create-vms.sh
}

configure_vcsim() {
  info "configuring vcsim"

  do_with_lock install_vcsim_service \
                         || { error "failed to install vcsim service"; error; }

  # At this point VCSIM_FQDN will equal HOST_FQDN if this is the host
  # running the vCenter simulator.

  config_vcsim_as_ccm    || { error "failed to config vcsim as ccm"; error; }
  create_govc_config     || { error "failed to create govc config"; error; }

  if [ "${VCSIM_FQDN}" = "${HOST_FQDN}" ]; then
    config_vcsim_service || { error "failed to config vcsim service"; error; }
    start_vcsim_service  || { error "failed to start vcsim service"; error; }
  fi

  debug "configured vcsim"
}

################################################################################
##                           Download Binaries                                ##
################################################################################

# This function returns the newest file of a specified type that matches the
# provided pattern.
#
# ARGS
#  $1 The root of the search
#  $2 The type to find
#  $3 The pattern to match
#
# WORKFLOW
#  1. find
#     Do a recursive search of the current directory for all files that
#     match the provided pattern.
#
#  2. file
#     Use the file command to print the matching files' type information.
#
#  3. grep
#     Keep the files that match the provided type.
#
#  4. awk
#     Keep only the file name
#
#  5. tr
#     Replace the newlines in the output with the null character in order to
#     give the list to the xargs program
#
#  6. xargs
#     Treat each element of the file list as an argument to the "ls" command
#
#  7. ls
#     Sort the files in descending order according to their MTIME
#
#  8. head
#     Prints the first element in the list -- the newest file
find_newest() {
  set +e
  _files=$(find "${1}" -name "${3}" -type f -exec file {} \; | \
    { grep -i "${2}" || true; } | \
    awk -F: '{print $1}' | \
    tr '\n' '\0')
  [ -n "${_files}" ] || { set -e && return 0; }
  printf '%s' "${_files}" | xargs -0 ls -1 -t | head -n 1
  set -e
}

file_nt() {
  [ -e "${2}" ] || return 0
  [ -n "$(find -L "${1}" -prune -newer "${2}")" ];
}

strip_file_uri() { echo "${1}" | sed 's~^file://~~'; }

replace_if_newer() {
  _src="${1}"
  _tgt="${BIN_DIR}/$(basename "${_src}")"

  if [ -e "${_src}" ] && file_nt "${_src}" "${_tgt}"; then
    cp -f "${_src}" "${_tgt}"
    info "replacing older ${_tgt} with newer ${_src}"
  fi
}

download_cni_plugins() {
  if [ -f "/opt/bin/cni/loopback" ]; then
    info "already downloaded CNI plug-ins"; return
  fi
  if is_url "${CNI_PLUGINS_VERSION}"; then
    url="${CNI_PLUGINS_VERSION}"
  else
    url=https://github.com/containernetworking/plugins/releases/download
    url="${url}/v${CNI_PLUGINS_VERSION}/cni-plugins-amd64-v${CNI_PLUGINS_VERSION}.tgz"
  fi
  http_ok "${url}" || { error "could not stat ${url}"; return; }
  mkdir -p "${CNI_BIN_DIR}"
  info "downloading ${url}"
  ${CURL} -L "${url}" | tar xzvC "${CNI_BIN_DIR}" || \
    error "failed to download ${url}"
  debug "downloaded ${url}"
}

download_containerd() {
  if [ -f "/opt/bin/containerd" ]; then
    info "already downloaded containerd"; return
  fi
  if is_url "${CONTAINERD_VERSION}"; then
    url="${CONTAINERD_VERSION}"
  else
    url=https://github.com/containerd/containerd/releases/download
    url="${url}/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}.linux-amd64.tar.gz"
  fi
  http_ok "${url}" || { error "could not stat ${url}"; return; }
  info "downloading ${url}"
  ${CURL} -L "${url}" | tar xzvC "${BIN_DIR}" --strip-components=1
  exit_code="${?}" && \
    [ "${exit_code}" -gt "1" ] && \
    { error "failed to download ${url}" "${exit_code}"; return; }
  debug "downloaded ${url}"
  return 0
}

download_coredns() {
  if [ -f "/opt/bin/coredns" ]; then
    info "already downloaded coredns"; return
  fi
  if is_url "${COREDNS_VERSION}"; then
    url="${COREDNS_VERSION}"
  else
    prefix=https://github.com/coredns/coredns/releases/download
    url="${prefix}/v${COREDNS_VERSION}/coredns_${COREDNS_VERSION}_linux_amd64.tgz"
    # Check to see if the CoreDNS artifact uses the old or new filename format.
    # The change occurred with release 1.2.2.
    http_ok "${url}" || \
      url="${prefix}/v${COREDNS_VERSION}/release.coredns_${COREDNS_VERSION}_linux_amd64.tgz"
  fi

  http_ok "${url}" || { error "could not stat ${url}"; return; }
  info "downloading ${url}"
  ${CURL} -L "${url}" | tar xzvC "${BIN_DIR}" || \
    error "failed to download ${url}"
  debug "downloaded ${url}"
}

download_crictl() {
  if [ -f "/opt/bin/crictl" ]; then
    info "already downloaded crictl"; return
  fi
  if is_url "${CRICTL_VERSION}"; then
    url="${CRICTL_VERSION}"
  else
    url=https://github.com/kubernetes-incubator/cri-tools/releases/download
    url="${url}/v${CRICTL_VERSION}/crictl-v${CRICTL_VERSION}-linux-amd64.tar.gz"
  fi
  http_ok "${url}" || { error "could not stat ${url}"; return; }
  info "downloading ${url}"
  ${CURL} -L "${url}" | tar xzvC "${BIN_DIR}" || \
    error "failed to download ${url}"
  debug "downloaded ${url}"
}

download_etcd() {
  if [ -f "/opt/bin/etcd" ]; then
    info "already downloaded etcd"; return
  fi
  if is_url "${ETCD_VERSION}"; then
    url="${ETCD_VERSION}"
  else
    url=https://github.com/etcd-io/etcd/releases/download
    url="${url}/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz"
  fi
  http_ok "${url}" || { error "could not stat ${url}"; return; }
  info "downloading ${url}"
  ${CURL} -L "${url}" | tar xzvC "${BIN_DIR}" \
    --strip-components=1 --wildcards \
    '*/etcd' '*/etcdctl'
  exit_code="${?}" && \
    [ "${exit_code}" -gt "1" ] && \
    { error "failed to download ${url}" "${exit_code}"; return; }
  debug "downloaded ${url}"
  
  # If the node is a worker then it doesn't need to install the etcd server.
  [ "${NODE_TYPE}" = "worker" ] && rm -fr "${BIN_DIR}/etcd"

  return 0
}

download_jq() {
  if [ -f "/opt/bin/jq" ]; then
    info "already downloaded jq"; return
  fi
  if is_url "${JQ_VERSION}"; then
    url="${JQ_VERSION}"
  else
    url=https://github.com/stedolan/jq/releases/download
    url="${url}/jq-${JQ_VERSION}/jq-linux64"
  fi
  http_ok "${url}" || { error "could not stat ${url}"; return; }
  info "downloading ${url}"
  ${CURL} -Lo "${BIN_DIR}/jq" "${url}" || error "failed to download ${url}"
  debug "downloaded ${url}"
}

KUBE_CLIENT_TGZ="kubernetes-client-linux-amd64.tar.gz"
KUBE_NODE_TGZ="kubernetes-node-linux-amd64.tar.gz"
KUBE_SERVER_TGZ="kubernetes-server-linux-amd64.tar.gz"
KUBE_TEST_TGZ="kubernetes-test.tar.gz"

KUBE_DOWNLOAD_DIR=/var/lib/kubernetes/install/remote
KUBE_DOWNLOAD_CLIENT="${KUBE_DOWNLOAD_DIR}/${KUBE_CLIENT_TGZ}"
KUBE_DOWNLOAD_NODE="${KUBE_DOWNLOAD_DIR}/${KUBE_NODE_TGZ}"
KUBE_DOWNLOAD_SERVER="${KUBE_DOWNLOAD_DIR}/${KUBE_SERVER_TGZ}"
KUBE_DOWNLOAD_TEST="${KUBE_DOWNLOAD_DIR}/${KUBE_TEST_TGZ}"

download_kubernetes_client() {
  if [ -f "${BIN_DIR}/kubectl" ]; then
    info "already downloaded kubernetes client"; return
  fi

  # If the Kubernetes artifact prefix begins with "file://" then the
  # bits to install Kubernetes are supposed to be available locally.
  if ! echo "${K8S_ARTIFACT_PREFIX}" | grep -q '^file://'; then
    mkdir -p "${KUBE_DOWNLOAD_DIR}"
    url="${K8S_ARTIFACT_PREFIX}/${KUBE_CLIENT_TGZ}"
    http_ok "${url}" || { error "could not stat ${url}"; return; }
    info "client: downloading ${url}"
    ${CURL} -Lo "${KUBE_DOWNLOAD_CLIENT}" "${url}" || \
      { error "failed to dowload ${url} to ${KUBE_DOWNLOAD_CLIENT}"; return ; }
    _k8s_download_dir="${KUBE_DOWNLOAD_DIR}"
  else
    _k8s_download_dir="$(strip_file_uri "${K8S_ARTIFACT_PREFIX}")"
    info "client: using local bits ${_k8s_download_dir}"
  fi

  _tarball=$(find_newest \
    "${_k8s_download_dir}" gzip "${KUBE_CLIENT_TGZ}") || \
    { error "failed to find client tarball"; return; }
  _kubectl_bin=$(find_newest "${_k8s_download_dir}" elf kubectl) || \
    { error "failed to find client binary: kubectl"; return; }

  # If the tarball exists and it's newer than at least one of the binaries,
  # then inflate the tarball.
  if [ -e "${_tarball}" ] && file_nt "${_tarball}" "${_kubectl_bin}"; then
    tar xzvC "${BIN_DIR}" \
      --strip-components=3 \
      kubernetes/client/bin/kubectl \
      <"${_tarball}"
    exit_code="${?}" && \
      [ "${exit_code}" -gt "1" ] && \
      { error "failed to inflate ${_tarball}" "${exit_code}"; return; }
    info "inflated ${_tarball}"
  fi

  replace_if_newer "${_kubectl_bin}" || \
    { error "failed to replace kubectl"; return; }

  return 0
}

download_kubernetes_node() {
  if [ -f "${BIN_DIR}/kubelet" ] && [ -f "${BIN_DIR}/kube-proxy" ]; then
    info "already downloaded kubernetes node"; return
  fi

  # If the Kubernetes artifact prefix begins with "file://" then the
  # bits to install Kubernetes are supposed to be available locally.
  if ! echo "${K8S_ARTIFACT_PREFIX}" | grep -q '^file://'; then
    mkdir -p "${KUBE_DOWNLOAD_DIR}"
    url="${K8S_ARTIFACT_PREFIX}/${KUBE_NODE_TGZ}"
    http_ok "${url}" || { error "could not stat ${url}"; return; }
    info "node: downloading ${url}"
    ${CURL} -Lo "${KUBE_DOWNLOAD_NODE}" "${url}" || \
      { error "failed to dowload ${url} to ${KUBE_DOWNLOAD_NODE}"; return ; }
    _k8s_download_dir="${KUBE_DOWNLOAD_DIR}"
  else
    _k8s_download_dir="$(strip_file_uri "${K8S_ARTIFACT_PREFIX}")"
    info "node: using local bits ${_k8s_download_dir}"
  fi

  _tarball=$(find_newest \
    "${_k8s_download_dir}" gzip "${KUBE_NODE_TGZ}") || \
    { error "failed to find node tarball"; return; }
  _kubelet_bin=$(find_newest "${_k8s_download_dir}" elf kubelet) || \
    { error "failed to find node binary: kubelet"; return; }
  _kube_proxy_bin=$(find_newest "${_k8s_download_dir}" elf kube-proxy) || \
    { error "failed to find node binary: kube-proxy"; return; }

  # If the tarball exists and it's newer than at least one of the binaries,
  # then inflate the tarball.
  if [ -e "${_tarball}" ] && \
    { file_nt "${_tarball}" "${_kubelet_bin}" || \
      file_nt "${_tarball}" "${_kube_proxy_bin}"; }; then

    tar xzvC "${BIN_DIR}" \
      --strip-components=3 \
      kubernetes/node/bin/kubelet \
      kubernetes/node/bin/kube-proxy \
      <"${_tarball}"
    exit_code="${?}" && \
      [ "${exit_code}" -gt "1" ] && \
      { error "failed to inflate ${_tarball}" "${exit_code}"; return; }
    info "inflated ${_tarball}"
  fi

  replace_if_newer "${_kubelet_bin}" || \
    { error "failed to replace kubelet"; return; }
  replace_if_newer "${_kube_proxy_bin}"  || \
    { error "failed to replace kube-proxy"; return; }

  return 0
}

download_kubernetes_server() {
  if [ -f "${BIN_DIR}/kube-apiserver" ] && \
    [ -f "${BIN_DIR}/kube-controller-manager" ] && \
    [ -f "${BIN_DIR}/kube-scheduler" ]; then
    info "already downloaded kubernetes server"; return
  fi

  # If the Kubernetes artifact prefix begins with "file://" then the
  # bits to install Kubernetes are supposed to be available locally.
  if ! echo "${K8S_ARTIFACT_PREFIX}" | grep -q '^file://'; then
    mkdir -p "${KUBE_DOWNLOAD_DIR}"
    url="${K8S_ARTIFACT_PREFIX}/${KUBE_SERVER_TGZ}"
    http_ok "${url}" || { error "could not stat ${url}"; return; }
    info "server: downloading ${url}"
    ${CURL} -Lo "${KUBE_DOWNLOAD_SERVER}" "${url}" || \
      { error "failed to dowload ${url} to ${KUBE_DOWNLOAD_SERVER}"; return ; }
    _k8s_download_dir="${KUBE_DOWNLOAD_DIR}"
  else
    _k8s_download_dir="$(strip_file_uri "${K8S_ARTIFACT_PREFIX}")"
    info "server: using local bits ${_k8s_download_dir}"
  fi

  _tarball=$(find_newest \
    "${_k8s_download_dir}" gzip "${KUBE_SERVER_TGZ}") || \
    { error "failed to find server tarball"; return; }
  _kube_api_bin=$(find_newest "${_k8s_download_dir}" elf kube-apiserver) || \
    { error "failed to find server binary: kube-apiserver"; return; }
  _kube_ctl_mgr=$(find_newest "${_k8s_download_dir}" elf kube-controller-manager) || \
    { error "failed to find server binary: kube-controller-manager"; return; }
  _kube_scheduler=$(find_newest "${_k8s_download_dir}" elf kube-scheduler) || \
    { error "failed to find server binary: kube-scheduler"; return; }

  # If the tarball exists and it's newer than at least one of the binaries,
  # then inflate the tarball.
  if [ -e "${_tarball}" ] && \
    { file_nt "${_tarball}" "${_kube_api_bin}" || \
      file_nt "${_tarball}" "${_kube_ctl_mgr}" || \
      file_nt "${_tarball}" "${_kube_scheduler}"; }; then

    tar xzvC "${BIN_DIR}" \
      --strip-components=3 \
      kubernetes/server/bin/kube-apiserver \
      kubernetes/server/bin/kube-controller-manager \
      kubernetes/server/bin/kube-scheduler \
      <"${_tarball}"
    exit_code="${?}" && \
      [ "${exit_code}" -gt "1" ] && \
      { error "failed to inflate ${_tarball}" "${exit_code}"; return; }
    info "inflated ${_tarball}"
  fi

  replace_if_newer "${_kube_api_bin}" || \
    { error "failed to replace kube-apiserver"; return; }
  replace_if_newer "${_kube_ctl_mgr}"  || \
    { error "failed to replace kube-controller-manager"; return; }
  replace_if_newer "${_kube_scheduler}"  || \
    { error "failed to replace kube-scheduler"; return; }

  return 0
}

download_kubernetes_test() {
  if [ -e "/var/lib/kubernetes/platforms/linux/amd64/e2e.test" ]; then
    info "already downloaded kubernetes test"; return
  fi

  [ "${INSTALL_CONFORMANCE_TESTS}" = "true" ] || return 0

  # If the Kubernetes artifact prefix begins with "file://" then the
  # bits to install Kubernetes are supposed to be available locally.
  if ! echo "${K8S_ARTIFACT_PREFIX}" | grep -q '^file://'; then
    mkdir -p "${KUBE_DOWNLOAD_DIR}"
    url="${K8S_ARTIFACT_PREFIX}/${KUBE_TEST_TGZ}"
    http_ok "${url}" || { error "could not stat ${url}"; return; }
    info "test: downloading ${url}"
    ${CURL} -Lo "${KUBE_DOWNLOAD_TEST}" "${url}" || \
      { error "failed to dowload ${url} to ${KUBE_DOWNLOAD_TEST}"; return ; }
    _k8s_download_dir="${KUBE_DOWNLOAD_DIR}"
  else
    _k8s_download_dir="$(strip_file_uri "${K8S_ARTIFACT_PREFIX}")"
    info "test: using local bits ${_k8s_download_dir}"
  fi

  _tarball=$(find_newest \
    "${_k8s_download_dir}" gzip "${KUBE_TEST_TGZ}") || \
    { error "failed to find test tarball"; return; }

  tar xzvC "/var/lib" <"${_tarball}" || \
    { error "failed to inflate ${_tarball}" "${exit_code}"; return; }
  info "inflated ${_tarball}"

  return 0
}

download_nginx() {
  if [ -f "/opt/bin/nginx" ]; then
    info "already downloaded nginx"; return
  fi
  if is_url "${NGINX_VERSION}"; then
    url="${NGINX_VERSION}"
  else
    url=http://cnx.vmware.s3.amazonaws.com/cicd/container-linux/nginx
    url="${url}/v${NGINX_VERSION}/nginx.tar.gz"
  fi
  http_ok "${url}" || { error "could not stat ${url}"; return; }
  info "downloading ${url}"
  ${CURL} -L "${url}" | tar xzvC "${BIN_DIR}" || \
    error "failed to download ${url}"
  debug "downloaded ${url}"
}

download_runc() {
  if [ -f "/opt/bin/runc" ]; then
    info "already downloaded runc"; return
  fi
  if is_url "${RUNC_VERSION}"; then
    url="${RUNC_VERSION}"
  else
    url=https://github.com/opencontainers/runc/releases/download
    url="${url}/v${RUNC_VERSION}/runc.amd64"
  fi
  http_ok "${url}" || { error "could not stat ${url}"; return; }
  info "downloading ${url}"
  ${CURL} -Lo "${BIN_DIR}/runc" "${url}" || error "failed to download ${url}"
  debug "downloaded ${url}"
}

download_runsc() {
  if [ -f "/opt/bin/runsc" ]; then
    info "already downloaded runsc"; return
  fi
  if is_url "${RUNSC_VERSION}"; then
    url="${RUNSC_VERSION}"
  else
    url=https://storage.googleapis.com/gvisor/releases/nightly
    url="${url}/${RUNSC_VERSION}/runsc"
  fi
  http_ok "${url}" || { error "could not stat ${url}"; return; }
  info "downloading ${url}"
  ${CURL} -Lo "${BIN_DIR}/runsc" "${url}" || error "failed to download ${url}"
  debug "downloaded ${url}"
}

download_vcsim() {
  if [ -f "/opt/bin/vcsim" ]; then
    info "already downloaded vcsim"; return
  fi
  url=https://s3-us-west-2.amazonaws.com/cnx.vmware/cicd/vcsim_linux_amd64
  ${CURL} -Lo "${BIN_DIR}/vcsim" "${url}" || error "failed to download ${url}"
  debug "downloaded ${url}"
}

download_govc() {
  if [ -f "/opt/bin/govc" ]; then
    info "already downloaded vcsim"; return
  fi
  url=https://s3-us-west-2.amazonaws.com/cnx.vmware/cicd/govc_linux_amd64
  ${CURL} -Lo "${BIN_DIR}/govc" "${url}" || error "failed to download ${url}"
  debug "downloaded ${url}"
}

download_binaries() {
  # Download binaries found on both control-plane and worker nodes.
  download_jq                || { error "failed to download jq"; return; }
  download_etcd              || { error "failed to download etcd"; return; }
  download_kubernetes_client || { error "failed to download kubernetes client"; return; }

  # Check to see if the vCenter simulator is enabled and the cloud provider
  # is set to vSphere.
  if is_vcsim; then
    download_govc  || { error "failed to download govc"; return; }
    download_vcsim || { error "failed to download vcsim"; return; }
  fi

  # Download binaries found only on control-plane nodes.
  if [ ! "${NODE_TYPE}" = "worker" ]; then
    download_kubernetes_server || { error "failed to download kubernetes server"; return; }
    download_nginx             || { error "failed to download nginx"; return; }
    download_coredns           || { error "failed to download coredns"; return; }
  fi

  # Download binaries found only on worker nodes.
  if [ ! "${NODE_TYPE}" = "controller" ]; then
    download_kubernetes_node || { error "failed to download kubernetes node"; return; }
    download_kubernetes_test || { error "failed to download kubernetes test"; return; }
    download_containerd      || { error "failed to download containerd"; return; }
    download_crictl          || { error "failed to download crictl"; return; }
    download_runc            || { error "failed to download runc"; return; }
    download_runsc           || { error "failed to download runsc"; return; }
    download_cni_plugins     || { error "failed to download cni-plugns"; return; }
  fi

  # Remove all of the potential tarballs created from downloading Kubernetes
  # from remote locations.
  rm -f -- "${KUBE_DOWNLOAD_DIR}"/*

  # Mark all the files in /opt/bin directory:
  # 1. Executable
  # 2. Owned by root:root
  debug 'update perms & owner for files in /opt/bin'
  chmod 0755 -- "${BIN_DIR}"/*
  chown root:root -- "${BIN_DIR}"/*
}

install_packages() {
  # PhotonOS
  if command -v tdnf >/dev/null 2>&1; then
    info "installing packages via tdnf"
    tdnf update --assumeno
    debug "tdnf install lsof bindutils iputils tar"
    tdnf -yq install lsof bindutils iputils tar || true
    if [ ! "${NODE_TYPE}" = "controller" ]; then
      debug "tdnf install socat ipset libnetfilter_conntrack libnetfilter_cthelper libnetfilter_cttimeout libnetfilter_queue"
      tdnf -yq install socat ipset \
        libnetfilter_conntrack libnetfilter_cthelper \
        libnetfilter_cttimeout libnetfilter_queue || true
      debug "rpm -ivh conntrack-tools"
      rpm -ivh https://dl.bintray.com/vmware/photon_updates_2.0_x86_64/x86_64/conntrack-tools-1.4.5-1.ph2.x86_64.rpm || \
        { error "failed to install conntrack-tools"; return; }
    fi
    debug "installed packages via tdnf"
  # RedHat/CentOS
  elif command -v yum >/dev/null 2>&1; then
    info "installing packages via yum"
    yum update --assumeno
    debug "yum install lsof bind-utils"
    yum -y install lsof bind-utils || true
    if [ ! "${NODE_TYPE}" = "controller" ]; then
      debug "yum install socat conntrack-tools ipset"
      yum -y install socat conntrack-tools ipset || true
    fi
    debug "installed packages via yum"
  # Debian/Ubuntu
  elif command -v apt-get >/dev/null 2>&1; then
    info "installing packages via apt-get"
    apt-get update
    debug "apt-get install lsof dnsutils"
    apt-get -y install lsof dnsutils || true
    if [ ! "${NODE_TYPE}" = "controller" ]; then
      debug "apt-get install socat conntrack ipset"
      apt-get -y install socat conntrack ipset
    fi
    debug "installed packages via apt-get"
  fi
}

wait_for_network() {
  retry_until_0 "waiting for network" ping -c1 www.google.com
}

init_k8s_artifact_prefix() {
  K8S_ARTIFACT_PREFIX="$(get_k8s_artifacts_url "${K8S_VERSION}")" ||
    error "failed to init k8s artifact prefix from '${K8S_VERSION}'"
}

################################################################################
##                        main(int argc, char *argv[])                        ##
################################################################################

# Writes /etc/default/path and /etc/profile.d/path.sh to make a sane,
# default path accessible by services and shells.
configure_path || fatal "failed to configure path"

# Creates /opt/bin/node-type to make discovery the node type very easy.
create_node_type_cmd || fatal "failed to create node-type command"

# Writes /etc/profile.d/prompt.sh to provide shells with a sane prompt.
configure_prompt || fatal "failed to configure prompt"

# Waits for the network to fully come online.
wait_for_network || fatal "failed to wait for network"

# Install distribution package dependencies. Uses yum or apt-get, whichever
# is available, to install socat and conntrack if either are not in the
# current path.
install_packages || fatal "failed to install packages"

# Initalize the kubernetes artifact prefix. This sets the global
# variable K8S_ARTIFACT_PREFIX to the URL from which to download the
# kubernetes artifacts. The artifact prefix is determined by parsing
# K8S_VERSION.
init_k8s_artifact_prefix || fatal "failed to init k8s artifact prefix"

# Download the binaries before doing almost anything else.
download_binaries || fatal "failed to download binaries"

# Creates the k8s-admin group if it does not exist.
create_k8s_admin_group || fatal "failed to create the k8s-admin group"

# Configure iptables.
configure_iptables || fatal "failed to configure iptables"

# If this host used NetworkManager then this step will keep NetworkManager
# from stomping on the contents of /etc/resolv.conf upon reboot.
disable_net_man_dns || fatal "failed to disable network manager dns"

# Installs the CA files to their configured locations.
install_ca_files || fatal "failed to install CA files"

# The etcd service and its certificates are only applicable on nodes
# participating in the control plane.
if [ ! "${NODE_TYPE}" = "worker" ]; then
  # Makes the directories used by etcd, generates the certs for etcd,
  # and installs and starts the etcd service.
  install_etcd || fatal "failed to install etcd"
fi

# Uses the etcd discovery URL to wait until all members of the etcd
# cluster have joined. Then the members' IPv4 addresses are recorded
# and used later in this script.
discover_etcd_cluster_members || fatal "failed to discover etcd cluster members"

# Generates the certs for etcdctl and creates the defaults and profile
# files for etcdctl to make it easily usable by root and members of k8s-admin.
configure_etcdctl || fatal "failed to configure etcdctl"

# Grants a lease that is associated with all keys added to etcd by this script.
do_with_lock grant_etcd_lease || fatal "failed to grant etcd lease"

# Records information about this node in etcd so that other nodes
# in the cluster can use the information. This function also builds
# the pod cidr for this node.
do_with_lock put_node_info || fatal "failed to put node info"

# Waits until all nodes have stored their information in etcd.
# After this step all node information should be available at
# the key prefix '/sk8/nodes'.
wait_on_all_node_info || fatal "failed to wait on all node info"

# Prints the information for each of the discovered nodes.
print_all_node_info || fatal "failed to print all node info"

# Creates the DNS entries in etcd that the CoreDNS servers running
# on the controller nodes will use.
create_dns_entries || fatal "failed to create DNS entries in etcd"

# If this host uses systemd-resolved, then this step will disable and
# mask the service. This is so port 53 is available for CoreDNS.
disable_resolved || fatal "failed to disable systemd-resolved"

# CoreDNS should be installed on members of the etcd cluster.
if [ ! "${NODE_TYPE}" = "worker" ]; then
  install_coredns || fatal "failed to install CoreDNS"
fi

# DNS resolution should be handled by the CoreDNS servers installed
# on the controller nodes.
resolve_via_coredns || fatal "failed to resolve via CoreDNS"

# Waits until all the nodes can be resolved by their IP addresses.
wait_on_reverse_lookup || fatal "failed to wait on reverse lookup"

# Configures the vCenter simulator if it is enabled.
if is_vcsim; then
  configure_vcsim || fatal "failed to configure vcsim"
fi

# Enable the bridge module for nodes where pod workloads are scheduled.
if [ ! "${NODE_TYPE}" = "controller" ]; then
  enable_bridge_module || fatal "failed to enable the bridge module"
fi

# Enable IP forwarding so nodes can access pod networks on other nodes.
enable_ip_forwarding || fatal "failed to enable IP forwarding"

# Ensures that this host can send traffic to any of the nodes where
# non-system pods may be scheduled.
create_pod_net_routes || fatal "failed to create pod net routes"

# If this node can schedule pod workloads then it needs CNI plug-ins
# and a container runtime.
if [ ! "${NODE_TYPE}" = "controller" ]; then
  install_cni_plugins || fatal "failed to install cni plug-ins"
  install_containerd  || fatal "failed to install containerd"
fi

# nginx should be installed on control plane nodes.
if [ ! "${NODE_TYPE}" = "worker" ]; then
  install_nginx || fatal "failed to install nginx"
fi

# Installs kubernetes. For controller nodes this installs kube-apiserver,
# kube-controller-manager, and kube-scheduler. For worker nodes this
# installs the kubelet and kube-proxy.
install_kubernetes || fatal "failed to install kubernetes"

info "So long, and thanks for all the fish."
