#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

cd $(dirname $0)/../

source ./lib/common.sh

# Add new group for every subsystem
for system_path in /tmp/warden/cgroup/*
do
  instance_path=$system_path/instance-$id

  mkdir -p $instance_path

  if [ $(basename $system_path) == "cpuset" ]
  then
    cat $system_path/cpuset.cpus > $instance_path/cpuset.cpus
    cat $system_path/cpuset.mems > $instance_path/cpuset.mems
  fi

  if [ $(basename $system_path) == "devices" ]
  then
    if [ $allow_nested_warden == "true" ]
    then
      # Allow everything
      echo "a *:* rw" > $instance_path/devices.allow
    else
      # Deny everything, allow explicitly
      echo a > $instance_path/devices.deny
      # /dev/null
      echo "c 1:3 rw" > $instance_path/devices.allow
      # /dev/zero
      echo "c 1:5 rw" > $instance_path/devices.allow
      # /dev/random
      echo "c 1:8 rw" > $instance_path/devices.allow
      # /dev/urandom
      echo "c 1:9 rw" > $instance_path/devices.allow
      # /dev/tty
      echo "c 5:0 rw" > $instance_path/devices.allow
      # /dev/ptmx
      echo "c 5:2 rw" > $instance_path/devices.allow
      # /dev/pts/*
      echo "c 136:* rw" > $instance_path/devices.allow
      # /dev/fuse
      echo "c 10:229 rw" > $instance_path/devices.allow
    fi
  fi

  echo $PID > $instance_path/tasks
done

echo $PID > ./run/wshd.pid

ip link add name $network_host_iface type veth peer name $network_container_iface
ip link set $network_host_iface netns 1
ip link set $network_container_iface netns $PID

ifconfig $network_host_iface $network_host_ip netmask $network_netmask mtu $container_iface_mtu

exit 0
