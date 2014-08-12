#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

cd $(dirname $0)/../

source ./lib/common.sh

mkdir -p /dev/pts
mount -t devpts -o newinstance,ptmxmode=0666 devpts /dev/pts
ln -sf pts/ptmx /dev/ptmx

mkdir -p /proc
mount -t proc none /proc

mkdir -p /dev/shm
mount -t tmpfs tmpfs /dev/shm

hostname $id

ifconfig lo 127.0.0.1
ifconfig $network_container_iface $network_container_ip netmask $network_netmask mtu $container_iface_mtu
route add default gw $network_host_ip $network_container_iface
