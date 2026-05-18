#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# ST-03 analyzer (ZGW operational) -- post-run verdict.
#
# Consumes a run_<UTC>/ folder produced by 07_run.sh and decides whether
# the ZGW process stayed alive, responsive, and free of fatal errors
# throughout the load. Three independent signals:
#
#   1. PID match: st03_pid_start.txt vs st03_pid_end.txt. A change
#      means the gateway restarted; an empty end PID means it died.
#
#   2. Probe history: every row in st03_zgw_probe.csv must have
#      status==ok. Any timeout/fail row means the gateway was
#      unresponsive at that sample.
#
#   3. ZGW log fatal-keyword scan: zipgateway.log must contain zero
#      matches of ST03_FATAL_RE (source-backed; see tests/stress/conf).
#
# Verdict policy (strict -- all three signals must pass for PASS):
#   PASS  (exit 0): PID unchanged, no non-ok probe rows, zero log matches.
#   FAIL  (exit 1): any of the three signals breaches.
#   INCONCLUSIVE (exit 2): a required input is missing/empty.
#
# Usage:
#   st03_analyze.sh --run-dir DIR [--conf FILE]
#
# Writes DIR/st03_verdict.txt and DIR/st03_summary.json.

set -uo pipefail

usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-2}"; }

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

FATAL_RE="${ST03_FATAL_RE:-Fatal error|Assertion failed|ASSERT|SIGSEGV|core dumped}"

VERDICT_TXT="${RUN_DIR}/st03_verdict.txt"
SUMMARY_JSON="${RUN_DIR}/st03_summary.json"

pid_start_file="${RUN_DIR}/07_run/st03_pid_start.txt"
pid_end_file="${RUN_DIR}/07_run/st03_pid_end.txt"
probe_csv="${RUN_DIR}/07_run/st03_zgw_probe.csv"
zgw_log="${RUN_DIR}/07_run/zipgateway.log"

reasons=()
inconclusive=0

pid_start=""
pid_end=""
pid_changed=0
pid_dead=0
if [ -s "${pid_start_file}" ] && [ -e "${pid_end_file}" ]; then
  pid_start=$(tr -d '[:space:]' < "${pid_start_file}")
  pid_end=$(tr -d '[:space:]' < "${pid_end_file}" 2>/dev/null || true)
  if [ -z "${pid_start}" ]; then
    inconclusive=1
    reasons+=("start PID file present but empty (${pid_start_file})")
  elif [ -z "${pid_end}" ]; then
    pid_dead=1
    reasons+=("ZGW not running at run end (empty ${pid_end_file})")
  elif [ "${pid_start}" != "${pid_end}" ]; then
    pid_changed=1
    reasons+=("ZGW PID changed during run: start=${pid_start} end=${pid_end} (process restarted)")
  fi
else
  inconclusive=1
  reasons+=("PID file(s) missing under ${RUN_DIR}/07_run/ (st03_pid_start.txt, st03_pid_end.txt)")
fi

probe_samples=0
probe_ok=0
probe_timeout=0
probe_fail=0
probe_first_bad=""
probe_unresponsive=0
if [ -s "${probe_csv}" ]; then
  while IFS=, read -r sample_iso _recv _lat _host _addr status; do
    [ "${sample_iso}" = "sample_iso" ] && continue
    [ -z "${status}" ] && continue
    probe_samples=$((probe_samples+1))
    case "${status}" in
      ok)      probe_ok=$((probe_ok+1)) ;;
      timeout) probe_timeout=$((probe_timeout+1));
               [ -z "${probe_first_bad}" ] && probe_first_bad="${sample_iso} timeout" ;;
      fail)    probe_fail=$((probe_fail+1));
               [ -z "${probe_first_bad}" ] && probe_first_bad="${sample_iso} fail" ;;
      *)       probe_fail=$((probe_fail+1));
               [ -z "${probe_first_bad}" ] && probe_first_bad="${sample_iso} ${status}" ;;
    esac
  done < "${probe_csv}"

  if [ "${probe_samples}" -eq 0 ]; then
    inconclusive=1
    reasons+=("probe CSV has no data rows")
  elif [ "${probe_timeout}" -gt 0 ] || [ "${probe_fail}" -gt 0 ]; then
    probe_unresponsive=1
    reasons+=("probe: ${probe_timeout} timeout + ${probe_fail} fail rows; first bad sample at ${probe_first_bad}")
  fi
else
  inconclusive=1
  reasons+=("probe CSV missing or empty under ${RUN_DIR}")
fi

fatal_count=0
fatal_samples=""
log_fatal=0
if [ -s "${zgw_log}" ]; then
  # See st01_analyze.sh for the grep -c / || fallback idiom.
  fatal_count=$(grep -E -c "${FATAL_RE}" "${zgw_log}" 2>/dev/null) || fatal_count=0
  if [ "${fatal_count}" -gt 0 ]; then
    log_fatal=1
    fatal_samples=$(grep -E "${FATAL_RE}" "${zgw_log}" 2>/dev/null | head -n3 | cut -c1-200)
    reasons+=("ZGW log: ${fatal_count} fatal-keyword match(es) for /${FATAL_RE}/")
  fi
else
  inconclusive=1
  reasons+=("ZGW log (zipgateway.log) missing or empty under ${RUN_DIR}")
fi

if [ "${inconclusive}" -eq 1 ]; then
  verdict="INCONCLUSIVE"; code=2
elif [ "${pid_dead}" -eq 1 ] || [ "${pid_changed}" -eq 1 ] || [ "${probe_unresponsive}" -eq 1 ] || [ "${log_fatal}" -eq 1 ]; then
  verdict="FAIL"; code=1
else
  verdict="PASS"; code=0
fi

{
  echo "ST-03 verdict: ${verdict}"
  echo "run_dir: ${RUN_DIR}"
  echo "generated: $(date -u +%FT%TZ)"
  echo
  echo "pid:"
  echo "  start_file: ${pid_start_file}"
  echo "  end_file:   ${pid_end_file}"
  echo "  start=${pid_start:-<none>} end=${pid_end:-<none>}"
  echo "  dead_at_end=${pid_dead}"
  echo
  echo "probe:"
  echo "  csv: ${probe_csv}"
  echo "  samples=${probe_samples} ok=${probe_ok} timeout=${probe_timeout} fail=${probe_fail}"
  echo "  first_bad=${probe_first_bad:-<none>}"
  echo
  echo "zgw_log:"
  echo "  log: ${zgw_log}"
  echo "  fatal_match_count=${fatal_count} regex=/${FATAL_RE}/"
  if [ -n "${fatal_samples}" ]; then
    echo "  first matches:"
    while IFS= read -r line; do echo "    ${line}"; done <<< "${fatal_samples}"
  fi
  echo
  if [ "${#reasons[@]}" -gt 0 ]; then
    echo "reasons:"
    for r in "${reasons[@]}"; do echo "  - ${r}"; done
  else
    echo "reasons: none (all three signals nominal)"
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
  echo "  \"pid\": {"
  echo "    \"start\": \"${pid_start}\","
  echo "    \"end\": \"${pid_end}\","
  echo "    \"dead_at_end\": ${pid_dead},"
  echo "    \"changed\": ${pid_changed}"
  echo "  },"
  echo "  \"probe\": {"
  echo "    \"csv\": \"${probe_csv}\","
  echo "    \"samples\": ${probe_samples},"
  echo "    \"ok\": ${probe_ok},"
  echo "    \"timeout\": ${probe_timeout},"
  echo "    \"fail\": ${probe_fail}"
  echo "  },"
  echo "  \"zgw_log\": {"
  echo "    \"log\": \"${zgw_log}\","
  echo "    \"fatal_match_count\": ${fatal_count},"
  echo "    \"fatal_regex\": \"${FATAL_RE}\""
  echo "  },"
  echo "  \"reasons\": [${json_reasons}]"
  echo "}"
} > "${SUMMARY_JSON}"

echo "ST-03 verdict: ${verdict} (exit ${code})" >&2
echo "  ${VERDICT_TXT}" >&2
echo "  ${SUMMARY_JSON}" >&2
exit "${code}"
