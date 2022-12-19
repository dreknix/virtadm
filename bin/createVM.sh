#!/usr/bin/env bash

SCRIPT_DIR="$(dirname "$(readlink -es "${BASH_SOURCE[0]}")")"
SCRIPT_BASE="$(cd "${SCRIPT_DIR}/.." && pwd)"

function __die() {
  echo -e "\e[01;31mError: $1\e[0m" >&2
  exit 1
}

function __parse_yaml {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*'
   local fs="$(echo @|tr @ '\034')"
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

function __check_kvm() {
  # Check if virtualization is enabled
  if ! grep -sq -E '(vmx|svm)' /proc/cpuinfo
  then
    __die "Virtualization is disabled"
  fi

  if ! command -v kvm-ok &> /dev/null
  then
    __die "Package 'cpu-checker' is not installed: 'kvm-ok' is missing"
  fi

  if ! kvm-ok > /dev/null
  then
    kvm-ok
    __die "Virtualization is not available"
  fi

  # Check if packages are installed
  # qemu qemu-kvm libvirt-daemon libvirt-clients bridge-utils virt-manager
  for p in qemu \
           qemu-system-x86 \
           libvirt-daemon \
           libvirt-clients \
           bridge-utils \
           virt-manager
  do
    if ! dpkg -s "${p}" > /dev/null 2>&1
    then
      __die "Package ${p} is not installed"
    fi
  done

  # Check if kernel modules are loaded
  if ! lsmod | grep -sq kvm > /dev/null
  then
    __die "Kernel modules are not loaded"
  fi

  # check if libvirtd.service is active
  if ! systemctl is-active --quiet libvirtd.service
  then
    __die "Service 'libvirtd.service' is not running"
  fi
}

__check_kvm

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

if [ -z "${vm_disk_image}" ]
then
  __die "Value vm.disk.image is not set in '${yaml_file}'"
fi

if [ -z "${vm_disk_size}" ]
then
  __die "Value vm.disk.size is not set in '${yaml_file}'"
fi

if [ -z "${vm_disk_driver}" ]
then
  __die "Value vm.disk.driver is not set in '${yaml_file}'"
fi

echo "vm_name: $vm_name"
echo "vm_desc: $vm_desc"

vm_disk_image="${SCRIPT_BASE}/images/${vm_disk_image}"
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
  qemu-img create \
    -b "${CI_IMAGE}" -F qcow2 -f qcow2 \
    "${vm_disk_image}" "${vm_disk_size}"G
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
#  --noautoconsole

#  --disk path="${vm_disk_image/server/server-cloudinit}",bus=${vm_disk_driver} \
#  --disk path="${vm_disk_image/server.qcow2/server-cloudinit.iso}",device=cdrom \

# VNC clients: vinagre, remmina

# --location /data/vms/iso/Fedora-Workstation-Live-x86_64-37-1.7.iso,initrd=images/pxeboot/initrd.img,kernel=images/pxeboot/vmlinuz \

# virsh destroy fedora37; virsh undefine fedora37
