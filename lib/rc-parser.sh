# shellcheck shell=bash
# lib/rc-parser.sh - Strict allowlist validator and parser for per-repository .bash-git-rc

declare -gA __GP_RC_OVERRIDES=()

# __gp_load_repo_rc <repo_toplevel_dir>
# Validates and reads <repo_toplevel_dir>/.bash-git-rc without ever sourcing or
# executing any file content.
#
# Rules (PRD Section 7.2):
#   1. Every line must strictly match one of the 5 allowlisted keys, followed
#      immediately by '=', followed only by lowercase ASCII letters and digits
#      (a-z, 0-9), with no whitespace, comments, quotes, or metacharacters.
#   2. If ANY line fails validation, zero lines from the file are applied, a
#      warning is emitted to stderr, and global settings remain active.
#   3. Parsed values are stored in __GP_RC_OVERRIDES for local consumption in the
#      current prompt cycle only, preventing state leakage across directories.
__gp_load_repo_rc() {
  local toplevel=${1:-}
  __GP_RC_OVERRIDES=()
  [[ -z $toplevel ]] && return 0

  local rc_file="${toplevel}/.bash-git-rc"
  [[ -f $rc_file && -r $rc_file ]] || return 0

  local LC_ALL=C
  local pattern='^(FETCH_REMOTE_STATUS|GIT_PROMPT_SHOW_UNTRACKED_FILES|GIT_PROMPT_IGNORE_SUBMODULES|GIT_PROMPT_SHOW_TRACKING|GIT_PROMPT_IGNORE)=([a-z0-9]+)$'
  local line key val
  local -A parsed=()

  while IFS= read -r line || [[ -n $line ]]; do
    if [[ ! $line =~ $pattern ]]; then
      __GP_RC_OVERRIDES=()
      printf 'bash-git-prompt: warning: %s may only contain NAME=value declarations; ignoring file.\n' "$rc_file" >&2
      return 1
    fi
    key=${BASH_REMATCH[1]}
    val=${BASH_REMATCH[2]}
    parsed[$key]=$val
  done < "$rc_file"

  for key in "${!parsed[@]}"; do
    __GP_RC_OVERRIDES[$key]=${parsed[$key]}
  done
  return 0
}
