#!/usr/bin/env bash
# tests/suites/08-security-rc-fetch.sh - .bash-git-rc security/scoping, untrusted repo safety & async fetch

source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
test_suite_begin "08 - Security, .bash-git-rc Validation/Scoping & Asynchronous Fetch"

REPO_ONE="${TEST_SANDBOX}/repo-one"
REPO_TWO="${TEST_SANDBOX}/repo-two"
git init -q -b main "$REPO_ONE"
git -C "$REPO_ONE" commit --allow-empty -q -m "c1"
git init -q -b main "$REPO_TWO"
git -C "$REPO_TWO" commit --allow-empty -q -m "c2"

GIT_PROMPT_FETCH_REMOTE_STATUS=0
source "${REPO_ROOT}/gitprompt.sh"

# 1. Valid .bash-git-rc scoping (no leakage to other repos)
test_case "Applies valid .bash-git-rc settings locally to that repo without leaking into other repos"
(
  touch "$REPO_ONE/untracked_a.txt" "$REPO_TWO/untracked_b.txt"
  printf 'GIT_PROMPT_SHOW_UNTRACKED_FILES=no\nGIT_PROMPT_SHOW_TRACKING=0\n' > "$REPO_ONE/.bash-git-rc"

  cd "$REPO_ONE"
  run_prompt_cycle 0
  assert_eq "0" "$__GP_STATUS_UNTRACKED" "Repo one .bash-git-rc must suppress untracked scan"
  assert_eq "normal" "${GIT_PROMPT_SHOW_UNTRACKED_FILES:-normal}" "Global variable must remain untouched"

  cd "$REPO_TWO"
  run_prompt_cycle 0
  assert_eq "1" "$__GP_STATUS_UNTRACKED" "Repo two must use session default (normal) without leakage"
) && pass_case

# 2. Invalid .bash-git-rc rejection (never executes commands, rejects entire file on any bad line)
test_case "Rejects invalid .bash-git-rc files completely without executing arbitrary code"
(
  pwn_marker="${TEST_SANDBOX}/rc_pwned"
  cat << EOF > "$REPO_ONE/.bash-git-rc"
GIT_PROMPT_SHOW_UNTRACKED_FILES=no
FETCH_REMOTE_STATUS=\$(touch "$pwn_marker")
EOF

  cd "$REPO_ONE"
  err_file="${TEST_SANDBOX}/rc_err.log"
  run_prompt_cycle 0 2>"$err_file"
  warn_msg=$(<"$err_file")
  [[ ! -e $pwn_marker ]] || { fail_case ".bash-git-rc executed command substitution!"; exit 1; }
  assert_contains "$warn_msg" "NAME=value declarations"

  # Verify the valid first line (GIT_PROMPT_SHOW_UNTRACKED_FILES=no) was ALSO rejected
  # because line 2 failed validation (both untracked_a.txt and .bash-git-rc are counted)
  assert_eq "2" "$__GP_STATUS_UNTRACKED" "Entire invalid .bash-git-rc file must be ignored"
  rm -f "$REPO_ONE/.bash-git-rc"
) && pass_case

# 3. Untrusted branch names, directory names, and virtualenv names with $(...), `...`, $VAR, *, ?, [...], &
test_case "Renders crafted branch, path, and virtualenv names safely without command execution or glob expansion"
(
  pwn_branch_marker="${TEST_SANDBOX}/branch_pwned"
  evil_helper="${TEST_SANDBOX}/pwn.sh"
  printf '#!/usr/bin/env bash\ntouch "%s"\n' "$pwn_branch_marker" > "$evil_helper"
  chmod +x "$evil_helper"
  export PATH="${TEST_SANDBOX}:${PATH}"

  evil_dir="${TEST_SANDBOX}/dir-\$(pwn.sh)-\`pwn.sh\`-&-*"
  git init -q -b 'feat/$(pwn.sh)`pwn.sh`$HOME&' "$evil_dir"
  cd "$evil_dir"
  git commit --allow-empty -q -m "evil"

  export VIRTUAL_ENV="/tmp/venv-\$(pwn.sh)&*"
  GIT_PROMPT_THEME="Minimal"
  shopt -s promptvars
  run_prompt_cycle 0

  # Expand PS1 using Bash's exact prompt expansion (@P)
  expanded_ps1="${PS1@P}"
  [[ ! -e $pwn_branch_marker ]] || { fail_case "Command substitution inside PS1 was executed during @P expansion!"; exit 1; }
  assert_contains "$expanded_ps1" '$(pwn.sh)'
  assert_contains "$expanded_ps1" '$HOME&'
) && pass_case || fail_case "Test subshell failed"

# 4. Asynchronous periodic remote fetch & missing file-age capability fallback
test_case "Performs non-blocking background remote fetch when stale and handles missing file-age capability once"
(
  remote_bare="${TEST_SANDBOX}/async-remote.git"
  clone_dir="${TEST_SANDBOX}/async-clone"
  git init -q --bare -b main "$remote_bare"
  git clone -q "$remote_bare" "$clone_dir" 2>/dev/null
  cd "$clone_dir"
  git commit --allow-empty -q -m "c1"
  git push -q -u origin main

  # Set FETCH_HEAD mtime to 10 minutes ago (> default 5 min timeout)
  fetch_head="$(git rev-parse --git-common-dir)/FETCH_HEAD"
  touch -d "10 minutes ago" "$fetch_head"

  GIT_PROMPT_FETCH_REMOTE_STATUS=1
  GIT_PROMPT_FETCH_TIMEOUT=5
  err_async="${TEST_SANDBOX}/async.err"
  run_prompt_cycle 0 >"${TEST_SANDBOX}/async.out" 2>"$err_async"
  out_Async="$(<"${TEST_SANDBOX}/async.out")$(<"$err_async")"
  assert_eq "" "$out_Async" "Background fetch must produce zero terminal/job-control output"

  # Missing file-age capability fallback emits one-time warning and sets GIT_PROMPT_FETCH_REMOTE_STATUS=0
  __GP_FORCE_MISSING_FILE_AGE_CAPABILITY=1
  run_prompt_cycle 0 2>"$err_async"
  warn1=$(<"$err_async")
  assert_contains "$warn1" "GIT_PROMPT_FETCH_REMOTE_STATUS=0"
  assert_eq "0" "$GIT_PROMPT_FETCH_REMOTE_STATUS"

  run_prompt_cycle 0 2>"$err_async"
  warn2=$(<"$err_async")
  assert_eq "" "$warn2" "Warning must only be emitted once per session"
) && pass_case

test_suite_end
