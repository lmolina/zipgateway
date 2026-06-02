# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
# SPDX-License-Identifier: LicenseRef-MSLA
#
# ST-02 false-dead bucketing (used by st02_analyze.sh).
#
# Read st02_events.csv from the tailer; bucket false_dead rows per node per
# 24 h window; print a line-oriented report for the shell wrapper to parse.
#
# Usage:
#   awk -F, -v maxfd=1 -f st02_bucket.awk /path/to/st02_events.csv
#
# Input CSV columns (comma-separated; raw_event is last and quoted):
#   event_iso,probe_iso,nodeid,mdns,target,status,raw_event
# Fields used: $1=event_iso, $3=nodeid, $6=status (raw_event is $7+).
#
# Output lines (stdout):
#   TOTAL <n>           total data rows
#   FD <n>              false_dead count
#   TD <n>              true_dead count
#   NP <n>              noparse count
#   NR <n>              noresolve count
#   NODE <id> <count>   false_dead per node (all windows)
#   OVER <id> <win> <c> bucket over maxfd (verdict FAIL)
#   WORST <id> <win> <c>  worst false_dead bucket (- if none)

BEGIN {
  if (maxfd == "") maxfd = 1
}

function iso_to_epoch(s,   n, t) {
  # event_iso like 2026-06-02T11:44:07.123Z or ...+0200
  gsub(/[TZ]/, " ", s)
  sub(/\..*/, "", s)
  sub(/[+-][0-9][0-9]:?[0-9][0-9]$/, "", s)
  n = split(s, p, /[- :]+/)
  if (n < 6) return -1
  t = sprintf("%04d %02d %02d %02d %02d %02d",
              p[1], p[2], p[3], p[4], p[5], p[6])
  return mktime(t)
}

NR == 1 { next }

{
  total++
  status = $6
  if (status == "false_dead") {
    fd_total++
  } else if (status == "true_dead") {
    td_total++
    next
  } else if (status == "noparse") {
    np_total++
    next
  } else if (status == "noresolve") {
    nr_total++
    next
  } else {
    next
  }

  ev = iso_to_epoch($1)
  node = $3
  if (ev < 0 || node == "") {
    skipped++
    next
  }
  if (t0 == "") t0 = ev
  win = int((ev - t0) / 86400)
  key = node SUBSEP win
  bucket[key]++
  nodefd[node]++
  seen_node[node] = 1
}

END {
  print "TOTAL", total + 0
  print "FD", fd_total + 0
  print "TD", td_total + 0
  print "NP", np_total + 0
  print "NR", nr_total + 0

  for (node_id in seen_node)
    print "NODE", node_id, nodefd[node_id] + 0

  wc = 0
  wn = "-"
  ww = "-"
  for (k in bucket) {
    split(k, a, SUBSEP)
    c = bucket[k]
    if (c > wc) {
      wc = c
      wn = a[1]
      ww = a[2]
    }
    if (c > maxfd)
      print "OVER", a[1], a[2], c
  }
  print "WORST", wn, ww, wc
}
