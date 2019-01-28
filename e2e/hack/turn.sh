#!/bin/sh

set -o pipefail

hackd=$(python -c "import os; print(os.path.realpath('$(dirname "${0}")'))")
xdir="${hackd}/.."

# Make sure the docker image is up to date.
make -C "${xdir}" build

# Build the docker run command line.
drun="docker run -it --rm -v "${xdir}/data":/tf/data"

# Map the terraform plug-ins directory into the Docker image so any
# plug-ins Terraform needs are persisted beyond the lifetime of the
# container and saves time when launching new containers.
drun="${drun} -v "${xdir}/.terraform/plugins":/tf/.terraform/plugins"

# If GIST and YAKITY are both set to valid file paths then
# mount GIST to /root/.gist and YAKITY to /tmp/yakity.sh
# so the local yakity source may be uploaded to a gist and made 
# available to Terraform's http provider.
[ -f "${HOME}/.gist" ] && \
  drun="${drun} -v "${HOME}/.gist":/root/.gist:ro"
[ -f "${xdir}/../yakity/yakity.sh" ] && \
  drun="${drun} -v "${xdir}/../yakity/yakity.sh":/tmp/yakity.sh:ro"

# Find all the exported Terraform vars that are not usernames or passwords.
for e in $(env | grep 'TF_VAR_'); do
  echo "${e}" | grep -iq '_\(\(user\(name\)\{0,1\}\)\|password\)=' || \
    drun="${drun} -e ${e}"
done

# Add the environment files if they exist.
[ -f "${xdir}/config.env" ] && drun="${drun} --env-file "${xdir}/config.env""
[ -f "${xdir}/secure.env" ] && drun="${drun} --env-file "${xdir}/secure.env""

# Check the first argument to see if it's a size. The sizes are:
#
#   sm  A single node cluster
#   md  A cluster with one control-plane node and one worker node
#   lg  A cluster with two control-plane nodes that can also schedule
#       workloads and three worker nodes
case "${1}" in
  sm)
    TF_VAR_ctl_count=1
    TF_VAR_bth_count=1
    TF_VAR_wrk_count=0
    shift
    ;;
  md)
    TF_VAR_ctl_count=1
    TF_VAR_bth_count=1
    TF_VAR_wrk_count=1
    shift
    ;;
  lg)
    TF_VAR_ctl_count=2
    TF_VAR_bth_count=2
    TF_VAR_wrk_count=3
    shift
    ;;
  *)
    # Use the existing values for the size, if set. Otherwise the size
    # defaults to "sm".
    TF_VAR_ctl_count=${TF_VAR_ctl_count:-1}
    TF_VAR_bth_count=${TF_VAR_bth_count:-1}
    TF_VAR_wrk_count=${TF_VAR_wrk_count:-0}
    ;;
esac

# Run docker.
${drun} \
  -e TF_VAR_ctl_count=${TF_VAR_ctl_count} \
  -e TF_VAR_bth_count=${TF_VAR_bth_count} \
  -e TF_VAR_wrk_count=${TF_VAR_wrk_count} \
  gcr.io/kubernetes-conformance-testing/yake2e \
  "${@}"
