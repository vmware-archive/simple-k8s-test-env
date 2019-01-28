// The ID of the subnet to which the load balancer is attached
variable "lb_subnet_id" {
  default = "subnet-fdee56b6"
}

// The ID of the VPC to which the load balancer is attached.
variable "lb_vpc_id" {
  default = "vpc-8f7048f6"
}

resource "aws_lb" "lb" {
  name_prefix        = "yaklb-"
  load_balancer_type = "network"
  internal           = false
  ip_address_type    = "ipv4"
  subnets            = ["${var.lb_subnet_id}"]

  tags {
    Cluster = "${var.name}"
  }
}

/*resource "aws_lb_listener" "ssh" {
  load_balancer_arn = "${aws_lb.lb.arn}"
  port              = "22"
  protocol          = "TCP"

  default_action {
    target_group_arn = "${aws_lb_target_group.ssh.arn}"
    type             = "forward"
  }
}*/

resource "aws_lb_listener" "http" {
  load_balancer_arn = "${aws_lb.lb.arn}"
  port              = "80"
  protocol          = "TCP"

  default_action {
    target_group_arn = "${aws_lb_target_group.http.arn}"
    type             = "forward"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = "${aws_lb.lb.arn}"
  port              = "443"
  protocol          = "TCP"

  default_action {
    target_group_arn = "${aws_lb_target_group.https.arn}"
    type             = "forward"
  }
}

/*resource "aws_lb_target_group" "ssh" {
  name_prefix = "yaklb-"
  target_type = "ip"
  port        = "22"
  protocol    = "TCP"
  vpc_id      = "${var.lb_vpc_id}"

  health_check = {
    port = "80"
  }

  tags {
    Cluster = "${var.name}"
  }
}*/

resource "aws_lb_target_group" "http" {
  name_prefix = "yaklb-"
  target_type = "ip"
  port        = "80"
  protocol    = "TCP"
  vpc_id      = "${var.lb_vpc_id}"

  health_check = {
    port = "80"
  }

  tags {
    Cluster = "${var.name}"
  }
}

resource "aws_lb_target_group" "https" {
  name_prefix = "yaklb-"
  target_type = "ip"
  port        = "${var.api_secure_port}"
  protocol    = "TCP"
  vpc_id      = "${var.lb_vpc_id}"

  health_check = {
    port = "80"
  }

  tags {
    Cluster = "${var.name}"
  }
}

/*resource "aws_lb_target_group_attachment" "ssh" {
  count             = "${var.ctl_count}"
  target_group_arn  = "${aws_lb_target_group.ssh.arn}"
  target_id         = "${element(vsphere_virtual_machine.controller.*.default_ip_address, count.index)}"
  port              = "22"
  availability_zone = "all"
}*/

resource "aws_lb_target_group_attachment" "http" {
  count             = "${var.ctl_count}"
  target_group_arn  = "${aws_lb_target_group.http.arn}"
  target_id         = "${element(vsphere_virtual_machine.controller.*.default_ip_address, count.index)}"
  port              = "80"
  availability_zone = "all"
}

resource "aws_lb_target_group_attachment" "https" {
  count             = "${var.ctl_count}"
  target_group_arn  = "${aws_lb_target_group.https.arn}"
  target_id         = "${element(vsphere_virtual_machine.controller.*.default_ip_address, count.index)}"
  port              = "${var.api_secure_port}"
  availability_zone = "all"
}

locals {
  external_fqdn = "${aws_lb.lb.dns_name}"
}

