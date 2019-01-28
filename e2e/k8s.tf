////////////////////////////////////////////////////////////////////////////////
//                                Globals                                     //
////////////////////////////////////////////////////////////////////////////////
locals {
  cluster_fqdn       = "${var.cluster_name}.${var.network_domain}"
  cluster_svc_ip     = "${cidrhost(var.service_cidr, "1")}"
  cluster_svc_dns_ip = "${cidrhost(var.service_cidr, "10")}"

  cluster_svc_domain = "cluster.local"

  cluster_svc_name = "kubernetes"

  cluster_svc_fqdn = "${local.cluster_svc_name}.default.svc.${local.cluster_svc_domain}"
}

// ctl_pod_cidr is reserved for future use in case workloads are scheduled
// on controller nodes
data "template_file" "ctl_pod_cidr" {
  count    = "${var.ctl_count}"
  template = "${format(var.pod_cidr, count.index)}"
}

// wrk_pod_cidr is always calculated as an offset from the ctl_pod_cidr.
data "template_file" "wrk_pod_cidr" {
  count    = "${var.wrk_count}"
  template = "${format(var.pod_cidr, var.ctl_count + count.index)}"
}

////////////////////////////////////////////////////////////////////////////////
//                             First Boot Env Vars                            //
////////////////////////////////////////////////////////////////////////////////

// Written to /etc/default/yakity
data "template_file" "yakity_env" {
  count = "${var.ctl_count + var.wrk_count}"

  template = <<EOF
DEBUG="$${debug}"
LOG_LEVEL="$${log_level}"
NODE_TYPE="$${node_type}"

# Information about the host's network.
NETWORK_DOMAIN="$${network_domain}"
NETWORK_IPV4_SUBNET_CIDR="$${network_ipv4_subnet_cidr}"
NETWORK_DNS_1="$${network_dns_1}"
NETWORK_DNS_2="$${network_dns_2}"
NETWORK_DNS_SEARCH="$${network_dns_search}"

# Can be generated with:
#  head -c 32 /dev/urandom | base64
ENCRYPTION_KEY="$${encryption_key}"

# The etcd discovery URL used by etcd members to join the etcd cluster.
# This URL can be curled to obtain FQDNs and IP addresses for the 
# members of the etcd cluster.
ETCD_DISCOVERY="$${etcd_discovery}"

# The number of controller nodes in the cluster.
NUM_CONTROLLERS="$${num_controllers}"

# The number of nodes in the cluster.
NUM_NODES="$${num_nodes}"

# The gzip'd, base-64 encoded CA cert/key pair used to generate certificates
# for the cluster.
TLS_CA_CRT_GZ="$${tls_ca_crt}"
TLS_CA_KEY_GZ="$${tls_ca_key}"

# The name of the cloud provider to use.
CLOUD_PROVIDER=$${cloud_provider}

# The gzip'd, base-64 encoded cloud provider configuration to use.
CLOUD_CONFIG="$${cloud_config}"

# The K8s cluster admin.
CLUSTER_ADMIN="$${k8s_cluster_admin}"

# The K8s cluster CIDR.
CLUSTER_CIDR="$${k8s_cluster_cidr}"

# The name of the K8s cluster.
CLUSTER_NAME="$${k8s_cluster_name}"

# The FQDN of the K8s cluster.
CLUSTER_FQDN="$${k8s_cluster_fqdn}"

# The public FQDN of the K8s cluster.
EXTERNAL_FQDN="$${external_fqdn}"

# The secure port on which the K8s API server is advertised.
SECURE_PORT=$${k8s_secure_port}

# The K8s cluster's service CIDR.
SERVICE_CIDR="$${k8s_service_cidr}"

# The IP address used to access the K8s API server on the service network.
SERVICE_IPV4_ADDRESS="$${k8s_service_ip}"

# The IP address of the DNS server for the service network.
SERVICE_DNS_IPV4_ADDRESS="$${k8s_service_dns_ip}"

# The name of the service DNS provider. Valid values include "coredns".
# Any other value results in kube-dns being used.
SERVICE_DNS_PROVIDER="$${service_dns_provider}"

# The domain name used by the K8s service network.
SERVICE_DOMAIN="$${k8s_service_domain}"

# The FQDN used to access the K8s API server on the service network.
SERVICE_FQDN="$${k8s_service_fqdn}"

# The name of the service record that points to the K8s API server on
# the service network.
SERVICE_NAME="$${k8s_service_name}"

# The log levels for the various kubernetes components.
LOG_LEVEL_KUBERNETES="$${log_level_kubernetes}"
LOG_LEVEL_KUBE_APISERVER="$${log_level_kube_apiserver}"
LOG_LEVEL_KUBE_SCHEDULER="$${log_level_kube_scheduler}"
LOG_LEVEL_KUBE_CONTROLLER_MANAGER="$${log_level_kube_controller_manager}"
LOG_LEVEL_KUBELET="$${log_level_kubelet}"
LOG_LEVEL_KUBE_PROXY="$${log_level_kube_proxy}"
LOG_LEVEL_CLOUD_CONTROLLER_MANAGER="$${log_level_cloud_controller_manager}"

INSTALL_CONFORMANCE_TESTS="$${install_conformance_tests}"
RUN_CONFORMANCE_TESTS="$${run_conformance_tests}"

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
MANIFEST_YAML_BEFORE_RBAC="$${manifest_yaml_before_rbac}"
MANIFEST_YAML_AFTER_RBAC_1="$${manifest_yaml_after_rbac_1}"
MANIFEST_YAML_AFTER_RBAC_2="$${manifest_yaml_after_rbac_2}"
MANIFEST_YAML_AFTER_ALL="$${manifest_yaml_after_all}"

# Versions of the software packages installed on the controller and
# worker nodes. Please note that not all the software packages listed
# below are installed on both controllers and workers. Some is intalled
# on one, and some the other. Some software, such as jq, is installed
# on both controllers and workers.
K8S_VERSION="$${k8s_version}"
CNI_PLUGINS_VERSION="$${cni_plugins_version}"
CONTAINERD_VERSION="$${containerd_version}"
COREDNS_VERSION="$${coredns_version}"
CRICTL_VERSION="$${crictl_version}"
ETCD_VERSION="$${etcd_version}"
JQ_VERSION="$${jq_version}"
NGINX_VERSION="$${nginx_version}"
RUNC_VERSION="$${runc_version}"
RUNSC_VERSION="$${runsc_version}"
EOF

  vars {
    //
    debug = "${var.debug}"

    // If there are controllers and the count index is less than the number of
    //  controller nodes, then check to see if the node type is "controller" or
    // "both". Otherwise the node type is "worker".
    node_type = "${var.ctl_count > 0 && count.index < var.ctl_count ? var.bth_count > 0 && count.index < var.bth_count ? "both" : "controller" : "worker"}"

    //
    network_domain           = "${var.network_domain}"
    network_ipv4_subnet_cidr = "${var.network_ipv4_gateway}/24"
    network_dns_1            = "${var.network_dns_1}"
    network_dns_2            = "${var.network_dns_2}"
    network_dns_search       = "${var.network_search_domains}"

    //
    etcd_discovery = "${local.etcd_discovery}"

    //
    num_controllers = "${var.ctl_count}"
    num_nodes       = "${var.ctl_count + var.wrk_count}"

    //
    encryption_key = "${var.k8s_encryption_key}"

    //
    cloud_provider = "${var.cloud_provider}"
    cloud_config   = "${var.cloud_provider == "external" ? base64gzip(data.template_file.ccm_config.rendered) : base64gzip(data.template_file.cloud_provider_config.rendered)}"

    //
    tls_ca_crt = "${base64gzip(local.tls_ca_crt)}"
    tls_ca_key = "${base64gzip(local.tls_ca_key)}"

    //
    k8s_version          = "${var.k8s_version}"
    k8s_cluster_admin    = "${var.cluster_admin}"
    k8s_cluster_cidr     = "${var.cluster_cidr}"
    k8s_cluster_fqdn     = "${local.cluster_fqdn}"
    external_fqdn        = "${local.external_fqdn}"
    k8s_cluster_name     = "${var.cluster_name}"
    k8s_secure_port      = "${var.api_secure_port}"
    k8s_service_cidr     = "${var.service_cidr}"
    k8s_service_ip       = "${local.cluster_svc_ip}"
    k8s_service_dns_ip   = "${local.cluster_svc_dns_ip}"
    k8s_service_domain   = "${local.cluster_svc_domain}"
    k8s_service_fqdn     = "${local.cluster_svc_fqdn}"
    k8s_service_name     = "${local.cluster_svc_name}"
    service_dns_provider = "${var.service_dns_provider}"

    //
    log_level                          = "${var.log_level}"
    log_level_kubernetes               = "${var.log_level_kubernetes}"
    log_level_kube_apiserver           = "${var.log_level_kube_apiserver}"
    log_level_kube_scheduler           = "${var.log_level_kube_scheduler}"
    log_level_kube_controller_manager  = "${var.log_level_kube_controller_manager}"
    log_level_kubelet                  = "${var.log_level_kubelet}"
    log_level_kube_proxy               = "${var.log_level_kube_proxy}"
    log_level_cloud_controller_manager = "${var.log_level_cloud_controller_manager}"

    //
    manifest_yaml_before_rbac  = "${var.manifest_yaml_before_rbac}"
    manifest_yaml_after_rbac_1 = "${var.manifest_yaml_after_rbac}"
    manifest_yaml_after_rbac_2 = "${base64gzip(data.template_file.manifest_secrets_yaml.rendered)}"
    manifest_yaml_after_all    = "${var.manifest_yaml_after_all}"

    //
    install_conformance_tests = "${var.install_conformance_tests}"
    run_conformance_tests     = "${var.run_conformance_tests}"

    //
    cni_plugins_version = "${var.cni_plugins_version}"
    containerd_version  = "${var.containerd_version}"
    coredns_version     = "${var.coredns_version}"
    crictl_version      = "${var.crictl_version}"
    etcd_version        = "${var.etcd_version}"
    jq_version          = "${var.jq_version}"
    k8s_version         = "${var.k8s_version}"
    nginx_version       = "${var.nginx_version}"
    runc_version        = "${var.runc_version}"
    runsc_version       = "${var.runsc_version}"
  }
}
