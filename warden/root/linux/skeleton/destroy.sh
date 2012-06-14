#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

cd $(dirname "${0}")

./net.sh teardown

if [ -f ppid ]
then
  ppid=$(cat ppid)
  rm -f ppid

  while true
  do
    kill -9 $ppid 2> /dev/null || true
    [ ! -d /proc/$ppid ] && exit 0
    sleep 0.1
  done
fi

exit 1
