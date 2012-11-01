#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

echo ${1} >> /tmp/abc
echo ${2} >> /tmp/abc
echo ${3} >> /tmp/abc
mknod ${2} b 7 ${3} >> /tmp/abc 2>&1
losetup ${2} ${1} >> /tmp/abc 2>&1
