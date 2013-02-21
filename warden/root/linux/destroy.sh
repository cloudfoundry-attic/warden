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

  rm -rf $target
fi
