#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

set -e
! /bin/sh -c 'set -o pipefail' >/dev/null 2>&1 || set -o pipefail

usage() {
  cat <<EOF 1>&2
usage: sk8e2e NAME CMD [ARGS...]

ARGS

  NAME
    The name of the cluster to deploy. Should be safe to use as a host and file 
    name. Must be unique in the content of the vCenter to which the cluster is 
    being deployed as well as in the context of the data directory.

    If TF_VAR_cloud_provider=external then "-ccm" is
    appended to whatever name is provided.

  CMD
    The command to execute.

COMMANDS

  up
    Turns up a new cluster

  down
    Turns down an existing cluster

  plan
    A dry-run version of up

  info [OUTPUTS...]
    Prints information about an existing cluster. If no arguments are provided 
    then all of the information is printed.

  test
    Schedules the e2e conformance tests.

  tdel
    Delete the e2e conformance tests job.

  tlog
    Follows the test job in real time.

  tget [RESULTS_DIR]
    Blocks until the test job has completed and then downloads the test
    artifacts from the test job. This command has one optional argument:
    
      RESULTS_DIR  OPTIONAL The path to which the test results are saved.

                   The default value is data/NAME/e2e.

  tput GCS_PATH KEY_FILE [RESULTS_DIR]
    Blocks until the test job has completed, downloads the test artifacts from
    the test job, and then processes and uploads the test artifacts to a GCS
    bucket.

    Please note this command takes the following arguments:

      GCS_PATH     The path to the GCS bucket and directory to which to write
                   the processed test artifacts.

      KEY_FILE     A Google Cloud key that has write permissions for GCS_PATH.

      RESULTS_DIR  OPTIONAL The path to which the test results are saved.

                   The default value is data/NAME/e2e.

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

# fatal MSG [EXIT_CODE]
#  Prints the supplied message to stderr and returns the shell's
#  last known exit code, $?. If a second argument is provided the
#  function returns its value as the return code.
fatal() {
  exit_code="${?}"; is_whole_num "${2}" && exit_code="${2}"
  [ "${exit_code}" -eq "0" ] && exit 0
  echo2 "FATAL [${exit_code}] - ${1}"; exit "${exit_code}"
}

# Define how curl should be used.
CURL="curl --retry 5 --retry-delay 1 --retry-max-time 120"

################################################################################
##                                   main                                     ##
################################################################################
# Drop out of the script if there aren't at least two args.
[ "${#}" -lt 2 ] && { echo2 "incorrect number of argumenmts"; usage; exit 1; }

NAME="${1}"; shift
CMD="${1}"; shift

# The warning (SC2154) for TF_VARTF_VAR_cloud_provider not being assigned
# is disabled since the environment variable is defined externally.
#
# shellcheck disable=SC2154
if [ "${TF_VAR_cloud_provider}" = "external" ]; then
  NAME_PREFIX="ccm"
fi
old_name="${NAME}"
NAME_PREFIX="${NAME_PREFIX:-k8s}"
NAME="${NAME_PREFIX}-${NAME}"
echo "${old_name} is now ${NAME}"

# Configure the data directory.
mkdir -p data
sed -i 's~data/terraform.state~data/'"${NAME}"'/terraform.state~g' data.tf
export TF_VAR_name="${NAME}"
export TF_VAR_ctl_vm_name="c%02d-${NAME}"
export TF_VAR_wrk_vm_name="w%02d-${NAME}"
#export TF_VAR_ctl_network_hostname="c%02d"
#export TF_VAR_wrk_network_hostname="w%02d"
export TF_VAR_ctl_network_hostname="${TF_VAR_ctl_vm_name}"
export TF_VAR_wrk_network_hostname="${TF_VAR_wrk_vm_name}"

# If any of the AWS access keys are missing then exit the script.
EXTERNAL=false
if [ -n "${AWS_ACCESS_KEY_ID}" ] && \
  [ -n "${AWS_SECRET_ACCESS_KEY}" ] && \
  [ -n "${AWS_DEFAULT_REGION}" ] && \
  [ ! "${AWS_LB}" = "false" ]; then

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

# Ensure the data directory exists.
mkdir -p "data/${NAME}"

# Check to see if there is a previous etcd discovery URL value. If so, 
# overwrite etcd.tf with that information.
if disco=$(terraform output etcd 2>/dev/null) && [ -n "${disco}" ]; then
  printf 'locals {\n  etcd_discovery = "%s"\n}\n' "${disco}" >etcd.tf
fi

# The e2e namespace.
if [ -f "data/${NAME}/namespace" ]; then
  E2E_NAMESPACE="$(cat "data/${NAME}/namespace")"
else
  E2E_NAMESPACE="sk8e2e-$(date +%s | { md5sum 2>/dev/null || md5; } | awk '{print $1}' | cut -c-7)"
  printf "%s" "${E2E_NAMESPACE}" >"data/${NAME}/namespace"
fi

# Define helpful means of executing kubectl and sonobuoy with the kubeconfig
# and e2e namespace pre-configured.
KUBECONFIG="data/${NAME}/kubeconfig"
[ -f "${KUBECONFIG}" ] || unset KUBECONFIG

cat <<EOF >"data/${NAME}/kubectl"
#!/bin/sh
KUBECONFIG="${KUBECONFIG}" exec kubectl -n "${E2E_NAMESPACE}" "\${@}"
EOF
cat <<EOF >"data/${NAME}/sonobuoy"
#!/bin/sh
KUBECONFIG="${KUBECONFIG}" exec sonobuoy -n "${E2E_NAMESPACE}" "\${@}"
EOF
chmod 0755 "data/${NAME}/kubectl" "data/${NAME}/sonobuoy"

KUBECTL="data/${NAME}/kubectl"
SONOBUOY="data/${NAME}/sonobuoy"

wait_for_test_resources() {
  printf "waiting for e2e resources to come online..."
  i=0; while true; do
    [ "${i}" -ge "100" ] && fatal "timed out waiting for e2e resources" 1
    pod_name=$(${KUBECTL} get pods --no-headers | \
      grep 'e2e.\{0,\}Running' | awk '{print $1}')
    [ -n "${pod_name}" ] && echo "${pod_name}" && return 0
    printf "."
    sleep 3; i=$((i+1))
  done
}

get_e2e_pod_name() {
  ${KUBECTL} get pods --no-headers | grep 'e2e.\{0,\}Running' | awk '{print $1}'
}

test_log() {
  if ${SONOBUOY} status 2>&1 | grep -iq 'e2e[[:space:]]\{0,\}complete'; then
    ${SONOBUOY} logs || true
    return
  fi
  wait_for_test_resources
  if ! e2e_pod_name=$(get_e2e_pod_name) || [ -z "${e2e_pod_name}" ]; then
    if ${SONOBUOY} status 2>&1 | grep -iq 'e2e[[:space:]]\{0,\}complete'; then
      ${SONOBUOY} logs || true
      return
    fi
  fi
  echo "e2e pod name: ${e2e_pod_name}"
  # shellcheck disable=SC2086
  if ! keepalive -- ${KUBECTL} logs -f -c e2e "${e2e_pod_name}"; then
    if ${SONOBUOY} status 2>&1 | grep -iq 'e2e[[:space:]]\{0,\}complete'; then
      ${SONOBUOY} logs || true
      return
    fi
  fi
}

test_get() {
  printf "waiting for e2e test(s) to complete..."
  i=0; while true; do
    [ "${i}" -ge "100" ] && fatal "timed out waiting for e2e test(s) to complete" 1
    if ${SONOBUOY} status 2>&1 | grep -iq 'e2e[[:space:]]\{0,\}complete'; then
      echo "success"; break
    fi
    printf "."
    sleep 3; i=$((i+1))
  done

  E2E_RESULTS_DIR="${1:-data/${NAME}/e2e}"
  mkdir -p "${E2E_RESULTS_DIR}"

  printf "downloading e2e test results..."
  i=0; while true; do
    [ "${i}" -ge "100" ] && fatal "timed out downloading e2e test results" 1
    if ${SONOBUOY} retrieve "${E2E_RESULTS_DIR}"; then
      echo "success"; break
    fi
    printf "."
    sleep 3; i=$((i+1))
  done

  tar xzf "${E2E_RESULTS_DIR}/"*.tar.gz -C "${E2E_RESULTS_DIR}" || \
    fatal "failed to inflate e2e test results"

  # Remove the e2e tarball once it has been inflated.
  rm -f "${E2E_RESULTS_DIR}/"*.tar.gz

  echo "test results saved to ${E2E_RESULTS_DIR}"
}

test_put() {
  # Drop out of the script if there aren't at least two args.
  [ "${#}" -lt 2 ] && { echo2 "incorrect number of argumenmts"; usage; exit 1; }

  GCS_PATH="${1}"; shift
  KEY_FILE="${1}"; shift
  E2E_RESULTS_DIR="${1:-data/${NAME}/e2e/plugins/e2e/results}"

  # Ensure the key file exists.
  [ -f "${KEY_FILE}" ] || fatal "GCS key file ${KEY_FILE} does not exist" 1

  # Ensure the test results exist.
  [ -f "${E2E_RESULTS_DIR}/e2e.log" ] || fatal "missing test results" 1

  ./upload_e2e.py --bucket   "${GCS_PATH}" \
                  --junit    "${E2E_RESULTS_DIR}/"'junit*.xml' \
                  --log      "${E2E_RESULTS_DIR}/e2e.log" \
                  --key-file "${KEY_FILE}" || \
    fatal "failed to upload the e2e test results"

  echo "test results uploaded to GCS"
}

test_delete() {
  ${SONOBUOY} delete || fatal "failed to delete e2e resources"
}

test_status() {
  ${SONOBUOY} status 2>&1 | grep -iq 'e2e[[:space:]]\{0,\}complete' || \
    wait_for_test_resources
  ${SONOBUOY} status --show-all || fatal "failed to query e2e status"
}

test_start() {
  KUBE_CONFORMANCE_IMAGE="${KUBE_CONFORMANCE_IMAGE:-gcr.io/heptio-images/kube-conformance:latest}"
  E2E_FOCUS="${E2E_FOCUS:-\\\[Conformance\\\]}"
  E2E_SKIP="${E2E_SKIP:-Alpha|\\\[(Disruptive|Feature:[^\\\]]+|Flaky)\\\]}"

  sed -e 's~{{E2E_FOCUS}}~'"${E2E_FOCUS}"'~g' \
      -e 's~{{E2E_SKIP}}~'"${E2E_SKIP}"'~g' \
      -e 's~{{NAMESPACE}}~'"${E2E_NAMESPACE}"'~g' \
      -e 's~{{KUBE_CONFORMANCE_IMAGE}}~'"${KUBE_CONFORMANCE_IMAGE}"'~g' \
      >"data/${NAME}/sonobuoy.yaml" <sonobuoy.yaml

  # Create the e2e job.
  ${KUBECTL} create -f "data/${NAME}/sonobuoy.yaml" || \
    fatal "failed to create e2e resources"

  wait_for_test_resources

  # Print the status.
  ${SONOBUOY} status --show-all || fatal "failed to query e2e status"
}

print_version() {
  if [ -f "${KUBECONFIG}" ]; then
    ${KUBECTL} version || true
  else
    ${KUBECTL} version --client || true
  fi
}

turn_up() {
  terraform apply -auto-approve || \
    fatal "failed to turn up cluster"

  if [ "${EXTERNAL}" = "true" ]; then
    # Get the external FQDN of the cluster from the Terraform output cache.
    ext_fqdn=$(terraform output external_fqdn) || \
      fatal "failed to read external fqdn"

    printf "waiting for cluster to finish coming online... "
    i=0 && while true; do
      [ "${i}" -ge 100 ] && fatal "timed out waiting for cluster to come online" 1
      [ "ok" = "$(${CURL} "http://${ext_fqdn}/healthz" 2>/dev/null)" ] && \
        echo "ok" && break
      printf "."
      sleep 3
      i=$((i+1))
    done
  fi
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
    info)
      terraform output "${@}"
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
    tsta)
      test_status
      ;;
    tdel)
      test_delete
      ;;
    tlog)
      test_log
      ;;
    tget)
      test_get "${@}"
      ;;
    tput)
      test_put "${@}"
      ;;
    version)
      print_version
      ;;
    sh|bash|shell)
      exec /bin/bash
      ;;
    *)
      echo2 "invalid command"; usage; exit 1
      ;;
  esac
  exit_code="${?}"
fi

echo "So long and thanks for all the fish."
exit "${exit_code:-0}"
