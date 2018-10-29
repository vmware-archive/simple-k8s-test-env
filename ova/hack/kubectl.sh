#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

script_dir=$(python -c "import os; print(os.path.realpath('$(dirname "${0}")'))")

LINUX_DISTRO="${LINUX_DISTRO:-photon}"
case "${LINUX_DISTRO}" in
photon)
  GOVC_VM="${GOVC_VM:-${GOVC_FOLDER}/photon2}"
  ;;
centos)
  GOVC_VM="${GOVC_VM:-${GOVC_FOLDER}/yakity-centos}"
  ;;
*)
  echo "invalid target os: ${LINUX_DISTRO}" 1>&2; exit 1
esac

export KUBECONFIG=kubeconfig
"${script_dir}/get-kubeconfig.sh" 1>"${KUBECONFIG}"

kubectl "${@}"
