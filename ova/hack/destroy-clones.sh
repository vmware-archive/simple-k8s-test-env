#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

GOVC_VM="${GOVC_VM:-${GOVC_FOLDER}/yakity-centos}"

_uuids=$(govc vm.info -vm.ipath "${GOVC_VM}" -json -e | \
  jq -r '.VirtualMachines[0].Config.ExtraConfig | .[] | select(.Key == "guestinfo.yakity.CLUSTER_UUIDS") | .Value')

for _type_and_uuid in ${_uuids}; do
  _uuid="$(echo "${_type_and_uuid}" | awk -F: '{print $2}')"
  if echo "${_uuid}" | grep -iq "42301ab6-f495-1845-25ff-5190f281430a"; then
    continue
  fi
  echo "destroying ${_type_and_uuid}"
  govc vm.destroy -vm.uuid "${_uuid}"
done
