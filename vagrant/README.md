# Provisioning Kubernetes clusters with Vagrant and yakity
This document illustrates how to provision Kubernetes with yakity
on several different Linux distributions using Vagrant.

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

3. Decide which type of cluster to deploy:

    | Linux | Single-node | Multi-node |
    |-------|-------------|------------|
    | CentOS 7 | ✓ | ✓ |
    | PhotonOS 2 | ✓ | ✓ |
    | Ubuntu 16.04 | ✓ | ✓ |

    The above table lists the supported Linux distributions on which yakity can be deployed. The _Single-node_ and _Multi-node_ columns indicate the supported cluster deployment models.

    For this example, a multi-node cluster will be deployed using PhotonOS 2, however, please keep in mind that other combinations may be selected as well. Play around with it!

4. The program `hack/vagrant.sh` makes turning up clusters with Vagrant and yakity even simpler. Type `hack/vagrant.sh -h` to print a full list of the program's capabilities. Use it to deploy a three-node cluster on Photon:

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

5. Please note that the previous command does **not** use the double-dash `--` to separate the yakity arguments from Vagrant's command `up`. That's because in this instance the command `up` belongs to yakity, not Vagrant. The `up` command is parsed by the script and actually uses `vagrant up` and `vagrant provision` to stand up the VMs and then provision them separately.

    The remainder of the commands will use the double-dash to separate the yakity arguments from the wrapped command's arguments.

6. Once all of the nodes have been created and provisioned, the following command can be used to follow the yakity process as it deploys Kubernetes:
    ```shell
    $ hack/vagrant.sh -b photon -3 -- ssh c01 -c 'tail -f /var/log/yakity/yakity.log'
    ```

    The other nodes may be monitored with the same command, just replace `c01` with either `c02` or `w01`.

7. The cluster is provisioned when the following log message appears:
    ```
    So long, and thanks for all the fish.
    ```

8. Use `hack/kubectl.sh` to access the cluster:
    ```shell
    $ hack/kubectl.sh -b photon -3 -- get cs
    NAME                 STATUS    MESSAGE             ERROR
    controller-manager   Healthy   ok                  
    scheduler            Healthy   ok                  
    etcd-0               Healthy   {"health":"true"}
    ```

    ```shell
    $ hack/kubectl.sh -b photon -3 -- get cs get nodes
    NAME         STATUS    ROLES     AGE       VERSION
    c02.yakity   Ready     <none>    118s      v1.12.2
    w01.yakity   Ready     <none>    118s      v1.12.2
    ```

    ```shell
    $ hack/kubectl.sh -b photon -3 -- get -n kube-system get pods
    NAME                        READY     STATUS    RESTARTS   AGE
    kube-dns-67b548dcff-mtkfv   3/3       Running   0          2m42s
    ```

9. Once the cluster is no longer needed it may be destroyed with the following command:
    ```shell
    $ hack/vagrant.sh -b photon -3 -- destroy -f
    ```
