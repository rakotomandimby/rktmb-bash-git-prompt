#!/usr/bin/env bash
# tests/suites/02-only-in-repo.sh - Operating modes outside/inside Git repos & stateful PS1 restoration

source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
test_suite_begin "02 - GIT_PROMPT_ONLY_IN_REPO, Toggle, Disable & COPILOT_AGENT"

REPO_A="${TEST_SANDBOX}/repo-a"
REPO_B="${TEST_SANDBOX}/repo-b"
NON_REPO="${TEST_SANDBOX}/plain-dir"
mkdir -p "$REPO_A/sub/deep" "$REPO_B" "$NON_REPO"
git init -q -b main "$REPO_A"
git -C "$REPO_A" commit --allow-empty -q -m "initial"
git init -q -b develop "$REPO_B"
git -C "$REPO_B" commit --allow-empty -q -m "initial b"

# 1. GIT_PROMPT_ONLY_IN_REPO=1 starting outside a Git repository
test_case "Preserves original PS1 outside repos, activates inside repos, and restores verbatim on exit"
(
  cd "$NON_REPO"
  PS1='ORIG_PROMPT:\w\$ '
  GIT_PROMPT_ONLY_IN_REPO=1
  GIT_PROMPT_FETCH_REMOTE_STATUS=0
  source "${REPO_ROOT}/gitprompt.sh"

  run_prompt_cycle 0
  assert_eq 'ORIG_PROMPT:\w\$ ' "$PS1" "PS1 must remain untouched outside repo"
  assert_eq "" "${GIT_BRANCH-}" "GIT_BRANCH must be unset outside repo"

  # Navigate into REPO_A nested directory
  cd "$REPO_A/sub/deep"
  run_prompt_cycle 0
  assert_ne 'ORIG_PROMPT:\w\$ ' "$PS1" "PS1 must activate inside Git repo"
  assert_contains "$PS1" "main"
  assert_eq "main" "${GIT_BRANCH-}"

  # Navigate directly to REPO_B
  cd "$REPO_B"
  run_prompt_cycle 0
  assert_contains "$PS1" "develop"
  assert_eq "develop" "${GIT_BRANCH-}"

  # Navigate back out to NON_REPO
  cd "$NON_REPO"
  run_prompt_cycle 0
  assert_eq 'ORIG_PROMPT:\w\$ ' "$PS1" "Original PS1 must be restored verbatim upon leaving repo"
  assert_eq "" "${GIT_BRANCH-}" "GIT_BRANCH must be unset upon leaving repo"
) && pass_case

# 2. Starting already inside a Git repository with GIT_PROMPT_ONLY_IN_REPO=1
test_case "Restores original pre-Git PS1 even when session starts inside a Git repository"
(
  cd "$REPO_A"
  PS1='STARTED_IN_REPO:\u\$ '
  GIT_PROMPT_ONLY_IN_REPO=1
  GIT_PROMPT_FETCH_REMOTE_STATUS=0
  source "${REPO_ROOT}/gitprompt.sh"

  run_prompt_cycle 0
  assert_contains "$PS1" "main"

  cd "$NON_REPO"
  run_prompt_cycle 0
  assert_eq 'STARTED_IN_REPO:\u\$ ' "$PS1"
) && pass_case

# 3. Runtime toggle (git_prompt_toggle), GIT_PROMPT_DISABLE, COPILOT_AGENT=1, and GIT_PROMPT_IGNORE=1
test_case "Restores original PS1 in ONLY_IN_REPO=1 mode when toggled off, COPILOT_AGENT=1, or ignored"
(
  cd "$REPO_A"
  PS1='CUSTOM_BASE> '
  GIT_PROMPT_ONLY_IN_REPO=1
  GIT_PROMPT_FETCH_REMOTE_STATUS=0
  source "${REPO_ROOT}/gitprompt.sh"

  run_prompt_cycle 0
  assert_contains "$PS1" "main"

  # Toggle off
  git_prompt_toggle
  assert_eq "1" "$GIT_PROMPT_DISABLE"
  run_prompt_cycle 0
  assert_eq 'CUSTOM_BASE> ' "$PS1"
  assert_eq "" "${GIT_BRANCH-}"

  # Toggle back on
  git_prompt_toggle
  assert_eq "0" "$GIT_PROMPT_DISABLE"
  run_prompt_cycle 0
  assert_contains "$PS1" "main"

  # COPILOT_AGENT=1 bypass
  COPILOT_AGENT=1
  run_prompt_cycle 0
  assert_eq 'CUSTOM_BASE> ' "$PS1"
  COPILOT_AGENT=0
  run_prompt_cycle 0
  assert_contains "$PS1" "main"

  # Per-repo .bash-git-rc GIT_PROMPT_IGNORE=1
  printf 'GIT_PROMPT_IGNORE=1\n' > "$REPO_A/.bash-git-rc"
  run_prompt_cycle 0
  assert_eq 'CUSTOM_BASE> ' "$PS1"
  rm -f "$REPO_A/.bash-git-rc"
  run_prompt_cycle 0
  assert_contains "$PS1" "main"
) && pass_case

test_suite_end
