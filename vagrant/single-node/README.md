# Provision a single-node Kubernetes cluster with Vagrant
This document is a step-by-step guide to provisioning a single-node Kubernetes 
cluster with Vagrant and yakity.

## Guide
1. Clone this repository:
    ```shell
    $ git clone https://github.com/akutz/yakity /tmp/yakity
    ```

2. Open a shell and change directories into `/tmp/yakity/vagrant/single-node`
    ```shell
    $ cd /tmp/yakity/vagrant/single-node
    ```

3. Run `vagrant up` to start provisioning the cluster. This command:

    * Generates a self-signed, x509 certificate authority at `../ca.crt` and `../ca.key`
    * Generates an x509 certificate/key pair for the K8s admin user at `../k8s-admin.crt` and `../k8s-admin.key`
    * Generates a kubeconfig for the K8s admin user at `../kubeconfig`
    * Starts turning up the node `c01`

4. Vagrant will declare the box ready before the cluster is actually online. The deploy process may be monitored with the following command:
    ```shell
    $ vagrant ssh c01 -c 'tail -f /var/log/yakity/yakity.log'
    ```

5. The cluster is provisioned when the following log message appears:
    ```
    So long, and thanks for all the fish.
    ```

6. Use the `kubectl` program to access the cluster:
    ```shell
    $ kubectl --kubeconfig ../kubeconfig get cs
    NAME                 STATUS    MESSAGE             ERROR
    controller-manager   Healthy   ok                  
    scheduler            Healthy   ok                  
    etcd-0               Healthy   {"health":"true"}
    ```

    ```shell
    $ kubectl --kubeconfig ../kubeconfig get nodes
    NAME         STATUS    ROLES     AGE       VERSION
    c01.yakity   Ready     <none>    118s      v1.12.2
    ```

    ```shell
    $ kubectl --kubeconfig ../kubeconfig -n kube-system get pods
    NAME                        READY     STATUS    RESTARTS   AGE
    kube-dns-67b548dcff-mtkfv   3/3       Running   0          2m42s
    ```

7. Once the cluster is no longer needed it may be destroyed with the following command:
    ```shell
    $ vagrant destroy -f
    ```