#!/usr/bin/env bash

function _virtadm_ssh() {

  if [ $# -ne 1 ]
  then
    __die "Missing argument 'config.yaml'"
  fi

  yaml_file="$1"

  if [ ! -f "${yaml_file}" ]
  then
    __die "Can not read config '${yaml_file}'"
  fi

  eval "$(__parse_yaml "${yaml_file}")"

  if [ -z "${vm_name}" ]
  then
    __die "Value vm.name is not set in '${yaml_file}'"
  fi

  if ! virsh dominfo "${vm_name}" &> /dev/null
  then
    __die "VM '${vm_name}' is not existent"
  fi

  local mac_address
  local ip_address
  mac_address="$(virsh dumpxml "${vm_name}" | grep "mac address" | awk -F\' '{ print $2 }')"
  ip_address="$(arp -n | grep "${mac_address}" | cut -f 1 -d ' ')"

  ssh -o UserKnownHostsFile=/dev/null \
      -o StrictHostKeyChecking=no \
      -l root -i ~/.ssh/id_dreknix \
      "${ip_address}"

}

export _virtadm_ssh