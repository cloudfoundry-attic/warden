#!/bin/bash

target="union"

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
  mkdir -p rootfs $target

  distrib_codename=$(get_distrib_codename)

  case "$distrib_codename" in
  lucid|natty|oneiric)
    mount -n -t aufs -o br:rootfs=rw:$1=ro+wh none $target
    ;;
  precise)
    mount -n -t overlayfs -o rw,upperdir=rootfs,lowerdir=$1 none $target
    ;;
  *)
    echo "Unsupported: $distrib_codename"
    exit 1
    ;;
  esac
}

function teardown_fs() {
  umount $target
}
