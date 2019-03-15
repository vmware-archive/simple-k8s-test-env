#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

! /bin/sh -c 'set -o pipefail' >/dev/null 2>&1 || set -o pipefail

usage() {
  cat <<EOF 1>&2
usage: sk8e2e NAME CMD [ARGS...]

ARGS

  NAME
    The name of the cluster to deploy. Should be safe to use as a host and file 
    name. Must be unique in the content of the vCenter to which the cluster is 
    being deployed as well as in the context of the data directory.

  CMD
    The command to execute.

COMMANDS

  up
    Turns up a new cluster

  down
    Turns down an existing cluster

  destroy
    Destroys a cluster with destroy.sh instead of Terraform.

  info [OUTPUTS...]
    Prints information about an existing cluster. If no arguments are provided 
    then all of the information is printed.

  plan
    A dry-run version of up

  prow
    Used when executed as a Prow job. This command executes up, test, and
    destroy. The results are copied into the ARTIFACTS directory, a location
    provided by Prow.

  test
    Schedules the e2e conformance tests.

  tdel
    Delete the e2e conformance tests job.

  tlog
    Follows the test job in real time.

  tget
    Blocks until the test job has completed and then downloads the test
    artifacts from the test job.

  tput GCS_PATH KEY_FILE
    Blocks until the test job has completed, downloads the test artifacts from
    the test job, and then processes and uploads the test artifacts to a GCS
    bucket.

    Please note this command takes the following arguments:

      GCS_PATH     The path to the GCS bucket and directory to which to write
                   the processed test artifacts.

      KEY_FILE     A Google Cloud key that has write permissions for GCS_PATH.

  version
    Prints the client and server version of Kubernetes.
EOF
}

[ -z "${DEBUG}" ] || set -x

# Returns a success if the provided argument is a whole number.
is_whole_num() { echo "${1}" | grep -q '^[[:digit:]]\{1,\}$'; }

# echo2 echos the provided arguments to file descriptor 2, stderr.
echo2() {
  echo "${@}" 1>&2
}

STDERR="/dev/null"

# error MSG [EXIT_CODE]
#  Prints the supplied message to stderr and returns the shell's
#  last known exit code, $?. If a second argument is provided the
#  function returns its value as the return code.
error() {
  _ec="${?}"; is_whole_num "${2}" && _ec="${2}"
  [ "${_ec}" -eq "0" ] && return 0
  echo2 "ERROR [${_ec}] - ${1}" | tee "${STDERR}"; return "${_ec}"
}

# fatal MSG [EXIT_CODE]
#  Prints the supplied message to stderr and returns the shell's
#  last known exit code, $?. If a second argument is provided the
#  function returns its value as the return code.
fatal() {
  _ec="${?}"; is_whole_num "${2}" && _ec="${2}"
  [ "${_ec}" -eq "0" ] && exit 0
  echo2 "FATAL [${_ec}] - ${1}" | tee "${STDERR}"; exit "${_ec}"
}

hash7() {
  { md5sum 2>/dev/null || md5; } | awk '{print $1}' | cut -c-7
}

# Define how curl should be used.
CURL="curl --retry 5 --retry-delay 1 --retry-max-time 120"

aws_vmc_routing_network_subnet_arn() {
  aws ec2 describe-subnets | \
    jq -r '.Subnets | .[] | select(.Tags != null) | select(any(.Tags[]; .Key == "Name" and .Value == "VMC Routing Network")) | .SubnetId'
}

aws_create_load_balancer() {
  # Get the subnet for the VMC routing network.
  aws_subnet_id="$(aws_vmc_routing_network_subnet_arn)" || \
    { error "error getting ARN for VMC routing network's subnet"; return; }

  # Create a temp file to write the result of the command that creates the
  # load balancer.
  lb_json="$(mktemp)" || \
    { error "error creatint temp file for load balancer JSON"; return; }

  # Create the load balancer.
  #
  # See https://docs.aws.amazon.com/cli/latest/reference/elbv2/create-load-balancer.html
  # for example output from this command.
  aws elbv2 create-load-balancer \
    --name "sk8lb-${CLUSTER_ID}" \
    --scheme internet-facing \
    --type network \
    --ip-address-type ipv4 \
    --tags "Key=Cluster,Value=${NAME}.${CLUSTER_ID}" \
    --subnets "${aws_subnet_id}" 1>"${lb_json}" || \
    { error "failed to create load balancer"; return; }
}

################################################################################
##                                   main                                     ##
################################################################################

# If there are no arguments or the first argument is sh|bash|shell then drop
# into a shell.
{ [ "${#}" -eq 0 ] || \
  echo "${1}" | \
  grep -iq '^[[:space:]]\{0,\}\(sh\|bash\|shell\)[[:space:]]\{0,\}$'; } && \
  exec /bin/bash

# Drop out of the script if there aren't at least two args.
[ "${#}" -lt 2 ] && { echo2 "incorrect number of argumenmts"; usage; exit 1; }

NAME="${1}"; shift
CMD="${1}"; shift
DATA="data/${NAME}"
STDERR="${DATA}/stderr.log"

if [ -n "${ARTIFACTS}" ] && [ -d "${ARTIFACTS}" ]; then
  RESULTS="${ARTIFACTS}"
else
  RESULTS="data/${NAME}/e2e"
fi

goodbye() {
  _exit_code="${1:-${?}}"
  printf '\nSo long and thanks for all the fish.\n'
  exit "${_exit_code}"
}

destroy() {
  TERRAFORM_STATE="${DATA}" ./destroy.sh "${1}"
}

# If the cmd is "destroy" then use destroy.sh to turn down the cluster.
if echo "${CMD}" | grep -iq '^[[:space:]]\{0,\}destroy[[:space:]]\{0,\}$'; then
  if [ -f "${DATA}/clusterid" ]; then
    destroy "${NAME}.$(cat "${DATA}/clusterid")"
  else
    destroy "${NAME}"
  fi
  goodbye
fi

# Configure the data directory.
mkdir -p "${DATA}" "${RESULTS}"
sed -i 's~data/terraform.state~'"${DATA}"'/terraform.state~g' data.tf

# Create the cluster ID.
if [ ! -f "${DATA}/clusterid" ]; then
  if [ -e "/proc/sys/kernel/random/uuid" ]; then
    CLUSTER_ID="$(cat <"/proc/sys/kernel/random/uuid")"
  elif command -v uuidgen >/dev/null 2>&1; then
    CLUSTER_ID="$(uuidgen)"
  else
    CLUSTER_ID="$(date +%s)"
  fi
  CLUSTER_ID="$(echo "${CLUSTER_ID}" | hash7)"
  printf "%s" "${CLUSTER_ID}" >"${DATA}/clusterid"
fi
CLUSTER_ID="$(cat "${DATA}/clusterid")"

export TF_VAR_data_dir="${DATA}"
export TF_VAR_name="${NAME}.${CLUSTER_ID}"
export TF_VAR_ctl_vm_name="c%02d.${CLUSTER_ID}"
export TF_VAR_wrk_vm_name="w%02d.${CLUSTER_ID}"
export TF_VAR_ctl_network_hostname="c%02d"
export TF_VAR_wrk_network_hostname="w%02d"
export TF_VAR_network_domain="${CLUSTER_ID}.sk8"
export TF_VAR_network_search_domains="${CLUSTER_ID}.sk8"

# If any of the AWS access keys are missing then exit the script.
EXTERNAL=false
if [ "${CMD}" = "plugins" ] || \
  { [ -n "${AWS_ACCESS_KEY_ID}" ] && \
  [ -n "${AWS_SECRET_ACCESS_KEY}" ] && \
  [ -n "${AWS_DEFAULT_REGION}" ] && \
  [ ! "${AWS_LB}" = "false" ]; }; then

  EXTERNAL=true

  # Copy the providers into the project.
  cp -f vmc/providers_aws.tf vmc/providers_local.tf vmc/providers_tls.tf .

  # Copy the load-balancer configuration into the project.
  cp -f vmc/load_balancer.tf load_balancer.tf

  # Copy the external K8s kubeconfig generator into the project.
  cp -f vmc/k8s_admin.tf .

  echo "external cluster access enabled"
fi

# Check to see if a CA needs to be generated.
#
# The warning (SC2154) for TF_VAR_tls_ca_crt and TF_VAR_tls_ca_key not being 
# assigned is disabled since the environment variables are defined externally.
#
# shellcheck disable=SC2154
if [ -z "${TF_VAR_tls_ca_crt}" ] || [ -z "${TF_VAR_tls_ca_key}" ]; then

  # If either the CA certificate or key is missing then a new pair must
  # be generated.
  unset TF_VAR_tls_ca_crt TF_VAR_tls_ca_key

  # Copy the providers into the project.
  cp -f vmc/providers_tls.tf .

  # Copy the CA generator into the project.
  cp -f vmc/tls_ca.tf .

  echo "one-time TLS CA generation enabled"
fi

# If no sk8 URL is defined, there's a gist authentication file at
# /root/.gist, and there's a sk8 source at /tmp/sk8.sh, then upload
# the sk8 script to a gist so the local sk8 script is consumeable
# by Terraform's http provider.
if [ -z "${TF_VAR_sk8_url}" ] && \
   [ -f /root/.gist ] && [ -f /tmp/sk8.sh ]; then

  # Check to see if an existing sk8 gist can be updated.
  if [ -f "data/.sk8.gist" ]; then

    echo "updating an existing sk8 gist"

    # Read the gist URL from the file or exit with an error.
    gurl="$(cat data/.sk8.gist)" || fatal "failed to read data/.sk8.gist"

    # If the file was empty then exist with an error.
    [ -n "${gurl}" ] || fatal "data/.sk8.gist is empty" 1

    # If a gist ID can be parsed from the URL then use it to update
    # an existing gist instead of creating a new one.
    if ! gist_id="$(echo "${gurl}" | grep -o '[^/]\{32\}')"; then
      fatal "failed to parse gist ID from gist url ${gurl}"
    fi

    gist -u "${gist_id}" /tmp/sk8.sh 1>/dev/null || 
      fatal "failed to update existing sk8 gist ${gurl}"

  # There's no existing sk8 gist, so one should be created.
  else
    echo "create a new sk8 gist"

    # Create a new gist with data/sk8.sh
    gurl=$(gist -pR /tmp/sk8.sh | tee data/.sk8.gist) || \
      fatal "failed to uplooad sk8 gist"
  fi

  # Provide the sk8 gist URL to Terraform.
  rgurl="$(echo "${gurl}" | \
    sed 's~gist.github.com~gist.githubusercontent.com~')" || \
    fatal "failed to transform gist URL ${gurl}"

  export TF_VAR_sk8_url="${rgurl}/sk8.sh"
  echo "using sk8 gist ${TF_VAR_sk8_url}"
fi

# Make sure terraform has everything it needs.
terraform init

# If the command was "plugins", then the container should exit after
# initializing Terraform and downloading the plug-ins.
if [ "${CMD}" = "plugins" ]; then
  rm -fr .terraform/terraform.tfstate "${DATA}"
  exit 0
fi

# Check to see if there is a previous etcd discovery URL value. If so, 
# overwrite etcd.tf with that information.
if disco=$(terraform output etcd 2>/dev/null) && [ -n "${disco}" ]; then
  printf 'locals {\n  etcd_discovery = "%s"\n}\n' "${disco}" >etcd.tf
fi

# The e2e namespace.
if [ ! -f "${DATA}/namespace" ]; then
  E2E_NAMESPACE="sk8e2e-$(date +%s | hash7)"
  printf "%s" "${E2E_NAMESPACE}" >"${DATA}/namespace"
fi
E2E_NAMESPACE="$(cat "${DATA}/namespace")"

# Define helpful means of executing kubectl and sonobuoy with the kubeconfig
# and e2e namespace pre-configured.
KUBECONFIG="${DATA}/kubeconfig"

cat <<EOF >"${DATA}/kubectl"
#!/bin/sh
[ -f "${KUBECONFIG}" ] && export KUBECONFIG="${KUBECONFIG}"
exec kubectl -n "${E2E_NAMESPACE}" "\${@}"
EOF
cat <<EOF >"${DATA}/sonobuoy"
#!/bin/sh
[ -f "${KUBECONFIG}" ] && export KUBECONFIG="${KUBECONFIG}"
exec sonobuoy -n "${E2E_NAMESPACE}" "\${@}"
EOF
chmod 0755 "${DATA}/kubectl" "${DATA}/sonobuoy"

KUBECTL="${DATA}/kubectl"
SONOBUOY="${DATA}/sonobuoy"

sonobuoy_status_ok() {
  ${SONOBUOY} status 2>>"${STDERR}" | grep -iq 'e2e[[:space:]]\{0,\}complete'
}

get_e2e_pod_name() {
  ${KUBECTL} get pods --no-headers 2>>"${STDERR}" | \
    grep 'e2e.\{0,\}Running' | awk '{print $1}'
}

keepalive_and_log() {
  # shellcheck disable=SC2086
  keepalive -- ${KUBECTL} logs -f -c e2e "${1}" 2>>"${STDERR}"
}

test_log() {
  i=0; while ! sonobuoy_status_ok; do
    [ "${i}" -ge 100 ] && { error "timed out following test logs" 1; return; }
    if e2e_pod_name=$(get_e2e_pod_name) && [ -n "${e2e_pod_name}" ]; then
      keepalive_and_log "${e2e_pod_name}" && return
    fi
    echo "."; sleep 3; i=$((i+1))
  done
  ${SONOBUOY} logs
}

retrieve_and_inflate() {
  { ${SONOBUOY} retrieve "${RESULTS}" && \
    tar xzf "${RESULTS}/"*.tar.gz -C "${RESULTS}"; } \
    2>>"${STDERR}" 1>&2
}

test_get() {
  i=0; while ! retrieve_and_inflate; do
    [ "${i}" -ge 100 ] && { error "timed out getting test results" 1; return; }
    rm -fr "${RESULTS:?}/*"
    echo "."; sleep 3; i=$((i+1))
  done
  echo "test results downloaded to ${RESULTS}"

  # Remove the e2e tarball once it has been inflated.
  rm -f "${RESULTS}/"*.tar.gz || true

  # Copy the e2e results into the root of the results directory.
  cp -f "${RESULTS}/plugins/e2e/results/"* "${RESULTS}/" 2>/dev/null || true
}

test_put() {
  # Drop out of the script if there aren't at least two args.
  [ "${#}" -lt 2 ] && \
    { echo2 "incorrect number of argumenmts"; usage; return 1; }

  GCS_PATH="${1}"; shift
  KEY_FILE="${1}"; shift

  # Ensure the key file exists.
  [ -f "${KEY_FILE}" ] || \
    { error "GCS key file ${KEY_FILE} does not exist" 1; return; }

  # Ensure the test results exist.
  [ -f "${RESULTS}/e2e.log" ] || { error "missing test results" 1; return; }

  ./upload_e2e.py --bucket   "${GCS_PATH}" \
                  --junit    "${RESULTS}/"'junit*.xml' \
                  --log      "${RESULTS}/e2e.log" \
                  --key-file "${KEY_FILE}" || \
    { error "failed to upload the e2e test results"; return; }

  echo "test results uploaded to GCS"
}

test_delete() {
  ${SONOBUOY} delete && rm -f "${DATA}/namespace" "${DATA}/sonobuoy.yaml"
}

test_status() {
  ${SONOBUOY} status --show-all
}

test_start() {
  rm -fr "${RESULTS:?}/*"

  KUBE_CONFORMANCE_IMAGE="${KUBE_CONFORMANCE_IMAGE:-gcr.io/heptio-images/kube-conformance:latest}"
  E2E_FOCUS="${E2E_FOCUS:-\\\[Conformance\\\]}"
  E2E_SKIP="${E2E_SKIP:-Alpha|\\\[(Disruptive|Feature:[^\\\]]+|Flaky)\\\]}"

  sed -e 's~{{E2E_FOCUS}}~'"${E2E_FOCUS}"'~g' \
      -e 's~{{E2E_SKIP}}~'"${E2E_SKIP}"'~g' \
      -e 's~{{NAMESPACE}}~'"${E2E_NAMESPACE}"'~g' \
      -e 's~{{KUBE_CONFORMANCE_IMAGE}}~'"${KUBE_CONFORMANCE_IMAGE}"'~g' \
      >"${DATA}/sonobuoy.yaml" <sonobuoy.yaml || \
      { error "failed to interpolate sonobuoy.yaml"; return; }

  # Create the e2e job.
  ${KUBECTL} apply -f "${DATA}/sonobuoy.yaml" || \
    { error "failed to create e2e resources"; return; }

  test_log
}

print_version() {
  if [ -f "${KUBECONFIG}" ]; then
    ${KUBECTL} version || true
  else
    ${KUBECTL} version --client || true
  fi
}

turn_up() {
  if [ "${EXTERNAL}" = "true" ]; then
    aws_create_load_balancer || \
      { error "error creating load balancer"; return; }

    lb_arn="$(jq -r '.LoadBalancers[0].LoadBalancerArn' <"${lb_json}")" || \
      { error "error getting ARN for load balancer"; return; }

    lb_dns="$(jq -r '.LoadBalancers[0].DNSName' <"${lb_json}")" || \
      { error "error getting DNS for load balancer"; return; }

    export TF_VAR_lb_arn="${lb_arn}" TF_VAR_lb_dns="${lb_dns}"
  fi

  terraform apply -auto-approve || \
    { error "failed to turn up cluster"; return; }

  if [ "${EXTERNAL}" = "true" ]; then
    printf "waiting for cluster to finish coming online... "
    i=0 && while true; do
      [ "${i}" -ge 100 ] && { error "timed out waiting for cluster" 1; return; }
      [ "ok" = "$(${CURL} "http://${lb_dns}/healthz" 2>/dev/null)" ] && \
        echo "ok" && break
      printf "."; sleep 3; i=$((i+1))
    done
  fi
}

prow() {
  turn_up && print_version && test_start && test_get; _ec_1="${?}"
  destroy "${NAME}.${CLUSTER_ID}";                    _ec_2="${?}"
  { [ "${_ec_1}" -ne "0" ] && goodbye "${_ec_1}"; } || goodbye "${_ec_2}"
}

# shellcheck disable=SC2154
if [ -n "${TF_VAR_k8s_version}" ] && [ -n "${SKIP_K8S_VERSIONS}" ] && \
  echo "${TF_VAR_k8s_version}" | grep -qF "${SKIP_K8S_VERSIONS}"; then
  echo "skipping K8s ${TF_VAR_k8s_version}"
else
  case "${CMD}" in
    plan)
      terraform plan
      ;;
    info|status)
      terraform output "${@}"
      ;;
    prow)
      prow
      ;;
    up)
      turn_up
      ;;
    down)
      terraform destroy -auto-approve
      ;;
    test)
      test_start
      ;;
    tsta|test-status)
      test_status
      ;;
    tdel|test-delete)
      test_delete
      ;;
    tlog|test-log)
      test_log
      ;;
    tget|test-results-get|test-results-download)
      test_get
      ;;
    tput|test-results-put|test-results-upload)
      test_put "${@}"
      ;;
    version)
      print_version
      ;;
    plugins)
      echo "downloaded terraform plug-ins"
      ;;
    *)
      echo2 "invalid command"; usage; exit 1
      ;;
  esac
fi

goodbye "${?}"
