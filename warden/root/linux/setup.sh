#!/bin/bash

set -o nounset
set -o errexit
shopt -s nullglob
cd $(dirname "${0}")

# Check if our old mount point exists, and if so clean it up
if [ -d /dev/cgroup ]
then
  if grep -q /dev/cgroup /proc/mounts
  then
    umount /dev/cgroup
  fi

  rmdir /dev/cgroup
fi

cgroup_path=/sys/fs/cgroup

if [ ! -d $cgroup_path ]
then
  echo "$cgroup_path does not exist..."
  exit 1
fi

# Mount if not already mounted
if ! grep -q ${cgroup_path} /proc/mounts; then
  mount -t cgroup -o blkio,devices,memory,cpuacct,cpu,cpuset none ${cgroup_path}
fi

./net.sh setup

# Make loop devices as needed
for i in $(seq 0 1023); do
  file=/dev/loop${i}
  if [ ! -b ${file} ]; then
    mknod -m0660 ${file} b 7 ${i}
    chown root.disk ${file}
  fi
done

# Disable AppArmor if possible
if [ -x /etc/init.d/apparmor ]; then
  /etc/init.d/apparmor teardown
fi
