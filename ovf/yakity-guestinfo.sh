#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

#
# Used by the yakity service to write the yakity environment
# file by reading properties from the VMware GuestInfo interface.
#

# Update the path so that "rpctool" is in it.
PATH=/var/lib/yakity:"${PATH}"

if ! command -v rpctool >/dev/null 2>&1; then
  exit_code="${?}"
  echo "failed to find rpctool command" 1>&2
  exit "${exit_code}"
fi

YAK_DEFAULTS="${YAK_DEFAULTS:-/etc/default/yakity}"

write_config_val() {
  if val=$(rpctool get "yakity.${1}" 2>/dev/null) && [ -n "${val}" ]; then
    printf '%s="%s"\n' "${1}" "${val}" >>"${YAK_DEFAULTS}"
  elif val=$(rpctool get.ovf "${1}" 2>/dev/null) && [ -n "${val}" ]; then
    printf '%s="%s"\n' "${1}" "${val}" >>"${YAK_DEFAULTS}"
  fi
}

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
write_config_val MANIFEST_YAML_AFTER_RBAC_2
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
write_config_val CLOUD_PROVIDER
write_config_val CLOUD_CONFIG
write_config_val CLOUD_PROVIDER_EXTERNAL
write_config_val CLOUD_PROVIDER_IMAGE
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

is_file_empty() {
  bytes=$(du "${1}" | awk '{print $1}')
  [ "${bytes}" -le "0" ]
}

# Check for the TLS CA cert and key since those are special cases.
ca_crt_pem="$(mktemp)"; ca_key_pem="$(mktemp)"; mkdir -p /etc/ssl
if [ ! -f /etc/ssl/ca.crt ]; then
  rpctool get.ovf "TLS_CA_CRT_PEM" 2>/dev/null 1>"${ca_crt_pem}" || true
  if ! is_file_empty "${ca_crt_pem}"; then
    mv "${ca_crt_pem}" /etc/ssl/ca.crt
    chmod 0644 /etc/ssl/ca.crt
  fi
  rm -f "${ca_crt_pem}"
fi
if [ ! -f /etc/ssl/ca.key ]; then
  rpctool get.ovf "TLS_CA_KEY_PEM" 2>/dev/null 1>"${ca_key_pem}" || true
  if ! is_file_empty "${ca_key_pem}"; then
    mv "${ca_key_pem}" /etc/ssl/ca.key
    chmod 0644 /etc/ssl/ca.key
  fi
  rm -f "${ca_key_pem}"
fi

# Get the SSH public keys to add to the root user.
ssh_pub_keys="$(mktemp)"
rpctool get.ovf "SSH_PUB_KEYS" 2>/dev/null 1>"${ssh_pub_keys}" || true
if ! is_file_empty "${ssh_pub_keys}"; then
  mkdir -p /root/.ssh; chmod 0700 /root/.ssh
  echo >>/root/.ssh/authorized_keys
  cat "${ssh_pub_keys}" >>/root/.ssh/authorized_keys
  chmod 0400 /root/.ssh/authorized_keys
  rm -f "${ssh_pub_keys}"
fi

# Check to see if the host name should be set.
if val=$(rpctool get.ovf "HOST_FQDN" 2>/dev/null) && [ -n "${val}" ]; then
  hostname "${val}"
  printf '\n127.0.0.1\t%s\n' "${val}" >>/etc/hosts
fi
