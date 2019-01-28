locals {
  tls_ca_crt = "${base64decode(var.tls_ca_crt)}"
  tls_ca_key = "${base64decode(var.tls_ca_key)}"
}