#!/bin/bash

set -o nounset
set -o errexit
shopt -s nullglob
cd $(dirname "${0}")

source ./common.sh
source ./config

if [ ! -f started ]; then
  echo "Container is not running..."
  exit 1
fi

./killprocs.sh
rm -f started