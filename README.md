# virtadm

Bash scripts for QEMU/KVM-based virtual machines.

## General

Existing VNC clients: vinagre, remmina

## Windows Guests

For testing Windows guest installations and the usage of `Autounattend.xml` use
[generic product keys[(
 https://learn.microsoft.com/en-us/windows-server/get-started/kms-client-activation-keys)
from Microsoft.

### Windows 11

[Download](https://www.microsoft.com/software-download/windows11) an ISO image
from Microsoft.

When no network is found (second boot) press <Shift> + <F10> to open a command
prompt. Then enter `OOBE\BYPASSNRO` and press <Enter>. The VM restarts
automatically and the out-of-box experience (OOBE) will start again. Now you can
select 'I don't have Internet' and 'Continue with limited setup'.

### Autounattend.xml

* [Sample: Configure UEFI/GPT-Based Hard Drive Partitions by Using Windows Setup](
   https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-8.1-and-8/hh825702(v=win.10))

## Linux Guests

### Cloud-Init

* [cloud-init documentation](https://cloudinit.readthedocs.io/en/latest/index.html)
  * [cloud-init: QEMU tutorial](
     https://cloudinit.readthedocs.io/en/latest/topics/tutorials/qemu.html)
  * [cloud-init: NoCloud data source](
     https://cloudinit.readthedocs.io/en/latest/topics/datasources/nocloud.html)
  * [cloud-init: cloud config examples](
     https://cloudinit.readthedocs.io/en/latest/topics/examples.html)

Get an image that has cloud-init enabled:

```console
$ curl -LO https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64-disk-kvm.img
```

Convert the image with new size:

```console
$ qemu-img create -b jammy-server-cloudimg-amd64-disk-kvm.img -F qcow2 -f qcow2 ubuntu.qcow2 50G
```

Create a disk for cloud-init to utilize the nocloud data source. Use the tool
`cloud-localds` from [cloud-utils](https://github.com/canonical/cloud-utils).

```console
$ cloud-localds -v --network-config=network.yaml ubuntu-ci.qcow2 userdata.yaml
```

Create the new virtual machine:

```console
$ virt-install 
 --name=ubuntu \
 --ram=4086 \
 --vcpus=2 \
 --disk path=./ubuntu.qcow2,bus=virtio,cache=none \
 --disk path=./ubuntu-ci.qcow2,device=cdrom \
 --graphics=vnc
```

Eject the cloud-init data source:

```console
virsh change-media ubuntu --path ubuntu-ci.qcow2 --eject --force
```

Disable cloud-init (inside the guest):

```console
$ sudo touch /etc/cloud/cloud-init.disabled
```

## License

[MIT](https://github.com/dreknix/virtadm/blob/main/LICENSE)
