# yakity
Yakity (_**Y**et **A**nother **K**ubernetes **I**nstaller 
**T**hing**Y**_) is:

  * _For developers building and testing Kubernetes and core Kubernetes components_
  * Capable of deploying *any* [version](https://github.com/akutz/yakity/wiki/Kubernetes-version) of Kubernetes (+1.10) on generic Linux distributions
  * Designed to deploy single-node, multi-node, and even multi-control plane node clusters
  * Able to deploy nodes on DHCP networks with support for both node FQDNs and IPv4 addresses
  * A single, POSIX-compliant shell script, making it portable and customizable

## Quick start
The quickest way to provision a Kubernetes cluster with Yakity is on vSphere 
using the [OVA](doc/provision-on-vsphere-with-ova.md).

## Getting started
  * [How does yakity work?](#how-does-yakity-work)
  * [What does yakity install?](#what-does-yakity-install)
  * [How to provision Kubernetes with yakity](#how-to-provision-kubernetes-with-yakity)

### How does yakity work?
Yakity is a single, POSIX-compliant shell script that is designed to work with
most Linux distributions. This [model](https://s3-us-west-2.amazonaws.com/cnx.vmware/cicd/yakity/svg/install-process.svg)
illustrates an example yakity execution.

### What does yakity install?
A yakity-provisioned cluster passes the Kubernetes e2e conformance test suite
because yakity uses a well-known, standard set of components to the control
plane and worker nodes:

![Node components](https://s3-us-west-2.amazonaws.com/cnx.vmware/cicd/yakity/svg/node-components.svg?v2)

### How to provision Kubernetes with yakity
There are several ways to provision a Kubernetes cluster with yakity:

  * [Provision a multi-node cluster on vSphere with the yakity OVA](doc/provision-on-vsphere-with-ova.md)
  * [Provision a multi-node cluster on VMware Cloud (VMC) on AWS with the yakity OVA](doc/provision-on-vmc-with-ova.md)
  * Provision a single-node cluster on the desktop using Vagrant
  * Provision a multi-node cluster on the desktop using Vagrant

## Todo
* Better testing
* Better documentaton
