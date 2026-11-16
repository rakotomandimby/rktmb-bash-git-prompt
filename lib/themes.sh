# shellcheck shell=bash
# lib/themes.sh - Color palette discovery, theme resolution, Default baseline
# inheritance, clean theme transitions, and session caching.

declare -g __GP_LOADED_COLOR_FILE=""
declare -g __GP_CACHED_THEME_KEY=""
declare -g __GP_ACTIVE_THEME_NAME=""
declare -g __GP_ACTIVE_THEME_FILE=""

declare -g __GP_BASE_SAVED=0
declare -g __GP_BASE_ONLY_IN_REPO=""
declare -g __GP_BASE_LEADING_SPACE=""
declare -g __GP_BASE_WITH_USERNAME_REPO=""
declare -g __GP_BASE_USERNAME_REPO_SEP=""
declare -g __GP_BASE_HAS_USER_CALLBACK=0
declare -g __GP_BASE_USER_CALLBACK_DEF=""

# No-op compatibility helper for custom theme files that call reload_git_prompt_colors
reload_git_prompt_colors() { :; }

# __gp_snapshot_user_baseline
# Records the user's initial session flags and any pre-existing prompt_callback
# function prior to the first theme load so switching away from themes that set
# session flags (e.g. Plague_Doctor, Single_line_username_repo, Minimal) cleanly
# restores the user's baseline.
__gp_snapshot_user_baseline() {
  (( __GP_BASE_SAVED == 1 )) && return 0
  __GP_BASE_ONLY_IN_REPO=${GIT_PROMPT_ONLY_IN_REPO-__UNSET__}
  __GP_BASE_LEADING_SPACE=${GIT_PROMPT_LEADING_SPACE-__UNSET__}
  __GP_BASE_WITH_USERNAME_REPO=${GIT_PROMPT_WITH_USERNAME_AND_REPO-__UNSET__}
  __GP_BASE_USERNAME_REPO_SEP=${GIT_PROMPT_USERNAME_REPO_SEPARATOR-__UNSET__}

  if declare -F prompt_callback >/dev/null 2>&1; then
    __GP_BASE_HAS_USER_CALLBACK=1
    __GP_BASE_USER_CALLBACK_DEF=$(declare -f prompt_callback)
  else
    __GP_BASE_HAS_USER_CALLBACK=0
    __GP_BASE_USER_CALLBACK_DEF=""
  fi
  __GP_BASE_SAVED=1
}

# __gp_restore_var_from_snapshot <var_name> <snapshot_value>
__gp_restore_var_from_snapshot() {
  local var_name=$1
  local snap=$2
  if [[ $snap == "__UNSET__" ]]; then
    unset -v "$var_name"
  else
    printf -v "$var_name" '%s' "$snap"
  fi
}

# __gp_load_colors
# Resolves and loads the color definitions file once per session according to
# PRD Section 4.6 precedence:
#   1. ~/.prompt-colors.sh
#   2. ~/prompt-colors.sh
#   3. ~/lib/prompt-colors.sh
#   4. ${__GIT_PROMPT_DIR}/prompt-colors.sh
__gp_load_colors() {
  local candidate=""
  local -a candidates=(
    "${HOME:-}/.prompt-colors.sh"
    "${HOME:-}/prompt-colors.sh"
    "${HOME:-}/lib/prompt-colors.sh"
    "${__GIT_PROMPT_DIR}/prompt-colors.sh"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -f $c && -r $c ]]; then
      candidate=$c
      break
    fi
  done

  [[ -z $candidate ]] && return 1
  if [[ $__GP_LOADED_COLOR_FILE == "$candidate" && -n ${ResetColor:-} ]]; then
    return 0
  fi

  # shellcheck source=/dev/null
  source "$candidate"
  __GP_LOADED_COLOR_FILE=$candidate
  return 0
}

# __gp_unset_theme_vars
# Clears all theme-scoped visual variables before loading a new theme so zero
# variable bleed-through occurs across theme switches.
__gp_unset_theme_vars() {
  unset -v \
    GIT_PROMPT_THEME_NAME \
    GIT_PROMPT_PREFIX \
    GIT_PROMPT_SUFFIX \
    GIT_PROMPT_SEPARATOR \
    GIT_PROMPT_BRANCH \
    GIT_PROMPT_MASTER_BRANCH \
    GIT_PROMPT_MASTER_BRANCHES \
    GIT_PROMPT_DETACHED_HEAD \
    GIT_PROMPT_REMOTE \
    GIT_PROMPT_UPSTREAM \
    GIT_PROMPT_STAGED \
    GIT_PROMPT_CONFLICTS \
    GIT_PROMPT_CHANGED \
    GIT_PROMPT_UNTRACKED \
    GIT_PROMPT_STASHED \
    GIT_PROMPT_CLEAN \
    GIT_PROMPT_COMMAND_OK \
    GIT_PROMPT_COMMAND_FAIL \
    GIT_PROMPT_VIRTUALENV \
    GIT_PROMPT_START_USER \
    GIT_PROMPT_START_ROOT \
    GIT_PROMPT_END_USER \
    GIT_PROMPT_END_ROOT \
    GIT_PROMPT_SYMBOLS_AHEAD \
    GIT_PROMPT_SYMBOLS_BEHIND \
    GIT_PROMPT_SYMBOLS_PREHASH \
    GIT_PROMPT_SYMBOLS_PRETAG \
    GIT_PROMPT_SYMBOLS_NO_REMOTE_TRACKING
}

# __gp_apply_default_theme_fallbacks
# Populates any unset theme variable from the canonical Default theme baseline
# (PRD Section 5.2 & 7.3). Checks `${VAR+x}` so intentional empty-string overrides
# (such as GIT_PROMPT_CLEAN="" or GIT_PROMPT_SEPARATOR="") are preserved.
__gp_apply_default_theme_fallbacks() {
  : "${Time12a:=\A}"
  : "${PathShort:=\w}"
  : "${NewLine:=\n}"

  [[ -z ${GIT_PROMPT_THEME_NAME+x} ]] && GIT_PROMPT_THEME_NAME="Default"
  [[ -z ${GIT_PROMPT_PREFIX+x} ]] && GIT_PROMPT_PREFIX="["
  [[ -z ${GIT_PROMPT_SUFFIX+x} ]] && GIT_PROMPT_SUFFIX="]"
  [[ -z ${GIT_PROMPT_SEPARATOR+x} ]] && GIT_PROMPT_SEPARATOR="|"
  [[ -z ${GIT_PROMPT_BRANCH+x} ]] && GIT_PROMPT_BRANCH="${Magenta}"
  [[ -z ${GIT_PROMPT_MASTER_BRANCH+x} ]] && GIT_PROMPT_MASTER_BRANCH="${GIT_PROMPT_BRANCH}"
  [[ -z ${GIT_PROMPT_MASTER_BRANCHES+x} ]] && GIT_PROMPT_MASTER_BRANCHES="master"
  [[ -z ${GIT_PROMPT_DETACHED_HEAD+x} ]] && GIT_PROMPT_DETACHED_HEAD="${GIT_PROMPT_BRANCH}"
  [[ -z ${GIT_PROMPT_REMOTE+x} ]] && GIT_PROMPT_REMOTE=" "
  [[ -z ${GIT_PROMPT_UPSTREAM+x} ]] && GIT_PROMPT_UPSTREAM=" {${Blue}_UPSTREAM_${ResetColor}}"
  [[ -z ${GIT_PROMPT_STAGED+x} ]] && GIT_PROMPT_STAGED="${Red}● "
  [[ -z ${GIT_PROMPT_CONFLICTS+x} ]] && GIT_PROMPT_CONFLICTS="${Red}✖ "
  [[ -z ${GIT_PROMPT_CHANGED+x} ]] && GIT_PROMPT_CHANGED="${Blue}✚ "
  [[ -z ${GIT_PROMPT_UNTRACKED+x} ]] && GIT_PROMPT_UNTRACKED="${Cyan}…"
  [[ -z ${GIT_PROMPT_STASHED+x} ]] && GIT_PROMPT_STASHED="${BoldBlue}⚑ "
  [[ -z ${GIT_PROMPT_CLEAN+x} ]] && GIT_PROMPT_CLEAN="${BoldGreen}✔"

  [[ -z ${GIT_PROMPT_COMMAND_OK+x} ]] && GIT_PROMPT_COMMAND_OK="${Green}✔"
  [[ -z ${GIT_PROMPT_COMMAND_FAIL+x} ]] && GIT_PROMPT_COMMAND_FAIL="${Red}✘-_LAST_COMMAND_STATE_"
  [[ -z ${GIT_PROMPT_VIRTUALENV+x} ]] && GIT_PROMPT_VIRTUALENV="(${Blue}_VIRTUALENV_${ResetColor}) "

  [[ -z ${GIT_PROMPT_START_USER+x} ]] && GIT_PROMPT_START_USER="_LAST_COMMAND_INDICATOR_ ${Yellow}${PathShort}${ResetColor}"
  [[ -z ${GIT_PROMPT_START_ROOT+x} ]] && GIT_PROMPT_START_ROOT="${GIT_PROMPT_START_USER}"
  [[ -z ${GIT_PROMPT_END_USER+x} ]] && GIT_PROMPT_END_USER=" \n${White}${Time12a}${ResetColor} $ "
  [[ -z ${GIT_PROMPT_END_ROOT+x} ]] && GIT_PROMPT_END_ROOT=" \n${White}${Time12a}${ResetColor} # "

  [[ -z ${GIT_PROMPT_SYMBOLS_AHEAD+x} ]] && GIT_PROMPT_SYMBOLS_AHEAD="↑·"
  [[ -z ${GIT_PROMPT_SYMBOLS_BEHIND+x} ]] && GIT_PROMPT_SYMBOLS_BEHIND="↓·"
  [[ -z ${GIT_PROMPT_SYMBOLS_PREHASH+x} ]] && GIT_PROMPT_SYMBOLS_PREHASH=":"
  [[ -z ${GIT_PROMPT_SYMBOLS_PRETAG+x} ]] && GIT_PROMPT_SYMBOLS_PRETAG=""
  [[ -z ${GIT_PROMPT_SYMBOLS_NO_REMOTE_TRACKING+x} ]] && GIT_PROMPT_SYMBOLS_NO_REMOTE_TRACKING="L"
}

# __gp_resolve_theme_target
# Resolves the active theme name and theme file path following PRD Section 5.1:
#   - Populates __GP_RESOLVED_THEME_NAME and __GP_RESOLVED_THEME_FILE
#   - Updates GIT_PROMPT_THEME to "Default" if an invalid theme or missing
#     "Custom" theme was explicitly requested.
__gp_resolve_theme_target() {
  local custom_file=${GIT_PROMPT_THEME_FILE:-"${HOME:-}/.git-prompt-colors.sh"}
  local default_file="${__GIT_PROMPT_DIR}/themes/Default.bgptheme"
  local requested=${GIT_PROMPT_THEME-}

  if [[ -z $requested ]]; then
    if [[ -f $custom_file && -r $custom_file ]]; then
      __GP_RESOLVED_THEME_NAME="Custom"
      __GP_RESOLVED_THEME_FILE=$custom_file
    else
      __GP_RESOLVED_THEME_NAME="Default"
      __GP_RESOLVED_THEME_FILE=$default_file
    fi
  elif [[ $requested == "Custom" ]]; then
    if [[ -f $custom_file && -r $custom_file ]]; then
      __GP_RESOLVED_THEME_NAME="Custom"
      __GP_RESOLVED_THEME_FILE=$custom_file
    else
      GIT_PROMPT_THEME="Default"
      __GP_RESOLVED_THEME_NAME="Default"
      __GP_RESOLVED_THEME_FILE=$default_file
    fi
  else
    local candidate="${__GIT_PROMPT_DIR}/themes/${requested}.bgptheme"
    if [[ -f $candidate && -r $candidate ]]; then
      __GP_RESOLVED_THEME_NAME=$requested
      __GP_RESOLVED_THEME_FILE=$candidate
    else
      GIT_PROMPT_THEME="Default"
      __GP_RESOLVED_THEME_NAME="Default"
      __GP_RESOLVED_THEME_FILE=$default_file
    fi
  fi
}

# __gp_load_theme
# Ensures colors and the resolved theme are loaded and cached for the session.
__gp_load_theme() {
  __gp_snapshot_user_baseline
  __gp_load_colors

  local __GP_RESOLVED_THEME_NAME="" __GP_RESOLVED_THEME_FILE=""
  __gp_resolve_theme_target

  # Include BlackOrWhite dynamic settings in cache key so tweaking them live in
  # the shell automatically re-evaluates the BlackOrWhite layout.
  local bow_sig=""
  if [[ $__GP_RESOLVED_THEME_NAME == "BlackOrWhite" ]]; then
    bow_sig="|${GIT_PROMPT_BLACK_OR_WHITE_THEME_PS1_COLOR-}|${GIT_PROMPT_BLACK_OR_WHITE_THEME_STYLE-}|${GIT_PROMPT_BLACK_OR_WHITE_THEME_VISIBLE_SECTIONS-}|${GIT_PROMPT_BLACK_OR_WHITE_THEME_ADD_OR_REPLACE_ICONS_IN_SECTIONS-}|${GIT_PROMPT_BLACK_OR_WHITE_THEME_ADD_EXTRA_SPACE_AFTER_ICONS-}|${__GP_EFFECTIVE_UID:-$EUID}"
  fi

  local cache_key="${__GP_LOADED_COLOR_FILE}|${__GP_RESOLVED_THEME_NAME}|${__GP_RESOLVED_THEME_FILE}|${SSH_CLIENT-}${bow_sig}"
  if [[ $__GP_CACHED_THEME_KEY == "$cache_key" ]]; then
    return 0
  fi

  # Restore session baseline and clear previous theme vars only when switching away from a cached theme
  if [[ -n $__GP_CACHED_THEME_KEY ]]; then
    __gp_restore_var_from_snapshot GIT_PROMPT_ONLY_IN_REPO "$__GP_BASE_ONLY_IN_REPO"
    __gp_restore_var_from_snapshot GIT_PROMPT_LEADING_SPACE "$__GP_BASE_LEADING_SPACE"
    __gp_restore_var_from_snapshot GIT_PROMPT_WITH_USERNAME_AND_REPO "$__GP_BASE_WITH_USERNAME_REPO"
    __gp_restore_var_from_snapshot GIT_PROMPT_USERNAME_REPO_SEPARATOR "$__GP_BASE_USERNAME_REPO_SEP"

    unset -f prompt_callback 2>/dev/null || true
    if (( __GP_BASE_HAS_USER_CALLBACK == 1 )) && [[ -n $__GP_BASE_USER_CALLBACK_DEF ]]; then
      eval "$__GP_BASE_USER_CALLBACK_DEF"
    fi
    __gp_unset_theme_vars
  fi

  Time12a="\A"
  PathShort="\w"
  NewLine="\n"

  unset -f override_git_prompt_colors 2>/dev/null || true
  if [[ -f $__GP_RESOLVED_THEME_FILE && -r $__GP_RESOLVED_THEME_FILE ]]; then
    # shellcheck source=/dev/null
    source "$__GP_RESOLVED_THEME_FILE"
  fi
  if declare -F override_git_prompt_colors >/dev/null 2>&1; then
    override_git_prompt_colors
    unset -f override_git_prompt_colors 2>/dev/null || true
  fi

  __gp_apply_default_theme_fallbacks

  __GP_ACTIVE_THEME_NAME=$__GP_RESOLVED_THEME_NAME
  __GP_ACTIVE_THEME_FILE=$__GP_RESOLVED_THEME_FILE
  __GP_CACHED_THEME_KEY=$cache_key
  return 0
}

# __gp_get_prompt_start_end
# Evaluates Prompt Start and Prompt End according to PRD Section 3.9:
#   - GIT_PROMPT_START (even if "") overrides GIT_PROMPT_START_ROOT / GIT_PROMPT_START_USER
#   - GIT_PROMPT_END (even if "") overrides GIT_PROMPT_END_ROOT / GIT_PROMPT_END_USER
#   - Effective UID (__GP_EFFECTIVE_UID can override EUID/UID in automated tests)
__gp_get_prompt_start_end() {
  local eff_uid=${__GP_EFFECTIVE_UID:-${EUID:-${UID:-1000}}}

  if [[ -n ${GIT_PROMPT_START+x} ]]; then
    __GP_PROMPT_START=$GIT_PROMPT_START
  elif (( eff_uid == 0 )); then
    __GP_PROMPT_START=$GIT_PROMPT_START_ROOT
  else
    __GP_PROMPT_START=$GIT_PROMPT_START_USER
  fi

  if [[ -n ${GIT_PROMPT_END+x} ]]; then
    __GP_PROMPT_END=$GIT_PROMPT_END
  elif (( eff_uid == 0 )); then
    __GP_PROMPT_END=$GIT_PROMPT_END_ROOT
  else
    __GP_PROMPT_END=$GIT_PROMPT_END_USER
  fi
}
