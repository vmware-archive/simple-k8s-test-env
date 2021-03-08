---

VMware has ended active development of this project, and its repository will no longer be updated.

---

# Simple Kubernetes Test Environment
The Simple Kubernetes Test Enviornment (sk8) project is:

  * _For developers building and testing Kubernetes and core Kubernetes components_
  * Capable of deploying *any* [version](https://github.com/vmware/simple-k8s-test-env/wiki/Kubernetes-version) of Kubernetes (+1.10) on generic Linux distributions
  * Designed to deploy single-node, multi-node, and even multi-control plane node clusters
  * Able to deploy nodes on DHCP networks with support for both node FQDNs and IPv4 addresses
  * A single, POSIX-compliant shell script, making it portable and customizable

## Quick start
The quickest way to provision a Kubernetes cluster with sk8 is on vSphere 
using the [OVA](ova/doc/provision-on-vsphere-with-ova.md).

## Getting started
  * [How does sk8 work?](#how-does-sk8-work)
  * [What does sk8 install?](#what-does-sk8-install)
  * [How to provision Kubernetes with sk8](#how-to-provision-kubernetes-sk8-sk8)

### How does sk8 work?
The sk8 project revolves around a single, POSIX-compliant shell script designed
to be compatible with most Linux distributions. This 
[model](https://s3-us-west-2.amazonaws.com/cnx.vmware/cicd/sk8/svg/install-process.svg)
illustrates an example sk8 execution.

### What does sk8 install?
A sk8-provisioned cluster passes the Kubernetes e2e conformance test suite
because sk8 uses a well-known, standard set of components to the control
plane and worker nodes:

![Node components](https://s3-us-west-2.amazonaws.com/cnx.vmware/cicd/sk8/svg/node-components.svg?v2)

### How to provision Kubernetes with sk8
There are several ways to provision a Kubernetes cluster with sk8:

  * [Provision a multi-node cluster on vSphere with the sk8 OVA](ova/doc/provision-on-vsphere-with-ova.md)
  * [Provision a multi-node cluster on VMware Cloud (VMC) on AWS with the sk8 OVA](ova/doc/provision-on-vmc-with-ova.md)
  * [Provision single-node and multi-node clusters with sk8 and Vagrant](vagrant/)

## Todo
* Better testing
* Better documentaton

## License
Please the [LICENSE](LICENSE) file for information about this project's license.
