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
# Used by the kube-update service to monitor well-defined paths in order
# to update K8s components on a running cluster.
#

# Load the yakity commons library.
# shellcheck disable=SC1090
. "$(pwd)/yakity-common.sh"

# The inotifywait program is required. If missing please install the
# distribution's inotify-tools (or equivalent) package.
require_program inotifywait

mkdir_and_chmod() { mkdir -p "${@}" && chmod 0755 "${@}"; }

info_env_var() {
  while [ -n "${1}" ]; do
    info "${1}=$(eval "echo \$${1}")" && shift
  done
}

# A flag that indicates whether to skip uploads that are the same as the
# files on the host.
SKIP_DUPLICATES="$(parse_bool "${SKIP_DUPLICATES}" true)"

# The file used to track which hosts have been validated.
HOSTS_FILE=/var/lib/yakity/kube-update/.hosts
mkdir_and_chmod "$(dirname ${HOSTS_FILE})"
touch "${HOSTS_FILE}"

# Get the name (sans domain) of this host.
HOST_NAME="$(hostname -s)"

# The directories where clients and peers upload files.
CLIENT_DIR=/var/lib/yakity/kube-update/client-uploads
PEER_IN_DIR=/var/lib/yakity/kube-update/peer-in
PEER_OUT_DIR=/var/lib/yakity/kube-update/peer-out
mkdir_and_chmod /var/lib/yakity /var/lib/yakity/kube-update \
                "${CLIENT_DIR}" "${PEER_IN_DIR}" "${PEER_OUT_DIR}"
info_env_var CLIENT_DIR PEER_IN_DIR PEER_OUT_DIR

# Create a symlink for the client uploads if one does not exist.
[ -e /kube-update ] || ln -s "${CLIENT_DIR}" /kube-update

# The area where uploaded files are moved while being processed.
TEMP_FILE_AREA="$(mktemp -d)"; info_env_var TEMP_FILE_AREA

# The following environment variables are the locations of the eponymous
# Kubernetes binaries.
KUBECTL_BIN="${KUBECTL_BIN:-${BIN_DIR}/kubectl}"
KUBELET_BIN="${KUBELET_BIN:-${BIN_DIR}/kubelet}"
KUBE_APISERVER_BIN="${KUBE_APISERVER_BIN:-${BIN_DIR}/kube-apiserver}"
KUBE_CONTROLLER_MANAGER_BIN="${KUBE_CONTROLLER_MANAGER_BIN:-${BIN_DIR}/kube-controller-manager}"
KUBE_SCHEDULER_BIN="${KUBE_SCHEDULER_BIN:-${BIN_DIR}/kube-scheduler}"
KUBE_PROXY_BIN="${KUBE_PROXY_BIN:-${BIN_DIR}/kube-proxy}"

mkdir_and_chmod "$(dirname "${KUBECTL_BIN}")" \
                "$(dirname "${KUBELET_BIN}")" \
                "$(dirname "${KUBE_APISERVER_BIN}")" \
                "$(dirname "${KUBE_CONTROLLER_MANAGER_BIN}")" \
                "$(dirname "${KUBE_SCHEDULER_BIN}")" \
                "$(dirname "${KUBE_PROXY_BIN}")"

info_env_var KUBECTL_BIN \
             KUBELET_BIN \
             KUBE_APISERVER_BIN \
             KUBE_CONTROLLER_MANAGER_BIN \
             KUBE_SCHEDULER_BIN \
             KUBE_PROXY_BIN

scp_file() {
  _file_path="${1}"
  _host_name="${2}"
  info "uploading ${_file_path} to ${_host_name}"
  scp -o StrictHostKeyChecking=no \
    "${_file_path}" "${_host_name}:${PEER_IN_DIR}/" || \
    error "failed to scp ${_file_path} to ${_host_name}"
}

cluster_members="$(rpc_get CLUSTER_MEMBERS)"
process_outload() {
  _file_dir="${1}"
  _file_name="${2}"
  _file_path="${_file_dir}/${_file_name}"

  for _member in ${cluster_members}; do
    _member_host_name="$(parse_member_host_name "${_member}")"

    if [ "${_member_host_name}" = "${HOST_NAME}" ]; then
      info "skipping outload for self: ${_member_host_name}"
      continue
    fi

    info "uploading ${_file_path} to ${_member_host_name}"
    scp -o StrictHostKeyChecking=no \
      "${_file_path}" "${_member_host_name}:${PEER_IN_DIR}/" || \
      error "failed to scp ${_file_path} to ${_member_host_name}"
  done

  rm -f "${_file_path}"
  info "completed outload for ${_file_path}"
}

process_upload() {
  _file_dir="${1}"
  _file_name="${2}"
  _file_path="${_file_dir}/${_file_name}"
  _upload_type=peer
  if [ "${_file_dir}" = "${CLIENT_DIR}" ]; then _upload_type=client; fi

  info "processing ${_upload_type} upload: ${_file_path}"

  if echo "${_file_name}" | grep -q '\.tar\.gz$'; then
    tar -xzf "${_file_path}" -C "${TEMP_FILE_AREA}"
  elif echo "${_file_name}" | grep -q '\.tar$'; then
    tar -xf "${_file_path}" -C "${TEMP_FILE_AREA}"
  elif echo "${_file_name}" | grep -q '\.gz$'; then
    (cd "${TEMP_FILE_AREA}" && gzip -d "${_file_path}")
  else
    cp -f "${_file_path}" "${TEMP_FILE_AREA}/"
  fi
  if [ "${_upload_type}" = "client" ]; then
    mv -f "${_file_path}" "${PEER_OUT_DIR}/"
  else
    rm -f "${_file_path}"
  fi
}

watch_client_dir() {
  inotifywait -m --format "%f" -e close_write "${CLIENT_DIR}" | \
  while read -r _file_name; do
    process_upload "${CLIENT_DIR}" "${_file_name}"
  done
}

watch_peer_in_dir() {
  inotifywait -m --format "%f" -e close_write "${PEER_IN_DIR}" | \
  while read -r _file_name; do
    process_upload "${PEER_IN_DIR}" "${_file_name}"
  done
}

watch_peer_out_dir() {
  inotifywait -m --format "%f" -e moved_to "${PEER_OUT_DIR}" | \
  while read -r _file_name; do
    process_outload "${PEER_OUT_DIR}" "${_file_name}"
  done
}

process_new_file() {
  _file_dir="${1}"
  _file_name="${2}"
  _file_path="${_file_dir}/${_file_name}"
  debug "processing unknown file: ${_file_path}"

  # If the file path does not exist then skip it.
  [ -f "${_file_path}" ] || return 0

  unset _service_name _tgt_bin

  # The action taken on each file depends on the file's name.
  _src_bin="${_file_path}"
  case "${_file_name}" in
  kubectl)
    _tgt_bin="${KUBECTL_BIN}"
    ;;
  kubelet)
    _service_name="${_file_name}"
    _tgt_bin="${KUBELET_BIN}"
    ;;
  kube-apiserver)
    _service_name="${_file_name}"
    _tgt_bin="${KUBE_APISERVER_BIN}"
    ;;
  kube-controller-manager)
    _service_name="${_file_name}"
    _tgt_bin="${KUBE_CONTROLLER_MANAGER_BIN}"
    ;;
  kube-scheduler)
    _service_name="${_file_name}"
    _tgt_bin="${KUBE_SCHEDULER_BIN}"
    ;;
  kube-proxy)
    _service_name="${_file_name}"
    _tgt_bin="${KUBE_PROXY_BIN}"
    ;;
  esac

  if [ -z "${_tgt_bin}" ]; then
    rm -fr "${_src_bin}"
    return 0
  fi

  info "processing known file: ${_src_bin}"

  if [ -f "${_tgt_bin}" ] && [ "${SKIP_DUPLICATES}" = "true" ]; then
    _tgt_hash="$(sha1sum -b "${_tgt_bin}" | awk '{print $1}')"
    _src_hash="$(sha1sum -b "${_src_bin}" | awk '{print $1}')"
    if [ "${_tgt_hash}" = "${_src_hash}" ]; then
      info "skipping duplicate: name=${_file_name} hash=${_src_hash}"
      return 0
    fi
  fi
  chmod 0755 "${_src_bin}"

  if [ -z "${_service_name}" ]; then
    mv -f "${_src_bin}" "${_tgt_bin}"
  elif systemctl is-enabled "${_service_name}" >/dev/null 2>&1; then
    systemctl -l stop "${_service_name}" && \
      mv -f "${_src_bin}" "${_tgt_bin}" && \
      systemctl -l start "${_service_name}"
  fi
  info "replaced ${_tgt_bin}"
}

watch_temp_file_area() {
  inotifywait -m -r --format "%f" -e close_write "${TEMP_FILE_AREA}" | \
  while read -r _file_name; do
    process_new_file "${TEMP_FILE_AREA}" "${_file_name}"
  done
}

# Start the background processes that monitor the upload and outload paths.
watch_client_dir &
watch_peer_in_dir &
watch_peer_out_dir &

# Start the process that monitors the temp file area.
watch_temp_file_area
