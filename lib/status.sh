# shellcheck shell=bash
# lib/status.sh - Lock-free Git repository discovery, in-progress operation
# detection, and porcelain-v2 working-tree/index/submodule/stash status engine.

# Global status outputs populated by __gp_evaluate_git_status:
declare -g __GP_GIT_TOPLEVEL=""
declare -g __GP_GIT_DIR=""
declare -g __GP_GIT_COMMON_DIR=""

declare -g __GP_STATUS_BRANCH=""
declare -g __GP_STATUS_BASE_BRANCH=""
declare -g __GP_STATUS_IS_DETACHED=0
declare -g __GP_STATUS_IS_UNBORN=0
declare -g __GP_STATUS_HAS_UPSTREAM=0
declare -g __GP_STATUS_REMOTE=""
declare -g __GP_STATUS_UPSTREAM=""
declare -g __GP_STATUS_STAGED=0
declare -g __GP_STATUS_CONFLICTS=0
declare -g __GP_STATUS_CHANGED=0
declare -g __GP_STATUS_UNTRACKED=0
declare -g __GP_STATUS_STASHED=0
declare -g __GP_STATUS_CLEAN=1

# __gp_discover_repo
# Detects whether PWD is inside a valid Git working tree and resolves:
#   __GP_GIT_TOPLEVEL, __GP_GIT_DIR, __GP_GIT_COMMON_DIR
# Returns 0 if inside a Git working tree, 1 otherwise.
__gp_discover_repo() {
  __GP_GIT_TOPLEVEL=""
  __GP_GIT_DIR=""
  __GP_GIT_COMMON_DIR=""

  local out
  out=$(LC_ALL=C git --no-optional-locks rev-parse \
    --is-inside-work-tree \
    --show-toplevel \
    --git-dir \
    --git-common-dir 2>/dev/null) || return 1

  local -a lines=()
  mapfile -t lines <<< "$out"
  [[ ${lines[0]:-} == "true" ]] || return 1
  [[ -n ${lines[1]:-} && -n ${lines[2]:-} && -n ${lines[3]:-} ]] || return 1

  __GP_GIT_TOPLEVEL=${lines[1]}
  __GP_GIT_DIR=${lines[2]}
  __GP_GIT_COMMON_DIR=${lines[3]}
  return 0
}

# __gp_read_first_line <file_path>
# Reads the first line of <file_path> into REPLY, trimming whitespace.
__gp_read_first_line() {
  REPLY=""
  [[ -f $1 && -r $1 ]] || return 1
  local line=""
  IFS= read -r line < "$1" || [[ -n $line ]] || return 1
  __gp_trim "$line"
  return 0
}

# __gp_detect_in_progress_op <git_dir>
# Inspects <git_dir> for active multi-step or conflict-paused Git operations
# without running any subprocesses.
# Populates:
#   __GP_OP_SUFFIX       (e.g. "|REBASE-i 1/3", "|MERGING", or "")
#   __GP_OP_HEAD_BRANCH  (original branch name during rebase, e.g. "feature", or "")
__gp_detect_in_progress_op() {
  local gdir=${1%/}
  __GP_OP_SUFFIX=""
  __GP_OP_HEAD_BRANCH=""

  local REPLY="" step="" total="" head_name=""
  if [[ -d "$gdir/rebase-merge" ]]; then
    if __gp_read_first_line "$gdir/rebase-merge/head-name"; then
      head_name=$REPLY
      if [[ $head_name != "detached HEAD" ]]; then
        __GP_OP_HEAD_BRANCH=${head_name#refs/heads/}
      fi
    fi
    __gp_read_first_line "$gdir/rebase-merge/msgnum" && step=$REPLY
    __gp_read_first_line "$gdir/rebase-merge/end" && total=$REPLY
    if [[ -f "$gdir/rebase-merge/interactive" ]]; then
      __GP_OP_SUFFIX="|REBASE-i"
    else
      __GP_OP_SUFFIX="|REBASE-m"
    fi
    if [[ -n $step && -n $total ]]; then
      __GP_OP_SUFFIX+=" ${step}/${total}"
    fi
  elif [[ -d "$gdir/rebase-apply" ]]; then
    __gp_read_first_line "$gdir/rebase-apply/next" && step=$REPLY
    __gp_read_first_line "$gdir/rebase-apply/last" && total=$REPLY
    if [[ -f "$gdir/rebase-apply/rebasing" ]]; then
      if __gp_read_first_line "$gdir/rebase-apply/head-name"; then
        head_name=$REPLY
        if [[ $head_name != "detached HEAD" ]]; then
          __GP_OP_HEAD_BRANCH=${head_name#refs/heads/}
        fi
      fi
      __GP_OP_SUFFIX="|REBASE"
    elif [[ -f "$gdir/rebase-apply/applying" ]]; then
      __GP_OP_SUFFIX="|AM"
    else
      __GP_OP_SUFFIX="|AM/REBASE"
    fi
    if [[ -n $step && -n $total ]]; then
      __GP_OP_SUFFIX+=" ${step}/${total}"
    fi
  elif [[ -f "$gdir/MERGE_HEAD" ]]; then
    __GP_OP_SUFFIX="|MERGING"
  elif [[ -f "$gdir/CHERRY_PICK_HEAD" ]]; then
    __GP_OP_SUFFIX="|CHERRY-PICKING"
  elif [[ -f "$gdir/REVERT_HEAD" ]]; then
    __GP_OP_SUFFIX="|REVERTING"
  elif [[ -f "$gdir/BISECT_LOG" ]]; then
    __GP_OP_SUFFIX="|BISECTING"
  fi
}

# __gp_run_custom_status_command <eff_untracked> <eff_submodules> <eff_ignore_stash>
# Executes user-configured GIT_PROMPT_STATUS_COMMAND and maps its output fields,
# performing literal placeholder token substitution (_AHEAD_, _BEHIND_,
# _NO_REMOTE_TRACKING_, _PRETAG_, _PREHASH_) without pathname expansion.
__gp_run_custom_status_command() {
  local eff_untracked=$1
  local eff_submodules=$2
  local eff_ignore_stash=$3

  local out
  out=$(
    LC_ALL=C \
    GIT_PROMPT_SHOW_UNTRACKED_FILES="$eff_untracked" \
    GIT_PROMPT_IGNORE_SUBMODULES="$eff_submodules" \
    GIT_PROMPT_IGNORE_STASH="$eff_ignore_stash" \
    "$GIT_PROMPT_STATUS_COMMAND" 2>/dev/null
  ) || return 1

  [[ -z $out ]] && return 1

  local -a lines=()
  mapfile -t lines <<< "$out"

  __GP_STATUS_BRANCH=${lines[0]:-}
  __GP_STATUS_REMOTE=${lines[1]:-}
  __GP_STATUS_UPSTREAM=${lines[2]:-}
  __GP_STATUS_STAGED=${lines[3]:-0}
  __GP_STATUS_CONFLICTS=${lines[4]:-0}
  __GP_STATUS_CHANGED=${lines[5]:-0}
  __GP_STATUS_UNTRACKED=${lines[6]:-0}
  __GP_STATUS_STASHED=${lines[7]:-0}
  __GP_STATUS_CLEAN=${lines[8]:-0}

  # Substitute symbolic placeholders without glob expansion
  local var
  for var in __GP_STATUS_BRANCH __GP_STATUS_REMOTE __GP_STATUS_UPSTREAM; do
    __gp_replace_all "$var" "_AHEAD_" "${GIT_PROMPT_SYMBOLS_AHEAD:-↑·}"
    __gp_replace_all "$var" "_BEHIND_" "${GIT_PROMPT_SYMBOLS_BEHIND:-↓·}"
    __gp_replace_all "$var" "_NO_REMOTE_TRACKING_" "${GIT_PROMPT_SYMBOLS_NO_REMOTE_TRACKING:-L}"
    __gp_replace_all "$var" "_PRETAG_" "${GIT_PROMPT_SYMBOLS_PRETAG-}"
    __gp_replace_all "$var" "_PREHASH_" "${GIT_PROMPT_SYMBOLS_PREHASH:-:}"
  done

  __GP_STATUS_BASE_BRANCH=${__GP_STATUS_BRANCH%%|*}
  __GP_STATUS_IS_DETACHED=0
  __GP_STATUS_IS_UNBORN=0
  if [[ -n $__GP_STATUS_UPSTREAM ]] || [[ $__GP_STATUS_REMOTE != "${GIT_PROMPT_SYMBOLS_NO_REMOTE_TRACKING:-L}" ]]; then
    __GP_STATUS_HAS_UPSTREAM=1
  else
    __GP_STATUS_HAS_UPSTREAM=0
  fi
  if [[ $__GP_STATUS_REMOTE == "." ]]; then
    __GP_STATUS_REMOTE=""
  fi
  if [[ $__GP_STATUS_UPSTREAM == "." ]]; then
    __GP_STATUS_UPSTREAM=""
  fi
  return 0
}

# __gp_evaluate_git_status <git_dir> <eff_untracked> <eff_submodules> <eff_ignore_stash>
# Evaluates full repository branch, operation suffix, upstream, divergence, and
# local file/stash counts using lock-free porcelain-v2 status inspection.
__gp_evaluate_git_status() {
  local git_dir=$1
  local eff_untracked=${2:-normal}
  local eff_submodules=${3:-0}
  local eff_ignore_stash=${4:-0}

  __GP_STATUS_BRANCH=""
  __GP_STATUS_BASE_BRANCH=""
  __GP_STATUS_IS_DETACHED=0
  __GP_STATUS_IS_UNBORN=0
  __GP_STATUS_HAS_UPSTREAM=0
  __GP_STATUS_REMOTE=""
  __GP_STATUS_UPSTREAM=""
  __GP_STATUS_STAGED=0
  __GP_STATUS_CONFLICTS=0
  __GP_STATUS_CHANGED=0
  __GP_STATUS_UNTRACKED=0
  __GP_STATUS_STASHED=0
  __GP_STATUS_CLEAN=1

  if [[ -n ${GIT_PROMPT_STATUS_COMMAND:-} ]]; then
    __gp_run_custom_status_command "$eff_untracked" "$eff_submodules" "$eff_ignore_stash"
    return $?
  fi

  local -a status_args=(--no-optional-locks status --porcelain=v2 -z --branch)
  case $eff_untracked in
    no)     status_args+=(-uno) ;;
    all)    status_args+=(-uall) ;;
    *)      status_args+=(-unormal) ;;
  esac

  if [[ $eff_submodules == "1" ]]; then
    status_args+=(--ignore-submodules=all)
  fi

  if [[ $eff_ignore_stash != "1" ]]; then
    status_args+=(--show-stash)
  fi

  local oid="" head="" upstream=""
  local has_upstream=0 has_ab=0 ahead=0 behind=0
  local staged=0 conflicts=0 changed=0 untracked=0 stashed=0
  local rec x y rest

  # Read NUL-delimited porcelain=v2 output from process substitution and verify
  # exit status via wait $! so corrupted repositories fail cleanly.
  local status_fd
  exec {status_fd}< <(LC_ALL=C git "${status_args[@]}" 2>/dev/null)
  local git_pid=$!

  while IFS= read -r -d '' -u "$status_fd" rec; do
    case $rec in
      "# branch.oid "*)
        oid=${rec#"# branch.oid "}
        ;;
      "# branch.head "*)
        head=${rec#"# branch.head "}
        ;;
      "# branch.upstream "*)
        upstream=${rec#"# branch.upstream "}
        has_upstream=1
        ;;
      "# branch.ab "*)
        rest=${rec#"# branch.ab "}
        # Format: +<ahead> -<behind>
        ahead=${rest%% *}
        ahead=${ahead#+}
        behind=${rest#* }
        behind=${behind#-}
        has_ab=1
        ;;
      "# stash "*)
        stashed=${rec#"# stash "}
        ;;
      "1 "*)
        x=${rec:2:1}
        y=${rec:3:1}
        [[ $x != "." ]] && (( ++staged ))
        [[ $y != "." ]] && (( ++changed ))
        ;;
      "2 "*)
        x=${rec:2:1}
        y=${rec:3:1}
        [[ $x != "." ]] && (( ++staged ))
        [[ $y != "." ]] && (( ++changed ))
        # Consume the second NUL-terminated field (<origPath>) for rename/copy records
        IFS= read -r -d '' -u "$status_fd" _ || true
        ;;
      "u "*)
        (( ++conflicts ))
        ;;
      "? "*)
        (( ++untracked ))
        ;;
    esac
  done
  exec {status_fd}<&-
  wait "$git_pid" || return 1

  # Fallback if git status exited 0 without emitting a # branch.head header
  [[ -n $head ]] || return 1

  local __GP_OP_SUFFIX="" __GP_OP_HEAD_BRANCH=""
  __gp_detect_in_progress_op "$git_dir"

  local base_ref="" is_detached=0 is_unborn=0
  if [[ $oid == "(initial)" ]]; then
    is_unborn=1
  fi

  if [[ -n $__GP_OP_HEAD_BRANCH ]]; then
    # During a branch rebase, Git detaches HEAD onto the replayed commit,
    # but the prompt must display the rebasing branch name from head-name.
    base_ref=$__GP_OP_HEAD_BRANCH
    is_detached=0
    if (( has_upstream == 0 )); then
      local up_check ab_check
      if up_check=$(LC_ALL=C git --no-optional-locks rev-parse --abbrev-ref "${base_ref}@{upstream}" 2>/dev/null) && [[ -n $up_check ]]; then
        upstream=$up_check
        has_upstream=1
        if ab_check=$(LC_ALL=C git --no-optional-locks rev-list --left-right --count "${upstream}...HEAD" 2>/dev/null) && [[ -n $ab_check ]]; then
          behind=${ab_check%%[[:space:]]*}
          ahead=${ab_check##*[[:space:]]}
          has_ab=1
        fi
      fi
    fi
  elif [[ $head == "(detached)" ]]; then
    is_detached=1
    local exact_tag short_sha
    if exact_tag=$(LC_ALL=C git --no-optional-locks describe --tags --exact-match HEAD 2>/dev/null) && [[ -n $exact_tag ]]; then
      base_ref="${GIT_PROMPT_SYMBOLS_PRETAG-}${exact_tag}"
    else
      short_sha=$(LC_ALL=C git --no-optional-locks rev-parse --short HEAD 2>/dev/null) || return 1
      base_ref="${GIT_PROMPT_SYMBOLS_PREHASH:-:}${short_sha}"
    fi
  else
    base_ref=$head
    is_detached=0
  fi

  __GP_STATUS_BASE_BRANCH=$base_ref
  __GP_STATUS_BRANCH="${base_ref}${__GP_OP_SUFFIX}"
  __GP_STATUS_IS_DETACHED=$is_detached
  __GP_STATUS_IS_UNBORN=$is_unborn

  # Trim upstream whitespace if present
  if (( has_upstream == 1 && is_unborn == 0 && is_detached == 0 )); then
    local REPLY=""
    __gp_trim "$upstream"
    __GP_STATUS_UPSTREAM=$REPLY
    __GP_STATUS_HAS_UPSTREAM=1
  else
    __GP_STATUS_UPSTREAM=""
    __GP_STATUS_HAS_UPSTREAM=0
  fi

  # Remote tracking indicator resolution (PRD Section 3.5.1)
  local remote_str=""
  if (( is_unborn == 1 )); then
    remote_str=${GIT_PROMPT_SYMBOLS_NO_REMOTE_TRACKING:-L}
  elif (( is_detached == 1 )); then
    remote_str=""
  elif (( has_upstream == 0 || has_ab == 0 )); then
    remote_str=${GIT_PROMPT_SYMBOLS_NO_REMOTE_TRACKING:-L}
    __GP_STATUS_HAS_UPSTREAM=0
    __GP_STATUS_UPSTREAM=""
  else
    # Synchronized when ahead == 0 && behind == 0; behind precedes ahead when diverged
    if (( behind > 0 )); then
      remote_str+="${GIT_PROMPT_SYMBOLS_BEHIND:-↓·}${behind}"
    fi
    if (( ahead > 0 )); then
      remote_str+="${GIT_PROMPT_SYMBOLS_AHEAD:-↑·}${ahead}"
    fi
  fi
  __GP_STATUS_REMOTE=$remote_str

  __GP_STATUS_STAGED=$staged
  __GP_STATUS_CONFLICTS=$conflicts
  __GP_STATUS_CHANGED=$changed
  __GP_STATUS_UNTRACKED=$untracked
  if [[ $eff_ignore_stash == "1" ]]; then
    __GP_STATUS_STASHED=0
  else
    __GP_STATUS_STASHED=$stashed
  fi

  if (( __GP_STATUS_STAGED == 0 && __GP_STATUS_CONFLICTS == 0 && __GP_STATUS_CHANGED == 0 && __GP_STATUS_UNTRACKED == 0 && __GP_STATUS_STASHED == 0 )); then
    __GP_STATUS_CLEAN=1
  else
    __GP_STATUS_CLEAN=0
  fi

  return 0
}
