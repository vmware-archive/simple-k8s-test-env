FROM alpine:3.8
LABEL "maintainer" "Andrew Kutz <akutz@vmware.com>"

# Install the common dependencies.
RUN apk --no-cache add \
    ca-certificates \
    curl \
    python \
    ruby \
    ruby-rdoc \
    unzip

# Clean up the alpine cache.
RUN rm -rf /var/cache/apk/*

# Install the ruby gem that enables the uploading of files as gists.
RUN gem install gist

# Download the Google Cloud SDK
RUN curl -sSL https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-217.0.0-linux-x86_64.tar.gz | \
    tar xzC /

# Download Terraform and place its binary in /usr/bin.
ENV TF_VERSION=0.11.8
ENV TF_ZIP=terraform_${TF_VERSION}_linux_amd64.zip
ENV TF_URL=https://releases.hashicorp.com/terraform/${TF_VERSION}/${TF_ZIP}
RUN curl -sSLO "${TF_URL}" && unzip "${TF_ZIP}" -d /usr/bin && rm -f "${TF_ZIP}"

# Create the directory structure.
RUN mkdir -p /tf/vmc

# Copy the assets into the /tf directory.
COPY *.tf cloud_config.yaml entrypoint.sh upload_e2e.py /tf/
COPY vmc/*.tf /tf/vmc/

# Make sure all of the scripts are marked as executable.
RUN chmod 0755 /tf/*.sh /tf/*.py

# The entrypoint command will be executed from the following working directory.
WORKDIR /tf

# Link some musl so e2e.test doesn't die.
RUN mkdir -p /lib64 && ln -s /lib/libc.musl-x86_64.so.1 /lib64/ld-linux-x86-64.so.2

# Update the PATH to include the Google Cloud SDK.
ENV PATH=/google-cloud-sdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# The default argument for the entrypoint will drop the user into a shell.
CMD [ "sh" ]
ENTRYPOINT [ "/tf/entrypoint.sh" ]
