#!/usr/bin/env bash

function _virtadm_create() {

  local virt_console_arg=("--noautoconsole")

  local LONG_OPTIONS=(
    "console"
  )

  # read function arguments
  opts=$(getopt \
             --longoptions "$(printf "%s," "${LONG_OPTIONS[@]}")" \
             --name "${progname:-}" \
             --options "" \
             -- "$@"
        ) || __die "getopt failed"
  eval set -- "$opts"

  while [[ $# -gt 0 ]]
  do
    case "$1" in
      --console)
        virt_console_arg=()
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

  if [ -z "${vm_name:-}" ]
  then
    __die "Value vm.name is not set in '${yaml_file}'"
  fi

  if virsh dominfo "${vm_name}" &> /dev/null
  then
    __die "VM '${vm_name}' is already existing"
  fi

  if [ -z "${vm_hostname:-}" ]
  then
    __die "Value vm.hostname is not set in '${yaml_file}'"
  fi

  if [ -z "${vm_desc:-}" ]
  then
    __die "Value vm.desc is not set in '${yaml_file}'"
  fi

  if [ -z "${vm_os:-}" ]
  then
    __die "Value vm.os is not set in '${yaml_file}'"
  fi

  if [ -z "${vm_hardware_cpu:-}" ]
  then
    __die "Value vm.hardware.cpu is not set in '${yaml_file}'"
  fi

  if [ -z "${vm_hardware_memory:-}" ]
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
    else
      curl -z "${CI_IMAGE}" -LO --output-dir "${SCRIPT_BASE}/iso" "${cloudinit_image}"
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

  local virt_misc_args=()

  local virt_cloud_init_arg=()
  if [ -n "${cloudinit_image:-}" ]
  then
    virt_misc_args+=("--import")

    export cloud_init_hostname="${vm_hostname%%.*}"
    export cloud_init_fqdn="${vm_hostname}"
    cloud_init_password="$(mkpasswd --method=SHA-512 "$(get-gopass.sh virtadm/defaultpw)")"
    export cloud_init_password
    export cloud_init_ip4_address="${cloudinit_ip4_address:-}"
    export cloud_init_ip4_gateway="${cloudinit_ip4_gateway:-}"
    export cloud_init_nameservers="${cloudinit_nameservers:-}"

    mkdir -p "${SCRIPT_BASE}/cloud-init/${vm_name}/"
    user_data="${SCRIPT_BASE}/cloud-init/${vm_name}/user-data.yaml"
    network="${SCRIPT_BASE}/cloud-init/${vm_name}/network.yaml"
    j2 "${SCRIPT_BASE}/cloud-init/${cloudinit_templates_config}" > "${user_data}"
    j2 "${SCRIPT_BASE}/cloud-init/${cloudinit_templates_network}" > "${network}"
    # create cloud-init.iso
    local cloud_init_iso="${SCRIPT_BASE}/cloud-init/${vm_name}/cloud-init.iso"
    cloud-localds \
      --disk-format raw \
      --filesystem iso9660 \
      --network-config "${network}" \
      "${cloud_init_iso}" \
      "${user_data}"

    virt_cloud_init_arg+=("--disk" "path=${cloud_init_iso},bus=virtio")
  fi

  if [ ! -f "${vm_disk_image}" ]
  then
    __die "Image '${vm_disk_image}' is not readable"
  fi

  virt_cdrom_arg=()
  if [ -n "${vm_cdrom:-}" ]
  then
    vm_cdrom="${SCRIPT_BASE}/iso/${vm_cdrom}"
    if [ ! -f "${vm_cdrom}" ]
    then
      __die "Image '${vm_cdrom}' is not readable"
    fi
    virt_cdrom_arg+=("--cdrom" "${vm_cdrom}")
  else
    virt_misc_args+=("--boot" "hd")
  fi

  if [[ "$vm_os" = win* ]]
  then
    virt_misc_args+=("--boot" "uefi")
    # TODO: read https://bugzilla.redhat.com/show_bug.cgi?id=1387479
    #virt_misc_args+=("--features" "kvm_hidden=on,smm=on")
    #virt_misc_args+=("--boot" "loader=/usr/share/OVMF/OVMF_CODE.secboot.fd,\
    #                            loader_ro=yes,\
    #                            loader_type=pflash,\
    #                            nvram_template=/usr/share/OVMF/OVMF_VARS.ms.fd")
    virt_misc_args+=("--tpm" "backend.type=emulator,backend.version=2.0,model=tpm-tis")

    virt_graphics_arg=("--graphics" "spice" "--video" "virtio")

    # add driver disk
    local virtio_url="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
    local virtio_driver_iso="${SCRIPT_BASE}/iso/virtio-win.iso"
    if [ ! -f "${virtio_driver_iso}" ]
    then
      curl -LO --output-dir "${SCRIPT_BASE}/iso" "${virtio_url}"
    else
      curl -z "${virtio_driver_iso}" -LO --output-dir "${SCRIPT_BASE}/iso" "${virtio_url}"
    fi
    virt_misc_args+=("--disk" "path=${SCRIPT_BASE}/iso/virtio-win.iso,device=cdrom")

    # check if Autounattend.xml should be provided
    if [ -n "${unattend_template:-}" ]
    then
      unattend_template="${SCRIPT_BASE}/unattend/${unattend_template}"
      if [ ! -r "${unattend_template}" ]
      then
        __die "Unattend template '${unattend_template}' is missing"
      fi
      local unattend_dir="${SCRIPT_BASE}/unattend/temp_${vm_name}/"
      mkdir "${unattend_dir}"
      local unattend_iso="${SCRIPT_BASE}/unattend/vm_${vm_name}_unattend.iso"
      # create Autounattend.xml from given template
      export unattend_hostname="${vm_hostname%%.*}"
      unattend_password="$(get-gopass.sh virtadm/defaultpw)"
      export unattend_password
      if [ -n "${unattend_product_key:-}" ]
      then
        export unattend_product_key
      fi
      if [ -z "${unattend_windows_version:-}" ]
      then
        unattend_windows_version="Windows 11 Pro"
      fi
      export unattend_windows_version
      if [ -z "${unattend_input:-}" ]
      then
        unattend_input="0409:00000409"
      fi
      export unattend_input
      if [ -z "${unattend_language:-}" ]
      then
        unattend_language="en-US"
      fi
      export unattend_language
      if [ -z "${unattend_locale:-}" ]
      then
        unattend_locale="en-US"
      fi
      export unattend_locale
      if [ -z "${unattend_timezone:-}" ]
      then
        unattend_timezone="Pacific Standard Time_dstoff"
      fi
      export unattend_timezone
      if [ "${unattend_enable_disk_configuration:-}" = "true" ]
      then
        export unattend_enable_disk_configuration="true"
      fi
      if [ "${unattend_debug:-}"  = "true" ]
      then
        export unattend_noexit="-NoExit"
      else
        export unattend_noexit=""
      fi
      # setup_tools_smb_path
      if [ -n "${SETUP_SMB_PATH:-}" ]
      then
        setup_tools_smb_path="${SETUP_SMB_PATH}"
      else
        setup_tools_smb_path='\\localhost\setup'
      fi
      export setup_tools_smb_path
      # setup_tools_smb_user
      if [ -n "${SETUP_SMB_USER:-}" ]
      then
        setup_tools_smb_user="${SETUP_SMB_USER}"
      else
        setup_tools_smb_user='dreknix'
      fi
      export setup_tools_smb_user
      # setup_tools_smb_password
      setup_tools_smb_password="$(get-gopass.sh "virtadm/smb/${SETUP_SMB_USER}")"
      export setup_tools_smb_password
      # setup_tools_smb_script
      if [ -n "${SETUP_SMB_SCRIPT:-}" ]
      then
        setup_tools_smb_script="${SETUP_SMB_SCRIPT}"
      else
        setup_tools_smb_script='Z:\setup\windows\setup.ps1'
      fi
      export setup_tools_smb_script
      j2 "${unattend_template}" > "${unattend_dir}/Autounattend.xml"
      unset unattend_hostname
      unset unattend_password
      unset setup_tools_smb_path
      unset setup_tools_smb_user
      unset setup_tools_smb_password
      unset setup_tools_smb_script
      # create ISO - remove if already existing
      rm -f "${unattend_iso}"
      mkisofs -o "${unattend_iso}" -input-charset utf-8 -J -r "${unattend_dir}" &> /dev/null
      rm -rf "${unattend_dir}"
      # add ISO to VM
      virt_misc_args+=("--disk" "path=${unattend_iso},device=cdrom")
    fi
  else
    virt_graphics_arg=("--nographics")
  fi

  # add the access to guest-daemon
  #virt_misc_args+=("--channel" "unix,mode=bind,path=/var/lib/libvirt/qemu/${vm_name}.agent,target_type=virtio,name=org.qemu.guest_agent.0")
  virt_misc_args+=("--channel" "unix,mode=bind,path=${SCRIPT_BASE}/images/${vm_name}.agent,target_type=virtio,name=org.qemu.guest_agent.0")
  # only working with --location
  # --console pty,target_type=serial \
  # --extra-args 'console=ttyS0,115200n8 serial' \
  # --graphics vnc \

  # get list of os: virt-install --osinfo list
  virt-install \
    -n "${vm_name}" \
    --description "${vm_desc}" \
    --os-variant="${vm_os}" \
    --boot uefi \
    --arch x86_64 \
    --virt-type kvm \
    --features kvm_hidden=on,smm=on \
    --memory="${vm_hardware_memory}" \
    --cpu Skylake-Client,-hle,-rtm \
    --vcpus="${vm_hardware_cpu}" \
    --network=default,model=virtio \
    --disk "path=${vm_disk_image},format=qcow2,device=disk,bus=${vm_disk_driver}" \
    "${virt_cdrom_arg[@]}" \
    "${virt_cloud_init_arg[@]}" \
    "${virt_console_arg[@]}" \
    "${virt_graphics_arg[@]}" \
    "${virt_misc_args[@]}"

  #  --disk path="${vm_disk_image/server/server-cloudinit}",bus=${vm_disk_driver} \
  #  --disk path="${vm_disk_image/server.qcow2/server-cloudinit.iso}",device=cdrom \

  # --location /data/vms/iso/Fedora-Workstation-Live-x86_64-37-1.7.iso,initrd=images/pxeboot/initrd.img,kernel=images/pxeboot/vmlinuz \

  # virsh destroy fedora37; virsh undefine fedora37
}

export _virtadm_create
