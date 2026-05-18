#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# ST-05 probe: periodic latency check via mDNS resolve.
# Measures how fast ZGW answers a directed query for one known hostname.
#
# Usage: ./zgw_latency_probe.sh <hostname> [cadence-seconds] [timeout-ms]
#   hostname:  full mDNS name, e.g. zwC9136E8F0001.local
#   cadence:   seconds between probes (default 10)
#   timeout:   per-probe timeout in ms (default 5000)
#
# Output: probe_latency_<hostname>_<UTC>.csv
# Stop with Ctrl+C.
set -u
HOST="${1:-}"
CADENCE_S="${2:-10}"
TIMEOUT_MS="${3:-5000}"
if [ -z "$HOST" ]; then
  echo "Usage: $0 <hostname> [cadence-seconds] [timeout-ms]" >&2
  echo "Example: $0 zwC9136E8F0001.local 10 5000" >&2
  exit 2
fi
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
SAFE_HOST=$(echo "$HOST" | tr '/.' '__')
OUT="probe_latency_${SAFE_HOST}_${STAMP}.csv"
# timeout(1) takes seconds; allow fractional.
TIMEOUT_S=$(awk -v ms="$TIMEOUT_MS" 'BEGIN{printf "%.3f", ms/1000.0}')
echo "send_iso,recv_iso,latency_ms,address,status" > "$OUT"
echo "Latency probe -> $OUT (host=$HOST, every ${CADENCE_S}s, timeout=${TIMEOUT_MS}ms)"
trap 'echo "Stopped. CSV: $OUT"; exit 0' INT TERM
while true; do
  send_ns=$(date +%s%N)
  send_iso=$(date -u -d "@$((send_ns/1000000000))" +%FT%T.%3NZ)
  if reply=$(timeout "$TIMEOUT_S" avahi-resolve -n "$HOST" 2>/dev/null); then
    address=$(echo "$reply" | awk '{print $2}')
    [ -n "$address" ] && status="ok" || status="fail"
  else
    address=""
    status="timeout"
  fi
  recv_ns=$(date +%s%N)
  recv_iso=$(date -u -d "@$((recv_ns/1000000000))" +%FT%T.%3NZ)
  latency_ms=$(( (recv_ns - send_ns) / 1000000 ))
  # Cap latency reporting at timeout for tidy CSV when status=timeout.
  [ "$status" = "timeout" ] && latency_ms="$TIMEOUT_MS"
  echo "$send_iso,$recv_iso,$latency_ms,$address,$status" | tee -a "$OUT"
  sleep "$CADENCE_S"
done
