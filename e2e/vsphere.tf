////////////////////////////////////////////////////////////////////////////////
//                                vSphere                                     //
////////////////////////////////////////////////////////////////////////////////
locals {
  vm_path_prefix   = "${var.cloud_provider == "external" ? "ccm" : "k8s"}"
  name_sans_prefix = "${replace(var.name, "/^(?:[^\\-]+\\-)?(.*)$/", "$1")}"

  vsphere_folder        = "${var.vsphere_folder}/${local.vm_path_prefix}/${local.name_sans_prefix}"
  vsphere_resource_pool = "${var.vsphere_resource_pool}/${local.vm_path_prefix}"

  vsphere_resource_pools = ["${split("/", local.vsphere_resource_pool)}"]
}

data "vsphere_datacenter" "datacenter" {
  name = "${var.vsphere_datacenter}"
}

resource "vsphere_folder" "folder" {
  path          = "${local.vsphere_folder}"
  type          = "vm"
  datacenter_id = "${data.vsphere_datacenter.datacenter.id}"
}

data "vsphere_resource_pool" "resource_pool" {
  count         = "${length(local.vsphere_resource_pools)}"
  name          = "${element(local.vsphere_resource_pools, count.index)}"
  datacenter_id = "${data.vsphere_datacenter.datacenter.id}"
}

resource "vsphere_resource_pool" "resource_pool" {
  name                    = "${local.name_sans_prefix}"
  parent_resource_pool_id = "${element(data.vsphere_resource_pool.resource_pool.*.id, length(data.vsphere_resource_pool.resource_pool.*.id) - 1)}"
}

data "vsphere_datastore" "datastore" {
  name          = "${var.vsphere_datastore}"
  datacenter_id = "${data.vsphere_datacenter.datacenter.id}"
}

data "vsphere_network" "network" {
  name          = "${var.vsphere_network}"
  datacenter_id = "${data.vsphere_datacenter.datacenter.id}"
}

data "vsphere_virtual_machine" "template" {
  name          = "${var.vsphere_template}"
  datacenter_id = "${data.vsphere_datacenter.datacenter.id}"
}

/*
locals {
  // Static MAC addresses are used for the K8s controller and worker nodes
  // in order to keep the network happy while testing.
  //
  // The number of elements in the list must equal or exceed the value
  // of var.ctl_count.

  ctl_mac_addresses = [
    "00:00:0f:41:1b:d3",
    "00:00:0f:59:aa:c3",
    "00:00:0f:77:88:e3",
  ]
}
*/

resource "vsphere_virtual_machine" "controller" {
  count = "${var.ctl_count}"

  name = "${format(var.ctl_vm_name, count.index+1)}"

  datastore_id         = "${data.vsphere_datastore.datastore.id}"
  folder               = "${vsphere_folder.folder.path}"
  resource_pool_id     = "${vsphere_resource_pool.resource_pool.id}"
  guest_id             = "${data.vsphere_virtual_machine.template.guest_id}"
  scsi_type            = "${data.vsphere_virtual_machine.template.scsi_type}"
  num_cpus             = "${var.bth_count > 0 && count.index < var.bth_count ? var.wrk_vm_num_cpu : var.ctl_vm_num_cpu}"
  num_cores_per_socket = "${var.bth_count > 0 && count.index < var.bth_count ? var.wrk_vm_num_cores_per_socket : var.ctl_vm_num_cores_per_socket}"
  memory               = "${var.bth_count > 0 && count.index < var.bth_count ? var.wrk_vm_memory : var.ctl_vm_memory}"

  // Required by the vSphere cloud provider
  enable_disk_uuid = true

  network_interface {
    network_id   = "${data.vsphere_network.network.id}"
    adapter_type = "${data.vsphere_virtual_machine.template.network_interface_types[0]}"

    //use_static_mac = true
    //mac_address    = "${local.ctl_mac_addresses[count.index]}"
  }

  disk {
    label            = "disk0"
    size             = "${var.bth_count > 0 && count.index < var.bth_count ? var.wrk_vm_disk_size : var.ctl_vm_disk_size}"
    eagerly_scrub    = "${data.vsphere_virtual_machine.template.disks.0.eagerly_scrub}"
    thin_provisioned = "${data.vsphere_virtual_machine.template.disks.0.thin_provisioned}"
  }

  clone {
    template_uuid = "${data.vsphere_virtual_machine.template.id}"
  }

  extra_config {
    "guestinfo.metadata"          = "${base64gzip(data.template_file.ctl_cloud_metadata.*.rendered[count.index])}"
    "guestinfo.metadata.encoding" = "gzip+base64"
    "guestinfo.userdata"          = "${base64gzip(data.template_file.ctl_cloud_config.*.rendered[count.index])}"
    "guestinfo.userdata.encoding" = "gzip+base64"
  }
}

resource "vsphere_virtual_machine" "worker" {
  count = "${var.wrk_count}"

  name = "${format(var.wrk_vm_name, count.index+1)}"

  datastore_id         = "${data.vsphere_datastore.datastore.id}"
  folder               = "${vsphere_folder.folder.path}"
  resource_pool_id     = "${vsphere_resource_pool.resource_pool.id}"
  guest_id             = "${data.vsphere_virtual_machine.template.guest_id}"
  scsi_type            = "${data.vsphere_virtual_machine.template.scsi_type}"
  num_cpus             = "${var.wrk_vm_num_cpu}"
  num_cores_per_socket = "${var.wrk_vm_num_cores_per_socket}"
  memory               = "${var.wrk_vm_memory}"

  // Required by the vSphere cloud provider
  enable_disk_uuid = true

  network_interface {
    network_id   = "${data.vsphere_network.network.id}"
    adapter_type = "${data.vsphere_virtual_machine.template.network_interface_types[0]}"

    //use_static_mac = true
    //mac_address    = "${local.wrk_mac_addresses[count.index]}"
  }

  disk {
    label            = "disk0"
    size             = "${var.wrk_vm_disk_size}"
    eagerly_scrub    = "${data.vsphere_virtual_machine.template.disks.0.eagerly_scrub}"
    thin_provisioned = "${data.vsphere_virtual_machine.template.disks.0.thin_provisioned}"
  }

  clone {
    template_uuid = "${data.vsphere_virtual_machine.template.id}"
  }

  extra_config {
    "guestinfo.metadata"          = "${base64gzip(data.template_file.wrk_cloud_metadata.*.rendered[count.index])}"
    "guestinfo.metadata.encoding" = "gzip+base64"
    "guestinfo.userdata"          = "${base64gzip(data.template_file.wrk_cloud_config.*.rendered[count.index])}"
    "guestinfo.userdata.encoding" = "gzip+base64"
  }
}
