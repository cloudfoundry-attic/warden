#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob
shopt -s globstar

if [ ! -f /etc/issue ]
then
  echo "/etc/issue doesn't exist; cannot determine distribution"
  exit 1
fi

if grep -q -i ubuntu /etc/issue
then
  exec $(dirname $0)/ubuntu.sh $@
fi

if grep -q -i centos /etc/issue
then
  exec $(dirname $0)/centos.sh $@
fi

echo "Unknown distribution: $(head -1 /etc/issue)"
exit 1
