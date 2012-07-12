#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

cd $(dirname "${0}")

if [ ! -f started ]; then
  echo "Container is not running..."
  exit 1
fi

ssh -F ssh/ssh_config root@container /sbin/warden-stop.sh "$@"
