#!/usr/bin/env bash
# tests/benchmark-compare.sh - Benchmark Comparison CLI (PRD Section 6.3.3)
#
# Usage:
#   ./tests/benchmark-compare.sh                 # Compare latest two runs
#   ./tests/benchmark-compare.sh --list          # List all recorded runs (1-based index, timestamp, commit)
#   ./tests/benchmark-compare.sh --all           # Full historical matrix of averages & run-over-run deltas
#   ./tests/benchmark-compare.sh <run_A> [<run_B>] # Compare 1-based run_A vs run_B (defaults run_B to latest)

set -u

TESTS_DIR=$(builtin cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RESULTS_FILE=${BENCHMARK_RESULTS_FILE:-"${TESTS_DIR}/benchmark-results.tsv"}

if [[ ! -f $RESULTS_FILE || ! -r $RESULTS_FILE ]]; then
  printf 'Error: benchmark results file not found at %s (run ./tests/benchmark.sh first).\n' "$RESULTS_FILE" >&2
  exit 1
fi

MODE="compare"
RUN_A=""
RUN_B=""

if (( $# == 0 )); then
  MODE="compare_latest"
elif [[ $1 == "--list" ]]; then
  MODE="list"
elif [[ $1 == "--all" ]]; then
  MODE="all"
elif [[ $1 =~ ^[0-9]+$ && $1 -gt 0 ]]; then
  MODE="compare_explicit"
  RUN_A=$1
  if (( $# >= 2 )); then
    if [[ $2 =~ ^[0-9]+$ && $2 -gt 0 ]]; then
      RUN_B=$2
    else
      printf 'Error: invalid run index: %s\n' "$2" >&2
      exit 1
    fi
  fi
else
  printf 'Usage: %s [--list | --all | <run_A> [<run_B>]]\n' "$0" >&2
  exit 1
fi

LC_ALL=C awk -F'\t' \
  -v mode="$MODE" \
  -v req_a="$RUN_A" \
  -v req_b="$RUN_B" '
  BEGIN {
    run_count = 0
    op_count = 0
    GREEN = "\033[0;32m"
    RED   = "\033[0;31m"
    RESET = "\033[0m"
  }
  NR == 1 && $1 == "timestamp" { next }
  NF >= 7 {
    ts = $1
    sha = $2
    iters = $3
    op = $4
    min_v = $5 + 0.0
    avg_v = $6 + 0.0
    max_v = $7 + 0.0

    key = ts "|" sha
    if (!(key in run_idx_by_key)) {
      run_count++
      run_idx_by_key[key] = run_count
      run_ts[run_count] = ts
      run_sha[run_count] = sha
      run_iters[run_count] = iters
    }
    r = run_idx_by_key[key]

    if (!(op in op_idx_by_name)) {
      op_count++
      op_idx_by_name[op] = op_count
      op_name[op_count] = op
    }
    o = op_idx_by_name[op]

    cell_min[r, o] = min_v
    cell_avg[r, o] = avg_v
    cell_max[r, o] = max_v
    has_cell[r, o] = 1
  }
  function fmt_delta(a, b,    diff, pct, sign, col) {
    if (a <= 0) {
      return "   0.0%"
    }
    diff = b - a
    pct = (diff / a) * 100.0
    if (pct < -0.05) {
      col = GREEN
      return sprintf("%s%+6.1f%%%s", col, pct, RESET)
    } else if (pct > 0.05) {
      col = RED
      return sprintf("%s%+6.1f%%%s", col, pct, RESET)
    } else {
      return "   0.0%"
    }
  }
  END {
    if (run_count == 0) {
      print "Error: no benchmark runs recorded." > "/dev/stderr"
      exit 1
    }

    if (mode == "list") {
      printf "%-6s  %-22s  %-12s  %s\n", "Run #", "Timestamp (UTC)", "Commit SHA", "Iterations"
      printf "----------------------------------------------------------\n"
      for (r = 1; r <= run_count; r++) {
        printf "%-6d  %-22s  %-12s  %s\n", r, run_ts[r], run_sha[r], run_iters[r]
      }
      exit 0
    }

    if (mode == "all") {
      printf "Historical Benchmark Matrix (%d runs)\n", run_count
      printf "================================================================================\n"
      printf "%-36s", "Operation"
      for (r = 1; r <= run_count; r++) {
        printf " | #%d %s", r, run_sha[r]
      }
      printf "\n--------------------------------------------------------------------------------\n"
      for (o = 1; o <= op_count; o++) {
        printf "%-36s", op_name[o]
        for (r = 1; r <= run_count; r++) {
          if (r == 1) {
            printf " | %6.1f ms", cell_avg[r, o]
          } else {
            printf " | %6.1f ms (%s)", cell_avg[r, o], fmt_delta(cell_avg[r-1, o], cell_avg[r, o])
          }
        }
        printf "\n"
      }
      exit 0
    }

    if (mode == "compare_latest") {
      if (run_count < 2) {
        print "Error: at least 2 recorded benchmark runs are required for comparison." > "/dev/stderr"
        exit 1
      }
      idx_a = run_count - 1
      idx_b = run_count
    } else {
      idx_a = req_a + 0
      idx_b = (req_b != "") ? (req_b + 0) : run_count
      if (idx_a < 1 || idx_a > run_count || idx_b < 1 || idx_b > run_count) {
        printf "Error: run indices out of range (1..%d).\n", run_count > "/dev/stderr"
        exit 1
      }
    }

    printf "Comparing Run #%d (%s @ %s) vs Run #%d (%s @ %s)\n", \
      idx_a, run_sha[idx_a], run_ts[idx_a], idx_b, run_sha[idx_b], run_ts[idx_b]
    printf "==============================================================================\n"
    printf "%-36s %10s %10s %10s %10s\n", "Operation", "A avg", "B avg", "B min", "Delta"
    printf "------------------------------------------------------------------------------\n"
    for (o = 1; o <= op_count; o++) {
      a_avg = cell_avg[idx_a, o]
      b_avg = cell_avg[idx_b, o]
      b_min = cell_min[idx_b, o]
      printf "%-36s %8.1fms %8.1fms %8.1fms   %s\n", \
        op_name[o], a_avg, b_avg, b_min, fmt_delta(a_avg, b_avg)
    }
    printf "==============================================================================\n"
  }
' "$RESULTS_FILE"
