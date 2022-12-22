#!/usr/bin/env bash

function _virtadm_connect() {

  if [ $# -ne 1 ]
  then
    __die "Missing argument 'config.yaml'"
  fi

  yaml_file="${1:?'First parameter is missing'}"

  if [ ! -f "${yaml_file}" ]
  then
    __die "Can not read config '${yaml_file}'"
  fi

  eval "$(__parse_yaml "${yaml_file}" "virt_")"

  if [ -z "${virt_vm_name:-}" ]
  then
    __die "Value vm.name is not set in '${yaml_file}'"
  fi

  if ! virsh dominfo "${virt_vm_name}" &> /dev/null
  then
    __die "VM '${virt_vm_name}' is not existent"
  fi

  if ! virsh domdisplay "${virt_vm_name}" &> /dev/null
  then
    virsh console "${virt_vm_name}"
  else
    virt-viewer --wait "${virt_vm_name}"
  fi
}

export _virtadm_connect
