#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

vm_ip=$(govc vm.ip -vm.uuid "${1}" -v4 -n ethernet-0)

mkdir -p "${HOME}/.yakity/ssh"
chmod 0700 "${HOME}/.yakity/ssh"
ssh_prv_key="${HOME}/.yakity/ssh/id_rsa"
curl -sSL http://bit.ly/get-ssh | sh -s -- "${1}" >"${ssh_prv_key}"
chmod 0600 "${ssh_prv_key}"

ssh_cmd="ssh -i \"${ssh_prv_key}\""
if [ -n "${JUMP_HOST}" ]; then
  ssh_cmd="${ssh_cmd} -o ProxyCommand=\"ssh -W ${vm_ip}:22 ${JUMP_HOST}\""
fi
ssh_cmd="${ssh_cmd} root@${vm_ip}"

printf 'log into host with the following command:\n\n  %s\n' "${ssh_cmd}"
if printf "%s" "${ssh_cmd}" | pbcopy >/dev/null 2>&1; then
  MOD_KEY="⌘"
elif printf "%s" "${ssh_cmd}" | xclip -selection clipboard >/dev/null 2>&1; then
  MOD_KEY="ctl"
fi
if [ -n "${MOD_KEY}" ]; then
  printf '\nthe above command is in the clipboard; use %s-v to paste the command into the terminal.\n' "${MOD_KEY}"
fi
