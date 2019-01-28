#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

set -o pipefail

usage() {
  cat <<EOF 1>&2
usage: yake2e NAME CMD [ARGS...]

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
    Schedules the e2e conformance tests as a job.

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

# If no yakity URL is defined, there's a gist authentication file at
# /root/.gist, and there's a yakity source at /tmp/yakity.sh, then upload
# the yakity script to a gist so the local yakity script is consumeable
# by Terraform's http provider.
if [ -z "${TF_VAR_yakity_url}" ] && \
   [ -f /root/.gist ] && [ -f /tmp/yakity.sh ]; then

  # Check to see if an existing yakity gist can be updated.
  if [ -f "data/.yakity.gist" ]; then

    echo "updating an existing yakity gist"

    # Read the gist URL from the file or exit with an error.
    gurl="$(cat data/.yakity.gist)" || fatal "failed to read data/.yakity.gist"

    # If the file was empty then exist with an error.
    [ -n "${gurl}" ] || fatal "data/.yakity.gist is empty" 1

    # If a gist ID can be parsed from the URL then use it to update
    # an existing gist instead of creating a new one.
    if ! gist_id="$(echo "${gurl}" | grep -o '[^/]\{32\}')"; then
      fatal "failed to parse gist ID from gist url ${gurl}"
    fi

    gist -u "${gist_id}" /tmp/yakity.sh 1>/dev/null || 
      fatal "failed to update existing yakity gist ${gurl}"

  # There's no existing yakity gist, so one should be created.
  else
    echo "create a new yakity gist"

    # Create a new gist with data/yakity.sh
    gurl=$(gist -pR /tmp/yakity.sh | tee data/.yakity.gist) || \
      fatal "failed to uplooad yakity gist"
  fi

  # Provide the yakity gist URL to Terraform.
  rgurl="$(echo "${gurl}" | \
    sed 's~gist.github.com~gist.githubusercontent.com~')" || \
    fatal "failed to transform gist URL ${gurl}"

  export TF_VAR_yakity_url="${rgurl}/yakity.sh"
  echo "using yakity gist ${TF_VAR_yakity_url}"
fi

# Make sure terraform has everything it needs.
terraform init

# Check to see if there is a previous etcd discovery URL value. If so, 
# overwrite etcd.tf with that information.
if disco=$(terraform output etcd 2>/dev/null) && [ -n "${disco}" ]; then
  printf 'locals {\n  etcd_discovery = "%s"\n}\n' "${disco}" >etcd.tf
fi

setup_kube() {
  kube_dir="data/${NAME}/.kubernetes/linux_amd64"; mkdir -p "${kube_dir}"
  export PATH="${kube_dir}:${PATH}"

  # Get the external FQDN of the cluster from the Terraform output cache.
  ext_fqdn=$(terraform output external_fqdn) || \
    fatal "failed to read external fqdn"

  # If there is a cached version of the artifact prefix then read it.
  if [ -f "data/${NAME}/artifactz" ]; then

    echo "reading existing artifactz.txt"

    # Get the kubertnetes artifact prefix from the file.
    kube_prefix=$(cat "data/${NAME}/artifactz") || \
      fatal "failed to read data/${NAME}/artifactz"

  # The artifact prefix has not been cached, so cache it.
  else
    # Get the artifact prefix from the cluster.
    kube_prefix=$(${CURL} "http://${ext_fqdn}/artifactz" | \
      tee "data/${NAME}/artifactz") || \
      fatal "failed to get k8s artifactz prefix"
  fi

  # If the kubectl program has not been cached then it needs to be downloaded.
  if [ ! -f "${kube_dir}/kubectl" ]; then
    ${CURL} -L "${kube_prefix}/kubernetes-client-linux-amd64.tar.gz" | \
      tar xzC "${kube_dir}" --strip-components=3
    exit_code="${?}" && \
      [ "${exit_code}" -gt "1" ] && \
      fatal "failed to download kubectl" "${exit_code}"
  fi

  # Define an alias for the kubectl program that includes the path to the
  # kubeconfig file and targets the e2e namespace for all operations.
  #
  # The --kubeconfig flag is used instead of exporting KUBECONFIG because
  # this results in command lines that can be executed from the host as
  # well since all paths are relative.
  KUBECTL="kubectl --kubeconfig "data/${NAME}/kubeconfig" -n e2e"
}

get_test_pod_name() {
  printf "getting the name of the e2e pod... "
  i=0; while true; do
    [ "${i}" -ge "100" ] && fatal "failed to get e2e pod" 1
    pod_name=$(${KUBECTL} get pods --no-headers | awk '{print $1}')
    [ -n "${pod_name}" ] && echo "${pod_name}" && return 0
    printf "."
    sleep 3; i=$((i+1))
  done
}

test_log() {
  setup_kube; get_test_pod_name
  echo "waiting for the log to have data"
  i=0; while true; do
    [ "${i}" -ge "100" ] && fatal "failed to get e2e log data" 1
    if b1=$(${KUBECTL} logs --limit-bytes 1 "${pod_name}" run); then
      [ -n "${b1}" ] && echo "${pod_name} has log data" && break
    fi
    printf "."
    sleep 3; i=$((i+1))
  done
  echo "tailing e2e log"
  i=0; while true; do
    [ "${i}" -ge "100" ] && fatal "failed to tail e2e log" 1
    ${KUBECTL} logs -f "${pod_name}" run && break
    echo "."
    sleep 3; i=$((i+1))
  done
}

test_get() {
  setup_kube; get_test_pod_name

  E2E_RESULTS_DIR="${1:-data/${NAME}/e2e}"

  ${KUBECTL} logs "${pod_name}" tgz | \
    base64 -d >"data/${NAME}/e2e-results.tar.gz" || \
    fatal "failed download the e2e test results"
  echo "downloaded the e2e test results"

  mkdir -p "${E2E_RESULTS_DIR}"
  tar xzf "data/${NAME}/e2e-results.tar.gz" -C "${E2E_RESULTS_DIR}" || \
    fatal "failed to inflate the e2e test results"

  echo "test results saved to ${E2E_RESULTS_DIR}"
}

test_put() {
  # Drop out of the script if there aren't at least two args.
  [ "${#}" -lt 2 ] && { echo2 "incorrect number of argumenmts"; usage; exit 1; }

  GCS_PATH="${1}"; shift
  KEY_FILE="${1}"; shift
  E2E_RESULTS_DIR="${1:-data/${NAME}/e2e}"; shift
  
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
  setup_kube
  ${KUBECTL} delete jobs e2e || fatal "failed to delete e2e job"
}

test_start() {
  setup_kube

  # If there's an e2e job spec in the data directy then use that.
  #if [ -f "data/e2e-job.yaml" ]; then
  #  echo "using e2e job spec from data/e2e-job.yaml"
  #  cp "data/e2e-job.yaml" "data/${NAME}"
  #fi

  # If the e2e job spec is not cached then download it from the cluster.
  if [ ! -f "data/${NAME}/e2e-job.yaml" ]; then
    echo "downloading e2e job spec from http://${ext_fqdn}/e2e/job.yaml"
    printf "waiting for e2e job spec to become available... "
    i=0 && while true; do
      [ "${i}" -ge 100 ] && fatal "timed out waiting for e2e job spec" 1
      ${CURL} -I "http://${ext_fqdn}/e2e/job.yaml" | \
        grep -qF 'HTTP/1.1 200 OK' && echo "ok" && break
      printf "."
      sleep 3
      i=$((i+1))
    done

    ${CURL} "http://${ext_fqdn}/e2e/job.yaml" >"data/${NAME}/e2e-job.yaml" || \
      fatal "failed to download e2e job spec"
  fi

  printf "waiting for e2e namespace... "
  i=0 && while true; do
    [ "${i}" -ge 100 ] && fatal "timed out waiting for e2e namespace" 1
    kubectl --kubeconfig "data/${NAME}/kubeconfig" get namespaces | \
      grep -q e2e && echo "ok" && break
    printf "."
    sleep 3
    i=$((i+1))
  done

  # Create the e2e job.
  ${KUBECTL} create -f "data/${NAME}/e2e-job.yaml" || \
    fatal "failed to create e2e job"

  # Get the name of the pod created for the e2e job.
  get_test_pod_name
}

version() {
  kubectl --kubeconfig "data/${NAME}/kubeconfig" version || true
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
      version
      ;;
    sh)
      exec /bin/sh
      ;;
    *)
      echo2 "invalid command"; usage; exit 1
      ;;
  esac
  exit_code="${?}"
fi

echo "So long and thanks for all the fish."
exit "${exit_code:-0}"
