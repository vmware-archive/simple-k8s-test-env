provider "http" {
  version = "1.0"
}

provider "template" {
  version = "1.0"
}

provider vsphere {
  version = "1.8"

  user                 = "${var.vsphere_user}"
  password             = "${var.vsphere_password}"
  vsphere_server       = "${var.vsphere_server}"
  allow_unverified_ssl = "${var.vsphere_allow_unverified_ssl}"
}