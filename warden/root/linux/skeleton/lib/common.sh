#!/bin/bash

[ -f etc/config ] && source etc/config

function get_distrib_codename() {
  if [ -r /etc/lsb-release ]
  then
    source /etc/lsb-release

    if [ -n "$DISTRIB_CODENAME" ]
    then
      echo $DISTRIB_CODENAME
      return 0
    fi
  else
    lsb_release -cs
  fi
}

function overlay_directory_in_rootfs() {
  # Skip if exists
  if [ ! -d tmp/rootfs/$1 ]
  then
    if [ -d mnt/$1 ]
    then
      cp -r mnt/$1 tmp/rootfs/
    else
      mkdir -p tmp/rootfs/$1
    fi
  fi

  mount -n --bind tmp/rootfs/$1 mnt/$1
  mount -n --bind -o remount,$2 tmp/rootfs/$1 mnt/$1
}

function setup_fs_other() {
  mkdir -p tmp/rootfs mnt
  mkdir -p $rootfs_path/proc

  mount -n --bind $rootfs_path mnt
  mount -n --bind -o remount,ro $rootfs_path mnt

  overlay_directory_in_rootfs /dev rw
  overlay_directory_in_rootfs /etc rw
  overlay_directory_in_rootfs /home rw
  overlay_directory_in_rootfs /sbin rw

  mkdir -p tmp/rootfs/tmp
  chmod 777 tmp/rootfs/tmp
  overlay_directory_in_rootfs /tmp rw
}

function setup_fs_ubuntu() {
  mkdir -p tmp/rootfs mnt

  distrib_codename=$(get_distrib_codename)

  case "$distrib_codename" in
  lucid|natty|oneiric)
    mount -n -t aufs -o br:tmp/rootfs=rw:$rootfs_path=ro+wh none mnt
    ;;
  precise)
    mount -n -t overlayfs -o rw,upperdir=tmp/rootfs,lowerdir=$rootfs_path none mnt
    ;;
  *)
    echo "Unsupported: $distrib_codename"
    exit 1
    ;;
  esac
}

function setup_fs() {
  if grep -q -i ubuntu /etc/issue
  then
    setup_fs_ubuntu
  else
    setup_fs_other
  fi
}

function teardown_fs() {
  umount mnt
}
