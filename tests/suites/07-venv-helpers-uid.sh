#!/usr/bin/env bash
# tests/suites/07-venv-helpers-uid.sh - Virtual environments, helpers, callback, and UID/start/end framing

source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
test_suite_begin "07 - Virtual Environments, Helper Utilities, Callback & Privilege Framing"

REPO="${TEST_SANDBOX}/venv-repo"
git init -q -b main "$REPO"
git -C "$REPO" commit --allow-empty -q -m "init"
cd "$REPO"

GIT_PROMPT_FETCH_REMOTE_STATUS=0
source "${REPO_ROOT}/gitprompt.sh"

# 1. Python, Node, and Conda multi-environment detection and ordering
test_case "Detects and accumulates Python, Node.js, and Conda environments in order and respects disable flags"
(
  export VIRTUAL_ENV="/opt/venvs/py-env"
  export NODE_VIRTUAL_ENV="/opt/node/node-env"
  export CONDA_DEFAULT_ENV="/opt/conda/envs/conda-env"
  unset -v VIRTUAL_ENV_DISABLE_PROMPT NODE_VIRTUAL_ENV_DISABLE_PROMPT VIRTUAL_ENV_PROMPT

  run_prompt_cycle 0
  assert_contains "$PS1" "(${Blue}py-env${ResetColor}) (${Blue}node-env${ResetColor}) (${Blue}conda-env${ResetColor}) "

  # Custom VIRTUAL_ENV_PROMPT with parentheses and whitespace
  export VIRTUAL_ENV_PROMPT=" (custom-py) "
  run_prompt_cycle 0
  assert_contains "$PS1" "(${Blue}custom-py${ResetColor}) (${Blue}node-env${ResetColor})"

  # Disable Python & Node prompt
  export VIRTUAL_ENV_DISABLE_PROMPT=1
  export NODE_VIRTUAL_ENV_DISABLE_PROMPT=1
  run_prompt_cycle 0
  assert_not_contains "$PS1" "custom-py"
  assert_not_contains "$PS1" "node-env"
  assert_contains "$PS1" "conda-env"

  # GIT_PROMPT_VIRTUAL_ENV_AFTER_PROMPT=1 places virtualenv after Prompt Start
  GIT_PROMPT_VIRTUAL_ENV_AFTER_PROMPT=1
  run_prompt_cycle 0
  # PathShort (\w) comes before conda-env when AFTER_PROMPT=1
  [[ $PS1 == *"\\w"*"conda-env"* ]] || { fail_case "Expected virtualenv after Prompt Start: [$PS1]"; exit 1; }

  # GIT_PROMPT_WITH_VIRTUAL_ENV=0 disables all virtual environment segments
  GIT_PROMPT_WITH_VIRTUAL_ENV=0
  run_prompt_cycle 0
  assert_not_contains "$PS1" "conda-env"
) && pass_case

# 2. gp_truncate_pwd and gp_set_window_title helpers
test_case "gp_truncate_pwd abbreviates HOME to ~ and left-truncates with ..., and gp_set_window_title wraps OSC"
(
  mkdir -p "$HOME/alpha/beta/gamma/delta"
  cd "$HOME"
  assert_eq "~" "$(gp_truncate_pwd 20)"

  cd "$HOME/alpha/beta/gamma/delta"
  assert_eq "~/alpha/beta/gamma/delta" "$(gp_truncate_pwd 50)"
  trunc10=$(gp_truncate_pwd 10)
  assert_eq "10" "${#trunc10}"
  assert_eq "...a/delta" "$trunc10"

  # Default max_length when COLUMNS is unset (80 / 3 = 26)
  unset -v COLUMNS
  assert_eq "~/alpha/beta/gamma/delta" "$(gp_truncate_pwd)"

  # Window title helper
  assert_eq '\[\033]0;My Title\007\]' "$(gp_set_window_title "My Title")"
) && pass_case

# 3. prompt_callback and User vs Root privilege framing + GIT_PROMPT_START / GIT_PROMPT_END overrides
test_case "Executes prompt_callback and applies user/root framing and global START/END overrides"
(
  prompt_callback() {
    printf '<<CB:_LAST_COMMAND_INDICATOR_>>'
  }

  __GP_EFFECTIVE_UID=1000
  run_prompt_cycle 0
  assert_contains "$PS1" "<<CB:${Green}✔${ResetColor}>>"
  assert_contains "$PS1" ' $ '

  __GP_EFFECTIVE_UID=0
  run_prompt_cycle 0
  assert_contains "$PS1" ' # '

  # Global GIT_PROMPT_START and GIT_PROMPT_END overrides (including empty string)
  GIT_PROMPT_START="START_OVR:"
  GIT_PROMPT_END=":END_OVR"
  run_prompt_cycle 0
  assert_contains "$PS1" "START_OVR:<<CB:"
  assert_contains "$PS1" ":END_OVR"

  GIT_PROMPT_START=""
  run_prompt_cycle 0
  [[ $PS1 == "<<CB:"* ]] || { fail_case "Empty GIT_PROMPT_START must override default start: [$PS1]"; exit 1; }
) && pass_case

test_suite_end
