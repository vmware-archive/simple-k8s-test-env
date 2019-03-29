FROM debian:stretch-20190204-slim
LABEL "maintainer" "Andrew Kutz <akutz@vmware.com>"

# Update the CA certificates and clean up the apt cache.
RUN apt-get -y update && \
    apt-get -y --no-install-recommends install \
    ca-certificates curl jq locales python3 ruby tar unzip && \
    rm -rf /var/cache/apt/* /var/lib/apt/lists/*

# Set the locale so that the gist command is happy.
ENV LANG=en_US.UTF-8
ENV LC_ALL=C.UTF-8

# Install pip
RUN curl -sSL https://bootstrap.pypa.io/get-pip.py | python3 -

# Install the ruby gem that enables the uploading of files as gists.
RUN gem install gist

# Install the AWS CLI
RUN pip3 install awscli --upgrade

# Download the Google Cloud SDK
RUN curl -sSL https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-217.0.0-linux-x86_64.tar.gz | \
    tar xzC / && \
    /google-cloud-sdk/bin/gcloud components update

# Download Sonobuoy
RUN curl -sSL https://github.com/heptio/sonobuoy/releases/download/v0.13.0/sonobuoy_0.13.0_linux_amd64.tar.gz | \
    tar xzC /usr/local/bin --exclude=LICENSE

# Download Terraform and place its binary in /usr/local/bin.
ENV TF_VERSION=0.11.8
ENV TF_ZIP=terraform_${TF_VERSION}_linux_amd64.zip
ENV TF_URL=https://releases.hashicorp.com/terraform/${TF_VERSION}/${TF_ZIP}
RUN curl -sSLO "${TF_URL}" && unzip "${TF_ZIP}" -d /usr/local/bin && rm -f "${TF_ZIP}"

# Download the kubectl binary.
RUN k8s_version="$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)" && \
    curl -sSLo /usr/local/bin/kubectl "https://storage.googleapis.com/kubernetes-release/release/${k8s_version}/bin/linux/amd64/kubectl" && \
    chmod 0755 /usr/local/bin/kubectl

# Copy the keepalive program to /usr/local/bin.
COPY hack/keepalive/keepalive.linux_amd64 /usr/local/bin/keepalive

# Download govc
RUN curl -sSL https://github.com/vmware/govmomi/releases/download/v0.20.0/govc_linux_amd64.gz | \
    gzip -d >/usr/local/bin/govc && chmod 0755 /usr/local/bin/govc

# Create the directory structure.
RUN mkdir -p /tf/vmc

# Copy the assets into the /tf directory.
COPY *.tf cloud_config.yaml destroy.sh entrypoint.sh upload_e2e.py sonobuoy.yaml /tf/
COPY vmc/*.tf /tf/vmc/

# Make sure all of the scripts are marked as executable.
RUN chmod 0755 /tf/*.sh /tf/*.py

# The entrypoint command will be executed from the following working directory.
WORKDIR /tf

# Update the PATH to include the Google Cloud SDK.
ENV PATH=/google-cloud-sdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Download the Terraform plug-ins.
RUN cp data.tf data.tf.bak && \
  ./entrypoint.sh null plugins && \
  mv -f data.tf.bak data.tf

# The default argument for the entrypoint will drop the user into a shell.
CMD [ "bash" ]
ENTRYPOINT [ "/tf/entrypoint.sh" ]
