# virtadm

Bash scripts for QEMU/KVM-based virtual machines.

## General

Existing VNC clients: vinagre, remmina

## Cloud-Init

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
