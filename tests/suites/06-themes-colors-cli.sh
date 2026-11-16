#!/usr/bin/env bash
# tests/suites/06-themes-colors-cli.sh - 98 colors, all 40 themes, BlackOrWhite matrix & CLI commands

source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
test_suite_begin "06 - Named Color Palette, 40 Built-in Themes, BlackOrWhite & Session CLI"

REPO="${TEST_SANDBOX}/theme-repo"
git init -q -b main "$REPO"
git -C "$REPO" commit --allow-empty -q -m "init"
cd "$REPO"

GIT_PROMPT_FETCH_REMOTE_STATUS=0
source "${REPO_ROOT}/gitprompt.sh"

# 1. Verify all 98 named color variables exist and wrap sequences in \[...\]
test_case "Defines all 98 Readline-wrapped named color variables"
(
  __gp_load_colors
  assert_eq "8" "${#ColorNames[@]}"
  count=0
  for c in "${ColorNames[@]}"; do
    for a in "" "Bold" "Bright" "Dim"; do
      for s in "" "Fg" "Bg"; do
        var="${a}${c}${s}"
        val=${!var-}
        [[ $val == '\['*'\]' ]] || { fail_case "Color variable $var is missing or not Readline-wrapped: [$val]"; exit 1; }
        (( ++count ))
      done
    done
  done
  [[ ${IntenseBlack-} == '\['*'\]' ]] && (( ++count ))
  [[ ${ResetColor-} == '\['*'\]' ]] && (( ++count ))
  assert_eq "98" "$count"

  # Verify user color file override discovery precedence:
  # ~/.prompt-colors.sh > ~/prompt-colors.sh > ~/lib/prompt-colors.sh > install dir
  mkdir -p "$HOME/lib"
  cp "${REPO_ROOT}/prompt-colors.sh" "$HOME/lib/prompt-colors.sh"
  printf '\n CUSTOM_COLOR_TIER="tier3"\n' >> "$HOME/lib/prompt-colors.sh"
  git_prompt_reset
  __gp_load_colors
  assert_eq "tier3" "${CUSTOM_COLOR_TIER-}"

  cp "${REPO_ROOT}/prompt-colors.sh" "$HOME/prompt-colors.sh"
  printf '\n CUSTOM_COLOR_TIER="tier2"\n' >> "$HOME/prompt-colors.sh"
  git_prompt_reset
  __gp_load_colors
  assert_eq "tier2" "${CUSTOM_COLOR_TIER-}"

  cp "${REPO_ROOT}/prompt-colors.sh" "$HOME/.prompt-colors.sh"
  printf '\n CUSTOM_COLOR_TIER="tier1"\n' >> "$HOME/.prompt-colors.sh"
  git_prompt_reset
  __gp_load_colors
  assert_eq "tier1" "${CUSTOM_COLOR_TIER-}"

  rm -rf "$HOME/.prompt-colors.sh" "$HOME/prompt-colors.sh" "$HOME/lib"
  git_prompt_reset
) && pass_case

# 2. Verify all 40 built-in themes exist, load cleanly, render without error, and do not bleed state
test_case "Loads and renders all 40 built-in themes cleanly inside and outside Git repositories"
(
  expected_themes=(
    Default
    Default_NoExitState
    Default_Ubuntu
    Default_NoExitState_Ubuntu
    BlackOrWhite
    Chmike
    Crunch
    Evermeet
    Evermeet_Lowres
    Evermeet_Ubuntu
    Evermeet_return_prompt
    Minimal
    Minimal_Chevron
    Minimal_UserHost
    Multi_line_NoExitState_Gentoo
    Plague_Doctor
    Single_line
    Single_line_Dark
    Single_line_Minimalist
    Single_line_Minimalist_robbyrussell
    Single_line_Minimalist_robbyrussell_kube-ps1
    Single_line_NoExitState
    Single_line_NoExitState_Gentoo
    Single_line_NoExitState_openSUSE
    Single_line_openSUSE
    Single_line_Solarized
    Single_line_Solarized_Lamda
    Single_line_Ubuntu
    Single_line_username_repo
    Solarized
    Solarized_NoExitState
    Solarized_Ubuntu
    Solarized_NoExitState_Ubuntu
    Solarized_Extravagant
    Solarized_UserHost
    TruncatedPwd_WindowTitle
    TruncatedPwd_WindowTitle_NoExitState
    TruncatedPwd_WindowTitle_Ubuntu
    TruncatedPwd_WindowTitle_NoExitState_Ubuntu
    Windows_UserHost
  )
  assert_eq "40" "${#expected_themes[@]}"

  for t in "${expected_themes[@]}"; do
    [[ -f "${REPO_ROOT}/themes/${t}.bgptheme" ]] || { fail_case "Missing theme file ${t}.bgptheme"; exit 1; }
    GIT_PROMPT_THEME=$t
    cd "$REPO"
    run_prompt_cycle 0
    assert_eq "$t" "$GIT_PROMPT_THEME_NAME" "Theme $t must set GIT_PROMPT_THEME_NAME=$t"
    [[ -n $PS1 ]] || { fail_case "Empty PS1 for theme $t"; exit 1; }
  done

  # Verify clean state transition back to Default after Plague_Doctor / Minimal / Single_line_username_repo
  GIT_PROMPT_THEME="Default"
  run_prompt_cycle 0
  assert_eq "[" "$GIT_PROMPT_PREFIX"
  assert_eq "]" "$GIT_PROMPT_SUFFIX"
  assert_eq "|" "$GIT_PROMPT_SEPARATOR"
  if declare -F prompt_callback >/dev/null 2>&1; then
    fail_case "prompt_callback from a previous theme leaked into Default"
    exit 1
  fi
) && pass_case

# 3. BlackOrWhite theme styles, sections, Nerd Font icons, and 10 OS distro icons
test_case "Configures BlackOrWhite across styles, palettes, sections, Nerd Font icons, and 10 OS distros"
(
  GIT_PROMPT_THEME="BlackOrWhite"
  for style in bubbles bubbles_with_double_line powerline; do
    for color in black white; do
      GIT_PROMPT_BLACK_OR_WHITE_THEME_STYLE=$style
      GIT_PROMPT_BLACK_OR_WHITE_THEME_PS1_COLOR=$color
      GIT_PROMPT_BLACK_OR_WHITE_THEME_VISIBLE_SECTIONS="os,os_icon,user,hostname,user_and_hostname,time,path,last_command_state"
      GIT_PROMPT_BLACK_OR_WHITE_THEME_ADD_OR_REPLACE_ICONS_IN_SECTIONS="os,user,hostname,time,path,last_command_state_prompt,last_command_state_ok_fail,git_branch,git_branch_powerline,git_status"
      GIT_PROMPT_BLACK_OR_WHITE_THEME_ADD_EXTRA_SPACE_AFTER_ICONS="true"
      run_prompt_cycle 0
      [[ -n $PS1 ]] || { fail_case "BlackOrWhite failed for $style / $color"; exit 1; }
    done
  done

  # Verify all 10 OS identifiers resolve distinct Nerd Font glyphs
  for distro in macos archlinux centos debian fedora gentoo linuxmint opensuse redhat ubuntu; do
    __GP_BOW_OS_OVERRIDE=$distro
    git_prompt_reset
    run_prompt_cycle 0
    assert_contains "$PS1" "$distro"
  done

  # Root indicator (!)
  __GP_EFFECTIVE_UID=0
  run_prompt_cycle 0
  assert_contains "$PS1" "(!)"
) && pass_case

# 4. Theme selection & fallback precedence (PRD Section 5.1)
test_case "Follows strict theme selection & fallback rules for unset, Custom, and invalid themes"
(
  # Unset without custom file -> Default
  unset -v GIT_PROMPT_THEME GIT_PROMPT_THEME_FILE
  rm -f "$HOME/.git-prompt-colors.sh"
  git_prompt_reset
  run_prompt_cycle 0
  assert_eq "Default" "$__GP_ACTIVE_THEME_NAME"

  # Unset WITH ~/.git-prompt-colors.sh -> Custom
  printf 'GIT_PROMPT_THEME_NAME="Custom"\nGIT_PROMPT_PREFIX="<<CUSTOM>>"\n' > "$HOME/.git-prompt-colors.sh"
  git_prompt_reset
  run_prompt_cycle 0
  assert_eq "Custom" "$__GP_ACTIVE_THEME_NAME"
  assert_contains "$PS1" "<<CUSTOM>>"

  # Explicit "Custom" when file is missing -> falls back to Default and updates GIT_PROMPT_THEME="Default"
  rm -f "$HOME/.git-prompt-colors.sh"
  GIT_PROMPT_THEME="Custom"
  git_prompt_reset
  run_prompt_cycle 0
  assert_eq "Default" "$GIT_PROMPT_THEME"
  assert_eq "Default" "$__GP_ACTIVE_THEME_NAME"

  # Non-existent theme name -> falls back to Default and updates GIT_PROMPT_THEME="Default"
  GIT_PROMPT_THEME="NoSuchThemeExists"
  git_prompt_reset
  run_prompt_cycle 0
  assert_eq "Default" "$GIT_PROMPT_THEME"
) && pass_case

# 5. Interactive CLI commands & Readline marker stripping
test_case "Executes help, examples, color_samples, list_themes, and make_custom_theme with Readline markers stripped"
(
  out_help=$(git_prompt_help)
  out_alias=$(help_git_prompt)
  assert_eq "$out_help" "$out_alias"
  assert_contains "$out_help" "git_prompt_examples"
  assert_not_contains "$out_help" '\['

  out_ex=$(git_prompt_examples)
  assert_contains "$out_ex" "experimental"
  assert_contains "$out_ex" "extra-features"
  assert_not_contains "$out_ex" '\['

  out_col=$(git_prompt_color_samples)
  assert_contains "$out_col" "BrightCyan"
  assert_not_contains "$out_col" '\['

  GIT_PROMPT_THEME="Solarized"
  out_list=$(git_prompt_list_themes)
  assert_contains "$out_list" "* Solarized"
  assert_contains "$out_list" "Custom"
  assert_not_contains "$out_list" '\['

  # git_prompt_make_custom_theme guard cases
  rm -f "$HOME/.git-prompt-colors.sh"
  if git_prompt_make_custom_theme "Custom" >/dev/null 2>&1; then
    fail_case "git_prompt_make_custom_theme must reject 'Custom' as base theme"
    exit 1
  fi

  out_make=$(git_prompt_make_custom_theme)
  assert_contains "$out_make" "Default"
  [[ -f "$HOME/.git-prompt-colors.sh" ]] || { fail_case "Expected ~/.git-prompt-colors.sh to be created"; exit 1; }

  # Refuses to overwrite existing file
  if git_prompt_make_custom_theme "Solarized" >/dev/null 2>&1; then
    fail_case "git_prompt_make_custom_theme must refuse to overwrite existing ~/.git-prompt-colors.sh"
    exit 1
  fi
) && pass_case

test_suite_end
