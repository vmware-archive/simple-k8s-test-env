#!/bin/sh

#
# This script is not meant to be used locally. It's copied to the
# Vagrant boxes and used to tail the sk8 log from the client.
# The log is followed only until the sk8 process is no longer
# writing to the log.
#
log_file=/var/log/sk8/sk8.log
done_file=/var/lib/sk8/.sk8.service.done
printf 'waiting for sk8 to start...'
i=0 && while [ "${i}" -lt "300" ] && \
             [ -z "${pid}" ] && \
             [ ! -f "${done_file}" ]; do
  if ! pid=$(sudo fuser /var/log/sk8/sk8.log 2>/dev/null | \
    awk '{print $NF;exit}' | tr -d '\n\r'); then
    printf '.'; sleep 1; i=$((i+1))
  fi
done; echo
if [ -f "${done_file}" ]; then
  exec cat "${log_file}"
elif [ -z "${pid}" ]; then
  echo "timed out" 1>&2 && exit 1
else
  exec tail --pid="${pid}" -f "${log_file}"
fi