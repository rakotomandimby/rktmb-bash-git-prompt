# shellcheck shell=bash
# gitprompt.sh - Main interactive entrypoint for Bash Git Prompt (GNU Bash 5.0+)

# Require GNU Bash 5.0 or newer
if [[ -z ${BASH_VERSINFO[0]:-} ]] || (( BASH_VERSINFO[0] < 5 )); then
  printf 'bash-git-prompt: GNU Bash 5.0 or newer is required (detected: %s).\n' "${BASH_VERSION:-unknown}" >&2
  return 1 2>/dev/null || exit 1
fi

declare -g __GP_ENTRYPOINT_SOURCE=${BASH_SOURCE[0]}
declare -g __GP_DIR_AUTO_DETECTED=0
declare -g __GP_LAST_EXIT_STATUS=0
declare -g __GP_IN_REPO_ACTIVE=0
declare -g __GP_SAVED_PS1=""
declare -g __GP_INITIAL_PS1=""

if [[ -z ${__GP_INITIAL_PS1_CAPTURED:-} ]]; then
  __GP_INITIAL_PS1=${PS1:-}
  __GP_SAVED_PS1=${PS1:-}
  declare -g __GP_INITIAL_PS1_CAPTURED=1
fi

# __gp_resolve_install_dir <source_path>
# Resolves the canonical installation directory, following symbolic links if
# gitprompt.sh was sourced via a symlinked path. Honors pre-set __GIT_PROMPT_DIR.
__gp_resolve_install_dir() {
  local src=${1:-${BASH_SOURCE[0]}}
  local dir target
  while [[ -L $src ]]; do
    dir=$(builtin cd -P "${src%/*}" 2>/dev/null && pwd) || break
    target=$(command readlink "$src" 2>/dev/null) || break
    if [[ $target == /* ]]; then
      src=$target
    else
      src="${dir}/${target}"
    fi
  done
  __GIT_PROMPT_DIR=$(builtin cd -P "${src%/*}" 2>/dev/null && pwd)
}

if [[ -z ${__GIT_PROMPT_DIR:-} ]]; then
  __GP_DIR_AUTO_DETECTED=1
  __gp_resolve_install_dir "${BASH_SOURCE[0]}"
fi

# Load internal runtime modules
# shellcheck source=lib/helpers.sh
source "${__GIT_PROMPT_DIR}/lib/helpers.sh"
# shellcheck source=lib/rc-parser.sh
source "${__GIT_PROMPT_DIR}/lib/rc-parser.sh"
# shellcheck source=lib/async-fetch.sh
source "${__GIT_PROMPT_DIR}/lib/async-fetch.sh"
# shellcheck source=lib/status.sh
source "${__GIT_PROMPT_DIR}/lib/status.sh"
# shellcheck source=lib/themes.sh
source "${__GIT_PROMPT_DIR}/lib/themes.sh"
# shellcheck source=lib/cli.sh
source "${__GIT_PROMPT_DIR}/lib/cli.sh"

# __gp_capture_exit_status
# First pre-prompt hook: captures the exact exit status of the interactive user
# command just executed and returns that identical status so any subsequent
# user-registered PROMPT_COMMAND hooks still observe the original exit status.
__gp_capture_exit_status() {
  local rc=$?
  __GP_LAST_EXIT_STATUS=$rc
  return "$rc"
}

# __gp_collect_virtual_envs
# Detects active Python, Node.js, and Conda environments in deterministic order
# (PRD Section 3.10) and formats each using GIT_PROMPT_VIRTUALENV into REPLY.
__gp_collect_virtual_envs() {
  REPLY=""
  [[ ${GIT_PROMPT_WITH_VIRTUAL_ENV:-1} == "0" ]] && return 0

  local -a env_names=()
  local name=""

  # 1. Python Virtual Environment
  if [[ -n ${VIRTUAL_ENV:-} && -z ${VIRTUAL_ENV_DISABLE_PROMPT-} ]]; then
    if [[ -n ${VIRTUAL_ENV_PROMPT:-} ]]; then
      name=$VIRTUAL_ENV_PROMPT
      # Strip leading whitespace and a leading '('
      name=${name#"${name%%[![:space:]]*}"}
      name=${name#\(}
      # Strip trailing whitespace and a trailing ')'
      name=${name%"${name##*[![:space:]]}"}
      name=${name%\)}
      name=${name%"${name##*[![:space:]]}"}
    else
      local venv_clean=${VIRTUAL_ENV%/}
      name=${venv_clean##*/}
    fi
    [[ -n $name ]] && env_names+=("$name")
  fi

  # 2. Node.js Virtual Environment
  if [[ -n ${NODE_VIRTUAL_ENV:-} && -z ${NODE_VIRTUAL_ENV_DISABLE_PROMPT-} ]]; then
    local node_clean=${NODE_VIRTUAL_ENV%/}
    name=${node_clean##*/}
    [[ -n $name ]] && env_names+=("$name")
  fi

  # 3. Conda Environment
  if [[ -n ${CONDA_DEFAULT_ENV:-} ]]; then
    local conda_clean=${CONDA_DEFAULT_ENV%/}
    name=${conda_clean##*/}
    [[ -n $name ]] && env_names+=("$name")
  fi

  local out="" seg safe_name
  local tmpl=${GIT_PROMPT_VIRTUALENV:-"(${Blue}_VIRTUALENV_${ResetColor}) "}
  for name in "${env_names[@]}"; do
    __gp_escape_for_ps1 "$name"
    safe_name=$REPLY
    seg=$tmpl
    __gp_replace_all seg "_VIRTUALENV_" "$safe_name"
    out+=$seg
  done
  REPLY=$out
}

# __gp_format_last_command_indicator
# Formats _LAST_COMMAND_STATE_ inside GIT_PROMPT_COMMAND_OK / GIT_PROMPT_COMMAND_FAIL
# into REPLY.
__gp_format_last_command_indicator() {
  local rc=${__GP_LAST_EXIT_STATUS:-0}
  __gp_format_exit_status_reply "$rc"
  local state=$REPLY

  local tmpl
  if [[ $rc == "0" ]]; then
    tmpl=${GIT_PROMPT_COMMAND_OK:-}
  else
    tmpl=${GIT_PROMPT_COMMAND_FAIL:-}
  fi

  __gp_replace_all tmpl "_LAST_COMMAND_STATE_" "$state"
  REPLY="${tmpl}${ResetColor}"
}

# __gp_render_non_git_prompt
# Renders the Non-Git prompt or restores the user's saved original PS1 when
# GIT_PROMPT_ONLY_IN_REPO=1 (PRD Section 3.2 & 4.1).
__gp_render_non_git_prompt() {
  unset -v GIT_BRANCH

  if [[ ${GIT_PROMPT_ONLY_IN_REPO:-0} == "1" ]]; then
    if (( __GP_IN_REPO_ACTIVE == 1 )); then
      PS1=$__GP_SAVED_PS1
      __GP_IN_REPO_ACTIVE=0
    fi
    return 0
  fi

  __gp_load_theme

  # Re-check in case the active theme (e.g. Plague_Doctor) enables GIT_PROMPT_ONLY_IN_REPO=1
  if [[ ${GIT_PROMPT_ONLY_IN_REPO:-0} == "1" ]]; then
    if (( __GP_IN_REPO_ACTIVE == 1 )); then
      PS1=$__GP_SAVED_PS1
      __GP_IN_REPO_ACTIVE=0
    fi
    return 0
  fi

  local __GP_PROMPT_START="" __GP_PROMPT_END=""
  __gp_get_prompt_start_end

  local REPLY=""
  __gp_collect_virtual_envs
  local venv_seg=$REPLY

  local callback_seg=""
  if declare -F prompt_callback >/dev/null 2>&1; then
    callback_seg=$(prompt_callback)
  fi

  local assembled=""
  if [[ ${GIT_PROMPT_VIRTUAL_ENV_AFTER_PROMPT:-0} == "1" ]]; then
    assembled="${__GP_PROMPT_START}${callback_seg}${venv_seg}${__GP_PROMPT_END}"
  else
    assembled="${venv_seg}${__GP_PROMPT_START}${callback_seg}${__GP_PROMPT_END}"
  fi

  __gp_format_last_command_indicator
  local cmd_indicator=$REPLY
  __gp_replace_all assembled "_LAST_COMMAND_INDICATOR_" "$cmd_indicator"

  PS1=$assembled
  return 0
}

# __gp_build_git_status_block <eff_tracking>
# Constructs the 13-part [Git Status Block] specified in PRD Section 4.2 into REPLY.
__gp_build_git_status_block() {
  local eff_tracking=${1:-1}
  local r=${ResetColor}

  # 1. Opening Prefix (with _USERNAME_REPO_ & optional separator resolution)
  local prefix=${GIT_PROMPT_PREFIX}
  if [[ $prefix == *"_USERNAME_REPO_"* ]]; then
    local repo_replacement="$r"
    if [[ ${GIT_PROMPT_WITH_USERNAME_AND_REPO:-0} == "1" ]] \
       && (( __GP_STATUS_IS_UNBORN == 0 && __GP_STATUS_HAS_UPSTREAM == 1 )); then
      local owner_repo
      owner_repo=$(gp_format_username_repo)
      if [[ -n $owner_repo ]]; then
        __gp_escape_for_ps1 "$owner_repo"
        repo_replacement="${REPLY}${r}${GIT_PROMPT_USERNAME_REPO_SEPARATOR-}"
      fi
    fi
    __gp_replace_all prefix "_USERNAME_REPO_" "$repo_replacement"
  fi

  # 2. Branch / Reference Style (PRD Section 3.4.1 & 3.4.3)
  local branch_style=${GIT_PROMPT_BRANCH}
  local master_pattern=${GIT_PROMPT_MASTER_BRANCHES:-master}
  # Bash 5 [[ == ]] evaluates extglob patterns natively on unquoted RHS
  # shellcheck disable=SC2053
  if [[ $__GP_STATUS_BRANCH == $master_pattern || $__GP_STATUS_BASE_BRANCH == $master_pattern ]]; then
    branch_style=${GIT_PROMPT_MASTER_BRANCH}
  elif (( __GP_STATUS_IS_DETACHED == 1 )); then
    branch_style=${GIT_PROMPT_DETACHED_HEAD}
  fi

  # 3. Branch / Tag / Prehash+SHA + In-Progress Operation Suffix + Color Reset
  __gp_escape_for_ps1 "$__GP_STATUS_BRANCH"
  local safe_branch=$REPLY
  local block="${prefix}${branch_style}${safe_branch}${r}"

  # 4. Upstream Branch Block (only if GIT_PROMPT_SHOW_UPSTREAM=1 and upstream exists)
  if [[ ${GIT_PROMPT_SHOW_UPSTREAM:-0} == "1" && -n $__GP_STATUS_UPSTREAM ]]; then
    __gp_escape_for_ps1 "$__GP_STATUS_UPSTREAM"
    local safe_upstream=$REPLY
    local upstream_seg=${GIT_PROMPT_UPSTREAM}
    __gp_replace_all upstream_seg "_UPSTREAM_" "$safe_upstream"
    block+=$upstream_seg
  fi

  # 5. Remote Tracking Status (only if eff_tracking != 0 and tracking is non-empty)
  if [[ $eff_tracking != "0" && -n $__GP_STATUS_REMOTE ]]; then
    __gp_escape_for_ps1 "$__GP_STATUS_REMOTE"
    block+="${GIT_PROMPT_REMOTE}${REPLY}${r}"
  fi

  # 6. Status Separator (omitted ONLY when repository is Clean AND GIT_PROMPT_CLEAN is empty)
  if (( __GP_STATUS_CLEAN == 0 )) || [[ -n ${GIT_PROMPT_CLEAN} ]]; then
    block+=${GIT_PROMPT_SEPARATOR}
  fi

  # 7..11. Local Status Indicators (with optional counts controlled by GIT_PROMPT_SHOW_CHANGED_FILES_COUNT)
  local show_counts=${GIT_PROMPT_SHOW_CHANGED_FILES_COUNT:-1}
  if (( __GP_STATUS_STAGED > 0 )); then
    if [[ $show_counts == "0" ]]; then
      block+="${GIT_PROMPT_STAGED}${r}"
    else
      block+="${GIT_PROMPT_STAGED}${__GP_STATUS_STAGED}${r}"
    fi
  fi
  if (( __GP_STATUS_CONFLICTS > 0 )); then
    if [[ $show_counts == "0" ]]; then
      block+="${GIT_PROMPT_CONFLICTS}${r}"
    else
      block+="${GIT_PROMPT_CONFLICTS}${__GP_STATUS_CONFLICTS}${r}"
    fi
  fi
  if (( __GP_STATUS_CHANGED > 0 )); then
    if [[ $show_counts == "0" ]]; then
      block+="${GIT_PROMPT_CHANGED}${r}"
    else
      block+="${GIT_PROMPT_CHANGED}${__GP_STATUS_CHANGED}${r}"
    fi
  fi
  if (( __GP_STATUS_UNTRACKED > 0 )); then
    if [[ $show_counts == "0" ]]; then
      block+="${GIT_PROMPT_UNTRACKED}${r}"
    else
      block+="${GIT_PROMPT_UNTRACKED}${__GP_STATUS_UNTRACKED}${r}"
    fi
  fi
  if (( __GP_STATUS_STASHED > 0 )); then
    if [[ $show_counts == "0" ]]; then
      block+="${GIT_PROMPT_STASHED}${r}"
    else
      block+="${GIT_PROMPT_STASHED}${__GP_STATUS_STASHED}${r}"
    fi
  fi

  # 12. Clean Indicator (never with count; only when Clean and GIT_PROMPT_CLEAN is non-empty)
  if (( __GP_STATUS_CLEAN == 1 )) && [[ -n ${GIT_PROMPT_CLEAN} ]]; then
    block+="${GIT_PROMPT_CLEAN}${r}"
  fi

  # 13. Closing Suffix
  block+="${r}${GIT_PROMPT_SUFFIX}"
  REPLY=$block
}

# __gp_update_prompt
# Final pre-prompt hook: inspects environment and Git state and renders PS1.
__gp_update_prompt() {
  # Scope shell option changes locally using Bash 5 `local -`
  local -
  set -f

  # Bypass Git evaluation when disabled or running inside COPILOT_AGENT=1
  if [[ ${GIT_PROMPT_DISABLE:-0} == "1" || ${COPILOT_AGENT:-0} == "1" ]]; then
    __gp_render_non_git_prompt
    return 0
  fi

  # Check if current directory is inside a Git working tree
  if ! __gp_discover_repo; then
    __gp_render_non_git_prompt
    return 0
  fi

  # Load and validate per-repository .bash-git-rc into __GP_RC_OVERRIDES
  __gp_load_repo_rc "$__GP_GIT_TOPLEVEL"

  # Compute strictly repository-scoped effective configuration values
  local eff_ignore=${__GP_RC_OVERRIDES[GIT_PROMPT_IGNORE]:-0}
  if [[ $eff_ignore == "1" ]]; then
    __gp_render_non_git_prompt
    return 0
  fi

  local eff_fetch=${__GP_RC_OVERRIDES[FETCH_REMOTE_STATUS]:-${GIT_PROMPT_FETCH_REMOTE_STATUS:-1}}
  local eff_untracked=${__GP_RC_OVERRIDES[GIT_PROMPT_SHOW_UNTRACKED_FILES]:-${GIT_PROMPT_SHOW_UNTRACKED_FILES:-normal}}
  local eff_submodules=${__GP_RC_OVERRIDES[GIT_PROMPT_IGNORE_SUBMODULES]:-${GIT_PROMPT_IGNORE_SUBMODULES:-0}}
  local eff_tracking=${__GP_RC_OVERRIDES[GIT_PROMPT_SHOW_TRACKING]:-${GIT_PROMPT_SHOW_TRACKING:-1}}
  local eff_ignore_stash=${GIT_PROMPT_IGNORE_STASH:-0}

  # Ensure colors and active theme are loaded (note: themes like Plague_Doctor
  # may configure GIT_PROMPT_ONLY_IN_REPO=1)
  __gp_load_theme

  # Trigger asynchronous background fetch if remote status is stale
  __gp_maybe_fetch_remote "$__GP_GIT_COMMON_DIR" "$eff_fetch"

  # Evaluate lock-free Git status; fall back to Non-Git prompt on fatal Git error
  if ! __gp_evaluate_git_status "$__GP_GIT_DIR" "$eff_untracked" "$eff_submodules" "$eff_ignore_stash"; then
    __gp_render_non_git_prompt
    return 0
  fi

  # Save pre-Git PS1 when entering a Git repository from a Non-Git state
  if (( __GP_IN_REPO_ACTIVE == 0 )); then
    __GP_SAVED_PS1=${PS1:-$__GP_INITIAL_PS1}
    __GP_IN_REPO_ACTIVE=1
  fi

  export GIT_BRANCH=$__GP_STATUS_BRANCH

  local __GP_PROMPT_START="" __GP_PROMPT_END=""
  __gp_get_prompt_start_end

  local REPLY=""
  __gp_collect_virtual_envs
  local venv_seg=$REPLY

  local callback_seg=""
  if declare -F prompt_callback >/dev/null 2>&1; then
    callback_seg=$(prompt_callback)
  fi

  local leading_space=" "
  if [[ ${GIT_PROMPT_LEADING_SPACE:-1} == "0" ]]; then
    leading_space=""
  fi

  __gp_build_git_status_block "$eff_tracking"
  local git_status_block=$REPLY

  local assembled=""
  if [[ ${GIT_PROMPT_VIRTUAL_ENV_AFTER_PROMPT:-0} == "1" ]]; then
    assembled="${__GP_PROMPT_START}${callback_seg}${venv_seg}${leading_space}${git_status_block}${__GP_PROMPT_END}"
  else
    assembled="${venv_seg}${__GP_PROMPT_START}${callback_seg}${leading_space}${git_status_block}${__GP_PROMPT_END}"
  fi

  __gp_format_last_command_indicator
  local cmd_indicator=$REPLY
  __gp_replace_all assembled "_LAST_COMMAND_INDICATOR_" "$cmd_indicator"

  PS1=$assembled
  return 0
}

# __gp_normalize_scalar_prompt_command <raw_string>
# Normalizes a scalar PROMPT_COMMAND string by replacing embedded newlines with
# semicolons, stripping existing internal hooks, and trimming stray semicolons/whitespace.
__gp_normalize_scalar_prompt_command() {
  local raw=${1:-}
  raw=${raw//$'\r'/}
  raw=${raw//$'\n'/;}

  local -a parts=() kept=()
  local part trimmed
  IFS=';' read -ra parts <<< "$raw"
  for part in "${parts[@]}"; do
    __gp_trim "$part"
    trimmed=$REPLY
    [[ -z $trimmed ]] && continue
    [[ $trimmed == "__gp_capture_exit_status" || $trimmed == "__gp_update_prompt" ]] && continue
    kept+=("$trimmed")
  done

  local joined=""
  local idx
  for idx in "${!kept[@]}"; do
    if (( idx > 0 )); then
      joined+="; "
    fi
    joined+=${kept[idx]}
  done
  REPLY=$joined
}

# __gp_install_prompt_hooks
# Idempotently installs __gp_capture_exit_status as the FIRST pre-prompt hook
# and __gp_update_prompt as the FINAL pre-prompt hook, preserving both scalar
# string and Bash 5+ indexed array PROMPT_COMMAND configurations.
__gp_install_prompt_hooks() {
  local decl
  decl=$(declare -p PROMPT_COMMAND 2>/dev/null || true)
  if [[ $decl == "declare -a"* ]]; then
    local -a kept=()
    local elem REPLY=""
    for elem in "${PROMPT_COMMAND[@]}"; do
      __gp_normalize_scalar_prompt_command "$elem"
      [[ -n $REPLY ]] && kept+=("$REPLY")
    done
    PROMPT_COMMAND=("__gp_capture_exit_status" "${kept[@]}" "__gp_update_prompt")
  else
    local REPLY=""
    __gp_normalize_scalar_prompt_command "${PROMPT_COMMAND-}"
    if [[ -n $REPLY ]]; then
      PROMPT_COMMAND="__gp_capture_exit_status; ${REPLY}; __gp_update_prompt"
    else
      PROMPT_COMMAND="__gp_capture_exit_status; __gp_update_prompt"
    fi
  fi
}

__gp_install_prompt_hooks
