#!/bin/bash

function permit_device_control() {
  local devices_mount_info=$(cat /proc/self/cgroup | grep devices)

  if [ -z "$devices_mount_info" ]; then
    # cgroups not set up; must not be in a container
    return
  fi

  local devices_subsytems=$(echo $devices_mount_info | cut -d: -f2)
  local devices_subdir=$(echo $devices_mount_info | cut -d: -f3)

  if [ "$devices_subdir" = "/" ]; then
    # we're in the root devices cgroup; must not be in a container
    return
  fi

  cgroup_dir=${RUN_DIR}/devices-cgroup

  if [ ! -e ${cgroup_dir} ]; then
    # mount our container's devices subsystem somewhere
    mkdir ${cgroup_dir}
  fi

  if ! mountpoint -q ${cgroup_dir}; then
    mount -t cgroup -o $devices_subsytems none ${cgroup_dir}
  fi

  # permit our cgroup to do everything with all devices
  echo a > ${cgroup_dir}${devices_subdir}/devices.allow || true
}

function create_loop_devices() {
  amt=$1
  for i in $(seq 0 $amt); do
    mknod -m 0660 /dev/loop$i b 7 $i || true
  done
}

function setup_warden_infrastructure() {
  permit_device_control
  create_loop_devices 100

  mkdir -p /tmp/warden
  mount -o size=4G,rw -t tmpfs tmpfs /tmp/warden

  loopdev=$(losetup -f)
  dd if=/dev/zero of=/tmp/warden/rootfs.img bs=1024 count=1048576
  losetup ${loopdev} /tmp/warden/rootfs.img
  mkfs -t ext4 -m 1 -v ${loopdev}
  mkdir /tmp/warden/rootfs
  mount -t ext4 ${loopdev} /tmp/warden/rootfs

  loopdev=$(losetup -f)
  dd if=/dev/zero of=/tmp/warden/containers.img bs=1024 count=1048576
  losetup ${loopdev} /tmp/warden/containers.img
  mkfs -t ext4 -m 1 -v ${loopdev}
  mkdir /tmp/warden/containers
  mount -t ext4 ${loopdev} /tmp/warden/containers
}
