#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

if [ $# -ne 1  ]
then
  echo "Usage: $0 <instance_path>"
  exit 1
fi

target=$1

# Ignore tmp directory
if [ $(basename $target) == "tmp" ]
then
  exit 0
fi

if [ -d $target ]
then
  if [ -f $target/destroy.sh ]
  then
    $target/destroy.sh
  fi

  # Retry 5 times to avoid ocational device busy
  count=0
  until `rm -rf $target` || [ $count -eq 4 ]; do
     ((count++))
     sleep 0.1
  done
  if [ $count -eq 4 ]
  then
    exit 1
  fi

fi
