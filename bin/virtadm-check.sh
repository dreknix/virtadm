#!/usr/bin/env bash

function __ok() {
  tput setaf 10
  echo "ok"
  tput sgr0
}

function __failed() {
  tput setaf 9
  echo "failed"
  tput sgr0
}

function __test() {
  printf "%- 45s " "${1}:"
  shift
  arr=("$@")
  if "${arr[@]}" &> /dev/null
  then
    __ok
  else
    __failed
  fi
}

function _virtadm_check() {

  # Check if virtualization is enabled
  __test "Check if virtualization is enabled" grep -sq -E '(vmx|svm)' /proc/cpuinfo

  # Check if 'kvm-ok' is installed
  __test "Check if 'kvm-ok' is installed" command -v kvm-ok

  # Check if virtualization is available
  __test "Check if virtualization is available" kvm-ok

  # Check if packages are installed
  # qemu qemu-kvm libvirt-daemon libvirt-clients bridge-utils virt-manager
  __test "Check if 'qemu' is installed" dpkg -s qemu
  __test "Check if 'libvirt-daemon' is installed" dpkg -s libvirt-daemon
  __test "Check if 'libvirt-clients' is installed" dpkg -s libvirt-clients
  __test "Check if 'virt-manager' is installed" dpkg -s virt-manager
  __test "Check if 'cloud-image-utils' is installed" dpkg -s cloud-image-utils
  __test "Check if 'j2cli' is installed" dpkg -s j2cli

  # Check if programs are available
  __test "Command 'virsh' is in path" command -v virsh
  __test "Command 'qemu-img' is in path" command -v qemu-img
  __test "Command 'kvm' is in path" command -v kvm
  __test "Command 'virt-install' is in path" command -v virt-install
  __test "Command 'cloud-localds' is in path" command -v cloud-localds
  __test "Command 'curl' is in path" command -v curl
  __test "Command 'j2' is in path" command -v j2

  # Check if kernel modules are loaded
  __test "Check if kernel modules are loaded" grep -sq kvm /proc/modules

  # Check if 'libvirtd.service' is active
  __test "Check if 'libvirtd.service' is active" systemctl is-active --quiet libvirtd.service

  __test "Check is current user in group 'libvirt'" test -w /var/run/libvirt/libvirt-sock
  __test "Check is current user in group 'kvm'" test -w /dev/kvm
}

export _virtadm_check
