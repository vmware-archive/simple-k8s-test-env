# yake2e
This project provides a turn-key solution for running the Kubernetes 
conformance tests on the VMware vSphere on VMC platform. In other words,
it's **Y**et **A**nother **K**ubernetes **e2e** runner :)

## Quick start
To run the Kubernetes conformance tests follow these steps:

1. Create a file named `config.env` with Terraform properties that
reflect the environment to which the cluster will be deployed. For a
full list of the properties available (as well as their default values), 
please see `input.tf`.

2. Create a file named `secure.env` with vSphere and AWS credentials
used to access the vSphere on VMC environment. For example:

```
TF_VAR_vsphere_server=1.2.3.4
TF_VAR_vsphere_user=admin
TF_VAR_vsphere_password=password

AWS_ACCESS_KEY_ID=abc123
AWS_SECRET_ACCESS_KEY=edf456
AWS_DEFAULT_REGION=us-west-2
```

3. Turn up a cluster named `stable`:
```shell
$ docker run -it --rm \
  -v "$(pwd)/data":/tf/data \
  --env-file config.env \
  --env-file secure.env \
  gcr.io/kubernetes-conformance-testing/yake2e \
  stable up
```

4. Schedule the e2e conformance tests as job on the turned-up cluster:
```shell
$ docker run -it --rm \
  -v "$(pwd)/data":/tf/data \
  gcr.io/kubernetes-conformance-testing/yake2e \
  stable test
```

5. Follow the remote, e2e conformance job's progress in real-time:
```shell
$ docker run -it --rm \
  -v "$(pwd)/data":/tf/data \
  gcr.io/kubernetes-conformance-testing/yake2e \
  stable tlog
```

6. Turn down the cluster:
```shell
$ docker run -it --rm \
  -v "$(pwd)/data":/tf/data \
  --env-file config.env \
  --env-file secure.env \
  gcr.io/kubernetes-conformance-testing/yake2e \
  stable down
```

## Run the e2e tests with an external cloud-provider
The cluster turned up in the [quick start](#quick-start) section is
deployed with the in-tree vSphere cloud provider. To turn up a cluster
using the out-of-tree vSphere cloud provider simply modify the third
step:

```shell
$ docker run -it --rm \
  -v "$(pwd)/data":/tf/data \
  --env-file config.env \
  --env-file secure.env \
  --env TF_VAR_cloud_provider=external \
  gcr.io/kubernetes-conformance-testing/yake2e \
  stable up
```

Beyond that all the other steps are the same.

## Download the e2e test results
The following command will block until the e2e tests have completed
and then download the test results as a tarball:

```shell
$ docker run -it --rm \
  -v "$(pwd)/data":/tf/data \
  gcr.io/kubernetes-conformance-testing/yake2e \
  stable tget
```

## Upload the e2e test results to GCS
After using `tget`, the following command will upload the test results
to a GCS bucket:

```shell
$ docker run -it --rm \
  -v "$(pwd)/data":/tf/data \
  gcr.io/kubernetes-conformance-testing/yake2e \
  stable tput gs://path-to-bucket google-cloud-key-file.json
```

## Stop the e2e test
The following command stops any in-progress e2e test job:

```shell
$ docker run -it --rm \
  -v "$(pwd)/data":/tf/data \
  gcr.io/kubernetes-conformance-testing/yake2e \
  stable tdel
```
