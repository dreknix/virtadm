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

  # disk image
  vm_disk_image="${SCRIPT_BASE}/images/${vm_name}.qcow2"
  vm_disk_driver="${vm_disk_driver:-virtio}"
  if [ -z "${vm_disk_size}" ]
  then
    __die "Value vm.disk.size is not set in '${yaml_file}'"
  fi

  if [ -n "${cloudinit_image:-}" ] && [ ! -f "${vm_disk_image}" ]
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
      "${vm_disk_image}" "${vm_disk_size}" &> /dev/null
    then
      __die "Creating disk image from cloud image failed"
    fi
  fi

  if [ -z "${cloudinit_image:-}" ]
  then
    if ! qemu-img create \
      -f qcow2 "${vm_disk_image}" "${vm_disk_size}" &> /dev/null
    then
      __die "Creating empty disk image failed"
    fi
  fi

  local additional_args=()

  local virt_cloud_init_arg=""
  if [ -n "${cloudinit_image:-}" ]
  then
    additional_args=("--import")

    export cloud_init_hostname="${vm_hostname%%.*}"
    export cloud_init_fqdn="${vm_hostname}"
    export cloud_init_password="$(mkpasswd --method=SHA-512 "$(get-gopass.sh virtadm/defaultpw)")"
    export cloud_init_ip4_address="${cloudinit_ip4_address:-}"
    export cloud_init_ip4_gateway="${cloudinit_ip4_gateway:-}"
    export cloud_init_nameservers="${cloudinit_nameservers:-}"

    mkdir -p "${SCRIPT_BASE}/cloud-init/${vm_name}/"
    user_data="${SCRIPT_BASE}/cloud-init/${vm_name}/user-data.yaml"
    network="${SCRIPT_BASE}/cloud-init/${vm_name}/network.yaml"
    j2 "${SCRIPT_BASE}/cloud-init/user-data.j2" > "${user_data}"
    j2 "${SCRIPT_BASE}/cloud-init/network.j2" > "${network}"
    #virt_cloud_init_arg="--cloud-init network-config=${network},user-data=${user_data}"
    cloud-localds \
      --disk-format raw \
      --filesystem iso9660 \
      --network-config "${network}" \
      "${SCRIPT_BASE}/cloud-init/${vm_name}/cloud-init.iso" \
      "${user_data}"

    virt_cloud_init_arg="--disk path=${SCRIPT_BASE}/cloud-init/${vm_name}/cloud-init.iso,bus=virtio"
  fi

  if [ ! -f "${vm_disk_image}" ]
  then
    __die "Image '${vm_disk_image}' is not readable"
  fi

  if [ -n "${vm_cdrom:-}" ]
  then
    vm_cdrom="${SCRIPT_BASE}/iso/${vm_cdrom}"
    if [ ! -f "${vm_cdrom}" ]
    then
      __die "Image '${vm_cdrom}' is not readable"
    fi
    vm_cdrom="--cdrom ${vm_cdrom}"
  else
    vm_cdrom=""
    additional_args+=("--boot" "hd")
  fi

  if [[ "$vm_os" = win* ]]
  then
    additional_args+=("--boot" "uefi")
    # TODO: read https://bugzilla.redhat.com/show_bug.cgi?id=1387479
    #additional_args+=("--features" "kvm_hidden=on,smm=on")
    #additional_args+=("--boot" "loader=/usr/share/OVMF/OVMF_CODE.secboot.fd,\
    #                            loader_ro=yes,\
    #                            loader_type=pflash,\
    #                            nvram_template=/usr/share/OVMF/OVMF_VARS.ms.fd")
    additional_args+=("--tpm" "backend.type=emulator,backend.version=2.0,model=tpm-tis")

    virt_graphics_arg=("--graphics" "spice" "--video" "virtio")

    # add driver disk
    local virtio_url="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
    local virtio_driver_iso="${SCRIPT_BASE}/iso/virtio-win.iso"
    if [ ! -f "${virtio_driver_iso}" ]
    then
      curl -LO --output-dir "${SCRIPT_BASE}/iso" "${virtio_url}"
    fi
    additional_args+=("--disk" "path=${SCRIPT_BASE}/iso/virtio-win.iso,device=cdrom")

    # check if Autounattend.xml should be provided
    if [ -n "${unattend_template:-}" ]
    then
      unattend_template="${SCRIPT_BASE}/unattend/${unattend_template}"
      if [ ! -r "${unattend_template}" ]
      then
        __die "Unattend template '${unattend_template}' is missing"
      fi
      local unattend_dir="${SCRIPT_BASE}/unattend/${vm_name}/"
      mkdir "${unattend_dir}"
      local unattend_iso="${SCRIPT_BASE}/unattend/${vm_name}.iso"
      # create Autounattend.xml from given template
      export unattend_hostname="${vm_hostname%%.*}"
      export unattend_password="$(get-gopass.sh virtadm/defaultpw)"
      j2 "${unattend_template}" > "${unattend_dir}/Autounattend.xml"
      unset unattend_hostname
      unset unattend_password
      # create ISO - remove if already existing
      rm -f "${unattend_iso}"
      mkisofs -o "${unattend_iso}" -input-charset utf-8 -J -r "${unattend_dir}"
      rm -rf "${unattend_dir}"
      # add ISO to VM
      additional_args+=("--disk" "path=${unattend_iso},device=cdrom")
    fi
  else
    virt_graphics_arg=("--nographics")
  fi

  # add the access to guest-daemon
  #additional_args+=("--channel" "unix,mode=bind,path=/var/lib/libvirt/qemu/${vm_name}.agent,target_type=virtio,name=org.qemu.guest_agent.0")
  additional_args+=("--channel" "unix,mode=bind,path=${SCRIPT_BASE}/images/${vm_name}.agent,target_type=virtio,name=org.qemu.guest_agent.0")
  # only working with --location
  # --console pty,target_type=serial \
  # --extra-args 'console=ttyS0,115200n8 serial' \
  # --graphics vnc \

  # get list of os: virt-install --osinfo list
  virt-install \
    -n "${vm_name}" \
    --description "${vm_desc}" \
    --osinfo="${vm_os}" \
    --ram="${vm_hardware_memory}" \
    --vcpus="${vm_hardware_cpu}" \
    --network=default,model=virtio \
    --disk "path=${vm_disk_image},format=qcow2,device=disk,bus=${vm_disk_driver}" \
    ${vm_cdrom} \
    ${virt_cloud_init_arg} \
    ${virt_console_arg} \
    "${virt_graphics_arg[@]}" \
    "${additional_args[@]}"

  #  --disk path="${vm_disk_image/server/server-cloudinit}",bus=${vm_disk_driver} \
  #  --disk path="${vm_disk_image/server.qcow2/server-cloudinit.iso}",device=cdrom \

  # --location /data/vms/iso/Fedora-Workstation-Live-x86_64-37-1.7.iso,initrd=images/pxeboot/initrd.img,kernel=images/pxeboot/vmlinuz \

  # virsh destroy fedora37; virsh undefine fedora37
}

export _virtadm_create
