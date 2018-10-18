#!/bin/sh

set -x
set -e
set -o pipefail

rm -f "${HOME}/Downloads/yakity-centos.ova" && \
rm -f "${HOME}/Downloads/yakity-centos.ovf" && \
cp -f "$(dirname "${0}")/centos.ovf" "${HOME}/Downloads/yakity-centos.ovf" && \
tar -C "${HOME}/Downloads" -cf "${HOME}/Downloads/yakity-centos.ova" yakity-centos.ovf yakity-centos-1.vmdk yakity-centos-2.nvram && \
aws s3 cp "${HOME}/Downloads/yakity-centos.ova" s3://cnx.vmware/cicd/yakity-centos.ova --grants read=uri=http://acs.amazonaws.com/groups/global/AllUsers && \
echo "https://s3-us-west-2.amazonaws.com/cnx.vmware/cicd/yakity-centos.ova"
