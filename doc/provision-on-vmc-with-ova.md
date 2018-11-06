# Provision Kubernetes on VMC with the yakity OVA
This document is a step-by-step guide to provisioning a Kubernetes cluster on
VMware Cloud (VMC) on AWS using the yakity OVA.

## VMC vs vSphere
The primary benefit to provisioning Kubernetes on VMC on AWS is the ability to
leverage AWS resources like its Elastic Load Balancer (ELB). The yakity OVA is 
capable an ELB to provide public access to a privately routed Kubernetes
cluster when deployed to VMC.

For more information on provisioning Kubernetes on vSphere that is **not** VMC,
please see the guide [_Provision Kubernetes on vSphere with the yakity OVA_](provision-on-vsphere-with-ova.md).

## Guide
1. Log into the vSphere web client.
2. Right-click on a resource pool or folder and select _Deploy OVF Template_
3. A new window will appear asking for the location of the OVF -- either a URL or one or more local files. Enter the value  `https://s3-us-west-2.amazonaws.com/cnx.vmware/cicd/yakity-photon.ova` into the _URL_ field and click _Next_.
4. A warning may appear regarding an SSL verification. Please click _Okay_ to continue.
5. Enter a name for the new VM (for example, _kubernetes_), select the folder in which the new VM will be created, and click _Next_.
6. Select the resource pool in which the new VM will be placed and click _Next_.
7. Review the details so far and click _Next_.
8. Select a storage policy and click _Next_.
9. Set the IP allocation to _DHCP_, select the network to which the new VM will be connected, and click _Next_.
10. The current screen should now reflect the OVF properties that may be customized. Please update the following properties to the below values and click _Next_:

    | Property | Value |
    |----------|-------|
    | Nodes | `3` |
    | Control plane members | `2` |
    | Control plane members + workloads | `1` |
    | vSphere server | The IP address or FQDN of the vSphere server |
    | vSphere username | A vSphere account that can clone VMs and read data for all VMs |
    | vSphere password | The password for the above account |
    | AWS load balancer | Enables the creation of an AWS load balancer for the control plane nodes |
    | AWS access key ID | The access key used to create the elastic load balancer |
    | AWS secret access key | The secret access key for the above access key ID |
    | AWS region | The region in which the VMC VPC is located |

    The above value will result in the deployment of a three-node cluster. Two of the nodes will be members of the cluster's control plane. One of the control plane members will also be able to schedule workloads. The third node will be a dedicated worker.

    The AWS credentials will result in the creation of an AWS load balancer that provides public, load-balanced access to the members of the Kubernetes control plane.

11. Click _Finish_ to deploy the OVF as a new VM.
12. Wait for the VM to be created and then power it on.
13. The VM will now clone itself into two new VMs. If the name of the VM is _kubernetes_, the new VMs will be named _kubernetes-c02_ and _kubernetes-w01_.
14. After a few moments the new VMs, and the Kubernetes cluster, will be online.
15. Inspect the VM's notes in the vCenter UI to find information on how to access the new cluster.
16. Before executing the script that provides remote access to the cluster, please remember that the VMs are deployed to VMC and will not be publiclly accessible. The AWS load balancer provides external access to the API endpoints, but it may still be useful to be able to SSH into the VMs.

    The following environment variables may be configured so that a jump host is used to provide SSH access to the VMs:

    | Name | Description | Default |
    |------|-------------|---------|
    | `JUMP_HOST` | The IP address or FQDN of a jump host to use when SSHing into the cluster's nodes | |
    | `JUMP_HOST_PORT` | The jump host's SSH port | `22` |
    | `JUMP_HOST_USER` | The user name that has access to the jump host | `$(whoami)` |
    | `JUMP_HOST_IDENT` | The SSH key file used to acccess the jump host | `${HOME}/.ssh/id_rsa`<br />`${HOME}/.ssh/id_dsa` |

    Once the jump host values are configured, please execute the access script:

    ```shell
    $ curl -sSL http://bit.ly/yakcess | sh -s -- 4230247a-8346-e622-6897-6466c6a583e3
    getting cluster information
    * id                          success!
    * members                     success!
    * ssh key                     success!
    * kubeconfig                  success!
    * load-balancer               success!

    generating cluster access
    * ssh config                  success!

    generating commands
    * ssh                         success!
    * scp                         success!
    * kubectl                     success!
    * turn-down                   success!

    cluster access is now enabled at /Users/akutz/.yakity/b4a019c.
    several aliases of common programs are available:

    * ssh-b4a019c
    * scp-b4a019c
    * kubectl-b4a019c
    * turn-down-b4a019c

    to use the above programs, execute the following:

    export PATH="/Users/akutz/.yakity/b4a019c/bin:${PATH}"
    ```

17. Add the cluster commands to the path:
    ```shell
    export PATH="/Users/akutz/.yakity/b4a019c/bin:${PATH}"
    ```

18. Clusters deployed with the yakity OVA are composed of nodes with host names that always follow a consistent pattern:

    * Members of the control plane have host names `c%02d`
    * Worker nodes have host names `w%02d`
    * The first member of a cluster deployed with the yakity OVA is always a member of the control plane, even if it is able to also schedule workloads. Therefore the first member of a cluster deployed with the yakity OVA will always have a host name of `c01`.

19. While the host names in a cluster deployed by the yakity OVA are always the  same, the host FQDNs are always unique. This is due to [kubernetes/cloud-provider-vsphere#87](https://github.com/kubernetes/cloud-provider-vsphere/issues/87). The Kubernetes cloud provider expects node names to be unique. Because the vSphere cloud provider for Kubernetes treats the guest's reported host FQDN as the node name, collisions may occur with great frequency when there is more than one Kubernetes cluster on a single vSphere platform. So while host _names_ in an OVA-deployed cluster always follow an identical pattern, host _FQDNs_ always include a unique hash as part of the domain. 

    For example, one cluster may consist of the following three host FQDNs:

    * `c01.b4a019c.yakity`
    * `c02.b4a019c.yakity`
    * `w01.b4a019c.yakity`

    Whereas another cluster is built on nodes with _these_ FQDNs:

    * `c01.072c882.yakity`
    * `c02.072c882.yakity`
    * `w01.072c882.yakity`

    Please note that clusters deployed with the yakity OVA consist of nodes with host names that follow a consistent pattern. All controllers have host names that follow the pattern `c%02d` and all workers follow the pattern `w%02d`. Since the first node in a cluster deployed by the yakity OVA is always a member of the control plane, there will always be a node with the host name `c01`.

20. Verify that all of the cluster's nodes are accessible via SSH:
    ```shell
    $ ssh-b4a019c c01 'hostname -f && exit "${?}"' && \
      ssh-b4a019c c02 'hostname -f && exit "${?}"' && \
      ssh-b4a019c w01 'hostname -f && exit "${?}"'
      c01.b4a019c.yakity
      c02.b4a019c.yakity
      w01.b4a019c.yakity
    ```

21. Since the cluster uses a load balancer it is possible to access it remotely using `kubectl`. Open a terminal on the local system and use `kubectl` to print information about the cluster:
    ```shell
    $ kubectl-b4a019c get nodes
    NAME                 STATUS    ROLES     AGE       VERSION
    c02.b4a019c.yakity   Ready     <none>    9m26s     v1.12.2
    w01.b4a019c.yakity   Ready     <none>    9m46s     v1.12.2
    ```

    ```shell
    $ kubectl-b4a019c get cs
    NAME                 STATUS    MESSAGE             ERROR
    controller-manager   Healthy   ok                  
    scheduler            Healthy   ok                  
    etcd-0               Healthy   {"health":"true"}   
    etcd-1               Healthy   {"health":"true"}
    ```

    ```shell
    $ kubectl-b4a019c -n kube-system get pods
    NAME                               READY     STATUS    RESTARTS   AGE
    kube-dns-67b548dcff-md8t8          3/3       Running   0          9m58s
    vsphere-cloud-controller-manager   1/1       Running   0          9m56s
    ```

22. Once the cluster is no longer needed, it can be destroyed with the local
    turn-down script:
    ```shell
    $ turn-down-b4a019c 
    destroying VM controller:4230247a-8346-e622-6897-6466c6a583e3:c01
    destroying VM worker:42309688-0e9e-95f7-3d2e-047e26b2c564:w01
    destroying VM both:4230aef7-18b4-bb80-8a1b-566c270f5a55:c02
    deleting load balancer arn:aws:elasticloadbalancing:us-west-2:571501312763:loadbalancer/net/yakity-b4a019c/93aebc4749440e2c
    waiting for load balancer to be deleted
    ```