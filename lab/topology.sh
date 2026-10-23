#!/usr/bin/env bash
# Only the three named laboratory namespaces are modified.
set -euo pipefail
[[ $(uname -s) == Linux ]] || { echo 'Run this inside Linux.' >&2; exit 1; }
[[ $EUID == 0 ]] || { echo "Run with sudo: $0 up|down|rate RATE|queue MODE|status" >&2; exit 1; }
names=(scream-tx scream-router scream-rx)

exists() { ip netns list | awk '{print $1}' | grep -Fxq "$1"; }
ns() { ip netns exec "$@"; }
down() {
  local name
  for name in "${names[@]}"; do
    if exists "$name"; then
      # Kill only processes attached to the namespace being deleted.
      ip netns pids "$name" | xargs -r kill -TERM
      sleep 1
      ip netns pids "$name" | xargs -r kill -KILL
      ip netns del "$name"
    fi
  done
}
up() {
  local name
  for name in "${names[@]}"; do
    if exists "$name"; then
      echo "$name already exists; use '$0 down' before rebuilding." >&2
      exit 1
    fi
  done
  # A built-in qdisc may not have a loadable module, so test it on the link below.
  modprobe sch_dualpi2 2>/dev/null || true
  trap 'echo "Setup failed; removing partial lab." >&2; down' ERR
  for name in "${names[@]}"; do
    ip netns add "$name"
    ns "$name" ip link set lo up
  done
  ip link add tx0 netns scream-tx type veth peer name rt0 netns scream-router
  ip link add rx0 netns scream-rx type veth peer name rr0 netns scream-router
  ns scream-tx ip addr add 10.200.1.2/24 dev tx0
  ns scream-router ip addr add 10.200.1.1/24 dev rt0
  ns scream-router ip addr add 10.200.2.1/24 dev rr0
  ns scream-rx ip addr add 10.200.2.2/24 dev rx0
  ns scream-tx ip link set tx0 up
  ns scream-router ip link set rt0 up
  ns scream-router ip link set rr0 up
  ns scream-rx ip link set rx0 up
  ns scream-tx ip route add default via 10.200.1.1
  ns scream-rx ip route add default via 10.200.2.1
  ns scream-router sysctl -qw net.ipv4.ip_forward=1
  # Avoid aggregated packets distorting packet timing and ECN observations.
  ns scream-tx ethtool -K tx0 tso off gso off gro off
  ns scream-router ethtool -K rt0 tso off gso off gro off
  ns scream-router ethtool -K rr0 tso off gso off gro off
  ns scream-rx ethtool -K rx0 tso off gso off gro off
  # 10 ms forward propagation before the bottleneck, 10 ms reverse propagation.
  ns scream-tx tc qdisc add dev tx0 root netem delay 10ms limit 10000
  ns scream-router tc qdisc add dev rt0 root netem delay 10ms limit 10000
  # HTB supplies the rate; DualPI2 supplies the actual coupled AQM queues.
  ns scream-router tc qdisc add dev rr0 root handle 1: htb default 10
  ns scream-router tc class add dev rr0 parent 1: classid 1:10 htb \
    rate 1mbit ceil 1mbit burst 1600 cburst 1600 quantum 1514
  ns scream-router tc qdisc add dev rr0 parent 1:10 handle 10: \
    dualpi2 l4s_ect step_thresh 1ms limit 1000
  ns scream-tx ping -c 3 -W 2 10.200.2.2
  ns scream-router tc -s qdisc show dev rr0
  trap - ERR
}
case "${1:-}" in
  up) up ;;
  down) down ;;
  rate)
    rate=${2:?Specify a rate, for example 250kbit or 1mbit}
    [[ $rate =~ ^[0-9]+(kbit|mbit)$ ]] || { echo 'Use an integer kbit or mbit rate.' >&2; exit 1; }
    ns scream-router tc class change dev rr0 parent 1: classid 1:10 htb \
      rate "$rate" ceil "$rate" burst 1600 cburst 1600 quantum 1514
    ;;
  queue)
    case "${2:-}" in
      dualpi2) ns scream-router tc qdisc replace dev rr0 parent 1:10 handle 10: dualpi2 l4s_ect step_thresh 1ms limit 1000 ;;
      fifo) ns scream-router tc qdisc replace dev rr0 parent 1:10 handle 20: pfifo limit 1000 ;;
      *) echo 'Queue must be dualpi2 or fifo.' >&2; exit 2 ;;
    esac
    ;;
  status)
    ns scream-router tc -s qdisc show dev rr0
    ns scream-router tc -s class show dev rr0
    ;;
  *) echo "Usage: sudo $0 up|down|rate RATE|queue dualpi2|queue fifo|status" >&2; exit 2 ;;
esac
