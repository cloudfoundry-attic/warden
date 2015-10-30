#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

cd $(dirname "${0}")

source ./etc/config

# rate is the bandwidth
if [ -z "${RATE:-}" ]; then
  echo "Please specify RATE..." 1>&2
  exit 1
fi

# burst is the burst size
if [ -z "${BURST:-}" ]; then
  echo "Please specify BURST..." 1>&2
  exit  1
fi

# clear rules if they exist
# delete host root egress tc qdisc
tc qdisc del dev ${network_host_iface} root 2> /dev/null || true

# delete host root ingress tc qdisc
tc qdisc del dev ${network_host_iface} ingress 2> /dev/null || true

# delete ifb root egress tc qdisc
tc qdisc del dev ${network_ifb_iface} root 2> /dev/null || true

# latency is the maximum time the packet waits to enqueue while no token left
# shape inbound to container (outside -> eth0 -> w-<cid>-0 -> w-<cid>-1) with tbf(token bucket filter) qdisc
tc qdisc add dev ${network_host_iface} root tbf rate ${RATE}bit burst ${BURST} latency 25ms

# limit outbound from container (w-<cid>-1 -> w-<cid>-0 -> w-<cid>-2 -> eth0 -> outside)
tc qdisc add dev ${network_ifb_iface} root tbf rate ${RATE}bit burst ${BURST} latency 25ms

# mirror outbound from container (host adapter ingress) to ifb
tc qdisc add dev ${network_host_iface} ingress handle ffff:
tc filter add dev ${network_host_iface} parent ffff: protocol all u32 match ip src 0.0.0.0/0 action mirred egress redirect dev ${network_ifb_iface}
