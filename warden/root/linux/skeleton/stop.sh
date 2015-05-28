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

source etc/config

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

pid=$(cat ./run/wshd.pid)
path=/tmp/warden/cgroup/cpu/instance-$id
tasks=$path/tasks

# pkill with -v (--inverse) does not work on
# both ubuntu trusty
while true
do
  if ! pgrep -c -P $pid; then
    # all child processes exited
    break
  fi

  subTasks=$(cat $tasks | grep -v $pid)

  signal=TERM
  if [[ $(ms) -gt $ms_end ]]; then
    # forcibly kill after the grace period
    signal=KILL
  fi

  kill -$signal $subTasks 2> /dev/null || true

  sleep 1
done
