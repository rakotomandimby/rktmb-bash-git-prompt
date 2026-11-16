#!/usr/bin/env bash
# tests/suites/04-worktrees-stash.sh - Linked Git worktrees, shared stash counting, and ignore-stash

source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
test_suite_begin "04 - Linked Git Worktrees & Stash Inspection"

MAIN_REPO="${TEST_SANDBOX}/main-repo"
LINKED_WT="${TEST_SANDBOX}/linked-wt"
mkdir -p "$MAIN_REPO"
git init -q -b main "$MAIN_REPO"
cd "$MAIN_REPO"
echo "hello" > a.txt
git add a.txt && git commit -q -m "initial"

# Create 2 stash entries in main repository
echo "stash1" >> a.txt
git stash push -q -m "s1"
echo "stash2" >> a.txt
git stash push -q -m "s2"

# Add a linked worktree
git worktree add -q "$LINKED_WT" -b wt-feature

GIT_PROMPT_FETCH_REMOTE_STATUS=0
source "${REPO_ROOT}/gitprompt.sh"

# 1. Shared stash count inside main repository and linked worktree
test_case "Accurately counts shared stash entries inside both main repo and linked worktree"
(
  cd "$MAIN_REPO"
  run_prompt_cycle 0
  assert_eq "2" "$__GP_STATUS_STASHED"
  assert_eq "0" "$__GP_STATUS_CLEAN"
  assert_contains "$PS1" "⚑ 2"

  cd "$LINKED_WT"
  run_prompt_cycle 0
  assert_eq "wt-feature" "$GIT_BRANCH"
  assert_eq "2" "$__GP_STATUS_STASHED" "Linked worktree must report shared stash count of 2"
  assert_eq "0" "$__GP_STATUS_CLEAN"
  assert_contains "$PS1" "⚑ 2"
) && pass_case

# 2. GIT_PROMPT_IGNORE_STASH=1
test_case "Skips stash counting when GIT_PROMPT_IGNORE_STASH=1 and marks clean worktree as clean"
(
  cd "$LINKED_WT"
  GIT_PROMPT_IGNORE_STASH=1
  run_prompt_cycle 0
  assert_eq "0" "$__GP_STATUS_STASHED"
  assert_eq "1" "$__GP_STATUS_CLEAN"
  assert_not_contains "$PS1" "⚑"
  assert_contains "$PS1" "✔"
) && pass_case

# 3. Common git-dir resolution inside linked worktree
test_case "Resolves shared common Git directory inside linked worktree for fetch tracking"
(
  cd "$LINKED_WT"
  __gp_discover_repo
  main_git_dir=$(cd "$MAIN_REPO" && git rev-parse --git-common-dir)
  wt_common_dir=$(cd "$LINKED_WT" && builtin cd -P "$__GP_GIT_COMMON_DIR" && pwd)
  main_abs_dir=$(cd "$MAIN_REPO" && builtin cd -P "$main_git_dir" && pwd)
  assert_eq "$main_abs_dir" "$wt_common_dir"
) && pass_case

test_suite_end
