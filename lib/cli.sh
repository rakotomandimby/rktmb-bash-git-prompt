# shellcheck shell=bash
# lib/cli.sh - Interactive user commands (PRD Section 6.1):
#   git_prompt_help / help_git_prompt
#   git_prompt_examples
#   git_prompt_color_samples
#   git_prompt_list_themes
#   git_prompt_make_custom_theme [<base_theme>]
#   git_prompt_toggle
#   git_prompt_reset

git_prompt_help() {
  __gp_load_theme

  __gp_print_colored "The git prompt format is ${GIT_PROMPT_PREFIX}<BRANCH><TRACKING>${GIT_PROMPT_SEPARATOR}<LOCALSTATUS>${GIT_PROMPT_SUFFIX}${ResetColor}"
  printf '\n'
  __gp_print_colored "BRANCH is a branch name, such as ${GIT_PROMPT_MASTER_BRANCH}master${ResetColor} or ${GIT_PROMPT_BRANCH}stage${ResetColor}, a tag name, or commit"
  __gp_print_colored "hash prefixed with '${GIT_PROMPT_SYMBOLS_PREHASH:-:}', such as ${GIT_PROMPT_DETACHED_HEAD}${GIT_PROMPT_SYMBOLS_PREHASH:-:}70c2952${ResetColor}."
  __gp_print_colored "Active Git operations append state suffixes such as |REBASE-i 1/3, |MERGING, |CHERRY-PICKING, |REVERTING, or |BISECTING."
  printf '\n'
  __gp_print_colored "TRACKING indicates how the local branch differs from the"
  __gp_print_colored "remote branch.  It can be empty, or one of:"
  __gp_print_colored "    ${GIT_PROMPT_REMOTE}${ResetColor}${GIT_PROMPT_SYMBOLS_AHEAD}N${ResetColor} - ahead of remote by N commits"
  __gp_print_colored "    ${GIT_PROMPT_REMOTE}${ResetColor}${GIT_PROMPT_SYMBOLS_BEHIND}M${ResetColor} - behind remote by M commits"
  __gp_print_colored "    ${GIT_PROMPT_REMOTE}${ResetColor}${GIT_PROMPT_SYMBOLS_BEHIND}M${GIT_PROMPT_SYMBOLS_AHEAD}N${ResetColor} - branches diverged, other by M commits, yours by N commits"
  __gp_print_colored "    ${GIT_PROMPT_REMOTE}${ResetColor}${GIT_PROMPT_SYMBOLS_NO_REMOTE_TRACKING}${ResetColor} - local branch, not remotely tracked"
  printf '\n'
  __gp_print_colored "LOCALSTATUS is one of the following:"
  __gp_print_colored "    ${GIT_PROMPT_CLEAN}${ResetColor} - repository clean"
  __gp_print_colored "  or a combination of:"
  __gp_print_colored "    ${GIT_PROMPT_STAGED}N${ResetColor} - N staged files (will be committed)"
  __gp_print_colored "    ${GIT_PROMPT_CONFLICTS}N${ResetColor} - N files with merge conflicts"
  __gp_print_colored "    ${GIT_PROMPT_CHANGED}N${ResetColor} - N changed but *unstaged* files"
  __gp_print_colored "    ${GIT_PROMPT_UNTRACKED}N${ResetColor} - N untracked files"
  __gp_print_colored "    ${GIT_PROMPT_STASHED}N${ResetColor} - N stashed files"
  printf '\n'
  __gp_print_colored "See 'git_prompt_examples' for examples."
}

help_git_prompt() {
  git_prompt_help "$@"
}

git_prompt_examples() {
  __gp_load_theme

  local p=${GIT_PROMPT_PREFIX}
  local s=${GIT_PROMPT_SUFFIX}
  local sep=${GIT_PROMPT_SEPARATOR}
  local b=${GIT_PROMPT_BRANCH}
  local m=${GIT_PROMPT_MASTER_BRANCH}
  local d=${GIT_PROMPT_DETACHED_HEAD}
  local rem=${GIT_PROMPT_REMOTE}
  local r=${ResetColor}

  __gp_print_colored "These are examples of the Git prompt:"
  printf '\n'
  __gp_print_colored "  ${p}${m}master${r}${rem}${GIT_PROMPT_SYMBOLS_AHEAD}3${r}${sep}${GIT_PROMPT_CHANGED}1${r}${s}  - on branch 'master', ahead of remote by 3 commits, 1 file changed but not staged"
  __gp_print_colored "  ${p}${b}status${r}${sep}${GIT_PROMPT_STAGED}2${r}${s}     - on branch 'status', 2 files staged"
  __gp_print_colored "  ${p}${m}master${r}${sep}${GIT_PROMPT_CHANGED}7${r}${GIT_PROMPT_UNTRACKED}4${r}${s}   - on branch 'master', 7 files changed, 4 files untracked"
  __gp_print_colored "  ${p}${m}master${r}${sep}${GIT_PROMPT_CONFLICTS}2${r}${GIT_PROMPT_CHANGED}3${r}${s}  - on branch 'master', 2 conflicts, 3 files changed"
  __gp_print_colored "  ${p}${m}master${r}${sep}${GIT_PROMPT_STASHED}2${r}${s}     - on branch 'master', 2 stash entries"
  __gp_print_colored "  ${p}${b}experimental${r}${rem}${GIT_PROMPT_SYMBOLS_BEHIND}2${GIT_PROMPT_SYMBOLS_AHEAD}3${r}${sep}${GIT_PROMPT_CLEAN}${r}${s} - on branch 'experimental'; your branch has diverged by 3 commits, remote by 2 commits; the repository is otherwise clean"
  __gp_print_colored "  ${p}${d}${GIT_PROMPT_SYMBOLS_PREHASH}70c2952${r}${sep}${GIT_PROMPT_CLEAN}${r}${s}    - not on any branch; parent commit has hash '70c2952'; the repository is otherwise clean"
  __gp_print_colored "  ${p}${b}extra-features${r}${rem}${GIT_PROMPT_SYMBOLS_NO_REMOTE_TRACKING}${r}${sep}${GIT_PROMPT_CHANGED}2${r}${GIT_PROMPT_UNTRACKED}4${r}${s} - on branch 'extra-features'; no remote set (see git push -u), 2 files changed and 4 untracked files exist"
}

git_prompt_color_samples() {
  __gp_load_colors

  local -a prefixes=("" "Dim" "Bold" "Bright")
  local color prefix var_name val
  for color in "${ColorNames[@]}"; do
    for prefix in "${prefixes[@]}"; do
      var_name="${prefix}${color}"
      val=${!var_name}
      __gp_print_colored "${val}${var_name}${ResetColor}"
    done
  done
}

git_prompt_list_themes() {
  __gp_load_theme

  local active=${__GP_ACTIVE_THEME_NAME:-Default}
  local theme_dir="${__GIT_PROMPT_DIR}/themes"
  local -a theme_files=()
  local LC_ALL=C
  shopt -s nullglob
  theme_files=("$theme_dir"/*.bgptheme)
  shopt -u nullglob

  local file name
  for file in "${theme_files[@]}"; do
    name=${file##*/}
    name=${name%.bgptheme}
    if [[ $name == "$active" ]]; then
      __gp_print_colored "${Red}* ${name}${ResetColor}"
    else
      printf '%s\n' "$name"
    fi
  done

  if [[ $active == "Custom" ]]; then
    __gp_print_colored "${Magenta}* Custom${ResetColor}"
  else
    __gp_print_colored "${Blue}Custom${ResetColor}"
  fi
}

git_prompt_make_custom_theme() {
  __gp_load_colors

  local base_theme=${1:-}
  local target_file=${GIT_PROMPT_THEME_FILE:-"${HOME}/.git-prompt-colors.sh"}

  if [[ -f $target_file && -r $target_file ]]; then
    __gp_print_colored "${Red}You have already created a custom theme in '${target_file}'! Do not overwrite it!${ResetColor}"
    return 1
  fi

  if [[ $base_theme == "Custom" ]]; then
    __gp_print_colored "${Red}You cannot use the 'Custom' theme as a base theme!${ResetColor}"
    return 1
  fi

  local src_file=""
  local used_base="Default"
  if [[ -n $base_theme && -f "${__GIT_PROMPT_DIR}/themes/${base_theme}.bgptheme" && -r "${__GIT_PROMPT_DIR}/themes/${base_theme}.bgptheme" ]]; then
    src_file="${__GIT_PROMPT_DIR}/themes/${base_theme}.bgptheme"
    used_base=$base_theme
  else
    if [[ -n $base_theme && $base_theme != "Default" ]]; then
      __gp_print_colored "${Yellow}Theme '${base_theme}' not found; using 'Default' as base theme.${ResetColor}"
    fi
    src_file="${__GIT_PROMPT_DIR}/themes/Custom.bgptemplate"
    used_base="Default"
  fi

  if ! command cp "$src_file" "$target_file"; then
    __gp_print_colored "${Red}Failed to write custom theme to '${target_file}'.${ResetColor}"
    return 1
  fi

  __gp_print_colored "${Green}Created custom theme in '${Magenta}${target_file}${Green}' using base theme '${Magenta}${used_base}${Green}'.${ResetColor}"
  __gp_print_colored "${Green}Please add '${Magenta}GIT_PROMPT_THEME=Custom${Green}' to your .bashrc to activate this theme!${ResetColor}"
  return 0
}

git_prompt_toggle() {
  if [[ ${GIT_PROMPT_DISABLE:-0} == "1" ]]; then
    GIT_PROMPT_DISABLE=0
  else
    GIT_PROMPT_DISABLE=1
  fi
}

git_prompt_reset() {
  __GP_LOADED_COLOR_FILE=""
  __GP_CACHED_THEME_KEY=""
  __GP_ACTIVE_THEME_NAME=""
  __GP_ACTIVE_THEME_FILE=""
  __gp_unset_theme_vars
  if (( __GP_DIR_AUTO_DETECTED == 1 )); then
    __gp_resolve_install_dir "${__GP_ENTRYPOINT_SOURCE:-${BASH_SOURCE[0]}}"
  fi
}
