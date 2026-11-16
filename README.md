# Informative Git Prompt for Bash (Bash 5.0+)

An interactive, themeable, fast, and security-hardened Git prompt for **GNU Bash 5.0+**.

Displays real-time Git repository metadata—active branch, detached tag or short commit SHA, in-progress multi-step operations (`REBASE-i`, `REBASE-m`, `REBASE`, `AM`, `MERGING`, `CHERRY-PICKING`, `REVERTING`, `BISECTING`) with step progress, remote tracking divergence (`↑·N`, `↓·M`, `L`), working-tree/index/submodule/stash counts, previous command exit status or OS signal name, and active Python/Node.js/Conda virtual environments.

---

## Requirements

- **GNU Bash**: Version **5.0** or newer (`5.0+`)
- **Git**: Standard command-line client (`2.15+`)

---

## Quick Start

Clone this repository and source `gitprompt.sh` from your `~/.bashrc`:

```bash
# Optional configuration before sourcing gitprompt.sh:
GIT_PROMPT_ONLY_IN_REPO=1
GIT_PROMPT_THEME=Default

source /path/to/bash-git-prompt/gitprompt.sh
```

---

## Prompt Format & Visual Symbols (`Default` Theme)

```text
<PREFIX><BRANCH><UPSTREAM><TRACKING><SEPARATOR><LOCAL_STATUS><SUFFIX>
```

| Symbol | Default Color | Meaning |
| :--- | :--- | :--- |
| `✔` | Green | Previous command exited with `0` |
| `✘-<state>` | Red | Previous command failed with exit status or signal name (`INT`, `KILL`, `TERM`, etc.) |
| `[branch\|...]` | Magenta | Checked-out branch, tag, or `:short_sha` in detached `HEAD` |
| `\|REBASE-i 1/3` | Magenta | Active multi-step or paused Git operation appended to branch |
| `{origin/main}` | Blue | Upstream tracking branch (when `GIT_PROMPT_SHOW_UPSTREAM=1`) |
| `↑·N` / `↓·M` | Default | Ahead of remote by `N` commits / Behind remote by `M` commits |
| `L` | Default | Local branch without an upstream remote-tracking branch |
| `● N` | Red | `N` staged file changes in the index |
| `✖ N` | Red | `N` unmerged paths with conflicts |
| `✚ N` | Blue | `N` unstaged modified paths in the working tree |
| `…N` | Cyan | `N` untracked files/directories |
| `⚑ N` | Bold Blue | `N` stash entries in the repository stash stack |
| `✔` | Bold Green | Clean repository (zero staged, conflicted, changed, untracked, or stashed items) |

---

## Interactive Session Commands

| Command | Description |
| :--- | :--- |
| `git_prompt_help` / `help_git_prompt` | Prints colorized reference documentation for the prompt format and symbols |
| `git_prompt_examples` | Displays 8 annotated sample Git prompts |
| `git_prompt_color_samples` | Previews all 32 foreground color/intensity combinations |
| `git_prompt_list_themes` | Lists all 40 built-in themes plus `Custom`, highlighting the active theme |
| `git_prompt_make_custom_theme [<base>]` | Generates `~/.git-prompt-colors.sh` from `<base>` (or `Default`) |
| `git_prompt_toggle` | Toggles `GIT_PROMPT_DISABLE` between `1` and `0` in the current session |
| `git_prompt_reset` | Clears cached colors and theme state so edits take effect on the next prompt |

---

## Configuration Variables

| Variable | Default | Accepted Values | Description |
| :--- | :--- | :--- | :--- |
| `GIT_PROMPT_ONLY_IN_REPO` | `0` | `0`, `1` | When `1`, leaves your original `PS1` untouched outside Git repositories |
| `GIT_PROMPT_DISABLE` | `0` | `0`, `1` | Suspends Git inspection when `1` (toggled via `git_prompt_toggle`) |
| `GIT_PROMPT_THEME` | *(Auto)* | `"Default"`, `"Custom"`, or theme name | Selects one of the 40 built-in themes or `Custom` |
| `GIT_PROMPT_THEME_FILE` | `~/.git-prompt-colors.sh` | File path | Custom theme file path |
| `GIT_PROMPT_FETCH_REMOTE_STATUS` | `1` | `0`, `1` | Enables asynchronous non-interactive background remote fetching |
| `GIT_PROMPT_FETCH_TIMEOUT` | `5` | Positive integer (minutes) | Minimum age in minutes before triggering a background `git fetch` |
| `GIT_PROMPT_SHOW_UPSTREAM` | `0` | `0`, `1` | Displays `{upstream}` tracking branch block when `1` |
| `GIT_PROMPT_SHOW_TRACKING` | `1` | `0`, `1` | Suppresses remote tracking symbols (`↑·`, `↓·`, `L`) when `0` |
| `GIT_PROMPT_SHOW_UNTRACKED_FILES` | `normal` | `no`, `normal`, `all` | Controls untracked file scanning |
| `GIT_PROMPT_SHOW_CHANGED_FILES_COUNT` | `1` | `0`, `1` | Displays only local status symbols without counts when `0` |
| `GIT_PROMPT_IGNORE_SUBMODULES` | `0` | `0`, `1` | Ignores dirty submodules when `1` |
| `GIT_PROMPT_IGNORE_STASH` | `0` | `0`, `1` | Skips counting stash entries when `1` |
| `GIT_PROMPT_WITH_VIRTUAL_ENV` | `1` | `0`, `1` | Displays active Python, Node.js, and Conda environments when `1` |
| `GIT_PROMPT_VIRTUAL_ENV_AFTER_PROMPT` | `0` | `0`, `1` | Places virtual environment segment after Prompt Start when `1` |
| `GIT_PROMPT_WITH_USERNAME_AND_REPO` | `0` | `0`, `1` | Substitutes `<owner>/<repo>` into `_USERNAME_REPO_` in `GIT_PROMPT_PREFIX` |
| `GIT_PROMPT_START` / `GIT_PROMPT_END` | *(Unset)* | Prompt template string | Overrides theme `GIT_PROMPT_START_*` / `GIT_PROMPT_END_*` |

### Per-Repository `.bash-git-rc`

Place an optional `.bash-git-rc` file at the root of a repository containing only allowlisted `KEY=value` lines:

```ini
FETCH_REMOTE_STATUS=0
GIT_PROMPT_SHOW_UNTRACKED_FILES=no
GIT_PROMPT_IGNORE_SUBMODULES=1
GIT_PROMPT_SHOW_TRACKING=0
GIT_PROMPT_IGNORE=0
```

---

## Testing & Performance Benchmarking

```bash
# Run all automated functional and security test suites
./tests/run.sh

# Run latency benchmark (default 20 iterations; pass --no-save to skip TSV logging)
./tests/benchmark.sh 20 --no-save

# Compare recorded benchmark runs
./tests/benchmark-compare.sh --list
./tests/benchmark-compare.sh
./tests/benchmark-compare.sh --all
```
