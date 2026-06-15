#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# ST-01 analyzer (NCP tx-queue lockup) -- post-run verdict.
#
# Consumes a run_<UTC>/ folder produced by 07_run.sh and decides whether
# the NCP tx path locked up during the run. Two independent signals:
#
#   1. Heartbeat CSV (checks/st01_heartbeat.sh output): the reliable
#      signal. We control its format exactly. A sustained run of
#      consecutive 'timeout' rows == a wedge. The longest streak and its
#      start time are reported.
#
#   2. ZGW log tx markers (TRANSMIT_COMPLETE_OK): corroborating.
#      A successful NCP transmit is logged by ZGW; if those markers stop
#      advancing for too long while the run was active, the tx path was
#      stuck. The marker regex is ZGW-version coupled (ST01_TX_MARKER_RE in
#      conf) and must be verified at the shakedown.
#
# Verdict policy (strict -- both signals must agree for PASS):
#   PASS  (exit 0): no heartbeat timeout streak >= ST01_MAX_TIMEOUT_STREAK
#                   AND no ZGW-log tx-marker gap > ST01_MAX_TX_GAP_S.
#   FAIL  (exit 1): either signal indicates a lockup.
#   INCONCLUSIVE (exit 2): a required input is missing/empty (no heartbeat
#                   CSV, or no ZGW log to corroborate).
#
# Usage:
#   st01_analyze.sh --run-dir DIR [--conf FILE]
#
# Writes DIR/verdict.txt and DIR/summary.json.

set -uo pipefail

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-2}"; }

RUN_DIR=""
CONF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --run-dir) RUN_DIR="${2:-}"; shift 2 ;;
    --conf)    CONF="${2:-}"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 2 ;;
  esac
done

if [ -z "${RUN_DIR}" ] || [ ! -d "${RUN_DIR}" ]; then
  echo "Error: --run-dir DIR (existing) is required." >&2
  usage 2
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
[ -z "${CONF}" ] && CONF="$(cd "${script_dir}/.." && pwd)/conf"
if [ -f "${CONF}" ]; then
  # shellcheck source=/dev/null
  source "${CONF}"
fi

# Thresholds (conf overrides; defaults keep the analyzer standalone-runnable).
MAX_STREAK="${ST01_MAX_TIMEOUT_STREAK:-3}"
MAX_TX_GAP_S="${ST01_MAX_TX_GAP_S:-60}"
TX_MARKER_RE="${ST01_TX_MARKER_RE:-TRANSMIT_COMPLETE_OK}"

VERDICT_TXT="${RUN_DIR}/et01_verdict.txt"
SUMMARY_JSON="${RUN_DIR}/et01_summary.json"

hb_csv="${RUN_DIR}/07_run/st01_heartbeat.csv"
zgw_log="${RUN_DIR}/07_run/zipgateway.log"

reasons=()
inconclusive=0

# --- Signal 1: heartbeat ----------------------------------------------------
hb_samples=0
hb_ok=0
hb_timeout=0
hb_max_streak=0
hb_streak_start=""
hb_lockup=0
if [ -n "${hb_csv}" ] && [ -s "${hb_csv}" ]; then
  # Parse data rows (skip header). Track the longest run of status==timeout.
  while IFS=, read -r sample_iso _recv _lat _host _addr status; do
    [ "${sample_iso}" = "sample_iso" ] && continue
    [ -z "${status}" ] && continue
    hb_samples=$((hb_samples+1))
    case "${status}" in
      ok)   hb_ok=$((hb_ok+1)); cur_streak=0; cur_start="" ;;
      timeout)
        hb_timeout=$((hb_timeout+1))
        if [ "${cur_streak:-0}" -eq 0 ]; then cur_start="${sample_iso}"; fi
        cur_streak=$(( ${cur_streak:-0} + 1 ))
        if [ "${cur_streak}" -gt "${hb_max_streak}" ]; then
          hb_max_streak="${cur_streak}"
          hb_streak_start="${cur_start}"
        fi
        ;;
      *)    cur_streak=0; cur_start="" ;;
    esac
  done < "${hb_csv}"

  if [ "${hb_samples}" -eq 0 ]; then
    inconclusive=1
    reasons+=("heartbeat CSV has no data rows")
  elif [ "${hb_max_streak}" -ge "${MAX_STREAK}" ]; then
    hb_lockup=1
    reasons+=("heartbeat: ${hb_max_streak} consecutive timeouts (>= ${MAX_STREAK}) starting ${hb_streak_start}")
  fi
else
  inconclusive=1
  reasons+=("heartbeat CSV missing or empty under ${RUN_DIR}")
fi

# --- Signal 2: ZGW log tx markers ------------------------------------------
tx_marker_count=0
tx_max_gap_s=0
tx_lockup=0
if [ -n "${zgw_log}" ] && [ -s "${zgw_log}" ]; then
  # `grep -c` prints the count (incl. "0") AND exits 1 on no matches.
  # `... || echo 0` would then append a second "0" -> "0\n0", breaking
  # the `[ -eq 0 ]` test below. Use a fallback assignment so the captured
  # value is grep's stdout in the no-match case (already "0") and only
  # overridden to 0 when grep itself errors (e.g. unreadable file).
  tx_marker_count=$(grep -E -c "${TX_MARKER_RE}" "${zgw_log}" 2>/dev/null) || tx_marker_count=0

  if [ "${tx_marker_count}" -eq 0 ]; then
    # No markers at all: either the run never transmitted (wedge from the
    # start) or the regex is wrong. Strict policy flags it; the regex
    # caveat is called out so the shakedown can disambiguate.
    tx_lockup=1
    reasons+=("ZGW log has zero tx markers matching /${TX_MARKER_RE}/ (lockup, or regex needs adjusting at shakedown)")
  else
    # Largest gap between consecutive marker timestamps. ZGW log lines
    # start with an epoch-ish or HH:MM:SS stamp depending on build; we
    # extract a leading HH:MM:SS if present and diff seconds. If no
    # parseable timestamps, gap stays 0 and only the count is reported.
    tx_max_gap_s=$(grep -E "${TX_MARKER_RE}" "${zgw_log}" 2>/dev/null \
      | grep -oE '[0-9]{2}:[0-9]{2}:[0-9]{2}' \
      | awk -F: '
          { t = $1*3600 + $2*60 + $3;
            if (NR>1) { d = t - p; if (d<0) d += 86400; if (d>max) max=d }
            p = t }
          END { print max+0 }' )
    if [ "${tx_max_gap_s:-0}" -gt "${MAX_TX_GAP_S}" ]; then
      tx_lockup=1
      reasons+=("ZGW log: ${tx_max_gap_s}s gap between tx markers (> ${MAX_TX_GAP_S}s)")
    fi
  fi
else
  inconclusive=1
  reasons+=("ZGW log (zipgateway.log) missing or empty under ${RUN_DIR}")
fi

# --- Verdict ---------------------------------------------------------------
if [ "${inconclusive}" -eq 1 ]; then
  verdict="INCONCLUSIVE"; code=2
elif [ "${hb_lockup}" -eq 1 ] || [ "${tx_lockup}" -eq 1 ]; then
  verdict="FAIL"; code=1
else
  verdict="PASS"; code=0
fi

# --- Emit verdict.txt ------------------------------------------------------
{
  echo "ST-01 verdict: ${verdict}"
  echo "run_dir: ${RUN_DIR}"
  echo "generated: $(date -u +%FT%TZ)"
  echo
  echo "heartbeat:"
  echo "  csv: ${hb_csv:-<none>}"
  echo "  samples=${hb_samples} ok=${hb_ok} timeout=${hb_timeout}"
  echo "  max_timeout_streak=${hb_max_streak} (threshold ${MAX_STREAK}) start=${hb_streak_start:-<none>}"
  echo
  echo "zgw_log:"
  echo "  log: ${zgw_log:-<none>}"
  echo "  tx_marker_count=${tx_marker_count} regex=/${TX_MARKER_RE}/"
  echo "  max_tx_gap_s=${tx_max_gap_s} (threshold ${MAX_TX_GAP_S})"
  echo
  if [ "${#reasons[@]}" -gt 0 ]; then
    echo "reasons:"
    for r in "${reasons[@]}"; do echo "  - ${r}"; done
  else
    echo "reasons: none (both signals nominal)"
  fi
} > "${VERDICT_TXT}"

# --- Emit summary.json -----------------------------------------------------
json_reasons=""
for r in "${reasons[@]:-}"; do
  [ -z "${r}" ] && continue
  esc=${r//\\/\\\\}; esc=${esc//\"/\\\"}
  json_reasons="${json_reasons}${json_reasons:+,}\"${esc}\""
done
{
  echo "{"
  echo "  \"verdict\": \"${verdict}\","
  echo "  \"exit_code\": ${code},"
  echo "  \"run_dir\": \"${RUN_DIR}\","
  echo "  \"heartbeat\": {"
  echo "    \"csv\": \"${hb_csv}\","
  echo "    \"samples\": ${hb_samples},"
  echo "    \"ok\": ${hb_ok},"
  echo "    \"timeout\": ${hb_timeout},"
  echo "    \"max_timeout_streak\": ${hb_max_streak},"
  echo "    \"streak_start\": \"${hb_streak_start}\","
  echo "    \"threshold\": ${MAX_STREAK}"
  echo "  },"
  echo "  \"zgw_log\": {"
  echo "    \"log\": \"${zgw_log}\","
  echo "    \"tx_marker_count\": ${tx_marker_count},"
  echo "    \"max_tx_gap_s\": ${tx_max_gap_s:-0},"
  echo "    \"gap_threshold_s\": ${MAX_TX_GAP_S}"
  echo "  },"
  echo "  \"reasons\": [${json_reasons}]"
  echo "}"
} > "${SUMMARY_JSON}"

echo "ST-01 verdict: ${verdict} (exit ${code})" >&2
echo "  ${VERDICT_TXT}" >&2
echo "  ${SUMMARY_JSON}" >&2
exit "${code}"
