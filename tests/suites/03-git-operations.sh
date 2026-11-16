#!/usr/bin/env bash
# tests/suites/03-git-operations.sh - In-progress rebase/merge/cherry-pick/revert/bisect & temp hygiene

source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
test_suite_begin "03 - In-Progress Git Operations, Rebase Safety & Temp Hygiene"

REPO="${TEST_SANDBOX}/op-repo"
mkdir -p "$REPO"
git init -q -b feature "$REPO"
cd "$REPO"

echo "line1" > file.txt
git add file.txt && git commit -q -m "c1"
echo "line2" >> file.txt
git add file.txt && git commit -q -m "c2"
echo "line3" >> file.txt
git add file.txt && git commit -q -m "c3"

GIT_PROMPT_FETCH_REMOTE_STATUS=0
source "${REPO_ROOT}/gitprompt.sh"

# 1. Real interactive rebase paused on 'edit'
test_case "Displays |REBASE-i <step>/<total>, leaves zero temp files, does not disrupt rebase, and clears after completion"
(
  # Pause interactive rebase on first commit using GIT_SEQUENCE_EDITOR
  GIT_SEQUENCE_EDITOR='sed -i "1s/^pick/edit/"' git rebase -i HEAD~2 >/dev/null 2>&1
  run_prompt_cycle 0

  assert_eq "feature|REBASE-i 1/2" "$GIT_BRANCH"
  assert_contains "$PS1" "feature|REBASE-i 1/2"
  assert_empty_dir "$TMPDIR" "Prompt evaluation during rebase must leave zero temporary files in TMPDIR"

  # Ensure git rebase --continue succeeds without lock or state corruption
  git rebase --continue >/dev/null 2>&1
  run_prompt_cycle 0
  assert_eq "feature" "$GIT_BRANCH"
  assert_not_contains "$PS1" "REBASE"
  assert_empty_dir "$TMPDIR"
) && pass_case

# 2. All other multi-step and paused Git operation suffixes (PRD Section 3.4.4)
test_case "Detects REBASE-m, REBASE, AM, AM/REBASE, MERGING, CHERRY-PICKING, REVERTING, and BISECTING"
(
  gdir=$(git rev-parse --git-dir)

  # REBASE-m 2/4
  mkdir -p "$gdir/rebase-merge"
  printf 'refs/heads/feature\n' > "$gdir/rebase-merge/head-name"
  printf '2\n' > "$gdir/rebase-merge/msgnum"
  printf '4\n' > "$gdir/rebase-merge/end"
  run_prompt_cycle 0
  assert_eq "feature|REBASE-m 2/4" "$GIT_BRANCH"
  rm -rf "$gdir/rebase-merge"

  # REBASE (apply backend) 1/3
  mkdir -p "$gdir/rebase-apply"
  touch "$gdir/rebase-apply/rebasing"
  printf 'refs/heads/feature\n' > "$gdir/rebase-apply/head-name"
  printf '1\n' > "$gdir/rebase-apply/next"
  printf '3\n' > "$gdir/rebase-apply/last"
  run_prompt_cycle 0
  assert_eq "feature|REBASE 1/3" "$GIT_BRANCH"
  rm -rf "$gdir/rebase-apply"

  # AM 1/2
  mkdir -p "$gdir/rebase-apply"
  touch "$gdir/rebase-apply/applying"
  printf '1\n' > "$gdir/rebase-apply/next"
  printf '2\n' > "$gdir/rebase-apply/last"
  run_prompt_cycle 0
  assert_eq "feature|AM 1/2" "$GIT_BRANCH"
  rm -rf "$gdir/rebase-apply"

  # Combined/ambiguous AM/REBASE
  mkdir -p "$gdir/rebase-apply"
  printf '2\n' > "$gdir/rebase-apply/next"
  printf '5\n' > "$gdir/rebase-apply/last"
  run_prompt_cycle 0
  assert_eq "feature|AM/REBASE 2/5" "$GIT_BRANCH"
  rm -rf "$gdir/rebase-apply"

  # MERGING
  touch "$gdir/MERGE_HEAD"
  run_prompt_cycle 0
  assert_eq "feature|MERGING" "$GIT_BRANCH"
  rm -f "$gdir/MERGE_HEAD"

  # CHERRY-PICKING
  touch "$gdir/CHERRY_PICK_HEAD"
  run_prompt_cycle 0
  assert_eq "feature|CHERRY-PICKING" "$GIT_BRANCH"
  rm -f "$gdir/CHERRY_PICK_HEAD"

  # REVERTING
  touch "$gdir/REVERT_HEAD"
  run_prompt_cycle 0
  assert_eq "feature|REVERTING" "$GIT_BRANCH"
  rm -f "$gdir/REVERT_HEAD"

  # BISECTING
  touch "$gdir/BISECT_LOG"
  run_prompt_cycle 0
  assert_eq "feature|BISECTING" "$GIT_BRANCH"
  rm -f "$gdir/BISECT_LOG"

  run_prompt_cycle 0
  assert_eq "feature" "$GIT_BRANCH"
) && pass_case

# 3. External GIT_INDEX_FILE preservation and corrupted index fallback
test_case "Honors external GIT_INDEX_FILE without mutating it and falls back cleanly on corrupt index"
(
  custom_idx="${TEST_SANDBOX}/custom.index"
  cp "$(git rev-parse --git-dir)/index" "$custom_idx"
  export GIT_INDEX_FILE="$custom_idx"
  echo "staged_only_in_custom" > staged_custom.txt
  git add staged_custom.txt

  run_prompt_cycle 0
  assert_eq "$custom_idx" "$GIT_INDEX_FILE"
  assert_contains "$PS1" "● 1"

  # Corrupt the custom index file and confirm graceful fallback with zero stderr output
  printf 'CORRUPT_INDEX_BYTES' > "$custom_idx"
  err_out=$(run_prompt_cycle 0 2>&1)
  assert_eq "" "$err_out" "Corrupted repository metadata must not print raw tracebacks"
  unset -v GIT_INDEX_FILE
  rm -f staged_custom.txt "$custom_idx"
) && pass_case

test_suite_end
