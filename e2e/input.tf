////////////////////////////////////////////////////////////////////////////////
//                                  Global                                    //
////////////////////////////////////////////////////////////////////////////////

// The name of the deployment. Used by some resources as a means to identify
// the deployment resources.
variable "name" {}

// Enables debug functionality in parts of the deployment, such as causing
// shell scripts to enable set -x.
variable "debug" {
  default = "false"
}

// Set the log level at which the yakity script is executed. Valid values
// include: fatal, warn, error, info, debug.
variable "log_level" {
  default = "info"
}

////////////////////////////////////////////////////////////////////////////////
//                                 Guest OS                                   //
////////////////////////////////////////////////////////////////////////////////

// The users created on the host. The variable format is a map of
// of key/value pairs with the keys the user names and the values the
// public SSH keys for the corresponding user. 
//
// The value may be specified with an environment variable using HCL
// syntax. For example:
//
//     TF_VAR_os_users='{"akutz","ssh_key","luoh",ssh_key",...}'
variable "os_users" {
  default = {
    akutz = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDE0c5FczvcGSh/tG4iw+Fhfi/O5/EvUM/96js65tly4++YTXK1d9jcznPS5ruDlbIZ30oveCBd3kT8LLVFwzh6hepYTf0YmCTpF4eDunyqmpCXDvVscQYRXyasEm5olGmVe05RrCJSeSShAeptv4ueIn40kZKOghinGWLDSZG4+FFfgrmcMCpx5YSCtX2gvnEYZJr0czt4rxOZuuP7PkJKgC/mt2PcPjooeX00vAj81jjU2f3XKrjjz2u2+KIt9eba+vOQ6HiC8c2IzRkUAJ5i1atLy8RIbejo23+0P4N2jjk17QySFOVHwPBDTYb0/0M/4ideeU74EN/CgVsvO6JrLsPBR4dojkV5qNbMNxIVv5cUwIy2ThlLgqpNCeFIDLCWNZEFKlEuNeSQ2mPtIO7ETxEL2Cz5y/7AIuildzYMc6wi2bofRC8HmQ7rMXRWdwLKWsR0L7SKjHblIwarxOGqLnUI+k2E71YoP7SZSlxaKi17pqkr0OMCF+kKqvcvHAQuwGqyumTEWOlH6TCx1dSPrW+pVCZSHSJtSTfDW2uzL6y8k10MT06+pVunSrWo5LHAXcS91htHV1M1UrH/tZKSpjYtjMb5+RonfhaFRNzvj7cCE1f3Kp8UVqAdcGBTtReoE8eRUT63qIxjw03a7VwAyB2w+9cu1R9/vAo8SBeRqw== sakutz@gmail.com"
    luoh  = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDdCb/l7v2Gu44VQTeiUH1sQAmXQpKkJvdQUS2YriO/ysx+adfimT34fkhX7ZbiAC6kNKHFGQ6sRLnudVRv65N4P5SkQ27EtjS1W7rGEykZHarunq6szg5gAEFqVOrucn5Xey+iqDwMvM9w8pqKbJYvDy/7SGfz/cDvnWEcqIoYLy66IUPIaNwN7/eR6bZ7ab3IMpAkaR9gWrl4vpFql0fEVJgisbC8oPuX7sREhpaaO4BSWwEUyn97NnAFbDRN1fsohaLJVYD2vA6oXet/J5w0eFEGEgYAZuBB1VqbUXD4FfLxf8MP7qFniuCcfZHgzO5cbyK4xjrpknkHkk+b7sgON/2olCqM7+XDfgeuSxZgN9OJTRl2TesNMvhbXgFpnWJxIAkH0mbByDUNo+TQK58khTkVDlB6BOchRKN5EzKpUdzlBxVGJie35xAIqcFQGBw7E1nWBgDgAA9KXz4/jAdn3e81aOHzIGmVf9glj65TQRb2qQ4Rr/VwPfyUHCQTeGL5ykcHid7QbvMMXSx6EEXV4zP21vL98eOnwnoTyLD4JrxkEUAJS+9yxB75Ck6DF2AVkF+hnW0BUmcHI0BnWyXdb9SLsGwG4W0O4jOVXmq/yz+I5JkkPX4OB/eugetbb3L1CPczG/N0RbXCykU7TJdLSpBV27P7ho9JfK+UWAC2Gw== luoh@luoh-m01.vmware.com"
    fabio = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCnu/TCGUvbpN0i4Urhv4ToTonD2cfu2WAbIKY6vnu7crFMi8g8aWc36fbfGXZMOMebQT1teduDicZ2t9ZIi73T7JUSVkjVZHbZE5cJwj6rSr0YNcQF1jNxBAmssUy9O7fGM1Qnn4rUoH3PqRMj/WH5mS5kReM9bcu5F2/EBiaXD8F6XMeiOQX3sQPfmypVXygygQMcb5e/xe3OQRffNNhx0q7hCcHie4pLBa3sy8v3eWxwDlZJxGFjvl/8S2XzeKGZNRCibzMPJzSmgE56ou4XAAyxuCReGlFPtz91xLM6bhFKreX4em8fg8BXaLHE6+pDoAbjQ6q9pEeqWekO7Cc88hMtWC89BCEZ73tldvGX+hIY8Kc7jRUntbxEmBRYodAHS/Ex5P1vedl4pxN1bYFAOd9B9RzaHwi32c2tIkBU1b7aa94omNCjZsTW8/c47heSIT7NrQE3y8o6ksFC5NUHrwnrvejtKDU29YiB6hCms6QxMdSRAsV8iSDRedRPbqjsKGEQ6HfLovgi3EpsZgsj8t9f4rL3qfcBmD57EqUdhKsow0hLRarhIJMpgJqkeTD7gPdkaHkLcuIqOQAevBjRK6/YJ1OY8BiZJj0lcUuwjwL+Y06JQp/Sd9BUI2I8K3dQnV9JSprdfh28x/J6EaLmzHEQNYNdQajz/ufoUHsEsw== cardno:000604159439"
  }
}

variable "os_seed_uid" {
  default = "1000"
}

variable "os_seed_gid" {
  default = "1000"
}

// If var.yakity and var.yakity_file are not set then the script is fetched 
// from the following URL.
variable "yakity_url" {
  default = "https://raw.githubusercontent.com/akutz/yakity/v0.1.0/yakity.sh"
}

////////////////////////////////////////////////////////////////////////////////
//                                Networking                                  //
////////////////////////////////////////////////////////////////////////////////

// The FQDN of the domain to which all hosts should belong.
variable "network_domain" {
  default = "vmware.ci"
}

// The name of the first network device in VMs provisioned from the CoreOS
// template.
variable "network_device" {
  default = "ens192"
}

// Please see the following URL for more information on "network_" variables:
// https://www.freedesktop.org/software/systemd/man/systemd.network.html.
variable "network_dhcp" {
  default = "no"
}

variable "network_dns_1" {
  default = "8.8.8.8"
}

variable "network_dns_2" {
  default = "8.8.4.4"
}

// A space-separated list of search domains.
variable "network_search_domains" {
  default = "vmware.ci"
}

// Per https://www.freedesktop.org/software/systemd/man/systemd.network.html
//
// > A static IPv4 or IPv6 address and its prefix length, separated by a 
// > "/" character. 
//variable "network_ipv4_address" {}

variable "network_ipv4_gateway" {
  default = "192.168.3.1"
}

////////////////////////////////////////////////////////////////////////////////
//                                vSphere                                     //
////////////////////////////////////////////////////////////////////////////////

variable "vsphere_user" {}

variable "vsphere_password" {}

variable "vsphere_server" {
  default = "vcenter.sddc-54-70-161-229.vmc.vmware.com"
}

variable "vsphere_server_port" {
  default = "443"
}

variable "vsphere_allow_unverified_ssl" {
  default = false
}

// The name of the datacenter to which VMs belong
variable "vsphere_datacenter" {
  default = "SDDC-Datacenter"
}

// The folder path where VMs are located
variable "vsphere_folder" {
  default = "Workloads/yake2e"
}

// The name of the resource pool to which VMs belong
variable "vsphere_resource_pool" {
  default = "Compute-ResourcePool/yake2e"
}

// The name of the datastore where VMs are located
variable "vsphere_datastore" {
  default = "WorkloadDatastore"
}

// The name of the vSphere network to which the VMs' NICs will be attached.
variable "vsphere_network" {
  default = "VMC Networks/sddc-cgw-network-3"
}

// The path of the template to use when cloning.
variable "vsphere_template" {
  default = "Templates/centos_cloud_template"
}

////////////////////////////////////////////////////////////////////////////////
//                                    K8s                                     //
////////////////////////////////////////////////////////////////////////////////

// k8s_version may be set to:
//
//    * release/(latest|stable|<version>)
//    * ci/(latest|<version>)
variable "k8s_version" {
  default = "release/stable"
}

// The name of the cloud provider to use.
variable "cloud_provider" {
  default = "vsphere"
}

// The name of the cluster
variable "cluster_name" {
  default = "k8s"
}

// The port on which K8s advertises the API server
variable "api_secure_port" {
  default = "443"
}

// The number of controller nodes
variable "ctl_count" {
  default = "2"
}

// The number of controller nodes that are also able to schedule workloads.
variable "bth_count" {
  default = "2"
}

// The number of worker nodes
variable "wrk_count" {
  default = "3"
}

variable "cluster_admin" {
  default = "kubernetes"
}

// A list of DNS SANs to add to the cluster's TLS certificate
variable "cluster_sans_dns_names" {
  default = []
}

// Can be generated with:
//
//  head -c 32 /dev/urandom | base64
variable "k8s_encryption_key" {
  default = ""
}

variable "service_cidr" {
  default = "10.32.0.0/24"
}

variable "cluster_cidr" {
  default = "10.200.0.0/16"
}

variable "pod_cidr" {
  default = "10.200.%d.0/24"
}

variable "install_conformance_tests" {
  default = true
}

variable "run_conformance_tests" {
  default = false
}

variable "service_dns_provider" {
  default = "kube-dns"
}

// If defined, each of the following manifest_yaml variables
// are applied from a control plane node with 
// "echo VAL | kubectl create -f -- -" using the order specified by the 
// environment variable's name. The manifests are applied exactly once, 
// no matter the number of control plane nodes.
//
// Each of the values should be gzip'd and base64-encoded.
variable "manifest_yaml_before_rbac" {
  default = ""
}

variable "manifest_yaml_after_rbac" {
  default = ""
}

variable "manifest_yaml_after_all" {
  default = ""
}

// The log_level variables set the log levels for the
// various components deployed by yakity. All defaults
// are controlled by yakity.
variable "log_level_kubernetes" {
  default = ""
}

variable "log_level_kube_apiserver" {
  default = ""
}

variable "log_level_kube_scheduler" {
  default = ""
}

variable "log_level_kube_controller_manager" {
  default = ""
}

variable "log_level_kubelet" {
  default = ""
}

variable "log_level_kube_proxy" {
  default = ""
}

variable "log_level_cloud_controller_manager" {
  default = ""
}

////////////////////////////////////////////////////////////////////////////////
//                                   VM                                       //
////////////////////////////////////////////////////////////////////////////////
variable "ctl_vm_name" {
  default = "k8s-c%02d"
}

variable "wrk_vm_name" {
  default = "k8s-w%02d"
}

variable "ctl_vm_num_cpu" {
  default = "8"
}

variable "ctl_vm_num_cores_per_socket" {
  default = "4"
}

variable "ctl_vm_memory" {
  default = "32768"
}

variable "ctl_vm_disk_size" {
  default = "20"
}

variable "wrk_vm_num_cpu" {
  default = "16"
}

variable "wrk_vm_num_cores_per_socket" {
  default = "4"
}

variable "wrk_vm_memory" {
  default = "65536"
}

variable "wrk_vm_disk_size" {
  default = "100"
}

////////////////////////////////////////////////////////////////////////////////
//                                Networking                                  //
////////////////////////////////////////////////////////////////////////////////
variable "ctl_network_hostname" {
  default = "k8s-c%02d"
}

variable "wrk_network_hostname" {
  default = "k8s-w%02d"
}

// The IP range for masters is 192.168.2.128-191, 63 hosts.
//
// Please see cidrhost at https://www.terraform.io/docs/configuration/interpolation.html 
// and http://www.rjsmith.com/CIDR-Table.html for more information. 
variable "ctl_network_ipv4_address" {
  default = "192.168.2.128/25"
}

// The IP range for masters is 192.168.2.192-254, 62 hosts.
//
// Please see cidrhost at https://www.terraform.io/docs/configuration/interpolation.html 
// and http://www.rjsmith.com/CIDR-Table.html for more information. 
variable "wrk_network_ipv4_address" {
  default = "192.168.2.192/26"
}

// A boolean true opens iptables wide-open. This setting should only be
// used during development.
variable "iptables_allow_all" {
  default = true
}

////////////////////////////////////////////////////////////////////////////////
//                              Artifacts                                     //
////////////////////////////////////////////////////////////////////////////////

variable "jq_version" {
  default = "1.5"
}

// controller

// https://github.com/etcd-io/etcd/releases
variable "etcd_version" {
  default = "3.3.9"
}

// https://github.com/coredns/coredns/releases
variable "coredns_version" {
  default = "1.2.2"
}

// Valid versions include:
//   * 1.14.0
//   * 1.15.2
variable "nginx_version" {
  default = "1.14.0"
}

// worker

// https://github.com/kubernetes-incubator/cri-tools/releases
variable "crictl_version" {
  default = "1.11.1"
}

// https://github.com/opencontainers/runc/releases
variable "runc_version" {
  default = "1.0.0-rc5"
}

// https://storage.googleapis.com/gvisor/releases/nightly
variable "runsc_version" {
  default = "2018-09-01"
}

// https://github.com/containernetworking/plugins/releases
variable "cni_plugins_version" {
  default = "0.7.1"
}

// https://github.com/containerd/containerd/releases
variable "containerd_version" {
  default = "1.1.4"
}

variable "containerd12_version" {
  default = "1.2.0-rc.0"
}

////////////////////////////////////////////////////////////////////////////////
//                                  TLS                                        //
////////////////////////////////////////////////////////////////////////////////
variable "tls_ca_crt" {
  default = ""
}

variable "tls_ca_key" {
  default = ""
}

variable "tls_bits" {
  default = "2048"
}

variable "tls_days" {
  default = "365"
}

variable "tls_org" {
  default = "VMware"
}

variable "tls_ou" {
  default = "CNX"
}

variable "tls_country" {
  default = "US"
}

variable "tls_province" {
  default = "California"
}

variable "tls_locality" {
  default = "Palo Alto"
}

variable "tls_email" {
  default = "cnx@vmware.com"
}
