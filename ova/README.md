# The yakity OVA
Yakity can be deployed many ways, but perhaps the simplest is onto a
vSphere platform using an OVA. This directory contains the bits
necessary to build the yakity OVA.

## Support Linux Distributions
The yakity OVA comes in a variety of flavors:
* CentOS 7 ([OVA](https://s3-us-west-2.amazonaws.com/cnx.vmware/cicd/yakity-centos.ova))
* PhotonOS (work-in-progress)

## Building the OVA
The OVA is built using a staging VM that lives on a vSphere platform.
The `hack/prep.sh` script uses the [`govc`](https://github.com/vmware/govmomi/tree/master/govc)
command to interact with the staging VM. Therefore building the OVA has
the following prerequisites:

1. Access to a vSphere platform
2. A staging VM based on CentOS or PhotonOS
3. The [`govc`](https://github.com/vmware/govmomi/tree/master/govc) command.

## Preparing the staging VM
A staging VM is nothing more than a VM deployed with CentOS7 Minimal Server
edition or PhotonOS 2. The VM should have the following, minmal hardware
specs:

* 1 CPU
* 2GiB RAM
* 16GiB HDD

Once the VM is deployed, copy a public SSH key to it and snapshot the VM.

### Preparing a PhotonOS staging VM
After remote access is enabled, take a snapshot of the VM and write down
the name.

The PhotonOS VM is ready to be sealed or debugged.

### Preparing a CentOS staging VM
Once the CentOS VM is accessible remotely, execute the contents
of the file `hack/centos/centos-prep.sh` on the VM. Shut down the guest
when the prep script has completed and take a snapshot of the VM and 
remember the name.

The CentOS staging VM is now ready to be sealed or debugged.

## Modifying the prep script
The file `hack/prep.sh` contains environment variables that define
the inventory path of the staging VM as well as the name of the snapshot
taken in the previous section. Please modify the script where necessary.

## Sealing the staging VM
The following command can be used to prep the staging VM and seal it in
preparation to be exported as an OVA:

```shell
$ make seal
```

## Debugging the staging VM
The following command performs all of the same tasks involved in sealing
the staging VM right up to the sealing part. Therefore the prep command
is ideal when it comes to debugging the OVA:

```shell
$ make prep
```

## Building the OVA
The first step to building the OVA is sealing the staging VM and then
exporting it to an OVF. Export the OVF as `yakity-centos` or `yakity-photon`
and then use the following command to build the OVA:

```shell
$ make build
```

If the command fails it may be necessary to run it with the following
environment variables:

```shell
$ YAKITY_CENTOS_VMDK=PATH_TO_OVF_VMDK \
  YAKITY_CENTOS_NVRAM=PATH_TO_OVF_NVRAM \
  make build
```
