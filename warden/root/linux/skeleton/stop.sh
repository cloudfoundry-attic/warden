#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

cd $(dirname $0)

if [ ! -f ./run/wshd.pid ]
then
  echo "wshd is not running..."
  exit 1
fi

# TODO: make graceful
kill -9 $(cat ./run/wshd.pid)
