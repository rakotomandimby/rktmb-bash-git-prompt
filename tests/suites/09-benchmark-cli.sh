#!/usr/bin/env bash
# tests/suites/09-benchmark-cli.sh - Verification of Latency Benchmark & Comparison CLIs

source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
test_suite_begin "09 - Latency Benchmark & Benchmark Comparison CLIs"

export BENCHMARK_RESULTS_FILE="${TEST_SANDBOX}/bench-results.tsv"

# 1. benchmark.sh --no-save
test_case "Runs benchmark.sh with --no-save without writing TSV file"
(
  out=$("${REPO_ROOT}/tests/benchmark.sh" 2 --no-save)
  assert_contains "$out" "Bash Git Prompt Latency Benchmark"
  assert_contains "$out" "full prompt update"
  [[ ! -f $BENCHMARK_RESULTS_FILE ]] || { fail_case "--no-save must not create TSV file"; exit 1; }
) && pass_case

# 2. benchmark.sh persistent runs & benchmark-compare.sh modes
test_case "Records benchmark runs and compares them via default, --list, --all, and explicit run indices"
(
  "${REPO_ROOT}/tests/benchmark.sh" 2 >/dev/null
  sleep 1
  "${REPO_ROOT}/tests/benchmark.sh" 2 >/dev/null
  [[ -f $BENCHMARK_RESULTS_FILE ]] || { fail_case "Expected TSV file to be created"; exit 1; }

  out_list=$("${REPO_ROOT}/tests/benchmark-compare.sh" --list)
  assert_contains "$out_list" "1"
  assert_contains "$out_list" "2"

  out_cmp=$("${REPO_ROOT}/tests/benchmark-compare.sh")
  assert_contains "$out_cmp" "Comparing Run #1"
  assert_contains "$out_cmp" "A avg"
  assert_contains "$out_cmp" "B avg"
  assert_contains "$out_cmp" "B min"

  out_all=$("${REPO_ROOT}/tests/benchmark-compare.sh" --all)
  assert_contains "$out_all" "Historical Benchmark Matrix"

  out_idx=$("${REPO_ROOT}/tests/benchmark-compare.sh" 1 2)
  assert_contains "$out_idx" "Comparing Run #1"

  out_idx_single=$("${REPO_ROOT}/tests/benchmark-compare.sh" 1)
  assert_contains "$out_idx_single" "Comparing Run #1"
) && pass_case

test_suite_end
