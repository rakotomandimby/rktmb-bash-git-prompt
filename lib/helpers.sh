# shellcheck shell=bash
# lib/helpers.sh - Core string manipulation, PS1 sanitization, Readline helpers,
# and user/theme helper commands (gp_*).

# __gp_replace_all <target_var_name> <needle> <replacement>
# Performs literal replacement of all occurrences of <needle> with <replacement>
# inside the variable named <target_var_name>, completely immune to pathname
# expansion (globbing), pattern metacharacters (*, ?, [...]), and Bash 5.2+
# patsub_replacement (&).
__gp_replace_all() {
  local -n _gp_r_target=$1
  local _gp_r_needle=$2
  local _gp_r_rep=$3

  [[ -z $_gp_r_needle || $_gp_r_target != *"$_gp_r_needle"* ]] && return 0

  local _gp_r_rest=$_gp_r_target
  local _gp_r_out="" _gp_r_prefix=""
  while [[ $_gp_r_rest == *"$_gp_r_needle"* ]]; do
    _gp_r_prefix=${_gp_r_rest%%"$_gp_r_needle"*}
    _gp_r_out+="${_gp_r_prefix}${_gp_r_rep}"
    _gp_r_rest=${_gp_r_rest#*"$_gp_r_needle"}
  done
  _gp_r_target="${_gp_r_out}${_gp_r_rest}"
}

# __gp_escape_for_ps1 <raw_string>
# Protects untrusted dynamic repository/filesystem values (branch names, tag
# names, remote URLs, virtualenv names, directory paths) before insertion into
# PS1 so Bash's two-stage prompt evaluator (Stage 1: backslash prompt escapes;
# Stage 2: promptvars parameter/command/arithmetic expansion) renders the text
# verbatim without ever executing $(...), `...`, or expanding $VAR.
# Sets REPLY to the safe string.
__gp_escape_for_ps1() {
  local s=${1:-}
  # Escape backslashes for Stage 1 prompt escape decoding (\\ -> \)
  s=${s//\\/\\\\}
  if shopt -q promptvars; then
    # Stage 1 decodes \\ -> \ and leaves $ untouched (even when UID==0, unlike \$),
    # handing \$ and \` to Stage 2 (promptvars) so command/var expansion is suppressed.
    s=${s//\$/\\\$}
    s=${s//\`/\\\`}
  fi
  REPLY=$s
}

# __gp_strip_readline <string>
# Strips Readline non-printing delimiters (\[, \], \001, \002) and expands
# backslash escape sequences (\033, \e, \n, etc.) into REPLY for direct terminal output.
__gp_strip_readline() {
  local s=${1:-}
  s=${s//\\\[/}
  s=${s//\\\]/}
  s=${s//$'\001'/}
  s=${s//$'\002'/}
  printf -v REPLY '%b' "$s"
}

# __gp_print_colored <string>
# Prints a prompt-formatted colored string directly to standard output with
# Readline markers removed.
__gp_print_colored() {
  local REPLY=""
  __gp_strip_readline "${1:-}"
  printf '%s\n' "$REPLY"
}

# __gp_trim <string>
# Trims leading and trailing whitespace into REPLY.
__gp_trim() {
  local s=${1:-}
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  REPLY=$s
}

# gp_set_window_title <title>
# Outputs the non-printing XTerm OSC window-title control sequence wrapped in
# Readline non-printing markers. Strips raw control characters from <title> to
# prevent terminal escape injection from untrusted directory names.
gp_set_window_title() {
  local title=${1:-}
  local LC_ALL=C
  title=${title//[$'\001'-$'\037'$'\177']/}
  local REPLY=""
  __gp_escape_for_ps1 "$title"
  printf '%s' "\[\033]0;${REPLY}\007\]"
}

# gp_truncate_pwd [<max_length>]
# Replaces leading $HOME in $PWD with ~. If the resulting character length
# exceeds <max_length> (default: COLUMNS / 3, using 80 if COLUMNS is unset),
# truncates from the left and prepends "..." so total length equals <max_length>.
# Outputs without a trailing newline.
gp_truncate_pwd() {
  local cols=${COLUMNS:-80}
  [[ $cols =~ ^[0-9]+$ && $cols -gt 0 ]] || cols=80
  local max_len=${1:-$(( cols / 3 ))}
  if [[ ! $max_len =~ ^[0-9]+$ || $max_len -le 0 ]]; then
    max_len=$(( cols / 3 ))
  fi

  local tilde="~"
  local newPWD=$PWD
  if [[ -n ${HOME:-} ]]; then
    local home_clean=${HOME%/}
    if [[ $newPWD == "$home_clean" ]]; then
      newPWD=$tilde
    elif [[ -n $home_clean && $newPWD == "$home_clean/"* ]]; then
      newPWD="${tilde}/${newPWD#"$home_clean"/}"
    fi
  fi

  if (( ${#newPWD} > max_len )); then
    if (( max_len > 3 )); then
      local keep=$(( max_len - 3 ))
      newPWD="...${newPWD: -keep}"
    else
      newPWD=${newPWD:0:max_len}
    fi
  fi

  printf '%s' "$newPWD"
}

# __gp_format_exit_status_reply <code>
# In-process helper that formats exit status into REPLY without spawning a subshell.
__gp_format_exit_status_reply() {
  local status=${1:-0}
  if [[ $status =~ ^[0-9]+$ ]] && (( 10#$status > 128 )); then
    local sig=$(( 10#$status - 128 ))
    local sig_name
    if sig_name=$(builtin kill -l "$sig" 2>/dev/null) && [[ -n $sig_name ]]; then
      sig_name=${sig_name#SIG}
      if [[ ! $sig_name =~ ^[0-9]+$ ]]; then
        REPLY=$sig_name
        return 0
      fi
    fi
  fi
  REPLY=$status
}

# gp_format_exit_status <code>
# Formats integer exit codes > 128 as symbolic OS signal names (exit_code - 128)
# without a SIG prefix when mapped by `kill -l`, falling back to the raw value
# if unmapped or <= 128.
gp_format_exit_status() {
  local REPLY=""
  __gp_format_exit_status_reply "${1:-0}"
  printf '%s' "$REPLY"
}

# gp_format_username_repo [<url>]
# Extracts <owner>/<repo> from the active repository's remote.origin.url (or an
# explicit URL argument for testing), handling HTTPS (with or without embedded
# user@ credentials/ports), SSH (ssh://...), and SCP-like (git@host:owner/repo.git)
# URLs, stripping schemes, user/host prefixes, and trailing .git suffixes.
gp_format_username_repo() {
  local url=${1:-}
  if [[ -z $url ]]; then
    url=$(LC_ALL=C git --no-optional-locks config --get remote.origin.url 2>/dev/null) || return 0
  fi
  [[ -z $url ]] && return 0

  # Strip trailing slashes and .git suffix
  while [[ $url == */ ]]; do
    url=${url%/}
  done
  url=${url%.git}
  while [[ $url == */ ]]; do
    url=${url%/}
  done

  if [[ $url == *://* ]]; then
    # Protocol URL: https://[user[:pass]@]host[:port]/owner/repo
    url=${url#*://}
    if [[ $url == */* ]]; then
      url=${url#*/}
    else
      return 0
    fi
  elif [[ $url == *:* ]]; then
    # SCP-like syntax: [user@]host:[/]owner/repo
    url=${url#*:}
    while [[ $url == /* ]]; do
      url=${url#/}
    done
  else
    return 0
  fi

  # If the remaining path has more than 2 segments (e.g. subgroups), keep last 2
  while [[ $url == */*/* ]]; do
    url=${url#*/}
  done

  if [[ $url == ?*/?* ]]; then
    printf '%s' "$url"
  fi
}
