#!/usr/bin/env bash
# tests/run.sh - Standalone Automated Test Suite Runner (PRD Section 6.3.1)
# Executes all functional test suites and exits with an exit status equal to
# the number of failed test files (0 when all pass).

set -u

TESTS_DIR=$(builtin cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)

shopt -s nullglob
suite_files=("$TESTS_DIR"/suites/*.sh)
shopt -u nullglob

if (( ${#suite_files[@]} == 0 )); then
  printf 'Error: no test suite files found in %s/suites\n' "$TESTS_DIR" >&2
  exit 1
fi

failed_suites=0
total_suites=${#suite_files[@]}

printf '\033[1mRunning Bash Git Prompt Automated Test Suites (%d suites)...\033[0m\n\n' "$total_suites"

for suite in "${suite_files[@]}"; do
  if ! bash "$suite"; then
    (( ++failed_suites ))
  fi
done

if (( failed_suites == 0 )); then
  printf '\033[1;32mALL %d TEST SUITES PASSED.\033[0m\n' "$total_suites"
else
  printf '\033[1;31m%d OF %d TEST SUITES FAILED.\033[0m\n' "$failed_suites" "$total_suites" >&2
fi

exit "$failed_suites"
