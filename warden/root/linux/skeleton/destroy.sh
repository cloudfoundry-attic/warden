#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

cd $(dirname $0)

source ./etc/config

./net.sh teardown

if [ -f ./run/wshd.pid ]
then
  pid=$(cat ./run/wshd.pid)
  path=/sys/fs/cgroup/cpu/instance-$id
  tasks=$path/tasks

  if [ -d $path ]
  then
    while true
    do
      kill -9 $pid 2> /dev/null || true

      # Wait while there are tasks in one of the instance's cgroups
      if [ -f $tasks ] && [ -n "$(cat $tasks)" ]
      then
        sleep 0.1
      else
        break
      fi
    done
  fi

  # Done, remove pid
  rm -f ./run/wshd.pid

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
