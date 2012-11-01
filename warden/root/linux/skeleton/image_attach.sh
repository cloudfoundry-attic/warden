#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

mknod ${2} b 7 ${3}
losetup ${2} ${1}
