#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# ST-04 analyzer (ZGW memory / CPU) -- post-run verdict.
#
# Consumes a run_<UTC>/ folder produced by 07_run.sh and evaluates only
# the two ST-04 metrics:
#   1. RSS slope: linear regression of RSS (KiB) over time.
#   2. CPU% rolling average: 5-minute rolling average (configurable).
#
# Verdict policy:
#   PASS  (exit 0): both metrics stay within threshold.
#   FAIL  (exit 1): RSS slope or rolling CPU average exceeds threshold.
#   INCONCLUSIVE (exit 2): required inputs missing/empty or too little
#                          valid data to compute the metrics.
#
# Usage:
#   st04_analyze.sh --run-dir DIR [--conf FILE]
#
# Writes DIR/st04_verdict.txt and DIR/st04_summary.json.

set -uo pipefail

usage() { sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-2}"; }

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

CPU_WINDOW_S="${ST04_CPU_ROLLING_WINDOW_S:-300}"
CPU_MAX_PCT="${ST04_CPU_MAX_PCT:-80}"
RSS_SLOPE_MAX="${ST04_RSS_SLOPE_MAX_KIB_PER_H:-0}"

VERDICT_TXT="${RUN_DIR}/st04_verdict.txt"
SUMMARY_JSON="${RUN_DIR}/st04_summary.json"
PROCESS_CSV="${RUN_DIR}/07_run/st04_process.csv"

reasons=()
inconclusive=0

total_rows=0
rss_rows=0
cpu_rows=0
slope_kib_per_h=""
max_cpu_rolling_pct=""
cpu_peak_iso=""
rss_over=0
cpu_over=0

if [ ! -s "${PROCESS_CSV}" ]; then
  inconclusive=1
  reasons+=("process sampler CSV missing or empty under ${RUN_DIR}")
else
  analysis="$(
    awk -F, \
      -v cpu_window_s="${CPU_WINDOW_S}" \
      -v cpu_max_pct="${CPU_MAX_PCT}" \
      -v rss_slope_max="${RSS_SLOPE_MAX}" '
      BEGIN {
        total_rows = rss_rows = cpu_rows = 0
        first_epoch = ""
        sum_x = sum_y = sum_xy = sum_xx = 0
        head = 1
        tail = 0
        queue_sum = 0
        slope = ""
        max_cpu = ""
        cpu_peak_iso = "-"
        rss_over = 0
        cpu_over = 0
      }
      NR == 1 { next }
      {
        total_rows++
        sample_iso = $1
        epoch = $2 + 0
        rss = $4
        cpu = $5
        status = $6

        if ((status == "ok" || status == "warmup") &&
            epoch > 0 && rss ~ /^[0-9]+([.][0-9]+)?$/) {
          if (first_epoch == "") {
            first_epoch = epoch
          }
          x = epoch - first_epoch
          rss_rows++
          sum_x += x
          sum_y += rss
          sum_xy += x * rss
          sum_xx += x * x
        }

        if (status == "ok" && epoch > 0 && cpu ~ /^-?[0-9]+([.][0-9]+)?$/) {
          cpu_rows++
          tail++
          q_epoch[tail] = epoch
          q_cpu[tail] = cpu + 0
          queue_sum += cpu + 0

          while (head <= tail && (epoch - q_epoch[head]) > cpu_window_s) {
            queue_sum -= q_cpu[head]
            delete q_epoch[head]
            delete q_cpu[head]
            head++
          }

          rolling = queue_sum / (tail - head + 1)
          if (max_cpu == "" || rolling > max_cpu) {
            max_cpu = rolling
            cpu_peak_iso = sample_iso
          }
          if (rolling > cpu_max_pct) {
            cpu_over = 1
          }
        }
      }
      END {
        if (rss_rows >= 2) {
          denom = rss_rows * sum_xx - sum_x * sum_x
          if (denom != 0) {
            slope = ((rss_rows * sum_xy) - (sum_x * sum_y)) / denom * 3600
            if (slope > rss_slope_max) {
              rss_over = 1
            }
          }
        }

        printf("TOTAL %d\n", total_rows)
        printf("RSS_ROWS %d\n", rss_rows)
        printf("CPU_ROWS %d\n", cpu_rows)
        printf("SLOPE_KIB_PER_H %s\n", (slope == "" ? "-" : sprintf("%.6f", slope)))
        printf("MAX_CPU_ROLLING_PCT %s\n", (max_cpu == "" ? "-" : sprintf("%.6f", max_cpu)))
        printf("CPU_PEAK_ISO %s\n", cpu_peak_iso)
        printf("RSS_OVER %d\n", rss_over)
        printf("CPU_OVER %d\n", cpu_over)
      }
    ' "${PROCESS_CSV}"
  )"

  while IFS= read -r ln; do
    [ -z "${ln}" ] && continue
    # shellcheck disable=SC2086
    set -- ${ln}
    case "$1" in
      TOTAL) total_rows="$2" ;;
      RSS_ROWS) rss_rows="$2" ;;
      CPU_ROWS) cpu_rows="$2" ;;
      SLOPE_KIB_PER_H) slope_kib_per_h="$2" ;;
      MAX_CPU_ROLLING_PCT) max_cpu_rolling_pct="$2" ;;
      CPU_PEAK_ISO) cpu_peak_iso="$2" ;;
      RSS_OVER) rss_over="$2" ;;
      CPU_OVER) cpu_over="$2" ;;
    esac
  done <<< "${analysis}"

  [ "${slope_kib_per_h}" = "-" ] && slope_kib_per_h=""
  [ "${max_cpu_rolling_pct}" = "-" ] && max_cpu_rolling_pct=""
  [ "${cpu_peak_iso}" = "-" ] && cpu_peak_iso=""

  if [ "${total_rows}" -eq 0 ]; then
    inconclusive=1
    reasons+=("process sampler CSV has no data rows")
  fi
  if [ "${rss_rows}" -lt 2 ]; then
    inconclusive=1
    reasons+=("need at least 2 valid RSS samples for regression (got ${rss_rows})")
  fi
  if [ "${cpu_rows}" -lt 1 ]; then
    inconclusive=1
    reasons+=("need at least 1 valid CPU sample for rolling average (got ${cpu_rows})")
  fi
  if [ -z "${slope_kib_per_h}" ]; then
    inconclusive=1
    reasons+=("RSS slope could not be computed from ${PROCESS_CSV}")
  fi

  if [ "${rss_over}" -eq 1 ]; then
    reasons+=("RSS slope ${slope_kib_per_h} KiB/hour exceeds threshold ${RSS_SLOPE_MAX}")
  fi
  if [ "${cpu_over}" -eq 1 ]; then
    reasons+=("CPU 5-minute rolling average peak ${max_cpu_rolling_pct}% at ${cpu_peak_iso:-<none>} exceeds threshold ${CPU_MAX_PCT}%")
  fi
fi

if [ "${inconclusive}" -eq 1 ]; then
  verdict="INCONCLUSIVE"; code=2
elif [ "${#reasons[@]}" -gt 0 ]; then
  verdict="FAIL"; code=1
else
  verdict="PASS"; code=0
fi

{
  echo "ST-04 verdict: ${verdict}"
  echo "run_dir: ${RUN_DIR}"
  echo "generated: $(date -u +%FT%TZ)"
  echo
  echo "sampler:"
  echo "  csv: ${PROCESS_CSV}"
  echo "  rows total=${total_rows}"
  echo
  echo "rss:"
  echo "  valid_samples=${rss_rows}"
  echo "  slope_kib_per_h=${slope_kib_per_h:-<none>}"
  echo "  threshold_kib_per_h=${RSS_SLOPE_MAX}"
  echo
  echo "cpu:"
  echo "  valid_samples=${cpu_rows}"
  echo "  rolling_window_s=${CPU_WINDOW_S}"
  echo "  peak_rolling_pct=${max_cpu_rolling_pct:-<none>}"
  echo "  peak_at=${cpu_peak_iso:-<none>}"
  echo "  threshold_pct=${CPU_MAX_PCT}"
  echo
  if [ "${#reasons[@]}" -gt 0 ]; then
    echo "reasons:"
    for r in "${reasons[@]}"; do echo "  - ${r}"; done
  else
    echo "reasons: none (RSS slope and rolling CPU average stayed within threshold)"
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
  echo "  \"sampler\": {"
  echo "    \"csv\": \"${PROCESS_CSV}\","
  echo "    \"total_rows\": ${total_rows}"
  echo "  },"
  echo "  \"rss\": {"
  echo "    \"valid_samples\": ${rss_rows},"
  echo "    \"slope_kib_per_h\": ${slope_kib_per_h:-null},"
  echo "    \"threshold_kib_per_h\": ${RSS_SLOPE_MAX}"
  echo "  },"
  echo "  \"cpu\": {"
  echo "    \"valid_samples\": ${cpu_rows},"
  echo "    \"rolling_window_s\": ${CPU_WINDOW_S},"
  echo "    \"peak_rolling_pct\": ${max_cpu_rolling_pct:-null},"
  echo "    \"peak_at\": \"${cpu_peak_iso}\","
  echo "    \"threshold_pct\": ${CPU_MAX_PCT}"
  echo "  },"
  echo "  \"reasons\": [${json_reasons}]"
  echo "}"
} > "${SUMMARY_JSON}"

echo "ST-04 verdict: ${verdict} (exit ${code})" >&2
echo "  ${VERDICT_TXT}" >&2
echo "  ${SUMMARY_JSON}" >&2
exit "${code}"
