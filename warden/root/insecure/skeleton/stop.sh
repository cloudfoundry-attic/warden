#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

WAIT=10

function usage() {
  echo "Usage $0 [OPTION]..." >&2
  echo "  -w N seconds to wait before sending SIGKILL;" >&2
  echo "       N=0 skips SIGTERM and sends SIGKILL immediately" >&2
  exit 1
}

while getopts ":w:h" opt
do
  case $opt in
    "w")
      WAIT=$OPTARG
      ;;
    "h")
      usage
      ;;
    "?")
      # Ignore invalid options
      ;;
  esac
done

cd $(dirname "$0")

function pids() {
  echo pids/* | xargs -r -n1 basename | xargs -r echo
}

# Wait for processes to exit
for i in $(seq $WAIT); do
  p=$(pids)

  # Break when there are no pids
  if [ -z "$p" ]
  then
    break
  fi

  # Send SIGTERM
  kill -TERM -$p || true

  # When none of the pids is a process `ps` exits with non-zero status
  if ! ps -o pid= -p $p > /dev/null
  then
    break
  fi

  sleep 1
done

p=$(pids)

# Send SIGKILL
if [ -n "$p" ]
then
  kill -KILL -$p || true
fi
