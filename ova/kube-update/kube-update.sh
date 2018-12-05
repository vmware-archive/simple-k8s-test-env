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

# A flag that indicates whether to skip uploads that are the same as the
# files on the host.
SKIP_DUPLICATES="$(parse_bool "${SKIP_DUPLICATES}" true)"

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

scp_file() {
  _file_path="${1}"
  _host_name="${2}"
  info "uploading ${_file_path} to ${_host_name}"
  scp -o StrictHostKeyChecking=no \
    "${_file_path}" "${_host_name}:${PEER_IN_DIR}/" || \
    error "failed to scp ${_file_path} to ${_host_name}"
}

# Store a list of the IPv4 addresses for this host.
self_ipv4_addresses=$(get_self_ipv4_addresses)

process_outload() {
  _file_dir="${1}"
  _file_name="${2}"
  _file_path="${_file_dir}/${_file_name}"

  for _addr in $(get_member_ipv4_addresses); do
    if echo "${self_ipv4_addresses}" | grep -qF "${_addr}"; then
      info "skipping outload for self: ${_addr}"
      continue
    fi

    info "uploading ${_file_path} to ${_addr}"
    scp -o StrictHostKeyChecking=no \
      "${_file_path}" "${_addr}:${PEER_IN_DIR}/" || \
      error "failed to scp ${_file_path} to ${_addr}"
  done

  rm -f "${_file_path}"
  info "completed outload for ${_file_path}"
}

process_upload() {
  _file_dir="${1}"; _file_name="${2}"; _file_path="${_file_dir}/${_file_name}"
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

  # If this is a client upload then copy the file into the watched peer outload
  # directory. Otherwise just remove the file.
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

replace_and_restart_service() {
  _service_name="${1}"; _src_bin="${2}"; _tgt_bin="${3}"
  systemctl -l stop "${_service_name}" || \
    error "failed to stop service ${_service_name}"
  mv -f "${_src_bin}" "${_tgt_bin}" || \
    error "failed to replace ${_tgt_bin}"
  systemctl -l start "${_service_name}" || \
    error "failed to start service ${_service_name}"
}

process_new_file() {
  _file_dir="${1}"
  _file_name="${2}"
  _file_path="${_file_dir}/${_file_name}"
  debug "processing unknown file: ${_file_path}"

  # If the file path does not exist then skip it.
  [ -f "${_file_path}" ] || return 0

  # The action taken on each file depends on the file's name.
  _src_bin="${_file_path}"
  _src_bin_base_name="$(basename "${_src_bin}")"
  _tgt_bin="${BIN_DIR}/${_src_bin_base_name}"
  if [ ! -f "${_tgt_bin}" ]; then
    debug "skipping unknown file: ${_src_bin}"
    return 0
  fi

  info "processing known file: ${_tgt_bin}"

  if [ "${SKIP_DUPLICATES}" = "true" ]; then
    _tgt_hash="$(sha1sum -b "${_tgt_bin}" | awk '{print $1}')"
    _src_hash="$(sha1sum -b "${_src_bin}" | awk '{print $1}')"
    if [ "${_tgt_hash}" = "${_src_hash}" ]; then
      info "skipping duplicate: name=${_file_name} hash=${_src_hash}"
      return 0
    fi
  fi
  chmod 0755 "${_src_bin}"

  _service_name="${_src_bin_base_name}"
  if systemctl is-enabled "${_service_name}" >/dev/null 2>&1; then
    replace_and_restart_service "${_service_name}" \
                                "${_src_bin}" \
                                "${_tgt_bin}" || \
      { error "failed to update service ${_service_name}"; return 0; }
    info "updated service ${_service_name}"
  else
    mv -f "${_src_bin}" "${_tgt_bin}" || \
      { error "failed to update ${_tgt_bin}"; return 0; }
    info "updated ${_tgt_bin}"
  fi
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
