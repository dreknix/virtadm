#!/usr/bin/env bash

function _virtadm_create() {

  local virt_console_arg="--noautoconsole"

  local LONG_OPTIONS=(
    "console"
  )

  # read function arguments
  opts=$(getopt \
             --longoptions "$(printf "%s," "${LONG_OPTIONS[@]}")" \
             --name "${progname}" \
             --options "" \
             -- "$@"
        ) || __die "getopt failed"
  eval set -- "$opts"

  while [[ $# -gt 0 ]]
  do
    case "$1" in
      --console)
        virt_console_arg=""
        shift
        ;;

      --)
        shift
        break
        ;;
      *)
        __die "Option '${1}' was not expected"
        break
        ;;
    esac
  done

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

  if virsh dominfo "${vm_name}" &> /dev/null
  then
    __die "VM '${vm_name}' is already existing"
  fi

  if [ -z "${vm_desc}" ]
  then
    __die "Value vm.desc is not set in '${yaml_file}'"
  fi

  if [ -z "${vm_os}" ]
  then
    __die "Value vm.os is not set in '${yaml_file}'"
  fi

  if [ -z "${vm_hardware_cpu}" ]
  then
    __die "Value vm.hardware.cpu is not set in '${yaml_file}'"
  fi

  if [ -z "${vm_hardware_memory}" ]
  then
    __die "Value vm.hardware.memory is not set in '${yaml_file}'"
  fi

  if [ -z "${vm_disk_size}" ]
  then
    __die "Value vm.disk.size is not set in '${yaml_file}'"
  fi

  if [ -z "${vm_disk_driver}" ]
  then
    __die "Value vm.disk.driver is not set in '${yaml_file}'"
  fi

  vm_disk_image="${SCRIPT_BASE}/images/${vm_name}.qcow2"
  if [ -n "${cloudinit_image}" ] && [ ! -f "${vm_disk_image}" ]
  then
    CI_IMAGE="${SCRIPT_BASE}/iso/${cloudinit_image##*/}"
    if [ ! -f "${CI_IMAGE}" ]
    then
      curl -LO --output-dir "${SCRIPT_BASE}/iso" "${cloudinit_image}"
    fi
    if [ ! -f "${CI_IMAGE}" ]
    then
      __die "cloud-init image not found"
    fi
    if ! qemu-img create \
      -b "${CI_IMAGE}" -F qcow2 -f qcow2 \
      "${vm_disk_image}" "${vm_disk_size}"G &> /dev/null
    then
      __die "Creating disk image from cloud image failed"
    fi
  fi

  cloud_init=""
  if [ -n "${cloudinit_image}" ]
  then
    export cloud_init_hostname="${vm_hostname%%.*}"
    export cloud_init_fqdn="${vm_hostname}"
    export cloud_init_password="$(get-gopass.sh virtadm/defaultpw)"
    export cloud_init_ip4_address="${cloudinit_ip4_address}"
    export cloud_init_ip4_gateway="${cloudinit_ip4_gateway}"
    export cloud_init_nameservers="${cloudinit_nameservers}"

    mkdir -p "${SCRIPT_BASE}/cloud-init/${vm_name}/"
    user_data="${SCRIPT_BASE}/cloud-init/${vm_name}/user-data.yaml"
    network="${SCRIPT_BASE}/cloud-init/${vm_name}/network.yaml"
    j2 "${SCRIPT_BASE}/cloud-init/user-data.j2" > "${user_data}"
    j2 "${SCRIPT_BASE}/cloud-init/network.j2" > "${network}"
    cloud_init="--cloud-init network-config=${network},user-data=${user_data}"
  fi

  if [ ! -f "${vm_disk_image}" ]
  then
    __die "Image '${vm_disk_image}' is not readable"
  fi

  additional_args=""
  if [ -n "${vm_cdrom}" ]
  then
    vm_cdrom="${SCRIPT_BASE}/iso/${vm_cdrom}"
    if [ ! -f "${vm_cdrom}" ]
    then
      __die "Image '${vm_cdrom}' is not readable"
    fi
    vm_cdrom="--location ${vm_cdrom}"
  else
    additional_args="--boot hd"
  fi

  echo "vm_disk_image: $vm_disk_image"
  # only working with --location
  # --console pty,target_type=serial \
  # --extra-args 'console=ttyS0,115200n8 serial' \
  # --graphics vnc \

  # get list of os: virt-install --osinfo list
  virt-install \
    -n "${vm_name}" \
    --description "${vm_desc}" \
    --osinfo="${vm_os}" \
    --ram=${vm_hardware_memory} \
    --vcpus=${vm_hardware_cpu} \
    --disk path="${vm_disk_image}",bus=${vm_disk_driver},size=${vm_disk_size} \
    ${vm_cdrom} \
    ${cloud_init} \
    --network=default,model=virtio \
    --import \
    --nographics \
    ${additional_args} \
    ${virt_console_arg}

  #  --disk path="${vm_disk_image/server/server-cloudinit}",bus=${vm_disk_driver} \
  #  --disk path="${vm_disk_image/server.qcow2/server-cloudinit.iso}",device=cdrom \

  # --location /data/vms/iso/Fedora-Workstation-Live-x86_64-37-1.7.iso,initrd=images/pxeboot/initrd.img,kernel=images/pxeboot/vmlinuz \

  # virsh destroy fedora37; virsh undefine fedora37
}

export _virtadm_create
