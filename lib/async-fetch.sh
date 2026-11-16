# shellcheck shell=bash
# lib/async-fetch.sh - Asynchronous, non-blocking, job-control-detached periodic remote fetch

declare -g __GP_STAT_MODE=""

# __gp_detect_stat_mode
# Determines and caches the host mechanism for checking file modification time:
#   - "gnu"  : stat -c %Y <file>
#   - "bsd"  : stat -f %m <file>
#   - "find" : find <file> -mmin +<N>
#   - "none" : unsupported
__gp_detect_stat_mode() {
  if [[ ${__GP_FORCE_MISSING_FILE_AGE_CAPABILITY:-0} == "1" ]]; then
    __GP_STAT_MODE="none"
    return 1
  fi
  [[ -n $__GP_STAT_MODE ]] && [[ $__GP_STAT_MODE != "none" ]] && return 0
  [[ $__GP_STAT_MODE == "none" ]] && return 1

  local probe=${BASH_SOURCE[0]}
  local out
  if out=$(LC_ALL=C command stat -c '%Y' "$probe" 2>/dev/null) && [[ $out =~ ^[0-9]+$ ]]; then
    __GP_STAT_MODE="gnu"
    return 0
  elif out=$(LC_ALL=C command stat -f '%m' "$probe" 2>/dev/null) && [[ $out =~ ^[0-9]+$ ]]; then
    __GP_STAT_MODE="bsd"
    return 0
  elif LC_ALL=C command find "$probe" -maxdepth 0 -mmin +5 >/dev/null 2>&1; then
    __GP_STAT_MODE="find"
    return 0
  else
    __GP_STAT_MODE="none"
    return 1
  fi
}

# __gp_is_fetch_head_stale <fetch_head_path> <timeout_minutes>
# Returns 0 if <fetch_head_path> does not exist or its modification timestamp is
# strictly older than <timeout_minutes> minutes; returns 1 if fresh; returns 2
# if the host lacks file-age inspection capability.
__gp_is_fetch_head_stale() {
  local fetch_head=$1
  local timeout=${2:-5}
  [[ $timeout =~ ^[0-9]+$ && $timeout -gt 0 ]] || timeout=5

  if ! __gp_detect_stat_mode; then
    return 2
  fi

  [[ ! -e $fetch_head ]] && return 0

  local mtime now
  now=$EPOCHSECONDS
  case $__GP_STAT_MODE in
    gnu)
      mtime=$(LC_ALL=C command stat -c '%Y' "$fetch_head" 2>/dev/null) || return 0
      (( now - mtime > timeout * 60 )) && return 0
      return 1
      ;;
    bsd)
      mtime=$(LC_ALL=C command stat -f '%m' "$fetch_head" 2>/dev/null) || return 0
      (( now - mtime > timeout * 60 )) && return 0
      return 1
      ;;
    find)
      local found
      found=$(LC_ALL=C command find "$fetch_head" -maxdepth 0 -mmin "+${timeout}" 2>/dev/null)
      [[ -n $found ]] && return 0
      return 1
      ;;
  esac
  return 2
}

# __gp_maybe_fetch_remote <git_common_dir> <effective_fetch_flag>
# Triggers a detached background fetch when enabled, a remote is configured,
# and <git_common_dir>/FETCH_HEAD is missing or older than GIT_PROMPT_FETCH_TIMEOUT.
__gp_maybe_fetch_remote() {
  local git_common_dir=$1
  local eff_fetch=${2:-1}

  [[ $eff_fetch == "1" ]] || return 0
  [[ -n $git_common_dir ]] || return 0

  local fetch_head="${git_common_dir%/}/FETCH_HEAD"
  local timeout=${GIT_PROMPT_FETCH_TIMEOUT:-5}

  __gp_is_fetch_head_stale "$fetch_head" "$timeout"
  local stale_rc=$?

  if (( stale_rc == 2 )); then
    printf 'bash-git-prompt: warning: unable to determine file modification age; disabling remote status fetching for this session. Set GIT_PROMPT_FETCH_REMOTE_STATUS=0 to silence this warning.\n' >&2
    GIT_PROMPT_FETCH_REMOTE_STATUS=0
    return 0
  fi

  (( stale_rc == 0 )) || return 0

  # Verify at least one remote is configured before spawning a background fetch
  local remotes
  remotes=$(LC_ALL=C git --no-optional-locks remote 2>/dev/null)
  [[ -n $remotes ]] || return 0

  # Double-fork inside a subshell so interactive Bash job control never tracks
  # the background process or prints [1] / [Done] notifications.
  (
    # Close any non-standard file descriptors (3..9) so none leak
    exec </dev/null >/dev/null 2>&1 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-
    # Record fetch attempt timestamp on FETCH_HEAD so repeated prompts within
    # the timeout window do not spawn concurrent duplicate fetches
    command touch "$fetch_head" 2>/dev/null || true
    GIT_TERMINAL_PROMPT=0 \
    GCM_INTERACTIVE=never \
    GIT_ASKPASS=true \
    SSH_ASKPASS="" \
    GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}" \
    LC_ALL=C git --no-optional-locks fetch --quiet >/dev/null 2>&1 </dev/null &
  ) </dev/null >/dev/null 2>&1
}
