//
// This file may be replaced when run via Docker. The replacement
// uses the etcd discovery URL response returned from a previous
// apply operation.
//
data "http" "etcd_discovery" {
  url = "https://discovery.etcd.io/new?size=${var.ctl_count}"
}

locals {
  etcd_discovery = "${data.http.etcd_discovery.body}"
}
