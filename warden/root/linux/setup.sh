#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

cd $(dirname "${0}")

# Check if the old mount point exists, and if so clean it up
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

# Check if /sys/fs/cgroup is mounted with a cgroup mount, and umount if so
if grep "${cgroup_path} " /proc/mounts | cut -d' ' -f3 | grep -q cgroup
then
  umount $cgroup_path
fi

# Mount tmpfs
if ! grep "${cgroup_path} " /proc/mounts | cut -d' ' -f3 | grep -q tmpfs
then
  mount -t tmpfs none $cgroup_path
fi

# Mount cgroup subsystems individually
for subsystem in cpu cpuacct devices memory
do
  mkdir -p $cgroup_path/$subsystem

  if ! grep -q "${cgroup_path}/$subsystem " /proc/mounts
  then
    mount -t cgroup -o $subsystem none $cgroup_path/$subsystem
  fi
done

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

# Figure out mount point of container depot path
container_depot_mount_point=$(stat -c "%m" $CONTAINER_DEPOT_PATH)

# quotaon(8) exits with non-zero status when quotas are ENABLED
if quotaon -p $container_depot_mount_point > /dev/null
then
  mount -o remount,usrjquota=aquota.user,grpjquota=aquota.group,jqfmt=vfsv0 $container_depot_mount_point
  quotacheck -ugmb -F vfsv0 $container_depot_mount_point
  quotaon $container_depot_mount_point
fi
