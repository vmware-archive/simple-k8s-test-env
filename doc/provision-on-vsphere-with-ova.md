# Provision Kubernetes on vSphere with the yakity OVA
This document is a step-by-step guide to provisioning a Kubernetes cluster on
VMware vSphere using the yakity OVA.

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

    The above value will result in the deployment of a three-node cluster. Two of the nodes will be members of the cluster's control plane. One of the control plane members will also be able to schedule workloads. The third node will be a dedicated worker.

11. Click _Finish_ to deploy the OVF as a new VM.
12. Wait for the VM to be created and then power it on.
13. The VM will now clone itself into two new VMs. If the name of the VM is _kubernetes_, the new VMs will be named _kubernetes-c02_ and _kubernetes-w01_.
14. After a few moments the new VMs, and the Kubernetes cluster, will be online.
15. Inspect the VM's notes in the vCenter UI to find information on how to access the new cluster.
16. Execute the remote access script locally. For example:

    ```shell
    $ curl -sSL http://bit.ly/yakcess | sh -s -- 4230384e-6392-e2c3-97cd-5dda6b4cfecf
    getting cluster information
      * id                          success!
      * members                     success!
      * ssh key                     success!
      * kubeconfig                  success!
      * load-balancer               notfound

    generating cluster access
      * ssh config                  success!

    generating commands
      * ssh                         success!
      * scp                         success!
      * kubectl                     success!
      * turn-down                   success!

    cluster access is now enabled at /Users/akutz/.yakity/c7c947f.
    several aliases of common programs are available:

      * ssh-c7c947f
      * scp-c7c947f
      * kubectl-c7c947f
      * turn-down-c7c947f

    to use the above programs, execute the following:

      export PATH="/Users/akutz/.yakity/c7c947f/bin:${PATH}"
    ```

17. Add the cluster commands to the path:
    ```shell
    export PATH="/Users/akutz/.yakity/c7c947f/bin:${PATH}"
    ```

18. Clusters deployed with the yakity OVA are composed of nodes with host names that always follow a consistent pattern:

    * Members of the control plane have host names `c%02d`
    * Worker nodes have host names `w%02d`
    * The first member of a cluster deployed with the yakity OVA is always a member of the control plane, even if it is able to also schedule workloads. Therefore the first member of a cluster deployed with the yakity OVA will always have a host name of `c01`.

19. While the host names in a cluster deployed by the yakity OVA are always the  same, the host FQDNs are always unique. This is due to [kubernetes/cloud-provider-vsphere#87](https://github.com/kubernetes/cloud-provider-vsphere/issues/87). The Kubernetes cloud provider expects node names to be unique. Because the vSphere cloud provider for Kubernetes treats the guest's reported host FQDN as the node name, collisions may occur with great frequency when there is more than one Kubernetes cluster on a single vSphere platform. So while host _names_ in an OVA-deployed cluster always follow an identical pattern, host _FQDNs_ always include a unique hash as part of the domain. 

    For example, one cluster may consist of the following three host FQDNs:

    * `c01.c7c947f.yakity`
    * `c02.c7c947f.yakity`
    * `w01.c7c947f.yakity`

    Whereas another cluster is built on nodes with _these_ FQDNs:

    * `c01.072c882.yakity`
    * `c02.072c882.yakity`
    * `w01.072c882.yakity`

    Please note that clusters deployed with the yakity OVA consist of nodes with host names that follow a consistent pattern. All controllers have host names that follow the pattern `c%02d` and all workers follow the pattern `w%02d`. Since the first node in a cluster deployed by the yakity OVA is always a member of the control plane, there will always be a node with the host name `c01`.

20. Verify that all of the cluster's nodes are accessible via SSH:
    ```shell
    $ ssh-c7c947f c01 'hostname -f && exit "${?}"' && \
      ssh-c7c947f c02 'hostname -f && exit "${?}"' && \
      ssh-c7c947f w01 'hostname -f && exit "${?}"'
      c01.c7c947f.yakity
      c02.c7c947f.yakity
      w01.c7c947f.yakity
    ```

21. SSH into the first node in the cluster with:
    ```shell
    $ ssh-c7c947f c01
    22:01:04 up  4:01,  0 users,  load average: 0.01, 0.08, 0.12
    tdnf update info not available yet!
    [0]root@c01:~$ 
    ```

22. Once remotely logged into `c01`, use the `kubectl` command to discover details about the cluster:
    ```shell
    $ kubectl get nodes
    NAME                 STATUS   ROLES    AGE     VERSION
    c02.c7c947f.yakity   Ready    <none>   3h59m   v1.12.2
    w01.c7c947f.yakity   Ready    <none>   3h59m   v1.12.2
    ```

    ```shell
    $ kubectl get cs
    NAME                 STATUS    MESSAGE             ERROR
    controller-manager   Healthy   ok                  
    scheduler            Healthy   ok                  
    etcd-0               Healthy   {"health":"true"}   
    etcd-1               Healthy   {"health":"true"}
    ```

    ```shell
    $ kubectl -n kube-system get pods
    NAME                               READY   STATUS    RESTARTS   AGE
    kube-dns-67b548dcff-hxlv8          3/3     Running   0          3h59m
    vsphere-cloud-controller-manager   1/1     Running   0          3h59m
    ```

23. Once the cluster is no longer needed, it can be destroyed with the local
    turn-down script:
    ```shell
    $ turn-down-c7c947f
      destroying VM controller:4230384e-6392-e2c3-97cd-5dda6b4cfecf:c01
      destroying VM both:4230947a-5258-faa3-45b6-f4fadce5f6c2:c02
      destroying VM worker:42305163-608e-532e-f8d8-37a544db51d3:w01
    ```