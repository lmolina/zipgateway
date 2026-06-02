#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# ST-02 analyzer (node false-dead events)
#
# Verdict policy:
#   PASS  (exit 0): every node has <= ST02_MAX_FALSE_DEAD_PER_24H false-dead
#                   events in every 24 h window of the run (zero events also
#                   passes).
#   FAIL  (exit 1): any (node, 24 h window) exceeds the threshold.
#   INCONCLUSIVE (exit 2): the tailer CSV is missing (no probe data).
#
# A present-but-header-only CSV means the load produced no failed-node
# events; that is a PASS with zero events, not INCONCLUSIVE.
#
# Usage:
#   st02_analyze.sh --run-dir DIR [--conf FILE]
#
# Writes DIR/st02_verdict.txt and DIR/st02_summary.json.

set -uo pipefail

usage() { sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-2}"; }

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

# Threshold (conf overrides; default keeps the analyzer standalone-runnable).
MAX_FD="${ST02_MAX_FALSE_DEAD_PER_24H:-1}"
# Corroboration: a "Node N is now ok" within this many seconds of a
# "Node N is now failing" is ZGW's own evidence that the node recovered,
# i.e. it was a false-dead. Reported as supporting context, not a verdict.
RECOVERY_RE="${ST02_RECOVERY_RE:-Node [0-9]+ is now ok}"

VERDICT_TXT="${RUN_DIR}/st02_verdict.txt"
SUMMARY_JSON="${RUN_DIR}/st02_summary.json"

events_csv="${RUN_DIR}/07_run/st02_events.csv"
zgw_log="${RUN_DIR}/07_run/zipgateway.log"

reasons=()
inconclusive=0

total_events=0
false_dead=0
true_dead=0
noparse=0
noresolve=0
worst_node=""
worst_window=""
worst_count=0
# Per-node false-dead counts for the JSON breakdown.
node_counts_json=""

if [ ! -f "${events_csv}" ]; then
  inconclusive=1
  reasons+=("tailer CSV missing under ${RUN_DIR} (${events_csv})")
else
  awk_script="${script_dir}/st02_bucket.awk"
  if [ ! -f "${awk_script}" ]; then
    inconclusive=1
    reasons+=("bucket script missing: ${awk_script}")
  else
    analysis=$(awk -F, -v maxfd="${MAX_FD}" -f "${awk_script}" "${events_csv}")
  fi

  # Parse the line-oriented report from st02_bucket.awk.
  over_lines=()
  while IFS= read -r ln; do
    [ -z "${ln}" ] && continue
    # Deliberate split: the awk report emits space-separated tokens.
    # shellcheck disable=SC2086
    set -- ${ln}
    case "$1" in
      TOTAL) total_events="$2" ;;
      FD)    false_dead="$2" ;;
      TD)    true_dead="$2" ;;
      NP)    noparse="$2" ;;
      NR)    noresolve="$2" ;;
      NODE)
        node_id="$2"; cnt="$3"
        node_counts_json="${node_counts_json}${node_counts_json:+,}\"${node_id}\": ${cnt}"
        ;;
      OVER)  over_lines+=("node $2 window $3: $4 false-dead events (> ${MAX_FD})") ;;
      WORST)
        worst_node="$2"; worst_window="$3"; worst_count="${4:-0}"
        [ "${worst_node}" = "-" ] && worst_node=""
        [ "${worst_window}" = "-" ] && worst_window=""
        ;;
    esac
  done <<< "${analysis}"

  if [ "${#over_lines[@]}" -gt 0 ]; then
    for o in "${over_lines[@]}"; do reasons+=("${o}"); done
  fi
fi

# Count "Node N is now ok" lines in the ZGW log. This is independent
# evidence of nodes recovering (consistent with false-deads). It is
# reported as context only and never changes the verdict.
log_recovery_count=0
if [ -f "${zgw_log}" ] && [ -s "${zgw_log}" ]; then
  log_recovery_count=$(grep -E -c "${RECOVERY_RE}" "${zgw_log}" 2>/dev/null) \
    || log_recovery_count=0
fi

if [ "${inconclusive}" -eq 1 ]; then
  verdict="INCONCLUSIVE"; code=2
elif [ "${#reasons[@]}" -gt 0 ]; then
  verdict="FAIL"; code=1
else
  verdict="PASS"; code=0
fi

{
  echo "ST-02 verdict: ${verdict}"
  echo "run_dir: ${RUN_DIR}"
  echo "generated: $(date -u +%FT%TZ)"
  echo
  echo "false-dead events:"
  echo "  csv: ${events_csv}"
  echo "  total_events=${total_events} false_dead=${false_dead} true_dead=${true_dead} noresolve=${noresolve} noparse=${noparse}"
  echo "  threshold=${MAX_FD} false-dead per node per 24h"
  echo "  worst bucket: node=${worst_node:-<none>} window=${worst_window:-<none>} count=${worst_count}"
  echo
  echo "corroboration (context only, not a verdict input):"
  echo "  zgw_log: ${zgw_log}"
  echo "  recovery markers (/${RECOVERY_RE}/): ${log_recovery_count}"
  echo
  if [ "${#reasons[@]}" -gt 0 ]; then
    echo "reasons:"
    for r in "${reasons[@]}"; do echo "  - ${r}"; done
  else
    echo "reasons: none (no node exceeded the false-dead threshold)"
  fi
} > "${VERDICT_TXT}"

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
  echo "  \"false_dead\": {"
  echo "    \"csv\": \"${events_csv}\","
  echo "    \"total_events\": ${total_events},"
  echo "    \"false_dead\": ${false_dead},"
  echo "    \"true_dead\": ${true_dead},"
  echo "    \"noresolve\": ${noresolve},"
  echo "    \"noparse\": ${noparse},"
  echo "    \"threshold_per_node_per_24h\": ${MAX_FD},"
  echo "    \"worst_node\": \"${worst_node}\","
  echo "    \"worst_window\": \"${worst_window}\","
  echo "    \"worst_count\": ${worst_count},"
  echo "    \"per_node_false_dead\": {${node_counts_json}}"
  echo "  },"
  echo "  \"corroboration\": {"
  echo "    \"zgw_log\": \"${zgw_log}\","
  echo "    \"recovery_marker_count\": ${log_recovery_count}"
  echo "  },"
  echo "  \"reasons\": [${json_reasons}]"
  echo "}"
} > "${SUMMARY_JSON}"

echo "ST-02 verdict: ${verdict} (exit ${code})" >&2
echo "  ${VERDICT_TXT}" >&2
echo "  ${SUMMARY_JSON}" >&2
exit "${code}"
