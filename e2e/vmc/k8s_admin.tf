resource "tls_private_key" "k8s_admin" {
  algorithm = "RSA"
  rsa_bits  = "${var.tls_bits}"
}

resource "tls_cert_request" "k8s_admin" {
  key_algorithm   = "RSA"
  private_key_pem = "${tls_private_key.k8s_admin.private_key_pem}"

  subject {
    common_name         = "admin"
    organization        = "system:masters"
    organizational_unit = "${var.tls_ou}"
    country             = "${var.tls_country}"
    province            = "${var.tls_province}"
    locality            = "${var.tls_locality}"
  }
}

resource "tls_locally_signed_cert" "k8s_admin" {
  cert_request_pem      = "${tls_cert_request.k8s_admin.cert_request_pem}"
  ca_key_algorithm      = "RSA"
  ca_private_key_pem    = "${local.tls_ca_key}"
  ca_cert_pem           = "${local.tls_ca_crt}"
  validity_period_hours = "${var.tls_days * 24}"

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth",
  ]
}

data "template_file" "k8s_admin_kubeconfig" {
  template = <<EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: $${tls_ca}
    server: $${public_fqdn}
  name: $${cluster_name}
contexts:
- context:
    cluster: $${cluster_name}
    user: $${user_name}
  name: default
current-context: default
kind: Config
preferences: {}
users:
- name: $${user_name}
  user:
    client-certificate-data: $${tls_user_crt}
    client-key-data: $${tls_user_key}
EOF

  vars {
    tls_ca       = "${base64encode(local.tls_ca_crt)}"
    public_fqdn  = "https://${local.external_fqdn}"
    cluster_name = "${local.cluster_fqdn}"
    user_name    = "admin"
    tls_user_crt = "${base64encode(tls_locally_signed_cert.k8s_admin.cert_pem)}"
    tls_user_key = "${base64encode(tls_private_key.k8s_admin.private_key_pem)}"
  }
}

// Write the admin kubeconfig to the local filesystem.
resource "local_file" "k8s_admin_kubeconfig" {
  content  = "${data.template_file.k8s_admin_kubeconfig.rendered}"
  filename = "data/${var.name}/kubeconfig"
}

output "kubeconfig" {
    value = "data/${var.name}/kubeconfig"
}
