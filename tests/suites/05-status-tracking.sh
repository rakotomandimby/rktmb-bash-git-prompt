#!/usr/bin/env bash
# tests/suites/05-status-tracking.sh - Branch/detached states, remote tracking, URLs, and file counts

source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
test_suite_begin "05 - Branch States, Remote Divergence, Owner/Repo & Status Counts"

GIT_PROMPT_FETCH_REMOTE_STATUS=0
source "${REPO_ROOT}/gitprompt.sh"

# 1. Unborn branch (zero commits)
test_case "Unborn branch displays branch name, L remote symbol, and suppresses _USERNAME_REPO_"
(
  repo="${TEST_SANDBOX}/unborn-repo"
  git init -q -b main "$repo"
  git -C "$repo" remote add origin "https://github.com/octocat/hello-world.git"
  cd "$repo"

  GIT_PROMPT_WITH_USERNAME_AND_REPO=1
  GIT_PROMPT_USERNAME_REPO_SEPARATOR=" | "
  GIT_PROMPT_PREFIX="[ _USERNAME_REPO_"
  run_prompt_cycle 0

  assert_eq "main" "$GIT_BRANCH"
  assert_eq "1" "$__GP_STATUS_IS_UNBORN"
  assert_eq "L" "$__GP_STATUS_REMOTE"
  assert_not_contains "$PS1" "octocat/hello-world"
) && pass_case

# 2. Detached HEAD: exact tag match vs commit SHA fallback
test_case "Detached HEAD renders exact tag (with PRETAG) or short SHA (with PREHASH) and omits L"
(
  repo="${TEST_SANDBOX}/detached-repo"
  git init -q -b main "$repo"
  cd "$repo"
  echo "v1" > a.txt && git add a.txt && git commit -q -m "c1"
  git tag v2.4.0
  echo "v2" > a.txt && git add a.txt && git commit -q -m "c2"
  sha_c2=$(git rev-parse --short HEAD)

  # Detached at untagged commit c2
  git checkout -q --detach HEAD
  run_prompt_cycle 0
  assert_eq ":${sha_c2}" "$GIT_BRANCH"
  assert_eq "" "$__GP_STATUS_REMOTE"
  assert_not_contains "$PS1" " L|"

  # Detached at exact tag v2.4.0
  git checkout -q v2.4.0
  run_prompt_cycle 0
  assert_eq "v2.4.0" "$GIT_BRANCH"
  assert_eq "" "$__GP_STATUS_REMOTE"

  # Custom PRETAG
  GIT_PROMPT_SYMBOLS_PRETAG="tag:"
  run_prompt_cycle 0
  assert_eq "tag:v2.4.0" "$GIT_BRANCH"
) && pass_case

# 3. Remote tracking: synchronized, ahead, behind, diverged, upstream display, and SHOW_TRACKING=0
test_case "Renders synchronized, ahead, behind, diverged (behind first), upstream block, and SHOW_TRACKING=0"
(
  remote_bare="${TEST_SANDBOX}/remote.git"
  local_repo="${TEST_SANDBOX}/local-clone"
  git init -q --bare -b main "$remote_bare"
  git clone -q "$remote_bare" "$local_repo" 2>/dev/null
  cd "$local_repo"
  git remote set-url origin "https://github.com/octocat/hello-world.git"
  git remote add local_origin "$remote_bare"
  echo "base" > f.txt && git add f.txt && git commit -q -m "base"
  git push -q -u local_origin main

  # Synchronized: remote indicator omitted completely
  run_prompt_cycle 0
  assert_eq "" "$__GP_STATUS_REMOTE"
  assert_eq "local_origin/main" "$__GP_STATUS_UPSTREAM"

  # GIT_PROMPT_WITH_USERNAME_AND_REPO=1 substitutes octocat/hello-world + separator when tracking
  GIT_PROMPT_WITH_USERNAME_AND_REPO=1
  GIT_PROMPT_USERNAME_REPO_SEPARATOR=" | "
  GIT_PROMPT_PREFIX="[ ${Blue}_USERNAME_REPO_"
  run_prompt_cycle 0
  assert_contains "$PS1" "octocat/hello-world${ResetColor} | "
  GIT_PROMPT_WITH_USERNAME_AND_REPO=0
  GIT_PROMPT_PREFIX="["

  # GIT_PROMPT_MASTER_BRANCHES extended glob matching
  GIT_PROMPT_MASTER_BRANCHES='@(master|main)'
  GIT_PROMPT_MASTER_BRANCH="<<MASTER_STYLE>>"
  GIT_PROMPT_BRANCH="<<BRANCH_STYLE>>"
  run_prompt_cycle 0
  assert_contains "$PS1" "<<MASTER_STYLE>>main"

  # GIT_PROMPT_SHOW_UPSTREAM=1
  GIT_PROMPT_SHOW_UPSTREAM=1
  run_prompt_cycle 0
  assert_contains "$PS1" "{${Blue}local_origin/main${ResetColor}}"
  GIT_PROMPT_SHOW_UPSTREAM=0

  # Ahead by 2
  echo "a1" >> f.txt && git commit -q -am "a1"
  echo "a2" >> f.txt && git commit -q -am "a2"
  run_prompt_cycle 0
  assert_eq "↑·2" "$__GP_STATUS_REMOTE"

  # Diverged: push to bare remote from a second clone
  other_clone="${TEST_SANDBOX}/other-clone"
  git clone -q "$remote_bare" "$other_clone" 2>/dev/null
  git -C "$other_clone" commit --allow-empty -q -m "remote1"
  git -C "$other_clone" commit --allow-empty -q -m "remote2"
  git -C "$other_clone" push -q origin main
  git fetch -q local_origin
  run_prompt_cycle 0
  # Behind 2, ahead 2 -> behind rendered first, then ahead
  assert_eq "↓·2↑·2" "$__GP_STATUS_REMOTE"

  # GIT_PROMPT_SHOW_TRACKING=0 suppresses remote tracking in prompt block
  GIT_PROMPT_SHOW_TRACKING=0
  run_prompt_cycle 0
  assert_not_contains "$PS1" "↓·2↑·2"
) && pass_case

# 4. gp_format_username_repo across URL schemes
test_case "Extracts <owner>/<repo> across HTTPS, credentialed HTTPS, SSH protocol, and SCP URLs"
(
  assert_eq "owner/repo" "$(gp_format_username_repo "https://github.com/owner/repo.git")"
  assert_eq "owner/repo" "$(gp_format_username_repo "https://github.com/owner/repo")"
  assert_eq "owner/repo" "$(gp_format_username_repo "https://token_user:secret@github.com:8443/owner/repo.git/")"
  assert_eq "owner/repo" "$(gp_format_username_repo "ssh://git@gitlab.com:22/owner/repo.git")"
  assert_eq "owner/repo" "$(gp_format_username_repo "git@github.com:owner/repo.git")"
  assert_eq "owner/repo" "$(gp_format_username_repo "git@github.com:/owner/repo.git")"
) && pass_case

# 5. Working tree, index, dual-state MM, conflicts, untracked modes, submodules, counts & separator suppression
test_case "Accurately counts staged, conflicts, changed (including dual MM), untracked modes, submodules, and separator suppression"
(
  repo="${TEST_SANDBOX}/counts-repo"
  git init -q -b master "$repo"
  cd "$repo"
  echo "1" > dual.txt
  echo "1" > mod.txt
  git add dual.txt mod.txt && git commit -q -m "init"

  # Dual-state file: staged modification + unstaged modification on dual.txt
  echo "2" > dual.txt && git add dual.txt
  echo "3" > dual.txt
  # Unstaged-only modification on mod.txt
  echo "2" > mod.txt
  # Untracked directory with 2 files
  mkdir -p udir
  echo "u1" > udir/u1.txt
  echo "u2" > udir/u2.txt

  GIT_PROMPT_SHOW_UNTRACKED_FILES=normal
  run_prompt_cycle 0
  assert_eq "1" "$__GP_STATUS_STAGED" "dual.txt must increment STAGED"
  assert_eq "2" "$__GP_STATUS_CHANGED" "dual.txt and mod.txt must both increment CHANGED"
  assert_eq "1" "$__GP_STATUS_UNTRACKED" "normal mode collapses udir/ to 1"

  GIT_PROMPT_SHOW_UNTRACKED_FILES=all
  run_prompt_cycle 0
  assert_eq "2" "$__GP_STATUS_UNTRACKED" "all mode counts 2 files inside udir/"

  GIT_PROMPT_SHOW_UNTRACKED_FILES=no
  run_prompt_cycle 0
  assert_eq "0" "$__GP_STATUS_UNTRACKED" "no mode skips untracked files"

  # GIT_PROMPT_SHOW_CHANGED_FILES_COUNT=0 hides local counts but keeps symbols
  GIT_PROMPT_SHOW_CHANGED_FILES_COUNT=0
  run_prompt_cycle 0
  assert_contains "$PS1" "${Red}● ${ResetColor}"
  assert_not_contains "$PS1" "${Red}● 1"
  GIT_PROMPT_SHOW_CHANGED_FILES_COUNT=1

  # Clean repo & conditional separator suppression when GIT_PROMPT_CLEAN=""
  git reset -q --hard HEAD
  rm -rf udir
  GIT_PROMPT_SHOW_UNTRACKED_FILES=normal
  run_prompt_cycle 0
  assert_eq "1" "$__GP_STATUS_CLEAN"
  assert_contains "$PS1" "|${BoldGreen}✔"

  GIT_PROMPT_CLEAN=""
  run_prompt_cycle 0
  assert_not_contains "$PS1" "|]" "GIT_PROMPT_SEPARATOR must be suppressed when CLEAN=1 and GIT_PROMPT_CLEAN is empty"
) && pass_case

# 6. Merge conflicts & submodule dirty/ignore modes
test_case "Counts unmerged conflict entries and respects GIT_PROMPT_IGNORE_SUBMODULES"
(
  sub="${TEST_SANDBOX}/sub-repo"
  sup="${TEST_SANDBOX}/sup-repo"
  git init -q -b main "$sub"
  echo "s" > "$sub/s.txt" && git -C "$sub" add s.txt && git -C "$sub" commit -q -m "s"

  git init -q -b main "$sup"
  cd "$sup"
  git submodule add -q "$sub" submod
  echo "base" > conflict.txt && git add conflict.txt
  git commit -q -m "initial super"

  # Dirty submodule
  echo "dirty" >> "$sup/submod/s.txt"
  GIT_PROMPT_IGNORE_SUBMODULES=0
  run_prompt_cycle 0
  assert_eq "1" "$__GP_STATUS_CHANGED"

  GIT_PROMPT_IGNORE_SUBMODULES=1
  run_prompt_cycle 0
  assert_eq "0" "$__GP_STATUS_CHANGED"
  git -C "$sup/submod" checkout -q -- s.txt
  GIT_PROMPT_IGNORE_SUBMODULES=0

  # Create real merge conflict
  git checkout -q -b side
  echo "side_change" > conflict.txt && git commit -q -am "side"
  git checkout -q main
  echo "main_change" > conflict.txt && git commit -q -am "main"
  git merge side >/dev/null 2>&1 || true

  run_prompt_cycle 0
  assert_eq "1" "$__GP_STATUS_CONFLICTS"
  assert_eq "0" "$__GP_STATUS_STAGED" "Conflict entry must not be double-counted in STAGED"
  assert_contains "$GIT_BRANCH" "main|MERGING"
) && pass_case

# 7. Custom GIT_PROMPT_STATUS_COMMAND interface & wildcard-safe token substitution
test_case "Supports custom GIT_PROMPT_STATUS_COMMAND and replaces placeholder tokens without globbing"
(
  repo="${TEST_SANDBOX}/custom-cmd-repo"
  git init -q -b main "$repo"
  cd "$repo"

  custom_provider="${TEST_SANDBOX}/my-status-provider.sh"
  cat << 'EOF' > "$custom_provider"
#!/usr/bin/env bash
printf '_PREHASH_deadbeef\n'
printf '_BEHIND_4_AHEAD_2\n'
printf 'origin/main\n'
printf '1\n2\n3\n4\n5\n0\n'
EOF
  chmod +x "$custom_provider"

  GIT_PROMPT_STATUS_COMMAND="$custom_provider"
  GIT_PROMPT_SYMBOLS_PREHASH=":"
  GIT_PROMPT_SYMBOLS_AHEAD="↑*?"
  GIT_PROMPT_SYMBOLS_BEHIND="↓*?"
  run_prompt_cycle 0

  assert_eq ":deadbeef" "$GIT_BRANCH"
  assert_eq "↓*?4↑*?2" "$__GP_STATUS_REMOTE"
  assert_eq "1" "$__GP_STATUS_STAGED"
  assert_eq "2" "$__GP_STATUS_CONFLICTS"
  assert_eq "3" "$__GP_STATUS_CHANGED"
  assert_eq "4" "$__GP_STATUS_UNTRACKED"
  assert_eq "5" "$__GP_STATUS_STASHED"
) && pass_case

test_suite_end
