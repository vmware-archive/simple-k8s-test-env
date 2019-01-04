# How to configure the vSphere Cloud Provider in a Yakity installation

Yakity conveniently installs the vSphere cloud provider for you, but doesn't actually configure it. It needs to be configured correctly in order to be functional.

Note that a lot of this info was gleaned from this document here: https://vmware.github.io/vsphere-storage-for-kubernetes/documentation/existing.html

### A note on GOVC

The document above and the instructions below use https://github.com/vmware/govmomi/tree/master/govc for verification. If you don't already have it, it's well worth taking the time to download. I simply set the following environment variables in a shell and then run govc <command>:

```
$ export GOVC_INSECURE="1"
$ export GOVC_PASSWORD=<vCenter password>
$ export GOVC_URL=<vCenter IP>
$ export GOVC_USERNAME=<vCenter user ID>
$ govc ls
/Datacenter/vm
/Datacenter/network
/Datacenter/host
/Datacenter/datastore
```

### 1. Place the worker VMs into a VM folder

You might as well place the whole cluster into a VM folder. This can be done while the VMs are running. I just created a Yakity folder using the vSphere UI from the 'VMs and Templates' view and then dragged and dropped the VMs into it.

You can then verify that the govc client sees what you've done correctly.

```
$ govc ls /Datacenter/vm/Yakity
/Datacenter/vm/Yakity/yakity-w01
/Datacenter/vm/Yakity/yakity-c02
/Datacenter/vm/Yakity/yakity
```

### 2. Ensure that DiskUUID is set to true for each VM

Whether or not this value is set by Yakity itself, it's good to double-check that it's correct.

```
govc vm.change -e="disk.enableUUID=1" -vm='/Datacenter/vm/Yakity/yakity-w01'
govc vm.change -e="disk.enableUUID=1" -vm='/Datacenter/vm/Yakity/yakity-c02'
govc vm.change -e="disk.enableUUID=1" -vm='/Datacenter/vm/Yakity/yakity'
```

### 3. Create and assign roles to vSphere user identities

You can skip this part if you're using administrator user. Otherwise see https://vmware.github.io/vsphere-storage-for-kubernetes/documentation/existing.html#create-and-assign-roles-to-the-vsphere-cloud-provider-user-and-vsphere-entities

### 4. Create the vSphere cloud config file (vsphere.conf)

Create a config file that contains the parameters that the Cloud Provider will use to authenticate to your cluster. Here's what worked for me:

```
[0]root@c02:default$ cat /etc/vsphere/vsphere.conf 
[Global]
user = "administrator@vsphere.local"
password = "<password>"
port = "443"
insecure-flag = "1"
datacenters = "Datacenter"

[VirtualCenter "<vCenter IP>"]

[Workspace]
server = "<vCenter IP>"
datacenter = "Datacenter"
default-datastore="vsanDatastore"
resourcepool-path="Minis/Resources"
folder = "Yakity"

[Disk]
scsicontrollertype = pvscsi

[Network]
public-network = "ExternalNetwork"
```
Note that the resourcepool and folder options aren't always obvious. They should be consistent with the output of govc as seen below. Note that "Minis" is the name of the DRS cluster I'm using and "Datacenter" is the name of my datacenter. The cluster will have a root resource pool called Resources. If your Yakity VMs are in a child resource pool, you should list that instead.

```
$ govc ls /Datacenter/host/Minis
/Datacenter/host/Minis/Resources
...

$ govc ls /Datacenter/vm/
...
/Datacenter/vm/Yakity
/Datacenter/vm/Discovered virtual machine
```

### 5. Configure the Kubernetes components to use the config file

Copy the vsphere.conf file to every VM in the Yakity cluster. I put mine in /etc/vsphere - but they could be anywhere you like.

Identifying the location of the default command-line options for each of the services on the VMs isn't at all obvious. As it happens, they're all conveniently located in /etc/default under the name you would expect. You need to add two lines of configuration to each of the following files in each VM:

```
/etc/default/kubelet
/etc/default/kube-controller-manager
/etc/default/kube-apiserver
```
The two lines in question are the following:

```
--cloud-provider=vsphere \
--cloud-config=/etc/vsphere/vsphere.conf \
```
All of the services in Yakity run using systemd, so restart all the ones that apply to the type of VM you're configuring. For some it may be just Kubelet. For others it will also be kube-apiserver and kube-controller-manager. So run the following on each VM:

```
$ systemctl daemon-reload
$ systemctl restart kubelet.service
$ systemctl restart kube-controller-manager.service
$ systemctl restart kube-apiserver.service
$ ps -ef | grep kube
```
Check that the services have come back up. If not, you can use journalctl to check for the reason why:
```
$ journalctl -xeu kubelet
```

### 6. Test the configuration

The simplest way to test the configuration is to create a storage class and then a Persistent Volume Claim. See https://github.com/kubernetes/examples/tree/master/staging/volumes/vsphere for more detail on this. The examples I used were:

```
$ cat vsphere-sc.yaml 
kind: StorageClass
apiVersion: storage.k8s.io/v1beta1
metadata:
  name: fast
provisioner: kubernetes.io/vsphere-volume
parameters:
    diskformat: zeroedthick
    fstype:     ext4
    datastore:  vsanDatastore

$ cat test-pvc1.yaml 
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: pvcsc001
  annotations:
    volume.beta.kubernetes.io/storage-class: fast
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi

$ kubectl create -f vsphere-sc.yaml 

$ kubectl create -f test-pvc1.yaml

$ kubectl describe pvc pvcsc001
Name:          pvcsc001
Namespace:     default
StorageClass:  fast
Status:        Bound
Volume:        pvc-b3e70af3-1053-11e9-89e0-005056b4cdf4
Labels:        <none>
Annotations:   pv.kubernetes.io/bind-completed: yes
               pv.kubernetes.io/bound-by-controller: yes
               volume.beta.kubernetes.io/storage-class: fast
               volume.beta.kubernetes.io/storage-provisioner: kubernetes.io/vsphere-volume
Finalizers:    [kubernetes.io/pvc-protection]
Capacity:      2Gi
Access Modes:  RWO
VolumeMode:    Filesystem
Events:
  Type       Reason                 Age                    From                         Message
  ----       ------                 ----                   ----                         -------
  Normal     ProvisioningSucceeded  96s                    persistentvolume-controller  Successfully provisioned volume pvc-b3e70af3-1053-11e9-89e0-005056b4cdf4 using kubernetes.io/vsphere-volume
```

