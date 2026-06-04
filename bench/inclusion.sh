#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# Step 05: automated SmartStart inclusion driver. Runs on [test-controller].
#
# For each end device (in bed.tsv slot order) it:
#   1. starts an ssh tail -F | grep of the ZGW log,
#   2. power-cycles the board over JLink-IP (off, settle, on),
#   3. waits for the SmartStart START line, then for the DONE line,
#   4. checks the resulting node id == slot + 4,
#   5. retries up to INCLUSION_MAX_RETRIES, then prompts the operator.

set -uo pipefail

script_folder=$(cd "$(dirname "$0")" && pwd)

# -- preconditions -----------------------------------------------------------

if [ -z "${TEST_DIR:-}" ]; then
  echo "Error: TEST_DIR is not set (call via tests/<name>/05_inclusion.sh)." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${TEST_DIR}/conf"
# shellcheck source=utils.sh
source "${script_folder}/utils.sh"

for v in TEST_DIR RUN_DIR STEP_DIR; do
  if [ -z "${!v:-}" ]; then
    echo "Error: ${v} must be set." >&2
    exit 1
  fi
done

req_conf=(ZGW_HOST ZGW_USER LOG_PATH ARTIFACTS_DIR BED_TSV REFERENCE_CLIENT
          INCLUSION_START_RE INCLUSION_DONE_RE INCLUSION_NODEID_RE)
missing=0
for v in "${req_conf[@]}"; do
  if [ -z "${!v:-}" ]; then
    echo "Error: required conf variable ${v} not set." >&2
    missing=1
  fi
done
[ "${missing}" -eq 0 ] || exit 2

if [ ! -f "${ARTIFACTS_DIR}/dsks" ]; then
  echo "Error: ${ARTIFACTS_DIR}/dsks not found (run 02_prepare_boards.sh)." >&2
  exit 1
fi

# -- knobs (with defaults) ---------------------------------------------------

START_TIMEOUT_S="${INCLUSION_START_TIMEOUT_S:-30}"
DONE_TIMEOUT_S="${INCLUSION_DONE_TIMEOUT_S:-120}"
SETTLE_OFF_S="${INCLUSION_SETTLE_OFF_S:-2}"
MAX_RETRIES="${INCLUSION_MAX_RETRIES:-3}"

ssh_target="${ZGW_USER}@${ZGW_HOST}"
ssh_opts=(-o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=15)

# -- run outputs -------------------------------------------------------------

mkdir -p "${STEP_DIR}"
out_csv="${STEP_DIR}/inclusion.csv"
verdict_file="${STEP_DIR}/verdict.txt"
summary_file="${STEP_DIR}/summary.json"
echo "slot,jlink_host,role,expected_node_id,observed_node_id,attempt_iso,started_iso,done_iso,attempts,status" \
  > "${out_csv}"

bed_load "${BED_TSV}"

now_iso() { date -u +%FT%T.%3NZ; }

# -- log tailer --------------------------------------------------------------
#
# One tailer per attempt. Monitors the zipgateway.log to identify the begin and end of the inclusion.
TAIL_PID=""
TAIL_FD=""
TAIL_FIFO=""

start_tailer() {
  TAIL_FIFO=$(mktemp -u "${STEP_DIR}/.tail.XXXXXX")
  mkfifo "${TAIL_FIFO}"
  # Hold the fifo open r/w so the bg writer can open it without blocking
  # and our reader does not see EOF when the writer transiently exits.
  exec {TAIL_FD}<>"${TAIL_FIFO}"

  # shellcheck disable=SC2016  # body is expanded by the inner shell, not here
  MATCH_RE="${INCLUSION_START_RE}|${INCLUSION_DONE_RE}" \
  setsid bash -c '
    ssh "$@" "tail -n0 -F \"${LOG_PATH}\"" 2>/dev/null \
      | sed -u -E "s/\x1b\[[0-9;]*m//g" \
      | grep --line-buffered -E -- "${MATCH_RE}"
  ' _ "${ssh_opts[@]}" "${ssh_target}" \
    >"${TAIL_FIFO}" 2>/dev/null \
    < /dev/null \
    & TAIL_PID=$!
}

stop_tailer() {
  if [ -n "${TAIL_FD}" ]; then
    eval "exec ${TAIL_FD}<&-" 2>/dev/null || true
    TAIL_FD=""
  fi
  if [ -n "${TAIL_PID}" ] && kill -0 "${TAIL_PID}" 2>/dev/null; then
    kill -TERM -"${TAIL_PID}" 2>/dev/null \
      || kill -TERM "${TAIL_PID}" 2>/dev/null || true
    wait "${TAIL_PID}" 2>/dev/null || true
  fi
  TAIL_PID=""
  if [ -n "${TAIL_FIFO}" ]; then
    rm -f "${TAIL_FIFO}"
    TAIL_FIFO=""
  fi
}

# shellcheck disable=SC2317  # invoked by trap
cleanup() { stop_tailer; }
# shellcheck disable=SC2317  # invoked by trap
on_int() { echo; echo "Interrupted; stopping ..." >&2; cleanup; exit 130; }
trap on_int INT TERM
trap cleanup EXIT

# LOG_PATH is exported so the setsid subshell sees it; MATCH_RE is set
# per-call as a one-shot env assignment in start_tailer.
export LOG_PATH

# -- HomeID + idempotency ----------------------------------------------------

echo "Detecting HomeID from ${ssh_target} ..."
home_id_raw="$(ssh "${ssh_opts[@]}" "${ssh_target}" \
  "tac '${LOG_PATH}' | grep -m1 HomeID 2>/dev/null | cut -f4 -d' '" || true)"
home_id_raw="${home_id_raw//[![:alnum:]]/}"
home_id="$(echo "${home_id_raw}" | tr '[:lower:]' '[:upper:]')"
if [[ ! "${home_id}" =~ ^[0-9A-F]{8}$ ]]; then
  echo "Error: could not detect a valid 8-hex HomeID from ${LOG_PATH}." >&2
  echo "       detected='${home_id_raw}'" >&2
  exit 1
fi
echo "Detected HomeID: ${home_id}"

# shellcheck disable=SC2154
included_list=$(ssh "${ssh_opts[@]}" "${ssh_target}" \
  "timeout 20 '${REFERENCE_CLIENT}' -s '${ZipLanIp6}' -p '${ZipPSK}' <<<'list' 2>/dev/null" \
  2>/dev/null || true)

node_already_included() {
  local slot="$1" hid="$2" uri
  [ -n "${included_list}" ] || return 1
  uri="$(bed_node_uri "${slot}" "${hid}")"
  printf '%s\n' "${included_list}" | grep -Fiq "${uri}"
}

# -- operator prompt ---------------------------------------------------------

prompt_operator() {
  local slot="$1" reply=""
  if [ ! -t 0 ]; then
    echo "  non-interactive: aborting on slot ${slot}." >&2
    echo "abort"; return
  fi
  while true; do
    printf '  slot %s failed after %s attempts. [c]ontinue / [s]kip / [a]bort? ' \
      "${slot}" "${MAX_RETRIES}" >&2
    read -r reply || { echo "abort"; return; }
    case "${reply}" in
      c|C|continue) echo "continue"; return ;;
      s|S|skip)     echo "skip"; return ;;
      a|A|abort)    echo "abort"; return ;;
      *) echo "  please answer c, s, or a." >&2 ;;
    esac
  done
}

# -- two-phase FSM (one attempt) --------------------------------------------
#
# Prints one of:
#   done|<started_iso>|<node_id>
#   wrong_nodeid|<started_iso>|<node_id>
#   timeout_start|
#   timeout_done|<started_iso>
#
# The caller decides what to do with each. The FSM never blocks beyond
# its declared timeouts: read -t bounds every wait.

await_line_until() {
  # Read one line from the tailer with an absolute deadline (epoch seconds).
  # Sets REPLY on success. Returns 0 on a line, 1 on timeout, 2 on EOF.
  local deadline="$1" now remaining
  now=$(date +%s)
  remaining=$(( deadline - now ))
  [ "${remaining}" -gt 0 ] || return 1
  IFS= read -r -t "${remaining}" -u "${TAIL_FD}" REPLY
  local rc=$?
  if [ "${rc}" -gt 128 ]; then return 1; fi  # timeout
  return "${rc}"                              # 0 ok, 1 EOF
}

try_once() {
  local expected="$1"
  local started_iso="" observed=""
  local deadline line

  # Phase 1: wait for START.
  deadline=$(( $(date +%s) + START_TIMEOUT_S ))
  while await_line_until "${deadline}"; do
    line="${REPLY}"
    if [[ ${line} =~ ${INCLUSION_START_RE} ]]; then
      started_iso="$(now_iso)"
      break
    fi
    # Drop everything else (e.g. a stale DONE from a previous attempt).
  done
  if [ -z "${started_iso}" ]; then
    printf 'timeout_start|\n'; return
  fi

  # Phase 2: wait for DONE.
  deadline=$(( $(date +%s) + DONE_TIMEOUT_S ))
  while await_line_until "${deadline}"; do
    line="${REPLY}"
    if [[ ${line} =~ ${INCLUSION_DONE_RE} ]]; then
      if [[ ${line} =~ ${INCLUSION_NODEID_RE} ]] \
         && [[ ${BASH_REMATCH[0]} =~ ([0-9]+) ]]; then
        observed="${BASH_REMATCH[1]}"
      fi
      if [ "${observed}" = "${expected}" ]; then
        printf 'done|%s|%s\n' "${started_iso}" "${observed}"
      else
        printf 'wrong_nodeid|%s|%s\n' "${started_iso}" "${observed}"
      fi
      return
    fi
  done
  printf 'timeout_done|%s\n' "${started_iso}"
}

# -- main loop ---------------------------------------------------------------

total=0; ok=0; failed=0; skipped=0; already=0
overall_rc=0

for slot in $(bed_iter_end_devices); do
  total=$((total + 1))
  host="${BED_HOST[slot]}"
  role="${BED_ROLE[slot]}"
  expected_node=$((slot + 4))

  echo
  echo "=== slot ${slot} (${role}) host=${host} expect node ${expected_node} ==="

  if node_already_included "${slot}" "${home_id}"; then
    echo "  slot ${slot} already included; skipping."
    printf '%s,%s,%s,%s,%s,%s,,,0,%s\n' \
      "${slot}" "${host}" "${role}" "${expected_node}" "${expected_node}" \
      "$(now_iso)" "already_included" >> "${out_csv}"
    already=$((already + 1))
    continue
  fi

  attempt=0
  status="timeout_start"
  observed_node=""; started_iso=""; done_iso=""
  attempt_iso="$(now_iso)"

  while : ; do
    attempt=$((attempt + 1))
    echo "  attempt ${attempt}/${MAX_RETRIES}: power-cycle ${host}"

    start_tailer

    # Give SSH and tail time to work before reset the board
    sleep 1
    power_off_board "${host}"
    sleep "${SETTLE_OFF_S}"
    power_on_board "${host}"

    outcome="$(try_once "${expected_node}")"
    stop_tailer

    IFS='|' read -r status started_iso observed_node <<< "${outcome}"
    case "${status}" in
      done)
        done_iso="$(now_iso)"
        echo "  done: node=${observed_node} (started ${started_iso})"
        ;;
      wrong_nodeid)
        echo "  WRONG node id: expected ${expected_node}, saw ${observed_node}" >&2
        ;;
      timeout_start)
        echo "  timeout: SmartStart never started" >&2
        ;;
      timeout_done)
        echo "  timeout: SmartStart started but never completed (S2 bootstrap?)" >&2
        ;;
    esac

    [ "${status}" = "done" ] && break

    if [ "${attempt}" -ge "${MAX_RETRIES}" ]; then
      decision="$(prompt_operator "${slot}")"
      case "${decision}" in
        continue) attempt=0; continue ;;
        skip)     status="skipped"; break ;;
        abort)    break ;;
      esac
    fi
  done

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "${slot}" "${host}" "${role}" "${expected_node}" "${observed_node}" \
    "${attempt_iso}" "${started_iso}" "${done_iso}" "${attempt}" "${status}" \
    >> "${out_csv}"

  case "${status}" in
    done)
      ok=$((ok + 1)) ;;
    skipped)
      skipped=$((skipped + 1)); overall_rc=1 ;;
    *)
      failed=$((failed + 1)); overall_rc=1
      echo "Aborting inclusion sequence at slot ${slot} (status=${status})." >&2
      break ;;
  esac
done

# -- verdict -----------------------------------------------------------------

if [ "${overall_rc}" -eq 0 ]; then
  verdict="PASS"
elif [ "${ok}" -gt 0 ]; then
  verdict="PARTIAL"
else
  verdict="FAIL"
fi
echo "${verdict}" > "${verdict_file}"
printf '{"verdict":"%s","total":%d,"ok":%d,"failed":%d,"skipped":%d,"already_included":%d}\n' \
  "${verdict}" "${total}" "${ok}" "${failed}" "${skipped}" "${already}" > "${summary_file}"

echo
echo "Inclusion ${verdict}: ok=${ok} failed=${failed} skipped=${skipped} already=${already} total=${total}"
echo "  CSV:     ${out_csv}"
echo "  verdict: ${verdict_file}"

[ "${verdict}" = "PASS" ] && exit 0
exit 1
