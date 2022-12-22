#!/usr/bin/env bash

function _virtadm_cleanup() {

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

  local undefine_args=()
  if [[ "${virt_vm_os:-}" = win* ]]
  then
    undefine_args+=("--nvram")
  fi

  echo -n "Cleanup ${virt_vm_name}: "
  for __cdrom in $(virsh domblklist --details "${virt_vm_name}" | awk '{ if ($2 == "cdrom") print $3}')
  do
    virsh change-media "${virt_vm_name}" "${__cdrom}" --eject &> /dev/null
  done

  # remove unattend ISO
  if [ -n "${virt_unattend_template:-}" ]
  then
    rm -f "${SCRIPT_BASE}/unattend/${virt_vm_name}.iso"
  fi

  echo "done"
}

export _virtadm_cleanup
