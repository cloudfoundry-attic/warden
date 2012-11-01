#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

umount ${1} > /dev/null 2>&1 || true
losetup -d ${1}
rm -f ${1}
