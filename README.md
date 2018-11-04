# yakity
*For developers building and testing Kubernetes and core Kubernets components*

## Overview
There are generally three types of people working with Kubernetes:

  1. Operators
  2. Developers building and testing applications for and with Kubernetes
  3. Developers building and testing Kubernetes

While there are multiple solutions available for the first two types of
people, there's a gap when it comes to helping the third. Yakity is
designed to assist developers building and testing Kubernetes and core
Kubernetes components such as cloud providers. Yakity is:

  * Capable of deploying single-node, multi-node, and even multi-control plane node clusters
  * Designed to deploy *any* version of Kubernetes (+1.10) on generic Linux distributions
  * Able to deploy Kubernetes from multiple sources such as GCS and S3 buckets or [any HTTP location](https://github.com/akutz/yakity/wiki/Kubernetes-version)
  * Capable of supporting nodes using DHCP via yakity's discovery process
  * A single, POSIX-compliant shell-script making it easy to modify

For more detailed information, the entire yakity process, including discovery,
is available as a UML [model](https://s3-us-west-2.amazonaws.com/cnx.vmware/cicd/yakity/svg/yakity-overview.svg).

## Quick Start
The quickest way to provision a Kubernetes cluster with Yakity is on
vSphere using the yakity-photon 
[OVA](https://s3-us-west-2.amazonaws.com/cnx.vmware/cicd/yakity-photon.ova).

## Getting Started
Yakity can provision Kubernetes on disparate hosts configured with DHCP
or static networking. This example demonstrates using yakity to
provision Kubernetes to two Amazon EC2 CentOS Linux instances.

The first step is to generate an etcd discovery URL:

```shell
$ ETCD_DISCOVERY=$(curl https://discovery.etcd.io/new?size=1)
```

Next, SSH into each instance and write a valid CA certificate and key
that can be used to generate certificates to `/etc/ssl/ca.crt` and
`/etc/ssl/ca.key`.

Once the CA is in place on both instances, SSH into the first instance and
use yakity to deploy the host as a control plane node:

```shell
$ curl -sSL https://raw.githubusercontent.com/akutz/yakity/master/yakity.sh | \
  NODE_TYPE=controller \
  ETCD_DISCOVERY="${ETCD_DISCOVERY}" \
  NUM_CONTROLLERS=1 \
  NUM_NODES=2 sh -
```

Deploy the worker node by SSHing into the second instance and executing:

```shell
$ curl -sSL https://raw.githubusercontent.com/akutz/yakity/master/yakity.sh | \
  NODE_TYPE=worker \
  ETCD_DISCOVERY="${ETCD_DISCOVERY}" \
  NUM_CONTROLLERS=1 \
  NUM_NODES=2 sh -
```

Finally, once both nodes are deployed (example logs for 
[controller](https://gist.github.com/akutz/00288cd1252f07139be6035c31a7e25a#file-yakity-sh-controller-log)
and [worker](https://gist.github.com/akutz/00288cd1252f07139be6035c31a7e25a#file-yakity-sh-worker-log)),
verify that the cluster is up and running as expected:

```shell
$ kubectl run busybox --image=busybox:1.28 --command -- sleep 3600 2>/dev/null || true; \
> POD_NAME=$(kubectl get pods -l run=busybox -o jsonpath="{.items[0].metadata.name}") && \
> kubectl exec -ti "${POD_NAME}" -- nslookup kubernetes
Server:    10.32.0.10
Address 1: 10.32.0.10

Name:      kubernetes
Address 1: 10.32.0.1
```

## Todo
* Better testing
* Better documentaton
