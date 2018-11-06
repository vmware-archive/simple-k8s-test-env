#!/bin/sh

# Yakity
#
# Copyright (c) 2018 VMware, Inc. All Rights Reserved.
#
# This product is licensed to you under the Apache 2.0 license (the "License").
# You may not use this product except in compliance with the Apache 2.0 License.
#
# This product may include a number of subcomponents with separate copyright
# notices and license terms. Your use of these subcomponents is subject to the
# terms and conditions of the subcomponent's license, as noted in the LICENSE
# file.

# posix compliant
# verified by https://www.shellcheck.net

#
# For Kubernetes clusters deployed to VMC with a linked AWS account, this
# program creates a load balancer that is used to provied external access
# to the privately routed cluster.
#

# Load the yakity commons library.
# shellcheck disable=SC1090
. "$(pwd)/yakity-common.sh"

_done_file="$(pwd)/.$(basename "${0}").done"
[ ! -f "${_done_file}" ] || exit 0

# Do not create the load balancer unless requested.
if is_false "$(rpc_get CREATE_LOAD_BALANCER)"; then
  info "load balancer creation disabled"
  exit 0
fi

# Ensure the aws program is available.
require_program aws

# The AWS access information is required to create a load balancer.
AWS_ACCESS_KEY_ID="$(rpc_get AWS_ACCESS_KEY_ID)"
AWS_SECRET_ACCESS_KEY="$(rpc_get AWS_SECRET_ACCESS_KEY)"
AWS_DEFAULT_REGION="$(rpc_get AWS_DEFAULT_REGION)"

require AWS_ACCESS_KEY_ID \
        AWS_SECRET_ACCESS_KEY \
        AWS_DEFAULT_REGION

export  AWS_ACCESS_KEY_ID \
        AWS_SECRET_ACCESS_KEY \
        AWS_DEFAULT_REGION

# Get the cluster ID.
cluster_id="$(rpc_get CLUSTER_ID)"
require cluster_id

# Get the short version of the cluster ID.
cluster_id7="$(get_cluster_id7 "${cluster_id}")"

get_vmc_subnet_arn() {
  aws ec2 describe-subnets | \
    jq -r '.Subnets | .[] | select(.Tags != null) | select(any(.Tags[]; .Key == "Name" and .Value == "VMC Routing Network")) | .SubnetId'
}

get_vmc_subnet_az() {
  aws ec2 describe-subnets | \
    jq -r '.Subnets | .[] | select(.Tags != null) | select(any(.Tags[]; .Key == "Name" and .Value == "VMC Routing Network")) | .AvailabilityZone'
}

get_default_vpc_arn() {
  aws ec2 describe-vpcs | jq -r '.Vpcs | .[] | select(.IsDefault) | .VpcId'
}

get_cluster_fqdn() {
  cluster_name="$(rpc_get CLUSTER_NAME)"
  cluster_name="${cluster_name:-kubernetes}"
  domain_name="$(hostname -d)"
  echo "${cluster_name}.${domain_name}"
}

create_load_balancer() {
  info "creating load balancer"

  # Get the subnet for the VMC routing network.
  aws_subnet_id="$(get_vmc_subnet_arn)"

  # Get the FQDN of the K8s cluster being deployed.
  cluster_fqdn="$(get_cluster_fqdn)"

  # Create a temp file to write the result of the command that creates the
  # load balancer.
  lb_json="$(mktemp)"

  # Create the load balancer.
  #
  # See https://docs.aws.amazon.com/cli/latest/reference/elbv2/create-load-balancer.html
  # for example output from this command.
  aws elbv2 create-load-balancer \
    --name "yakity-${cluster_id7}" \
    --scheme internet-facing \
    --type network \
    --ip-address-type ipv4 \
    --tags "Key=ClusterID,Value=${cluster_id}" \
    --subnets "${aws_subnet_id}" | tee "${lb_json}" || \
    fatal "failed to create load balancer"

  # Get the LB's ARN.
  lb_arn="$(jq -r '.LoadBalancers[0].LoadBalancerArn' <"${lb_json}")"

  # Get the LB's DNS name.
  lb_dns="$(jq -r '.LoadBalancers[0].DNSName' <"${lb_json}")"

  # Set the EXTERNAL_FQDN to the LB's DNS name.
  rpc_set EXTERNAL_FQDN "${lb_dns}"

  # Persist the LB's ARN.
  rpc_set LOAD_BALANCER_ID "${lb_arn}"

  # Get rid of the on-disk JSON.
  /bin/rm -f "${lb_json}"

  info "created new load balancer: lb_arn=${lb_arn} lb_dns=${lb_dns}"
}

connect_load_balancer() {
  lb_arn="$(rpc_get LOAD_BALANCER_ID)"
  lb_dns="$(rpc_get EXTERNAL_FQDN)"
  require lb_arn lb_dns

  # Get the FQDN of the K8s cluster being deployed.
  cluster_fqdn="$(get_cluster_fqdn)"

  # Get the ARN of the default VPC.
  aws_vpc_id="$(get_default_vpc_arn)"

  # Create the target groups.
  #
  # See https://docs.aws.amazon.com/cli/latest/reference/elbv2/create-target-group.html
  # for example output from this command.
  tg_http_json="$(mktemp)"
  aws elbv2 create-target-group \
    --name "yakity-${cluster_id7}-http" \
    --target-type ip \
    --protocol TCP \
    --port 80 \
    --vpc-id "${aws_vpc_id}" \
    --health-check-port 80 | tee "${tg_http_json}" || \
    fatal "failed to create load balancer target group http"
  tg_http_arn="$(jq -r '.TargetGroups[0].TargetGroupArn' <"${tg_http_json}")"
  info "created load balancer target group http: target_group_arn=${tg_http_arn}"

  # Add tags to the target groups.
  aws elbv2 add-tags \
    --resource-arns "${tg_http_arn}" \
    --tags "Key=ClusterID,Value=${cluster_id}" || \
    fatal "failed to create load balancer target group http tags"

  tg_https_json="$(mktemp)"
  aws elbv2 create-target-group \
    --name "yakity-${cluster_id7}-https" \
    --target-type ip \
    --protocol TCP \
    --port 443 \
    --vpc-id "${aws_vpc_id}" \
    --health-check-port 80 | tee "${tg_https_json}" || \
    fatal "failed to create load balancer target group https"
  tg_https_arn="$(jq -r '.TargetGroups[0].TargetGroupArn' <"${tg_https_json}")"
  info "created load balancer target group https: target_group_arn=${tg_https_arn}"

  # Add tags to the target groups.
  aws elbv2 add-tags \
    --resource-arns "${tg_http_arn}" \
    --tags "Key=ClusterID,Value=${cluster_id}" || \
    fatal "failed to create load balancer target group https tags"

  # Create the listeners.
  #
  # See https://docs.aws.amazon.com/cli/latest/reference/elbv2/create-listener.html
  # for example output from this command.
  aws elbv2 create-listener \
    --load-balancer-arn "${lb_arn}" \
    --protocol TCP \
    --port 80 \
    --default-actions "Type=forward,TargetGroupArn=${tg_http_arn}" || \
    fatal "failed to create load balancer listener http"

  aws elbv2 create-listener \
    --load-balancer-arn "${lb_arn}" \
    --protocol TCP \
    --port 443 \
    --default-actions "Type=forward,TargetGroupArn=${tg_https_arn}" || \
    fatal "failed to create load balancer listener https"

  # Register the targets.
  secure_port="$(rpc_get SECURE_PORT)"
  secure_port="${secure_port:-443}"

  cluster_name="$(rpc_get CLUSTER_NAME)"
  cluster_name="${cluster_name:-kubernetes}"
  network_name="$(rpc_get NETWORK_NAME)"
  network_name="${network_name:-$(hostname -d)}"
  cluster_fqdn="${cluster_name}.${network_name}"

  ipv4_addrs="$(host -t A "${cluster_fqdn}" | awk '{print $4}' | sort -u)"
  debug "registering targets: ${ipv4_addrs}"

  aws_subnet_az="$(get_vmc_subnet_az)"

  for i in ${ipv4_addrs}; do
    http_target="Id=${i},Port=80,AvailabilityZone=${aws_subnet_az}"
    https_target="Id=${i},Port=${secure_port},AvailabilityZone=${aws_subnet_az}"
    if [ -z "${http_target_list}" ]; then
      http_target_list="${http_target}"
    else
      http_target_list="${http_target_list} ${http_target}"
    fi
    if [ -z "${https_target_list}" ]; then
      https_target_list="${https_target}"
    else
      https_target_list="${https_target_list} ${https_target}"
    fi
  done

  aws elbv2 register-targets \
    --target-group-arn "${tg_http_arn}" \
    --targets "${http_target_list}" || \
    fatal "failed to create load balancer http targets"

  aws elbv2 register-targets \
    --target-group-arn "${tg_https_arn}" \
    --targets "${https_target_list}" || \
    fatal "failed to create load balancer https targets"

  # Get rid of the on-disk JSON.
  /bin/rm -f "${tg_http_json}" "${tg_https_json}"

  info "connected load balancer: lb_arn=${lb_arn} lb_dns=${lb_dns} ipv4_addrs=${ipv4_addrs}"
}

case "${1}" in
create)
  create_load_balancer
  ;;
connect)
  connect_load_balancer && touch "${_done_file}"
  ;;
esac
