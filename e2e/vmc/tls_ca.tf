resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = "${var.tls_bits}"
}

resource "tls_self_signed_cert" "ca" {
  key_algorithm         = "RSA"
  private_key_pem       = "${tls_private_key.ca.private_key_pem}"
  is_ca_certificate     = true
  validity_period_hours = "${var.tls_days * 24}"

  subject {
    common_name         = "${var.name} CA"
    organization        = "${var.tls_org}"
    organizational_unit = "${var.tls_ou}"
    country             = "${var.tls_country}"
    province            = "${var.tls_province}"
    locality            = "${var.tls_locality}"
  }

  allowed_uses = [
    "digital_signature",
    "cert_signing",
    "crl_signing",
  ]
}

locals {
  tls_ca_crt = "${tls_self_signed_cert.ca.cert_pem}"
  tls_ca_key = "${tls_private_key.ca.private_key_pem}"
}
