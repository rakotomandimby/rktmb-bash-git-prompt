# shellcheck shell=bash
# prompt-colors.sh - Named ANSI color palette for Bash Git Prompt (Bash 5.0+)
#
# Defines all 98 Readline-wrapped color variables:
#   - 8 base colors in ColorNames: Black, Red, Green, Yellow, Blue, Magenta, Cyan, White
#   - 4 attribute prefixes: "" (0), Bold (1), Bright (1), Dim (2)
#   - 3 layer suffixes per pair: "" (foreground), Fg (foreground alias), Bg (background)
#   - 2 special variables: IntenseBlack (0;90), ResetColor (0)

__gp_define_prompt_colors() {
  ColorNames=(Black Red Green Yellow Blue Magenta Cyan White)

  local idx a_idx color name attr code fg_seq bg_seq
  local -a attr_names=("" "Bold" "Bright" "Dim")
  local -a attr_codes=("0" "1" "1" "2")

  for idx in "${!ColorNames[@]}"; do
    color=${ColorNames[idx]}
    for a_idx in "${!attr_names[@]}"; do
      attr=${attr_names[a_idx]}
      code=${attr_codes[a_idx]}
      fg_seq="\\[\\033[${code};3${idx}m\\]"
      if [[ -z $attr ]]; then
        # Omit leading 0; on normal background so combining "${FgColor}${BgColor}"
        # in Powerline themes never resets the preceding foreground attribute.
        bg_seq="\\[\\033[4${idx}m\\]"
      else
        bg_seq="\\[\\033[${code};4${idx}m\\]"
      fi

      name="${attr}${color}"
      printf -v "$name" '%s' "$fg_seq"
      printf -v "${name}Fg" '%s' "$fg_seq"
      printf -v "${name}Bg" '%s' "$bg_seq"
    done
  done

  IntenseBlack='\[\033[0;90m\]'
  ResetColor='\[\033[0m\]'
}

__gp_define_prompt_colors
