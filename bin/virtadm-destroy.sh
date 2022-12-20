#!/usr/bin/env bash

function _virtadm_destroy() {

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

  echo -n "Delete ${vm_name}: "
  virsh shutdown "${vm_name}" &> /dev/null
  sleep 1
  virsh destroy "${vm_name}" &> /dev/null
  virsh undefine "${vm_name}" &> /dev/null
  rm -f "images/${vm_name}.qcow2" &> /dev/null
  echo "done"
}

export _virtadm_destroy
