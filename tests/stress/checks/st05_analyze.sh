#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# ST-05 analyzer (ZGW responsiveness) -- post-run verdict.
#
# Consumes a run_<UTC>/ folder produced by 07_run.sh and decides whether
# the shared ZGW probe stayed within the latency budget for the whole run.
#
# Signal:
#   Probe history from 07_run/st03_zgw_probe.csv (shared with ST-03).
#   Every row must satisfy both:
#     - status == ok
#     - latency_s <= ST05_MAX_LATENCY_S (default 5)
#
# Verdict policy:
#   PASS  (exit 0): every probe row is ok and within budget.
#   FAIL  (exit 1): any timeout/fail row or any latency breach.
#   INCONCLUSIVE (exit 2): required input missing/empty/malformed.
#
# Usage:
#   st05_analyze.sh --run-dir DIR [--conf FILE]
#
# Writes DIR/st05_verdict.txt and DIR/st05_summary.json.

set -uo pipefail

usage() { sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-2}"; }

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

MAX_LATENCY_S="${ST05_MAX_LATENCY_S:-5}"

VERDICT_TXT="${RUN_DIR}/st05_verdict.txt"
SUMMARY_JSON="${RUN_DIR}/st05_summary.json"
probe_csv="${RUN_DIR}/07_run/st03_zgw_probe.csv"

reasons=()
inconclusive=0

probe_samples=0
probe_ok=0
probe_timeout=0
probe_fail=0
probe_slow=0
probe_first_bad=""
probe_first_slow=""
probe_max_latency_s="0"

is_number() {
  [[ "${1:-}" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

float_gt() {
  awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'
}

if [ -s "${probe_csv}" ]; then
  while IFS=, read -r sample_iso _recv latency_s _host _addr status; do
    [ "${sample_iso}" = "sample_iso" ] && continue
    [ -z "${sample_iso}" ] && continue
    [ -z "${status}" ] && continue
    probe_samples=$((probe_samples+1))

    case "${status}" in
      ok)
        probe_ok=$((probe_ok+1))
        ;;
      timeout)
        probe_timeout=$((probe_timeout+1))
        [ -z "${probe_first_bad}" ] && probe_first_bad="${sample_iso} timeout"
        ;;
      fail)
        probe_fail=$((probe_fail+1))
        [ -z "${probe_first_bad}" ] && probe_first_bad="${sample_iso} fail"
        ;;
      *)
        probe_fail=$((probe_fail+1))
        [ -z "${probe_first_bad}" ] && probe_first_bad="${sample_iso} ${status}"
        ;;
    esac

    if ! is_number "${latency_s}"; then
      inconclusive=1
      reasons+=("probe CSV has non-numeric latency '${latency_s}' at ${sample_iso}")
      continue
    fi

    if float_gt "${latency_s}" "${probe_max_latency_s}"; then
      probe_max_latency_s="${latency_s}"
    fi

    if float_gt "${latency_s}" "${MAX_LATENCY_S}"; then
      probe_slow=$((probe_slow+1))
      [ -z "${probe_first_slow}" ] && probe_first_slow="${sample_iso} ${latency_s}s"
    fi
  done < "${probe_csv}"

  if [ "${probe_samples}" -eq 0 ]; then
    inconclusive=1
    reasons+=("probe CSV has no data rows")
  elif [ "${probe_timeout}" -gt 0 ] || [ "${probe_fail}" -gt 0 ]; then
    reasons+=("probe: ${probe_timeout} timeout + ${probe_fail} fail rows; first bad sample at ${probe_first_bad}")
  fi

  if [ "${probe_slow}" -gt 0 ]; then
    reasons+=("probe latency: ${probe_slow} sample(s) exceeded ${MAX_LATENCY_S}s; first slow sample at ${probe_first_slow}")
  fi
else
  inconclusive=1
  reasons+=("probe CSV missing or empty under ${RUN_DIR}")
fi

if [ "${inconclusive}" -eq 1 ]; then
  verdict="INCONCLUSIVE"; code=2
elif [ "${probe_timeout}" -gt 0 ] || [ "${probe_fail}" -gt 0 ] || [ "${probe_slow}" -gt 0 ]; then
  verdict="FAIL"; code=1
else
  verdict="PASS"; code=0
fi

{
  echo "ST-05 verdict: ${verdict}"
  echo "run_dir: ${RUN_DIR}"
  echo "generated: $(date -u +%FT%TZ)"
  echo
  echo "probe:"
  echo "  csv: ${probe_csv}"
  echo "  latency_budget_s=${MAX_LATENCY_S}"
  echo "  samples=${probe_samples} ok=${probe_ok} timeout=${probe_timeout} fail=${probe_fail} slow=${probe_slow}"
  echo "  max_latency_s=${probe_max_latency_s}"
  echo "  first_bad=${probe_first_bad:-<none>}"
  echo "  first_slow=${probe_first_slow:-<none>}"
  echo
  if [ "${#reasons[@]}" -gt 0 ]; then
    echo "reasons:"
    for r in "${reasons[@]}"; do echo "  - ${r}"; done
  else
    echo "reasons: none (all probe rows within budget)"
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
  echo "  \"probe\": {"
  echo "    \"csv\": \"${probe_csv}\","
  echo "    \"latency_budget_s\": ${MAX_LATENCY_S},"
  echo "    \"samples\": ${probe_samples},"
  echo "    \"ok\": ${probe_ok},"
  echo "    \"timeout\": ${probe_timeout},"
  echo "    \"fail\": ${probe_fail},"
  echo "    \"slow\": ${probe_slow},"
  echo "    \"max_latency_s\": ${probe_max_latency_s}"
  echo "  },"
  echo "  \"reasons\": [${json_reasons}]"
  echo "}"
} > "${SUMMARY_JSON}"

echo "ST-05 verdict: ${verdict} (exit ${code})" >&2
echo "  ${VERDICT_TXT}" >&2
echo "  ${SUMMARY_JSON}" >&2
exit "${code}"
