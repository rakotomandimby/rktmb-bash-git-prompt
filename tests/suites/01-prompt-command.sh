#!/usr/bin/env bash
# tests/suites/01-prompt-command.sh - Lifecycle, PROMPT_COMMAND hooks, signals, and symlink resolution

source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
test_suite_begin "01 - Shell Lifecycle, PROMPT_COMMAND & Signal Formatting"

# 1. PROMPT_COMMAND starting unset
test_case "Installs hooks cleanly when PROMPT_COMMAND starts unset"
(
  unset -v PROMPT_COMMAND __GIT_PROMPT_DIR
  source "${REPO_ROOT}/gitprompt.sh"
  assert_eq "__gp_capture_exit_status; __gp_update_prompt" "$PROMPT_COMMAND"
) && pass_case

# 2. Scalar PROMPT_COMMAND with messy formatting and exit status preservation
test_case "Preserves scalar PROMPT_COMMAND hooks, normalizes formatting, and propagates exit status"
(
  unset -v __GIT_PROMPT_DIR
  OBSERVED_BY_USER_HOOK=-1
  my_user_hook() { OBSERVED_BY_USER_HOOK=$?; }
  PROMPT_COMMAND=$' ; \n my_user_hook ; \n ; '
  source "${REPO_ROOT}/gitprompt.sh"
  assert_eq "__gp_capture_exit_status; my_user_hook; __gp_update_prompt" "$PROMPT_COMMAND"

  # Source a second time to verify idempotency
  source "${REPO_ROOT}/gitprompt.sh"
  assert_eq "__gp_capture_exit_status; my_user_hook; __gp_update_prompt" "$PROMPT_COMMAND"

  run_prompt_cycle 42
  assert_eq "42" "$OBSERVED_BY_USER_HOOK" "User hook must observe original exit code 42"
  assert_contains "$PS1" "✘-42" "Prompt must render exit status 42"
) && pass_case

# 3. Bash 5+ Indexed Array PROMPT_COMMAND
test_case "Supports Bash 5+ indexed array PROMPT_COMMAND and preserves ordering & exit status"
(
  unset -v __GIT_PROMPT_DIR
  HOOK1_RC=-1
  HOOK2_RC=-1
  ORDER_TRACE=""
  hook_one() { HOOK1_RC=$?; ORDER_TRACE+="1"; (exit "$HOOK1_RC"); }
  hook_two() { HOOK2_RC=$?; ORDER_TRACE+="2"; }
  PROMPT_COMMAND=("hook_one" "" "hook_two")
  source "${REPO_ROOT}/gitprompt.sh"

  assert_eq "4" "${#PROMPT_COMMAND[@]}"
  assert_eq "__gp_capture_exit_status" "${PROMPT_COMMAND[0]}"
  assert_eq "hook_one" "${PROMPT_COMMAND[1]}"
  assert_eq "hook_two" "${PROMPT_COMMAND[2]}"
  assert_eq "__gp_update_prompt" "${PROMPT_COMMAND[3]}"

  # Idempotent reload on array PROMPT_COMMAND
  source "${REPO_ROOT}/gitprompt.sh"
  assert_eq "4" "${#PROMPT_COMMAND[@]}"

  run_prompt_cycle 17
  assert_eq "12" "$ORDER_TRACE"
  assert_eq "17" "$HOOK1_RC"
  assert_eq "17" "$HOOK2_RC"
  assert_contains "$PS1" "✘-17"
) && pass_case

# 4. Signal formatting (> 128) and normal exit codes (0..128)
test_case "Formats exit codes 0..128 as numbers and >128 as OS signal names"
(
  source "${REPO_ROOT}/gitprompt.sh"
  assert_eq "0" "$(gp_format_exit_status 0)"
  assert_eq "1" "$(gp_format_exit_status 1)"
  assert_eq "127" "$(gp_format_exit_status 127)"
  assert_eq "128" "$(gp_format_exit_status 128)"
  assert_eq "HUP" "$(gp_format_exit_status 129)"
  assert_eq "INT" "$(gp_format_exit_status 130)"
  assert_eq "KILL" "$(gp_format_exit_status 137)"
  assert_eq "PIPE" "$(gp_format_exit_status 141)"
  assert_eq "TERM" "$(gp_format_exit_status 143)"
  assert_eq "999" "$(gp_format_exit_status 999)"

  run_prompt_cycle 130
  assert_contains "$PS1" "✘-INT"
  run_prompt_cycle 0
  assert_contains "$PS1" "✔"
) && pass_case

# 5. Symlinked installation path resolution & __GIT_PROMPT_DIR override
test_case "Resolves symlinked gitprompt.sh path and honors explicit __GIT_PROMPT_DIR"
(
  unset -v __GIT_PROMPT_DIR
  ln -s "${REPO_ROOT}/gitprompt.sh" "${TEST_SANDBOX}/symlinked-gitprompt.sh"
  source "${TEST_SANDBOX}/symlinked-gitprompt.sh"
  assert_eq "$REPO_ROOT" "$__GIT_PROMPT_DIR"
) && pass_case

# 6. Shell option hygiene (noglob set -f scoped locally)
test_case "Does not pollute interactive shell options (such as noglob)"
(
  set +f
  source "${REPO_ROOT}/gitprompt.sh"
  run_prompt_cycle 0
  [[ $- != *f* ]] || { fail_case "noglob (-f) leaked into interactive shell"; exit 1; }
) && pass_case

test_suite_end
