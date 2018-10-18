#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

#
# Used by the yakity service to write the yakity environment
# file by reading properties from the VMware GuestInfo interface.
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

YAK_DEFAULTS="${YAK_DEFAULTS:-/etc/default/yakity}"

get_config_val() {
  if val="$(rpctool get "yakity.${1}" 2>/dev/null)" && [ -n "${val}" ]; then
    printf 'got config val\n  key = %s\n  src = %s\n' \
      "${1}" "guestinfo.yakity" 1>&2
    echo "${val}"
  elif val="$(rpctool get.ovf "${1}" 2>/dev/null)" && [ -n "${val}" ]; then
    printf 'got config val\n  key = %s\n  src = %s\n' \
      "${1}" "guestinfo.ovfEnv" 1>&2
    echo "${val}"
  fi
}

write_config_val() {
  if [ -n "${2}" ]; then
    printf '%s="%s"\n' "${1}" "${2}" >>"${YAK_DEFAULTS}"
    printf 'set config val\n  key = %s\n' "${1}" 1>&2
  elif val="$(get_config_val "${1}")" && [ -n "${val}" ]; then
    printf '%s="%s"\n' "${1}" "${val}" >>"${YAK_DEFAULTS}"
    printf 'set config val\n  key = %s\n' "${1}" 1>&2
  fi
}

# Check to see if there is an SSH public key to add to the root user.
if val="$(get_config_val SSH_PUB_KEY)" && [ -n "${val}" ]; then
  mkdir -p /root/.ssh; chmod 0700 /root/.ssh
  echo >>/root/.ssh/authorized_keys; chmod 0400 /root/.ssh/authorized_keys
  echo "${val}" >>/root/.ssh/authorized_keys
  echo2 "updated /root/.ssh/authorized_keys"
fi

# Get the PEM-encoded CA.
if val="$(get_config_val TLS_CA_PEM)" && [ -n "${val}" ]; then
  pem="$(mktemp)"
  echo "${val}" | \
    sed -r 's/(-{5}BEGIN [A-Z ]+-{5})/&\n/g; s/(-{5}END [A-Z ]+-{5})/\n&\n/g' | \
    sed -r 's/.{64}/&\n/g; /^\s*$/d' | \
    sed -r '/^$/d' >"${pem}"
  ca_crt_gz="$(openssl x509 2>/dev/null <"${pem}" | gzip -9c | base64 -w0)"
  write_config_val TLS_CA_CRT_GZ "${ca_crt_gz}"
  ca_key_gz="$(openssl rsa 2>/dev/null <"${pem}" | gzip -9c | base64 -w0)"
  write_config_val TLS_CA_KEY_GZ "${ca_key_gz}"
  rm -f "${pem}"
fi

# Check to see if the information necessary to create a cloud provider
# configuration has been specified.
vsphere_server="$(get_config_val VSPHERE_SERVER)"
vsphere_server_port="$(get_config_val VSPHERE_SERVER_PORT)"
vsphere_server_insecure="$(get_config_val VSPHERE_SERVER_INSECURE)"
vsphere_network="$(get_config_val VSPHERE_NETWORK)"
vsphere_username="$(get_config_val VSPHERE_USER)"
vsphere_password="$(get_config_val VSPHERE_PASSWORD)"
vsphere_datacenter="$(get_config_val VSPHERE_DATACENTER)"
vsphere_datastore="$(get_config_val VSPHERE_DATASTORE)"
vsphere_folder="$(get_config_val VSPHERE_FOLDER)"
vsphere_resource_pool="$(get_config_val VSPHERE_RESOURCE_POOL)"
cloud_provider_image="$(get_config_val CLOUD_PROVIDER_IMAGE)"
cloud_provider_external="$(get_config_val CLOUD_PROVIDER_EXTERNAL)"

if [ -n "${vsphere_server}" ] && [ -n "${vsphere_server_port}" ] && \
   [ -n "${vsphere_server_insecure}" ] && [ -n "${vsphere_network}" ] && \
   [ -n "${vsphere_username}" ] && [ -n "${vsphere_password}" ] && \
   [ -n "${vsphere_datacenter}" ] && [ -n "${vsphere_datastore}" ] && \
   [ -n "${vsphere_folder}" ] && [ -n "${vsphere_resource_pool}" ] && \
   [ -n "${cloud_provider_image}" ] && [ -n "${cloud_provider_external}" ]; then

  cloud_conf=/tmp/cloud.config.toml

  # Update the insecure flag based on the expected value.
  echo "${vsphere_server_insecure}" | grep -iq 'false' && \
    vsphere_server_insecure=0 || vsphere_server_insecure=1

  if echo "${cloud_provider_external}" | grep -iq 'false'; then
    echo2 "selected in-tree vSphere cloud provider"

    cloud_provider=vsphere

    cat <<EOF >"${cloud_conf}"
[Global]
  user               = "${vsphere_username}"
  password           = "${vsphere_password}"
  port               = "${vsphere_server_port}"
  insecure-flag      = "${vsphere_server_insecure}"
  datacenters        = "${vsphere_datacenter}"

[VirtualCenter "${vsphere_server}"]

[Workspace]
  server             = "${vsphere_server}"
  datacenter         = "${vsphere_datacenter}"
  folder             = "${vsphere_folder}"
  default-datastore  = "${vsphere_datastore}"
  resourcepool-path  = "${vsphere_resource_pool}"

[Disk]
  scsicontrollertype = pvscsi

[Network]
  public-network     = "${vsphere_network}"
EOF

  else
    echo2 "selected out-of-tree vSphere cloud provider"
    echo2 "  image = ${cloud_provider_image}"

    cloud_provider=external

    cat <<EOF >"${cloud_conf}"
[Global]
  secret-name        = "cloud-provider-vsphere-credentials"
  secret-namespace   = "kube-system"
  service-account    = "cloud-controller-manager"
  port               = "${vsphere_server_port}"
  insecure-flag      = "${vsphere_server_insecure}"
  datacenters        = "${vsphere_datacenter}"

[VirtualCenter "${vsphere_server}"]

[Network]
  public-network     = "${vsphere_network}"
EOF

    secrets_conf=/tmp/cloud-secrets.config.yaml

    cat <<EOF >"${secrets_conf}"
apiVersion: v1
kind: Secret
metadata:
  name: cloud-provider-vsphere-credentials
  namespace: kube-system
data:
  ${vsphere_server}.username: "$(printf '%s' "${vsphere_username}" | base64 -w0)"
  ${vsphere_server}.password: "$(printf '%s' "${vsphere_password}" | base64 -w0)"
EOF

    { printf '%s="%s"\n' \
        "CLOUD_PROVIDER_EXTERNAL" \
        "vsphere"; \
      printf '%s="%s"\n' \
        "CLOUD_PROVIDER_IMAGE" \
          "${cloud_provider_image}"; \
      printf '%s="%s"\n' \
        "MANIFEST_YAML_AFTER_RBAC_2" \
        "$(gzip -9c <"${secrets_conf}" | base64 -w0)"; } >>"${YAK_DEFAULTS}"

    rm -f "${secrets_conf}"
  fi

  { printf '%s="%s"\n' \
      "CLOUD_PROVIDER" \
      "${cloud_provider}"; \
    printf '%s="%s"\n' \
      "CLOUD_CONFIG" \
      "$(gzip -9c <"${cloud_conf}" | base64 -w0)"; } >>"${YAK_DEFAULTS}"

  rm -f "${cloud_conf}"
fi

write_config_val NODE_TYPE
write_config_val ETCD_DISCOVERY
write_config_val NUM_CONTROLLERS
write_config_val NUM_NODES

write_config_val LOG_LEVEL
write_config_val DEBUG
write_config_val BIN_DIR

write_config_val NETWORK_DNS_1
write_config_val NETWORK_DNS_2

write_config_val ETCD_LEASE_TTL

write_config_val IPTABLES_ALLOW_ALL

write_config_val CLEANUP_DISABLED

write_config_val CNI_BIN_DIR

write_config_val LOG_LEVEL_KUBERNETES
write_config_val LOG_LEVEL_KUBE_APISERVER
write_config_val LOG_LEVEL_KUBE_SCHEDULER
write_config_val LOG_LEVEL_KUBE_CONTROLLER_MANAGER
write_config_val LOG_LEVEL_KUBELET
write_config_val LOG_LEVEL_KUBE_PROXY
write_config_val LOG_LEVEL_CLOUD_CONTROLLER_MANAGER

write_config_val INSTALL_CONFORMANCE_TESTS
write_config_val RUN_CONFORMANCE_TESTS

write_config_val MANIFEST_YAML_BEFORE_RBAC
write_config_val MANIFEST_YAML_AFTER_RBAC_1
write_config_val MANIFEST_YAML_AFTER_ALL

write_config_val ENCRYPTION_KEY

write_config_val CLUSTER_ADMIN
write_config_val CLUSTER_NAME
write_config_val CLUSTER_FQDN
write_config_val EXTERNAL_FQDN
write_config_val CLUSTER_CIDR
write_config_val POD_CIDR_FORMAT
write_config_val SECURE_PORT
write_config_val SERVICE_CIDR
write_config_val SERVICE_IPV4_ADDRESS
write_config_val SERVICE_DNS_PROVIDER
write_config_val SERVICE_DNS_IPV4_ADDRESS
write_config_val SERVICE_DOMAIN
write_config_val SERVICE_NAME
write_config_val CLOUD_PROVIDER_IMAGE_SECRETS

write_config_val K8S_VERSION
write_config_val CNI_PLUGINS_VERSION
write_config_val CONTAINERD_VERSION
write_config_val COREDNS_VERSION
write_config_val CRICTL_VERSION
write_config_val ETCD_VERSION
write_config_val JQ_VERSION
write_config_val NGINX_VERSION
write_config_val RUNC_VERSION
write_config_val RUNSC_VERSION

write_config_val TLS_DEFAULT_BITS
write_config_val TLS_DEFAULT_DAYS
write_config_val TLS_COUNTRY_NAME
write_config_val TLS_STATE_OR_PROVINCE_NAME
write_config_val TLS_LOCALITY_NAME
write_config_val TLS_ORG_NAME
write_config_val TLS_OU_NAME
write_config_val TLS_COMMON_NAME
write_config_val TLS_EMAIL

write_config_val TLS_IS_CA
write_config_val TLS_KEY_USAGE
write_config_val TLS_EXT_KEY_USAGE
write_config_val TLS_SAN
write_config_val TLS_SAN_DNS
write_config_val TLS_SAN_IP
write_config_val TLS_KEY_UID
write_config_val TLS_KEY_GID
write_config_val TLS_KEY_PERM
write_config_val TLS_CRT_UID
write_config_val TLS_CRT_GID
write_config_val TLS_CRT_PERM

exit 0
