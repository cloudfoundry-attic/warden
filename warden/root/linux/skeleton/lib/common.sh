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

function setup_fs() {
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

function teardown_fs() {
  umount mnt
}
