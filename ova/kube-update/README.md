# kube-update
When deployed on vSphere as an OVA, yakity supports the `kube-update` service --
updating Kubernetes components on a live cluster with incremental builds from a
developer's desktop.

Please note that the below examples do not illustrate building the binaries
locally or staging them to a remote location.

## Update the `kubectl` binary **only**

### Notify the Kubernetes node there is an update
The following command is executed from the developer's desktop:
```shell
$ govc vm.change \
  -vm.ipath "${GOVC_VM}" \
  -e guestinfo.kube-update.url=https://storage.googleapis.com/k8s-staged-builds/devel/v1.13.0-alpha.0-109-gc5d15cb0b8-akutz/kubectl
```

### Follow the `kube-update` service on the Kubernetes node
```shell
Oct 21 14:40:08 yakity.localdomain kube-update.sh[1409]: processing URL = https://storage.googleapis.com/k8s-staged-builds/devel/v1.13.0-alpha.0-109-gc5d15cb0b8-akutz/kubectl
Oct 21 14:40:08 yakity.localdomain kube-update.sh[1409]: % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
Oct 21 14:40:08 yakity.localdomain kube-update.sh[1409]: Dload  Upload   Total   Spent    Left  Speed
Oct 21 14:40:11 yakity.localdomain kube-update.sh[1409]: [392B blob data]
Oct 21 14:40:11 yakity.localdomain kube-update.sh[1409]: updating kubectl:
Oct 21 14:40:11 yakity.localdomain kube-update.sh[1409]: src_bin   = /tmp/tmp.d1WvSBr9uD/kubectl
Oct 21 14:40:11 yakity.localdomain kube-update.sh[1409]: tgt_bin   = /opt/bin/kubectl
Oct 21 14:40:11 yakity.localdomain kube-update.sh[1409]: service   =
```

### Monitor the progress from the developer's desktop
```shell
$ govc vm.info -vm.ipath "${GOVC_VM}" -e -json | \
  jq -r '.VirtualMachines[0].Config.ExtraConfig | .[] | select(.Key == "guestinfo.kube-update.log") | .Value'
processing URL = https://storage.googleapis.com/k8s-staged-builds/devel/v1.13.0-alpha.0-109-gc5d15cb0b8-akutz/kubectl
updating kubectl:
  src_bin   = /tmp/tmp.d1WvSBr9uD/kubectl
  tgt_bin   = /opt/bin/kubectl
  service   = 
chmod 0755 /tmp/tmp.d1WvSBr9uD/kubectl
mv -f /tmp/tmp.d1WvSBr9uD/kubectl /opt/bin/kubectl
```

## Update all the node components

### Notify the Kubernetes node there is an update
The following command is executed from the developer's desktop:
```shell
$ govc vm.change \
  -vm.ipath "${GOVC_VM}" \
  -e guestinfo.kube-update.url=https://storage.googleapis.com/k8s-staged-builds/devel/v1.13.0-alpha.0-109-gc5d15cb0b8-akutz/kubernetes-node-linux-amd64.tar.gz
```

### Follow the `kube-update` service on the Kubernetes node
```shell
$ journalctl -fu kube-update
-- Logs begin at Sun 2018-10-21 14:35:10 CDT. --
Oct 21 14:39:07 yakity.localdomain kube-update.sh[1409]: processing URL = https://storage.googleapis.com/k8s-staged-builds/devel/v1.13.0-alpha.0-109-gc5d15cb0b8-akutz/kubernetes-node-linux-amd64.tar.gz
Oct 21 14:39:07 yakity.localdomain kube-update.sh[1409]: % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
Oct 21 14:39:07 yakity.localdomain kube-update.sh[1409]: Dload  Upload   Total   Spent    Left  Speed
Oct 21 14:39:12 yakity.localdomain kube-update.sh[1409]: [550B blob data]
Oct 21 14:39:12 yakity.localdomain kube-update.sh[1409]: skipping unknown file '/tmp/tmp.d1WvSBr9uD/kubernetes/kubernetes-src.tar.gz'
Oct 21 14:39:12 yakity.localdomain kube-update.sh[1409]: skipping unknown file '/tmp/tmp.d1WvSBr9uD/kubernetes/LICENSES'
Oct 21 14:39:12 yakity.localdomain kube-update.sh[1409]: skipping unknown file '/tmp/tmp.d1WvSBr9uD/kubernetes/node/bin/kubeadm'
Oct 21 14:39:12 yakity.localdomain kube-update.sh[1409]: updating kubelet:
Oct 21 14:39:12 yakity.localdomain kube-update.sh[1409]: src_bin   = /tmp/tmp.d1WvSBr9uD/kubernetes/node/bin/kubelet
Oct 21 14:39:12 yakity.localdomain kube-update.sh[1409]: tgt_bin   = /opt/bin/kubelet
Oct 21 14:39:12 yakity.localdomain kube-update.sh[1409]: service   = kubelet
Oct 21 14:39:12 yakity.localdomain kube-update.sh[1409]: updating kube-proxy:
Oct 21 14:39:12 yakity.localdomain kube-update.sh[1409]: src_bin   = /tmp/tmp.d1WvSBr9uD/kubernetes/node/bin/kube-proxy
Oct 21 14:39:12 yakity.localdomain kube-update.sh[1409]: tgt_bin   = /opt/bin/kube-proxy
Oct 21 14:39:12 yakity.localdomain kube-update.sh[1409]: service   = kube-proxy
Oct 21 14:39:12 yakity.localdomain kube-update.sh[1409]: updating kubectl:
Oct 21 14:39:12 yakity.localdomain kube-update.sh[1409]: src_bin   = /tmp/tmp.d1WvSBr9uD/kubernetes/node/bin/kubectl
Oct 21 14:39:12 yakity.localdomain kube-update.sh[1409]: tgt_bin   = /opt/bin/kubectl
Oct 21 14:39:12 yakity.localdomain kube-update.sh[1409]: service   =
```

### Monitor the progress from the developer's desktop
```shell
$ govc vm.info -vm.ipath "${GOVC_VM}" -e -json | \
  jq -r '.VirtualMachines[0].Config.ExtraConfig | .[] | select(.Key == "guestinfo.kube-update.log") | .Value'
processing URL = https://storage.googleapis.com/k8s-staged-builds/devel/v1.13.0-alpha.0-109-gc5d15cb0b8-akutz/kubernetes-node-linux-amd64.tar.gz
updating kubelet:
  src_bin   = /tmp/tmp.d1WvSBr9uD/kubernetes/node/bin/kubelet
  tgt_bin   = /opt/bin/kubelet
  service   = kubelet
chmod 0755 /tmp/tmp.d1WvSBr9uD/kubernetes/node/bin/kubelet
systemctl -l stop kubelet
mv -f /tmp/tmp.d1WvSBr9uD/kubernetes/node/bin/kubelet /opt/bin/kubelet
systemctl -l start kubelet
updating kube-proxy:
  src_bin   = /tmp/tmp.d1WvSBr9uD/kubernetes/node/bin/kube-proxy
  tgt_bin   = /opt/bin/kube-proxy
  service   = kube-proxy
chmod 0755 /tmp/tmp.d1WvSBr9uD/kubernetes/node/bin/kube-proxy
systemctl -l stop kube-proxy
mv -f /tmp/tmp.d1WvSBr9uD/kubernetes/node/bin/kube-proxy /opt/bin/kube-proxy
systemctl -l start kube-proxy
updating kubectl:
  src_bin   = /tmp/tmp.d1WvSBr9uD/kubernetes/node/bin/kubectl
  tgt_bin   = /opt/bin/kubectl
  service   = 
chmod 0755 /tmp/tmp.d1WvSBr9uD/kubernetes/node/bin/kubectl
mv -f /tmp/tmp.d1WvSBr9uD/kubernetes/node/bin/kubectl /opt/bin/kubectl
```
