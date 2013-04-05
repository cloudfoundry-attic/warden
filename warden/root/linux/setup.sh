#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

cd $(dirname "${0}")

cgroup_path=/tmp/warden/cgroup

if [ ! -d $cgroup_path ]
then
  mkdir -p $cgroup_path

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
fi

./net.sh setup

# Disable AppArmor if possible
if [ -x /etc/init.d/apparmor ]; then
  /etc/init.d/apparmor teardown
fi

# quotaon(8) exits with non-zero status when quotas are ENABLED
if [ "$DISK_QUOTA_ENABLED" = "true" ] && quotaon -p $CONTAINER_DEPOT_MOUNT_POINT_PATH > /dev/null
then
  mount -o remount,usrjquota=aquota.user,grpjquota=aquota.group,jqfmt=vfsv0 $CONTAINER_DEPOT_MOUNT_POINT_PATH
  quotacheck -ugmb -F vfsv0 $CONTAINER_DEPOT_MOUNT_POINT_PATH
  quotaon $CONTAINER_DEPOT_MOUNT_POINT_PATH
elif [ "$DISK_QUOTA_ENABLED" = "false" ] && ! quotaon -p $CONTAINER_DEPOT_MOUNT_POINT_PATH > /dev/null
then
  quotaoff $CONTAINER_DEPOT_MOUNT_POINT_PATH
fi
