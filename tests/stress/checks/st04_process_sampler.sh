#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# ST-04 process sampler (ZGW memory / CPU).
#
# Usage:
#   st04_process_sampler.sh --out FILE [options]
#
# Options:
#   --out FILE            CSV output path (required).
#   --process-name NAME   Process name to sample via pgrep -x
#                         (default zipgateway).
#   --cadence-s SEC       Seconds between samples (default 60).
#   --duration-s SEC      Stop after this many seconds (default: run until
#                         SIGINT/SIGTERM).
#
# CSV columns: sample_iso,sample_epoch_s,pid,rss_kib,cpu_pct,status
#   status:
#     ok         PID/RSS/CPU% all available
#     warmup     PID/RSS available, but CPU% cannot be computed yet
#                (first sample or PID changed)
#     missing    no matching process found
#     parse_error /proc data unreadable or malformed
#
# Stop with Ctrl+C; a final summary line is printed to stderr.

set -uo pipefail

usage() {
  sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-2}"
}

OUT=""
PROCESS_NAME="zipgateway"
CADENCE_S=60
DURATION_S=""

while [ $# -gt 0 ]; do
  case "$1" in
    --out)          OUT="${2:-}"; shift 2 ;;
    --process-name) PROCESS_NAME="${2:-}"; shift 2 ;;
    --cadence-s)    CADENCE_S="${2:-}"; shift 2 ;;
    --duration-s)   DURATION_S="${2:-}"; shift 2 ;;
    -h|--help)      usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 2 ;;
  esac
done

if [ -z "${OUT}" ]; then
  echo "Error: --out is required." >&2
  usage 2
fi

mkdir -p "$(dirname "${OUT}")"
echo "sample_iso,sample_epoch_s,pid,rss_kib,cpu_pct,status" > "${OUT}"
echo "ST-04 sampler -> ${OUT}" >&2
duration_disp="until-signal"
[ -n "${DURATION_S}" ] && duration_disp="${DURATION_S}s"
echo "  process=${PROCESS_NAME} cadence=${CADENCE_S}s duration=${duration_disp}" >&2

CLK_TCK=$(getconf CLK_TCK 2>/dev/null || echo 100)

samples=0
ok_rows=0
warmup_rows=0
missing_rows=0
parse_error_rows=0
start_s=$(date +%s)

prev_pid=""
prev_ticks=""
prev_epoch=""

summary() {
  echo "ST-04 sampler stopped: samples=${samples} ok=${ok_rows} warmup=${warmup_rows} missing=${missing_rows} parse_error=${parse_error_rows}" >&2
  echo "  CSV: ${OUT}" >&2
}
trap 'summary; exit 0' INT TERM

while true; do
  if [ -n "${DURATION_S}" ] && [ "$(( $(date +%s) - start_s ))" -ge "${DURATION_S}" ]; then
    break
  fi

  sample_epoch_s=$(date +%s)
  sample_iso=$(date -u -d "@${sample_epoch_s}" +%FT%T.%3NZ)

  pid="$(pgrep -x "${PROCESS_NAME}" | head -n1 || true)"
  if [ -z "${pid}" ]; then
    echo "${sample_iso},${sample_epoch_s},,,,missing" >> "${OUT}"
    samples=$((samples+1))
    missing_rows=$((missing_rows+1))
    prev_pid=""
    prev_ticks=""
    prev_epoch=""
    sleep "${CADENCE_S}"
    continue
  fi

  rss_kib="$(awk '/^VmRSS:/ {print $2; exit}' "/proc/${pid}/status" 2>/dev/null || true)"
  total_ticks="$(awk '{print $14 + $15}' "/proc/${pid}/stat" 2>/dev/null || true)"
  if [[ ! "${rss_kib}" =~ ^[0-9]+$ ]] || [[ ! "${total_ticks}" =~ ^[0-9]+$ ]]; then
    echo "${sample_iso},${sample_epoch_s},${pid},${rss_kib},,parse_error" >> "${OUT}"
    samples=$((samples+1))
    parse_error_rows=$((parse_error_rows+1))
    prev_pid=""
    prev_ticks=""
    prev_epoch=""
    sleep "${CADENCE_S}"
    continue
  fi

  cpu_pct=""
  status="warmup"
  if [ -n "${prev_pid}" ] && [ "${prev_pid}" = "${pid}" ] && [ -n "${prev_ticks}" ] && [ -n "${prev_epoch}" ]; then
    elapsed_s=$((sample_epoch_s - prev_epoch))
    if [ "${elapsed_s}" -gt 0 ]; then
      cpu_pct="$(awk -v curr="${total_ticks}" -v prev="${prev_ticks}" -v hz="${CLK_TCK}" -v dt="${elapsed_s}" \
        'BEGIN{printf "%.3f", ((curr-prev)/hz)/dt*100}')"
      status="ok"
    fi
  fi

  echo "${sample_iso},${sample_epoch_s},${pid},${rss_kib},${cpu_pct},${status}" >> "${OUT}"
  samples=$((samples+1))
  if [ "${status}" = "ok" ]; then
    ok_rows=$((ok_rows+1))
  else
    warmup_rows=$((warmup_rows+1))
  fi

  prev_pid="${pid}"
  prev_ticks="${total_ticks}"
  prev_epoch="${sample_epoch_s}"

  sleep "${CADENCE_S}"
done

summary
