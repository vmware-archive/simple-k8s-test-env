# Provisioning Kubernetes clusters with Vagrant and yakity
This document illustrates how to provision Kubernetes with yakity
on several different Linux distributions using Vagrant.

## Quick start
This example illustrates how to provision a Kubernetes cluster with three nodes
on Ubuntu running on VirtualBox:
```shell
$ git clone https://github.com/akutz/yakity /tmp/yakity && \
  cd /tmp/yakity/vagrant && \
  hack/vagrant.sh -b photon -3 up
```

## Support matrix
This section outlines the supported virtualization providers and Linux 
distributions:

|               | CentOS 7 | PhotonOS 2 | Ubuntu 16.04 (Xenial) |
|---------------|:--------:|:----------:|:---------------------:|
| VirtualBox    | ✓        | ✓          | ✓                     |
| VMware Fusion | ✓        | ✓          | ✓                     |

## Getting started
Please follow these steps to provision a Kubernetes cluster with Vagrant and yakity:

1. Clone this repository:
    ```shell
    $ git clone https://github.com/akutz/yakity /tmp/yakity
    ```

2. Open a shell and change directories into `/tmp/yakity/vagrant`
    ```shell
    $ cd /tmp/yakity/vagrant
    ```

3. The program `hack/vagrant.sh` makes turning up clusters with Vagrant and yakity even simpler. Type `hack/vagrant.sh -h` to print a full list of the program's capabilities. Use it to deploy a three-node cluster on Photon:

    ```shell
    $ hack/vagrant.sh -b photon -3 up
    ```

    The above command deploys and initializes three VMs:

    | Name | Description |
    |------|-------------|
    | `c01` | A dedicated control-plane node |
    | `c02` | A control plane node on which workloads may be scheduled |
    | `w01` | A dedicated worker node |

    The command also performs the following actions:
    
    * The following actions occur once, regardless of the number of nodes:
      * Generates a self-signed, x509 certificate authority
      * Generates an x509 certificate/key pair for the K8s admin user
      * Generates a kubeconfig for the K8s admin user
    * The following steps occur per node:
      * Creates the VM
      * Initializes the guest according to distribution specific requirements
      * Copies several files to the guest
      * Initializes the yakity environment
      * Starts yakity

4. Once all of the nodes have been created and provisioned, the following command can be used to follow the yakity process as it deploys Kubernetes:
    ```shell
    $ hack/vagrant.sh ssh c01 -c 'tail -f /var/log/yakity/yakity.log'
    ```

    The other nodes may be monitored with the same command, just replace `c01` with either `c02` or `w01`.

5. The cluster is provisioned when the following log message appears:
    ```
    So long, and thanks for all the fish.
    ```

6. Use `hack/kubectl.sh` to access the cluster:
    ```shell
    $ hack/kubectl.sh get cs
    NAME                 STATUS    MESSAGE             ERROR
    controller-manager   Healthy   ok                  
    scheduler            Healthy   ok                  
    etcd-0               Healthy   {"health":"true"}
    ```

    ```shell
    $ hack/kubectl.sh get nodes
    NAME         STATUS    ROLES     AGE       VERSION
    c02.yakity   Ready     <none>    118s      v1.12.2
    w01.yakity   Ready     <none>    118s      v1.12.2
    ```

    ```shell
    $ hack/kubectl.sh -n kube-system get pods
    NAME                        READY     STATUS    RESTARTS   AGE
    kube-dns-67b548dcff-mtkfv   3/3       Running   0          2m42s
    ```

7. Once the cluster is no longer needed it may be destroyed with the following command:
    ```shell
    $ hack/vagrant.sh destroy -f
    ```

## Deploying local Kubernetes builds
The program `hack/vagrant.sh` accepts the flag `-k` in order to specify the
[version](https://github.com/akutz/yakity/wiki/Kubernetes-version) of
Kubernetes to install. However, the flag may *also* be used to deploy a 
**local** build of Kubernetes!

```shell
$ hack/vagrant.sh -p fusion -b ubuntu -3 -k "${GOPATH}/src/k8s.io/kubernetes" up
```

The above command creates a three-node Kubernetes cluster using Ubuntu
boxes on VMware Fusion. The cluster is built using files found in the directory
specified with the `-k` flag.

### The keyword `local`
The keyword `local` may be used as a shortcut to reference the Kubernetes 
source tree in the `GOPATH`. For example, the previous command could be
rewritten like so:

```shell
$ hack/vagrant.sh -p fusion -b ubuntu -3 -k local up
```

### Bring your own builds
Yakity does not build Kubernetes from source. In fact, the directory specified
with the `-k` flag doesn't have to be a Kubernetes source directory at all.
It's simply the case that the files for which yakity searches are *likely* to be
found in the Kubernetes source directory. Yakity performs a recursive search
of the directory looking for any of the following file groups:

**Client**
* `kubernetes-client-linux-amd64.tar.gz`
* `kubectl`

**Node**
* `kubernetes-node-linux-amd64.tar.gz`
* `kubelet`
* `kube-proxy`

**Server**
* `kubernetes-server-linux-amd64.tar.gz`
* `kube-apiserver`
* `kube-controller-manager`
* `kube-scheduler`

**Test**
* `kubernetes-test-linux-amd64.tar.gz`
* `e2e.test`

If any of the discovered tarballs in a group is newer than discovered 
programs from that group, then the tarball is inflated. Next each 
discovered group is checked to see if *it* is newer than its analogue
from the tarball.

If multiple copies of the same file (tarball or program) are discovered,
only the newest copy is used in the above comparison.

### Linux distributions that support deploying local Kubernetes builds
Plesae note that only the CentOS and Ubuntu box types support deploying 
a local Kubernetes build. This is because there is no PhotonOS box in the
Vagrant registry that includes support for mounting shared folders. If
someone would like to provide such a box, then PhotonOS could also support
deploying Kubernetes using local development builds.

## Using `dig`, `kubectl`, and `vagrant`
There are three scripts that wrap some useful commands:
* `hack/dig.sh`
* `hack/kubectl.sh`
* `hack/vagrant.sh`

Each of the above commands accept the same set of command line arguments:
```shell
  -k      K8S   The version of Kubernetes to install. Please see the section
                KUBERNETES VERSION for accepted versions.
                The default value is "release/stable".

  -b      BOX   Valid box types include: "photon", "centos", and "ubuntu".
                The default value is "ubuntu".

  -c      CPU   The number of CPUs to assign to each box.
                The default value is "1".

  -m      MEM   The amount of memory (MiB) to assign to each box.
                The default value is "1024".

  -p PROVIDER   Valid providers are: "virtualbox" and "vmware".
                The default value is "virtualbox".

  -1            Provision a single-node cluster
                  c01  Controller+Worker

  -2            Provision a two-node cluster
                  c01  Controller
                  w01  Worker

  -3            Provision a three-node cluster
                  c01  Controller
                  c02  Controller+Worker
                  w01  Worker
```

### Configuration checksums
Whenever any of these commands are invoked, the command line arguments are used
to build a YAML configuration file that describes the cluster. For example:
```yaml
---
k8s:         release/stable
box:         bento/ubuntu-16.04
cpu:         1
mem:         1024
nodes:       3
controllers: 2
both:        1
```

A SHA-1 hash is derived from the configuration file so the commands then know
in which directory to look for the files related to the deployed cluster. For
instance, the above configuration file produces the SHA-1 hash, 
`dafad8af9c2e7fa5dbfbe23a91100f31ba15208a`. The first seven characters from this
string are use to generate the data directory for the cluster, 
`${HOME}/.yakity/vagrant/dafad8a`.

### The `instance` symlink
Another result of invoking the above commands is the creation of an `instance`
symlink that points to the data directory derived from the aforementioned
configuration file checksum. For example, imagine the following command is used
to deploy a single-node Kubernetes cluster onto Photon OS:
```shell
$ hack/vagrant.sh -b photon -1
```

Aside from standing up a new Kubernetes cluster, the above command will also
create the following:

* `$HOME/.yakity/vagrant/931b9bb`
* `$HOME/.yakity/vagrant/instance`

The first path is the data directory for the new cluster. The second path is
a symlink that references the first path. The benefit this provides is the
ability to invoke subsequent commands without the need to provide the command
line flags needed to derive the configuration checksum:
```shell
$ hack/kubectl.sh get nodes
NAME         STATUS    ROLES     AGE       VERSION
c01.yakity   Ready     <none>    25m       v1.12.2
```

The `instance` symlink is updated everytime one of the helper commands is
invoked with one or more of the flags `-b`, `-c`, `-m`, `-1`, `-2`, or `-3`.

