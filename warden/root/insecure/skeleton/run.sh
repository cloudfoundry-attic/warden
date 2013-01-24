#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

cd $(dirname "$0")

touch pids/$$

# Run script with PWD=root
cd root

# Replace process with bash interpreting stdin
exec setsid env -i bash
