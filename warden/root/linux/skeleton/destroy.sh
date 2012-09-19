#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

cd $(dirname "${0}")

source ./config

./net.sh teardown

if [ -f ppid ]
then
  ppid=$(cat ppid)
  rm -f ppid

  path=/sys/fs/cgroup/cpu/instance-$id
  tasks=$path/tasks

  while true
  do
    kill -9 $ppid 2> /dev/null || true

    # Wait while there are tasks in one of the instance's cgroups
    if [ -f $tasks ] && [ -n "$(cat $tasks)" ]
    then
      sleep 0.1
    else
      break
    fi
  done

  # Remove cgroups
  for system_path in /sys/fs/cgroup/*
  do
    path=$system_path/instance-$id

    if [ -d $path ]
    then
      rmdir $path
    fi
  done

  exit 0
fi
