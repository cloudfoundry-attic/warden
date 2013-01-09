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

function ms() {
  echo $(($(date +%s%N)/1000000))
}

ms_start=$(ms)
ms_end=$(($ms_start + ($WAIT * 1000)))

# Send SIGTERM
if [[ $(ms) -lt $ms_end ]]
then
  bin/wsh pkill -TERM -v -P 0 || true
fi

# Wait for processes to quit
while [[ $(ms) -lt $ms_end ]]
do
  if ! bin/wsh pgrep -c -v -P 0 > /dev/null
  then
    exit 0
  fi

  sleep 1
done

# Send SIGKILL
bin/wsh pkill -KILL -v -P 0 || true
