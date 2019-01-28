data "template_file" "ctl_network_hostname" {
  count    = "${var.ctl_count}"
  template = "${format(var.ctl_network_hostname, count.index+1)}"
}

data "template_file" "ctl_network_hostfqdn" {
  count    = "${var.ctl_count}"
  template = "${format(var.ctl_network_hostname, count.index+1)}.${var.network_domain}"
}

data "template_file" "wrk_network_hostname" {
  count    = "${var.wrk_count}"
  template = "${format(var.wrk_network_hostname, count.index+1)}"
}

data "template_file" "wrk_network_hostfqdn" {
  count    = "${var.wrk_count}"
  template = "${format(var.wrk_network_hostname, count.index+1)}.${var.network_domain}"
}

data "template_file" "cloud_users" {
  count = "${length(keys(var.os_users))}"

  template = <<EOF
  - name: $${name}
    primary_group: $${name}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo, wheel, k8s-admin
    ssh_import_id: None
    lock_passwd: true
    ssh_authorized_keys:
      - $${key}
EOF

  vars {
    name = "${element(keys(var.os_users), count.index)}"
    key  = "${element(values(var.os_users), count.index)}"
  }
}

data "template_file" "manifest_secrets_yaml" {
  template = <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloud-provider-vsphere-credentials
  namespace: kube-system
data:
  $${server}.username: "$${username}"
  $${server}.password: "$${password}"
EOF

  vars {
    server   = "${var.vsphere_server}"
    username = "${base64encode(var.vsphere_user)}"
    password = "${base64encode(var.vsphere_password)}"
  }
}

data "template_file" "cloud_provider_config" {
  template = <<EOF
[Global]
  user               = "$${username}"
  password           = "$${password}"
  port               = "$${port}"
  insecure-flag      = "$${insecure}"
  datacenters        = "$${datacenter}"

[VirtualCenter "$${server}"]

[Workspace]
  server             = "$${server}"
  datacenter         = "$${datacenter}"
  folder             = "$${folder}"
  default-datastore  = "$${datastore}"
  resourcepool-path  = "$${resource_pool}"

[Disk]
  scsicontrollertype = pvscsi

[Network]
  public-network     = "$${network}"
EOF

  vars {
    server        = "${var.vsphere_server}"
    username      = "${var.vsphere_user}"
    password      = "${var.vsphere_password}"
    port          = "${var.vsphere_server_port}"
    insecure      = "${var.vsphere_allow_unverified_ssl ? 1 : 0}"
    datacenter    = "${var.vsphere_datacenter}"
    folder        = "${var.vsphere_folder}"
    datastore     = "${var.vsphere_datastore}"
    resource_pool = "${var.vsphere_resource_pool}"
    network       = "${var.vsphere_network}"
  }
}

data "template_file" "ccm_config" {
  template = <<EOF
[Global]
  secret-name        = "cloud-provider-vsphere-credentials"
  secret-namespace   = "kube-system"
  service-account    = "cloud-controller-manager"
  port               = "$${port}"
  insecure-flag      = "$${insecure}"
  datacenters        = "$${datacenter}"

[VirtualCenter "$${server}"]
EOF

  vars {
    server     = "${var.vsphere_server}"
    username   = "${var.vsphere_user}"
    password   = "${var.vsphere_password}"
    port       = "${var.vsphere_server_port}"
    insecure   = "${var.vsphere_allow_unverified_ssl ? 1 : 0}"
    datacenter = "${var.vsphere_datacenter}"
  }
}

data "template_file" "ctl_cloud_network" {
  count = "${var.ctl_count}"

  template = <<EOF
version: 1
config:
  - type: physical
    name: $${network_device}
    subnets:
      - type: dhcp
  - type: nameserver:
    address: $${network_dns}
    search: $${network_search_domains}
EOF

  vars {
    network_device         = "${var.network_device}"
    network_dns            = "${join("", formatlist("\n% 7s %s", "-", list(var.network_dns_1, var.network_dns_2)))}"
    network_search_domains = "${join("", formatlist("\n% 7s %s", "-", split(" ", var.network_search_domains)))}"
  }
}

data "template_file" "ctl_cloud_metadata" {
  count = "${var.ctl_count}"

  template = <<EOF
{
  "network": "$${network}",
  "network.encoding": "gzip+base64",
  "local-hostname": "$${local_hostname}",
  "instance-id": "$${instance_id}"
}
EOF

  vars {
    network        = "${base64gzip(data.template_file.ctl_cloud_network.*.rendered[count.index])}"
    local_hostname = "${data.template_file.ctl_network_hostfqdn.*.rendered[count.index]}"
    instance_id    = "${data.template_file.ctl_network_hostfqdn.*.rendered[count.index]}"
  }
}

data "template_file" "ctl_cloud_config" {
  count = "${var.ctl_count}"

  template = "${file("${path.module}/cloud_config.yaml")}"

  vars {
    debug = "${var.debug}"

    //
    yakity_env = "${base64gzip(data.template_file.yakity_env.*.rendered[count.index])}"
    yakity_url = "${var.yakity_url}"

    // If the count.index >= the number of controller nodes that are able to
    // schedule workloads then set the node_type="both".
    node_type  = "${var.bth_count > 0 && count.index < var.bth_count ? "both" : "controller"}"

    //
    users = "${join("\n", data.template_file.cloud_users.*.rendered)}"
  }
}

data "template_file" "wrk_cloud_network" {
  count = "${var.wrk_count}"

  template = <<EOF
version: 1
config:
  - type: physical
    name: $${network_device}
    subnets:
      - type: dhcp
  - type: nameserver:
    address:
      - 8.8.8.8
      - 8.8.4.4
    search: $${network_search_domains}
EOF

  vars {
    network_device         = "${var.network_device}"
    network_search_domains = "${join("", formatlist("\n% 7s %s", "-", split(" ", var.network_search_domains)))}"
  }
}

data "template_file" "wrk_cloud_metadata" {
  count = "${var.wrk_count}"

  template = <<EOF
{
  "network": "$${network}",
  "network.encoding": "gzip+base64",
  "local-hostname": "$${local_hostname}",
  "instance-id": "$${instance_id}"
}
EOF

  vars {
    network        = "${base64gzip(data.template_file.wrk_cloud_network.*.rendered[count.index])}"
    local_hostname = "${data.template_file.wrk_network_hostfqdn.*.rendered[count.index]}"
    instance_id    = "${data.template_file.wrk_network_hostfqdn.*.rendered[count.index]}"
  }
}

data "template_file" "wrk_cloud_config" {
  count = "${var.wrk_count}"

  template = "${file("${path.module}/cloud_config.yaml")}"

  vars {
    debug = "${var.debug}"

    //
    yakity_env = "${base64gzip(data.template_file.yakity_env.*.rendered[count.index])}"
    yakity_url = "${var.yakity_url}"
    node_type  = "worker"

    //
    users = "${join("\n", data.template_file.cloud_users.*.rendered)}"
  }
}
