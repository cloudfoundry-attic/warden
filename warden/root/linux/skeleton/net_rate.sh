#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

cd $(dirname "${0}")

source ./etc/config

if [ -z "${RATE:-}" ]; then
  echo "Please specify RATE..." 1>&2
  exit 1
fi

if [ -z "${BURST:-}" ]; then
  echo "Please specify BURST..." 1>&2
  exit  1
fi

# clear rule if exist
# delete root egress tc qdisc
tc qdisc del dev ${network_host_iface} root 2> /dev/null || true

# delete root ingress tc qdisc
tc qdisc del dev ${network_host_iface} ingress 2> /dev/null || true

# set outbound(w-<cid>-1 -> w-<cid>-0 -> eth0 -> outside) rule with tbf(token bucket filter)
# rate is the bandwidth
# burst is the burst size
# latency is the maxium time the packet wait to enqueue while no token left
tc qdisc add dev ${network_host_iface} root tbf rate ${RATE}bit burst ${BURST} latency 25ms

# set inbound(outside -> eth0 -> w-<cid>-0 -> w-<cid>-1) rule with ingress qdisc
tc qdisc add dev ${network_host_iface} ingress handle ffff:

# use u32 filter with target(0.0.0.0) mask (0) to filter all the ingress packets
tc filter add dev ${network_host_iface} parent ffff: protocol ip prio 1 u32 match ip src 0.0.0.0/0 police rate ${RATE}bit burst ${BURST} drop flowid :1
