#!/bin/bash

[ -n "$DEBUG" ] && set -o xtrace
set -o nounset
set -o errexit
shopt -s nullglob

cd $(dirname "${0}")

source ./etc/config

filter_forward_chain="warden-forward"
filter_default_chain="warden-default"
filter_instance_prefix="warden-i-"
filter_instance_chain="${filter_instance_prefix}${id}"
filter_instance_log_chain="${filter_instance_prefix}${id}-log"
nat_prerouting_chain="warden-prerouting"
nat_instance_prefix="warden-i-"
nat_instance_chain="${filter_instance_prefix}${id}"

external_ip=$(ip route get 8.8.8.8 | sed 's/.*src\s\(.*\)\s/\1/;tx;d;:x')

function teardown_filter() {
  echo "Teardown filter"
  # Prune forward chain
  iptables -w -S ${filter_forward_chain} 2> /dev/null |
    grep "\-g ${filter_instance_chain}\b" |
    sed -e "s/-A/-D/" |
    xargs --no-run-if-empty --max-lines=1 iptables -w

  # Flush and delete instance chain
  iptables -w -F ${filter_instance_chain} 2> /dev/null || true
  iptables -w -X ${filter_instance_chain} 2> /dev/null || true
  iptables -w -F ${filter_instance_log_chain} 2> /dev/null || true
  iptables -w -X ${filter_instance_log_chain} 2> /dev/null || true
}

function setup_filter() {
  teardown_filter

  # Create instance chain
  iptables -w -N ${filter_instance_chain}
  iptables -w -A ${filter_instance_chain} \
    --goto ${filter_default_chain}

  # Bind instance chain to forward chain
  iptables -w -I ${filter_forward_chain} 2 \
    --in-interface ${network_host_iface} \
    --goto ${filter_instance_chain}

  # Create instance log chain
  iptables -w -N ${filter_instance_log_chain}
  iptables -w -A ${filter_instance_log_chain} \
    -p tcp -m conntrack --ctstate NEW,UNTRACKED,INVALID -j LOG --log-prefix "${filter_instance_chain} "
  iptables -w -A ${filter_instance_log_chain} \
    --jump RETURN
}

function teardown_nat() {
  echo "Teardown nat"
  # Prune prerouting chain
  iptables -w -t nat -S ${nat_prerouting_chain} 2> /dev/null |
    grep "\-j ${nat_instance_chain}\b" |
    sed -e "s/-A/-D/" |
    xargs --no-run-if-empty --max-lines=1 iptables -w -t nat

  # Flush and delete instance chain
  iptables -w -t nat -F ${nat_instance_chain} 2> /dev/null || true
  iptables -w -t nat -X ${nat_instance_chain} 2> /dev/null || true
}

function setup_nat() {
  teardown_nat

  # Create instance chain
  iptables -w -t nat -N ${nat_instance_chain}

  # Bind instance chain to prerouting chain
  iptables -w -t nat -A ${nat_prerouting_chain} \
    --jump ${nat_instance_chain}
}

# Lock execution
mkdir -p ../tmp
exec 3> ../tmp/$(basename $0).lock
flock -x -w 10 3

case "${1}" in
  "setup")
    setup_filter
    setup_nat

    ;;

  "teardown")
    teardown_filter
    teardown_nat

    ;;

  "in")
    if [ -z "${HOST_PORT:-}" ]; then
      echo "Please specify HOST_PORT..." 1>&2
      exit 1
    fi

    if [ -z "${CONTAINER_PORT:-}" ]; then
      echo "Please specify CONTAINER_PORT..." 1>&2
      exit 1
    fi

    iptables -w -t nat -A ${nat_instance_chain} \
      --protocol tcp \
      --destination "${external_ip}" \
      --destination-port "${HOST_PORT}" \
      --jump DNAT \
      --to-destination "${network_container_ip}:${CONTAINER_PORT}"

    ;;

  "out")
    if [ "${PROTOCOL:-}" != "icmp" ] && [ -z "${NETWORK:-}" ] && [ -z "${PORTS:-}" ]; then
      echo "Please specify NETWORK and/or PORTS..." 1>&2
      exit 1
    fi

    opts="--protocol ${PROTOCOL:-tcp}"

    if [ -n "${NETWORK:-}" ]; then
      case ${NETWORK} in
        *-*)
          opts="${opts} -m iprange --dst-range ${NETWORK}"
          ;;
        *)
          opts="${opts} --destination ${NETWORK}"
          ;;
      esac
    fi

    if [ -n "${PORTS:-}" ]; then
      opts="${opts} --destination-port ${PORTS}"
    fi

    if [ "${PROTOCOL}" == "icmp" ]; then
      if [ -n "${ICMP_TYPE}" ]; then
        opts="${opts} --icmp-type ${ICMP_TYPE}"
        if [ -n "${ICMP_CODE}" ]; then
          opts="${opts}/${ICMP_CODE}"
        fi
      fi
    fi

    if [ "${LOG}"  == "true" ]; then
      target="--goto ${filter_instance_log_chain}"
    else
      target="--jump RETURN"
    fi

    iptables -w -I ${filter_instance_chain} 1 ${opts} ${target}

    ;;
  "get_ingress_info")
    if [ -z "${ID:-}" ]; then
      echo "Please specify container ID..." 1>&2
      exit 1
    fi
    tc filter show dev w-${ID}-0 parent ffff:

    ;;
  "get_egress_info")
    if [ -z "${ID:-}" ]; then
      echo "Please specify container ID..." 1>&2
      exit 1
    fi
    tc qdisc show dev w-${ID}-0

    ;;
  *)
    echo "Unknown command: ${1}" 1>&2
    exit 1

    ;;
esac
