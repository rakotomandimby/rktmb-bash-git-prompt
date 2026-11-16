# shellcheck shell=bash
# tests/lib/harness.sh - Pure-Bash 5 test sandbox & assertion helpers

set -u

declare -g __TEST_SUITE_NAME=""
declare -g __TEST_PASSED=0
declare -g __TEST_FAILED=0
declare -g __TEST_CURRENT=""
declare -g TEST_SANDBOX=""
declare -g REPO_ROOT=""

REPO_ROOT=$(builtin cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

test_suite_begin() {
  __TEST_SUITE_NAME=${1:-"Unnamed Suite"}
  TEST_SANDBOX=$(command mktemp -d "${TMPDIR:-/tmp}/bgp-test.XXXXXX")
  export HOME="${TEST_SANDBOX}/home"
  export TMPDIR="${TEST_SANDBOX}/tmp"
  command mkdir -p "$HOME" "$TMPDIR"

  # Isolated deterministic Git identity
  export GIT_AUTHOR_NAME="Test User"
  export GIT_AUTHOR_EMAIL="test@example.com"
  export GIT_COMMITTER_NAME="Test User"
  export GIT_COMMITTER_EMAIL="test@example.com"
  export GIT_CONFIG_NOSYSTEM=1
  git config --global init.defaultBranch main 2>/dev/null || true
  git config --global user.name "Test User"
  git config --global user.email "test@example.com"
  git config --global protocol.file.allow always

  printf '\033[1;34m==> Suite: %s\033[0m\n' "$__TEST_SUITE_NAME"
}

test_case() {
  __TEST_CURRENT=$1
}

pass_case() {
  (( ++__TEST_PASSED ))
  printf '  \033[0;32m✔\033[0m %s\n' "$__TEST_CURRENT"
}

fail_case() {
  local reason=${1:-"Assertion failed"}
  (( ++__TEST_FAILED ))
  if [[ -n ${TEST_SANDBOX:-} && -d $TEST_SANDBOX ]]; then
    printf '1\n' >> "${TEST_SANDBOX}/.failed_assertions"
  fi
  printf '  \033[0;31m✘ %s\033[0m\n    Reason: %s\n' "$__TEST_CURRENT" "$reason" >&2
  if (( BASH_SUBSHELL > 0 )); then
    exit 1
  fi
}

assert_eq() {
  local expected=$1
  local actual=$2
  local msg=${3:-"Expected '$expected', got '$actual'"}
  if [[ $actual == "$expected" ]]; then
    return 0
  else
    fail_case "$msg (expected=[$expected], actual=[$actual])"
    return 1
  fi
}

assert_ne() {
  local unexpected=$1
  local actual=$2
  local msg=${3:-"Expected value different from '$unexpected'"}
  if [[ $actual != "$unexpected" ]]; then
    return 0
  else
    fail_case "$msg (actual=[$actual])"
    return 1
  fi
}

assert_contains() {
  local haystack=$1
  local needle=$2
  local msg=${3:-"Expected string to contain '$needle'"}
  if [[ $haystack == *"$needle"* ]]; then
    return 0
  else
    fail_case "$msg (haystack=[$haystack], missing=[$needle])"
    return 1
  fi
}

assert_not_contains() {
  local haystack=$1
  local needle=$2
  local msg=${3:-"Expected string NOT to contain '$needle'"}
  if [[ $haystack != *"$needle"* ]]; then
    return 0
  else
    fail_case "$msg (haystack=[$haystack], unwanted=[$needle])"
    return 1
  fi
}

assert_empty_dir() {
  local dir=$1
  local msg=${2:-"Expected directory '$dir' to contain zero leftover files"}
  local -a entries=()
  shopt -s nullglob dotglob
  entries=("$dir"/*)
  shopt -u nullglob dotglob
  if (( ${#entries[@]} == 0 )); then
    return 0
  else
    fail_case "$msg (found: ${entries[*]})"
    return 1
  fi
}

# Simulates Bash executing PROMPT_COMMAND after a user command exits with <exit_code>
run_prompt_cycle() {
  local simulated_exit=${1:-0}
  local decl
  decl=$(declare -p PROMPT_COMMAND 2>/dev/null || true)
  if [[ $decl == "declare -a"* ]]; then
    local cmd
    (exit "$simulated_exit")
    for cmd in "${PROMPT_COMMAND[@]}"; do
      eval "$cmd"
    done
  else
    (exit "$simulated_exit")
    eval "${PROMPT_COMMAND-}"
  fi
}

test_suite_end() {
  if [[ -n ${TEST_SANDBOX:-} && -f "${TEST_SANDBOX}/.failed_assertions" ]]; then
    local sub_fails
    sub_fails=$(wc -l < "${TEST_SANDBOX}/.failed_assertions")
    __TEST_FAILED=$(( __TEST_FAILED + sub_fails ))
  fi
  if [[ -n ${TEST_SANDBOX:-} && -d $TEST_SANDBOX ]]; then
    command rm -rf "$TEST_SANDBOX"
  fi
  printf '  Summary: %d passed, %d failed\n\n' "$__TEST_PASSED" "$__TEST_FAILED"
  (( __TEST_FAILED == 0 ))
}
