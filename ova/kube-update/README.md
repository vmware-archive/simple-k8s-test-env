# kube-update
When deployed on vSphere as an OVA, yakity supports the `kube-update` service --
updating Kubernetes components on a live cluster with incremental builds from a
developer's desktop.

## Uploading a new version of a program
To upload a new version of one or more programs, simply SCP the files to the
`/kube-update` directory on any of the cluster's nodes. A member of the cluster
will redistribute the files until all members receive updated copies.
