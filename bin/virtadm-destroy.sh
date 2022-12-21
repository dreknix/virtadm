#!/usr/bin/env bash

function _virtadm_destroy() {

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

  echo -n "Delete ${virt_vm_name}: "
  virsh shutdown "${virt_vm_name}" &> /dev/null
  sleep 1
  virsh destroy "${virt_vm_name}" &> /dev/null
  virsh undefine "${virt_vm_name}" &> /dev/null
  rm -f "images/${virt_vm_name}.qcow2" &> /dev/null
  rm -rf "cloud-init/${virt_vm_name}/" &> /dev/null
  echo "done"
}

export _virtadm_destroy
