#!/bin/sh

echo "kube-update.status"
govc vm.info -vm.ipath "${GOVC_VM}" -e -json | \
  jq -r '.VirtualMachines[0].Config.ExtraConfig | .[] | select(.Key == "guestinfo.kube-update.status") | .Value'
echo
echo "kube-update.url"
govc vm.info -vm.ipath "${GOVC_VM}" -e -json | \
  jq -r '.VirtualMachines[0].Config.ExtraConfig | .[] | select(.Key == "guestinfo.kube-update.url") | .Value'
echo
echo "kube-update.log"
govc vm.info -vm.ipath "${GOVC_VM}" -e -json | \
  jq -r '.VirtualMachines[0].Config.ExtraConfig | .[] | select(.Key == "guestinfo.kube-update.log") | .Value'