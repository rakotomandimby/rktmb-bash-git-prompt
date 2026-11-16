# Product Requirements Document (PRD): Informative Git Prompt for Bash

## 1. Document Overview & Scope

### 1.1 Document Purpose
This Product Requirements Document (PRD) defines the complete functional, visual, behavioral, configuration, and quality specifications for a clean-slate rewrite of **Bash Git Prompt**—an interactive, themeable, Git-aware command-line prompt system for GNU Bash.

This document specifies **what** the software must accomplish and **how users interact with and configure it**, intentionally excluding all internal architectural prescriptions, implementation mechanisms, and code snippets so engineering design decisions remain unconstrained.

### 1.2 Target Platform & Runtime Environment
- **Implementation Language & Target Shell**: GNU Bash, strictly targeting **Bash versions newer than v4** (Bash 5.0 and later).
- **Operating Systems**: Linux, macOS, and POSIX-compliant Unix environments running Bash 5.0+ and a standard Git command-line client.
- **Terminal Emulators**: ANSI/XTerm-compatible terminal emulators supporting 8/16-color palettes, bold/dim/high-intensity attributes, 24-bit truecolor (for themes using extended colors), Unicode glyphs, emojis, Powerline symbols, Nerd Fonts, and XTerm window-title control sequences.

### 1.3 Clean-Slate Scope & Explicit Non-Goals
- **No Legacy Software Migration**: The software starts from a blank workspace with no automated migration utilities or backward-compatibility shims for internal hooks of older releases.
- **No Legacy Bash Support**: Compatibility workarounds for Bash v4.x and earlier are explicitly out of scope.
- **No Multi-Shell Compatibility Layers**: Support for non-Bash shells (such as Zsh or Fish) is out of scope; the product targets modern Bash exclusively.
- **No Legacy External Language Backends**: Support for secondary status backends in external scripting languages (such as Python) or workarounds for ancient Git versions is out of scope.

---

## 2. Product Purpose & Objectives

### 2.1 Product Purpose
Software developers working in interactive Bash terminals frequently switch branches, rebase commits, resolve merge conflicts, stash work-in-progress changes, manage submodules and linked worktrees, and activate language-specific virtual environments. Querying repository and environment state manually after every command introduces cognitive overhead and slows down development workflows, or leads to costly mistakes (such as committing to the wrong branch, forgetting stashed or untracked files, or pushing diverged history).

**Bash Git Prompt** solves this by dynamically rendering an informative, customizable, color-coded terminal prompt prior to each interactive command entry. It surfaces real-time Git repository metadata, preceding command execution outcomes, and active virtual environment context directly in the shell prompt.

### 2.2 Core Objectives
1. **Immediate Repository Situational Awareness**: Present accurate, real-time visibility into the active Git branch or detached HEAD reference (tag or short commit hash), in-progress multi-step Git operations (rebase, merge, cherry-pick, revert, bisect, patch application) with step progress, upstream remote-tracking branch identity, commit divergence (ahead, behind, diverged, or untracked local branch), and local working-tree/index/stash counts (staged, conflicted, unstaged-modified, untracked, stashed, or clean).
2. **Actionable Command Execution Feedback**: Visually indicate whether the user's previous interactive command succeeded or failed, optionally displaying either the numeric exit status or the human-readable operating system signal name when a process was terminated by a signal.
3. **Development Environment & Session Context**: Automatically surface active Python, Node.js, and Conda virtual environments, privilege state (standard user vs. superuser/root), working directory (full, home-abbreviated, basename, repository-relative, or dynamically width-truncated), timestamps, host/SSH context, and terminal window titles.
4. **Non-Intrusive Shell Coexistence**: Integrate cleanly into the Bash prompt lifecycle without overwriting pre-existing user prompt hooks, altering the last command's exit status seen by other hooks, locking Git repositories during concurrent Git operations, or modifying prompts outside Git repositories when configured for repository-only operation.
5. **Responsive Interactive Performance**: Ensure prompt rendering remains fast and non-blocking by performing periodic remote updates asynchronously in the background without terminal output or interactive credential prompts, caching static theme/color definitions across prompt cycles, and offering global and per-repository performance controls for massive repositories or deep submodule hierarchies.
6. **Rich Out-of-the-Box Aesthetics & Deep Customizability**: Ship with a comprehensive catalog of ready-to-use themes alongside a partial-override custom theming system, named color palette, template placeholders, dynamic user callback hooks, and interactive help/discovery commands.

---

## 3. Core Functional Specifications

### 3.1 Shell Session Lifecycle & Prompt Hook Integration
- **Session Initialization**: Loading the software in an interactive Bash 5+ session registers the prompt management lifecycle automatically.
- **Idempotent Registration**: Loading the software multiple times in the same shell session must not register duplicate pre-prompt hooks.
- **Preservation of Existing Pre-Prompt Hooks**:
  - Must support both scalar string configurations and Bash 5+ indexed array configurations of Bash's pre-prompt command mechanism.
  - Any pre-existing user pre-prompt commands must remain intact and execute in their intended order.
  - Any malformed formatting in scalar pre-prompt command configurations (such as embedded newlines, leading/trailing semicolons, or trailing whitespace) must be normalized cleanly without breaking existing entries.
- **Execution Ordering & Exit Status Preservation**:
  1. **First Hook (Status Capture)**: Must execute *before* all other pre-prompt commands so it captures the exact exit status of the interactive command just executed by the user. It must return that exact same exit status so any subsequent user-registered pre-prompt hooks still observe the original exit status.
  2. **Final Hook (Prompt Rendering)**: Must execute *after* all other pre-prompt commands to evaluate environment/Git context and assemble the final primary prompt string.
- **Installation Directory Resolution**:
  - Automatically determines its own installation root directory (resolving symbolic links if loaded via a symlinked path) so bundled themes and support resources are located reliably.
  - Honors an explicit installation directory override if pre-configured by the user via `__GIT_PROMPT_DIR`.
- **Runtime Toggle, Bypass & Cache Reset**:
  - Supports interactive toggling (`git_prompt_toggle`) and configuration (`GIT_PROMPT_DISABLE`) to suspend and resume Git prompt evaluation within a live session.
  - Automatically bypasses Git repository inspection when running inside an automated coding agent environment where `COPILOT_AGENT` is set to `1`.
  - Supports interactive cache invalidation (`git_prompt_reset`) so edits to theme or color configuration files take effect on the very next prompt cycle without restarting the shell.

### 3.2 Operating Modes Outside and Inside Git Repositories
The software supports two primary operating modes controlled by `GIT_PROMPT_ONLY_IN_REPO`:

1. **Always-Active Prompt Mode (Default — `GIT_PROMPT_ONLY_IN_REPO` disabled)**:
   - **Inside an active, non-ignored Git repository**: Renders the full themed prompt including the Git Status Segment.
   - **Outside a Git repository (or when ignored/disabled)**: Renders the themed Non-Git Prompt (comprising active virtual environments if enabled, Prompt Start, dynamic callback output, Prompt End, and resolved last-command status indicator, omitting the Git Status Segment).
2. **Repository-Only Mode (`GIT_PROMPT_ONLY_IN_REPO` enabled)**:
   - **Outside a Git repository**: Leaves the user's original pre-existing shell prompt completely untouched.
   - **Directory Transitions**: Saving and restoring the original prompt must be stateful across directory changes:
     - Starting outside a Git repository preserves the original prompt.
     - Navigating into a Git repository saves the pre-Git prompt state and activates the Git-aware prompt.
     - Navigating back out of the Git repository into any non-Git directory restores the user's exact original prompt verbatim.
   - **Ignored or Disabled State in Repository-Only Mode**: If the current repository is ignored via per-repository configuration, or if the prompt is disabled via `GIT_PROMPT_DISABLE` or `COPILOT_AGENT`, the saved original prompt is displayed.

### 3.3 Git Repository Detection, Worktrees & Concurrency Safety
- **Repository Detection**: Accurately detects whether the current working directory resides inside a Git working tree (at the repository root or any nested subdirectory depth).
- **Linked Git Worktree Support**:
  - Full functional parity inside linked Git worktrees (linked working trees sharing common repository metadata with a main repository).
  - Stash counting inside a linked worktree must accurately reflect the shared repository stash count.
  - Periodic remote fetch staleness tracking inside a linked worktree must inspect the shared repository fetch state rather than failing on worktree-local paths.
- **Lock-Free & Non-Intrusive Inspection**:
  - Status inspection must never acquire persistent or optional Git locks that could cause user-initiated Git commands running concurrently in another terminal or background process to fail with lock contention errors.
  - Prompt rendering must never race with, mutate, or disrupt active multi-step or conflict-paused Git operations (including interactive or non-interactive rebases, merges, cherry-picks, reverts, and bisects).
  - Must honor `GIT_INDEX_FILE` if configured externally in the user's shell environment without modifying or polluting `GIT_INDEX_FILE` in the interactive session.
  - Any transient resources created during prompt evaluation (honoring `TMPDIR` when set) must be cleaned up immediately before the prompt cycle completes, leaving zero leftover files on disk.
  - Fatal errors from Git commands (such as corrupted repositories or unreadable metadata) must be handled gracefully by falling back to the Non-Git prompt without printing raw error tracebacks into the user's prompt.

### 3.4 Branch, HEAD Reference & In-Progress Operation Detection
When inside an active Git repository, the current reference and operation state are resolved as follows:

1. **Standard Checked-Out Branch**:
   - Resolves the short local branch name (e.g., `main`, `feature/login`).
   - Compares the branch name (including any appended operation state, or base branch name) against `GIT_PROMPT_MASTER_BRANCHES`:
     - If matched: styles the branch using `GIT_PROMPT_MASTER_BRANCH`.
     - Otherwise: styles the branch using `GIT_PROMPT_BRANCH`.
2. **Newly Initialized / Unborn Branch (Zero Commits)**:
   - When a repository has just been initialized and has no commits yet on the initial branch, resolves and displays the unborn branch name, marks tracking status as local-only (untracked remote symbol), and suppresses remote owner/repository display.
3. **Detached HEAD State**:
   - Applies the `GIT_PROMPT_DETACHED_HEAD` style (unless matched by `GIT_PROMPT_MASTER_BRANCHES`).
   - **Exact Tag Match**: If `HEAD` points directly to a tagged commit, displays `GIT_PROMPT_SYMBOLS_PRETAG` (empty by default) followed immediately by the exact tag name.
   - **Commit SHA Fallback**: If no exact tag points to `HEAD`, displays `GIT_PROMPT_SYMBOLS_PREHASH` (`:` by default) followed immediately by the abbreviated commit hash of `HEAD` (e.g., `:70c2952`).
4. **In-Progress Git Operation Suffix**:
   - Detects active Git operations and appends the corresponding state indicator directly to the resolved branch/reference identifier. When step and total counts exist for multi-step operations, appends ` <current_step>/<total_steps>`:

| Active Git Operation | Appended State Suffix | Step Progress Included |
| :--- | :--- | :--- |
| Interactive rebase | `\|REBASE-i <step>/<total>` (or `\|REBASE-i`) | Yes, when available |
| Merge-backend rebase (non-interactive) | `\|REBASE-m <step>/<total>` (or `\|REBASE-m`) | Yes, when available |
| Apply-backend rebase | `\|REBASE <step>/<total>` (or `\|REBASE`) | Yes, when available |
| Mailbox patch application (`am`) | `\|AM <step>/<total>` (or `\|AM`) | Yes, when available |
| Combined/ambiguous `am` or rebase-apply | `\|AM/REBASE <step>/<total>` (or `\|AM/REBASE`) | Yes, when available |
| Merge in progress (uncommitted merge state) | `\|MERGING` | No |
| Cherry-pick in progress | `\|CHERRY-PICKING` | No |
| Revert in progress | `\|REVERTING` | No |
| Bisect session active | `\|BISECTING` | No |

   - Once the operation completes or is aborted, the suffix must disappear automatically on the very next prompt render.
5. **Exported Session Variable (`GIT_BRANCH`)**:
   - Exports `GIT_BRANCH` containing the resolved branch/tag/hash plus any active operation suffix while inside an active Git repository, and unsets `GIT_BRANCH` when reconfiguring outside an active Git prompt.

### 3.5 Remote Tracking, Upstream Branch & Owner/Repository Extraction
1. **Remote Divergence & Tracking Status** (displayed unless `GIT_PROMPT_SHOW_TRACKING` is `0`):
   - Prefixed with `GIT_PROMPT_REMOTE` (a single space by default) whenever a non-empty tracking indicator applies:
     - **Synchronized with Upstream**: Nothing rendered (omitted completely).
     - **Ahead of Upstream**: Renders `<GIT_PROMPT_SYMBOLS_AHEAD><ahead_count>` (default `↑·N`).
     - **Behind Upstream**: Renders `<GIT_PROMPT_SYMBOLS_BEHIND><behind_count>` (default `↓·M`).
     - **Diverged from Upstream**: Renders behind count first, immediately followed by ahead count: `<GIT_PROMPT_SYMBOLS_BEHIND><behind_count><GIT_PROMPT_SYMBOLS_AHEAD><ahead_count>` (default `↓·M↑·N`).
     - **Local Branch Without Upstream Remote Tracking**: Renders `<GIT_PROMPT_SYMBOLS_NO_REMOTE_TRACKING>` (default `L`). Applies to local branches without an upstream and unborn branches; omitted in detached HEAD state.
2. **Upstream Tracking Branch Display** (controlled by `GIT_PROMPT_SHOW_UPSTREAM`, disabled `0` by default):
   - When enabled (`1`) and the active branch tracks an upstream branch (e.g., `origin/main`), renders `GIT_PROMPT_UPSTREAM` with `_UPSTREAM_` replaced by the whitespace-trimmed upstream branch name, positioned immediately after the branch name and before remote divergence symbols.
   - Omitted automatically when disabled or when no upstream tracking branch exists.
3. **Abbreviated Remote Owner & Repository (`username/repo`)**:
   - Controlled by `GIT_PROMPT_WITH_USERNAME_AND_REPO` (`0` by default).
   - When enabled (`1`) and the active branch tracks a remote on a repository with a configured `origin` remote URL, extracts `<owner>/<repo>` from the `origin` URL:
     - Must handle HTTPS URLs without credentials, HTTPS URLs with embedded `user@` credentials, and SSH SCP-like syntax (`git@host:owner/repo.git` or `ssh://...`), stripping protocol schemes, user/host prefixes, and trailing `.git` suffixes.
   - Substitutes `<owner>/<repo>` in place of the `_USERNAME_REPO_` placeholder inside `GIT_PROMPT_PREFIX`, resets color, and—if `GIT_PROMPT_USERNAME_REPO_SEPARATOR` is defined—appends `GIT_PROMPT_USERNAME_REPO_SEPARATOR`.
   - When disabled, or when in an unborn branch, untracked local branch, or repository without an `origin` remote URL, `_USERNAME_REPO_` resolves to a clean color reset and `GIT_PROMPT_USERNAME_REPO_SEPARATOR` is omitted so no orphaned separator appears.

### 3.6 Working Tree, Index, Submodule & Stash Status Inspection
 Status evaluation computes exact item counts in a locale-independent manner (`C` locale semantics so parsing never breaks on localized system languages):

1. **Staged Files (`STAGED`)**:
   - Number of paths with staged changes in the index (newly added, staged modifications, staged deletions, renames, copies, or file-type changes), excluding unmerged conflict entries.
2. **Merge Conflicts (`CONFLICTS`)**:
   - Number of unmerged paths with conflict states (updated-but-unmerged on either side, added by both, or deleted by both).
3. **Unstaged Working-Tree Changes (`CHANGED`)**:
   - Number of tracked paths modified in the working tree whose working-tree modifications are not staged in the index.
   - Dual-state accuracy: A tracked file that has *both* staged changes in the index and additional unstaged modifications in the working tree increments *both* `STAGED` and `CHANGED`.
4. **Untracked Files (`UNTRACKED`)**:
   - Number of untracked paths in the repository, governed by `GIT_PROMPT_SHOW_UNTRACKED_FILES`:
     - `no`: Skips untracked file scanning completely (count is `0`), maximizing speed in repositories with large build artifact trees.
     - `normal` (default): Counts untracked files and collapsed untracked directories not ignored by Git ignore rules.
     - `all`: Recursively counts individual untracked files inside untracked directories (respecting standard Git untracked-all semantics).
5. **Submodule Inspection (`GIT_PROMPT_IGNORE_SUBMODULES`)**:
   - By default (`0`), dirty/modified submodules contribute to repository change status according to Git's standard status reporting.
   - When set to `1`, changes inside submodules are ignored during status inspection to maintain speed in repositories with deep or numerous submodules.
6. **Stash Entries (`STASHED`)**:
   - Number of entries currently stored in the repository's Git stash stack (shared across linked worktrees).
   - Skipped (treated as `0`) when `GIT_PROMPT_IGNORE_STASH` is set to `1`.
7. **Clean Repository Determination (`CLEAN`)**:
   - The repository is considered **Clean** (`1`) if and only if all five local counts (`STAGED`, `CONFLICTS`, `CHANGED`, `UNTRACKED`, `STASHED`) equal `0`. Otherwise it is **Dirty** (`0`).
8. **Changed File Count Visibility (`GIT_PROMPT_SHOW_CHANGED_FILES_COUNT`)**:
   - When `1` (default): Each active local status indicator (`STAGED`, `CONFLICTS`, `CHANGED`, `UNTRACKED`, `STASHED`) displays its configured prefix/symbol immediately followed by its numeric count; `CLEAN` never displays a numeric count.
   - When `0`: Active local status indicators display only their configured prefix/symbol without numeric counts. Remote tracking ahead/behind commit counts continue to display their numeric counts whenever tracking is enabled.
9. **Conditional Separator Suppression**:
   - `GIT_PROMPT_SEPARATOR` is rendered before the local status indicators whenever the repository is Dirty (`CLEAN == 0`), OR whenever the repository is Clean (`CLEAN == 1`) and `GIT_PROMPT_CLEAN` is non-empty.
   - If the repository is Clean (`CLEAN == 1`) AND `GIT_PROMPT_CLEAN` is set to an empty string (`""`), `GIT_PROMPT_SEPARATOR` is suppressed so no dangling separator precedes `GIT_PROMPT_SUFFIX`.

### 3.7 Asynchronous Periodic Remote Fetching
- **Enablement**: Active by default (`GIT_PROMPT_FETCH_REMOTE_STATUS` = `1`), overridable globally or per-repository (`FETCH_REMOTE_STATUS` = `0` in `.bash-git-rc`).
- **Trigger Conditions**: On prompt evaluation inside an active, non-ignored Git repository when remote fetching is enabled:
  1. At least one Git remote is configured for the repository.
  2. Either the repository has never recorded a fetch, OR the modification timestamp of the repository's last fetch record (resolved across common Git metadata for linked worktrees) is strictly older than `GIT_PROMPT_FETCH_TIMEOUT` minutes (default `5` minutes).
- **Asynchronous Non-Blocking Execution**:
  - Launches a quiet fetch in the background and returns control to prompt rendering immediately without waiting for network I/O.
  - Background fetch jobs must be completely detached/disowned from interactive shell job control so the user never sees job-start or `[Done]` notifications in their terminal, and no extra open file descriptors are leaked into the background process.
  - All standard output and standard error from the background fetch must be suppressed.
  - **Non-Interactive Guarantee**: Interactive terminal credential prompts must be disabled for background fetches so an unauthenticated HTTPS/SSH remote never blocks or prints password prompts over the user's active command line.
- **Missing File-Age Capability Fallback**:
  - If the host environment lacks a supported capability to determine file modification age in minutes, emit a one-time warning message to standard error explaining how to silence the warning via `GIT_PROMPT_FETCH_REMOTE_STATUS=0`, and disable remote status fetching for the remainder of the session rather than repeating the warning on every prompt.

### 3.8 Last Command Exit Status & Signal Name Formatting
- Evaluates the exit status captured from the most recently executed interactive user command:
  - **Exit Status `0`**: Selects `GIT_PROMPT_COMMAND_OK`.
  - **Exit Status Non-Zero**: Selects `GIT_PROMPT_COMMAND_FAIL`.
- **Exit State Formatting (`_LAST_COMMAND_STATE_`)**:
  - For integer exit codes `0` through `128` (and any non-integer strings): formats verbatim as the numeric value (e.g., `1`, `2`, `126`, `127`, `128`).
  - For integer exit codes strictly greater than `128`: interprets the status as termination by operating system signal `exit_code - 128` and resolves it to the corresponding symbolic signal name without a `SIG` prefix where standard shell signal listing provides short names (e.g., `130` -> `INT`, `137` -> `KILL`, `141` -> `PIPE`, `143` -> `TERM`), falling back to the raw numeric exit code if `exit_code - 128` does not map to a recognized signal.
- Substitutes `_LAST_COMMAND_STATE_` inside the selected `GIT_PROMPT_COMMAND_OK` / `GIT_PROMPT_COMMAND_FAIL` template, then substitutes the resulting indicator wherever `_LAST_COMMAND_INDICATOR_` appears in the assembled prompt.

### 3.9 User vs. Root Privilege Framing & Global Start/End Overrides
- Determines whether the effective user ID of the shell process is `0` (superuser/root) or non-zero (regular user).
- **Prompt Start Precedence**:
  1. If `GIT_PROMPT_START` is set (even if set to an empty string), uses `GIT_PROMPT_START` unconditionally.
  2. Otherwise, uses `GIT_PROMPT_START_ROOT` when running as root (`UID == 0`), or `GIT_PROMPT_START_USER` when running as a regular user (`UID != 0`).
- **Prompt End Precedence**:
  1. If `GIT_PROMPT_END` is set (even if set to an empty string), uses `GIT_PROMPT_END` unconditionally.
  2. Otherwise, uses `GIT_PROMPT_END_ROOT` when running as root (`UID == 0`), or `GIT_PROMPT_END_USER` when running as a regular user (`UID != 0`).
- Switching themes or invoking `git_prompt_reset` must re-evaluate theme-defined start/end templates whenever global `GIT_PROMPT_START` / `GIT_PROMPT_END` overrides are not set.

### 3.10 Virtual Environment Detection & Multi-Environment Accumulation
- Controlled by `GIT_PROMPT_WITH_VIRTUAL_ENV` (enabled `1` by default; `0` disables all virtual environment detection in the prompt).
- Inspects three environment ecosystems in deterministic order, accumulating formatted segments if more than one is active simultaneously:
  1. **Python Virtual Environment**:
     - Active when `VIRTUAL_ENV` is non-empty AND `VIRTUAL_ENV_DISABLE_PROMPT` is unset.
     - Name resolution: If `VIRTUAL_ENV_PROMPT` is set and non-empty, strips leading whitespace and a leading `(`, and strips a trailing `)` and trailing whitespace to extract the custom prompt label; otherwise extracts the final directory basename of `VIRTUAL_ENV`.
  2. **Node.js Virtual Environment**:
     - Active when `NODE_VIRTUAL_ENV` is non-empty AND `NODE_VIRTUAL_ENV_DISABLE_PROMPT` is unset.
     - Name resolution: Extracts the final directory basename of `NODE_VIRTUAL_ENV`.
  3. **Conda Environment**:
     - Active when `CONDA_DEFAULT_ENV` is non-empty.
     - Name resolution: Extracts the final basename/name of `CONDA_DEFAULT_ENV`.
- **Template Formatting**: Each detected environment name is formatted by replacing `_VIRTUALENV_` inside `GIT_PROMPT_VIRTUALENV` (default `(` + Blue environment name + Reset + `) `), and active segments are concatenated in the order above.
- **Placement**:
  - `GIT_PROMPT_VIRTUAL_ENV_AFTER_PROMPT` = `0` (default): Prepended at the very start of the prompt, before Prompt Start and dynamic callback output.
  - `GIT_PROMPT_VIRTUAL_ENV_AFTER_PROMPT` = `1`: Inserted after Prompt Start and dynamic callback output, immediately before the Git Status Segment (or before Prompt End when outside a repository).

### 3.11 Dynamic Prompt Callback & Built-in Helper Capabilities
- **`prompt_callback` Hook**:
  - Users (in their shell startup files) or themes may define a Bash function named `prompt_callback`.
  - On each prompt render (unless `GIT_PROMPT_ONLY_IN_REPO=1` is restoring the raw original prompt outside a repo), if `prompt_callback` is defined as a function, it is executed and its standard output is inserted directly after Prompt Start.
  - If `prompt_callback` is undefined, nothing is inserted (default no-op).
- **Provided Helper Utilities** (callable from `prompt_callback`, custom themes, or interactive shell):
  1. **Window Title Setter (`gp_set_window_title`)**: Accepts a single title string argument and outputs the non-printing XTerm OSC window-title control sequence so the terminal window/tab title updates when the prompt renders.
  2. **Dynamic Path Truncator (`gp_truncate_pwd`)**: Accepts an optional positive integer `<max_length>` argument (defaulting to one-third of the terminal column width `COLUMNS / 3`, using `80` when `COLUMNS` is unset, i.e., `26`). Replaces a leading `$HOME` prefix in `PWD` with `~`. If the resulting path's character length exceeds `<max_length>`, truncates characters from the left and prepends `...` so the total returned string length is `<max_length>` (retaining the rightmost `<max_length> - 3` characters). Outputs the result without a trailing newline.
  3. **Exit Status Formatter (`gp_format_exit_status`)**: Accepts a single exit status argument and outputs the symbolic signal name (for integers `> 128`) or the verbatim exit status (for `<= 128` or unmapped values).
  4. **Remote Owner/Repo Extractor (`gp_format_username_repo`)**: Outputs the `<owner>/<repo>` string extracted from the current repository's `remote.origin.url` configuration.

---

## 4. User Interface Elements & Visual Prompt Specifications

### 4.1 Complete Prompt Segment Assembly Order

| Context | `GIT_PROMPT_VIRTUAL_ENV_AFTER_PROMPT` | Assembled Prompt Segment Sequence (Left to Right) |
| :--- | :--- | :--- |
| **Active Git Repo** | `0` (Default) | `[Virtual Env] + [Prompt Start] + [Callback Output] + [Leading Space] + [Git Status Block] + [Prompt End]` |
| **Active Git Repo** | `1` | `[Prompt Start] + [Callback Output] + [Virtual Env] + [Leading Space] + [Git Status Block] + [Prompt End]` |
| **Non-Git / Disabled / Ignored** (`ONLY_IN_REPO=0`, `WITH_VIRTUAL_ENV=1`) | `0` (Default) | `[Virtual Env] + [Prompt Start] + [Callback Output] + [Prompt End]` |
| **Non-Git / Disabled / Ignored** (`ONLY_IN_REPO=0`, `WITH_VIRTUAL_ENV=1`) | `1` | `[Prompt Start] + [Callback Output] + [Virtual Env] + [Prompt End]` |
| **Non-Git / Disabled / Ignored** (`ONLY_IN_REPO=0`, `WITH_VIRTUAL_ENV=0`) | Any | `[Prompt Start] + [Callback Output] + [Prompt End]` |
| **Non-Git / Disabled / Ignored** (`ONLY_IN_REPO=1`) | Any | Exact restoration of user's pre-existing shell prompt (`PS1`) |

*(Note: After assembling all segments above, all occurrences of `_LAST_COMMAND_INDICATOR_` across the prompt string are replaced with the resolved command-status indicator plus color reset.)*

### 4.2 Git Status Block Internal Element Order
Inside an active Git repository, the `[Git Status Block]` consists of the following ordered elements:

1. **Opening Prefix** (`GIT_PROMPT_PREFIX`, with `_USERNAME_REPO_` and optional `GIT_PROMPT_USERNAME_REPO_SEPARATOR` resolved)
2. **Branch / Reference Style** (`GIT_PROMPT_MASTER_BRANCH`, `GIT_PROMPT_DETACHED_HEAD`, or `GIT_PROMPT_BRANCH`)
3. **Branch / Tag / Prehash+SHA + In-Progress Operation Suffix** (`GIT_BRANCH`) + Color Reset
4. **Upstream Branch Block** (`GIT_PROMPT_UPSTREAM` with `_UPSTREAM_` resolved, only if `GIT_PROMPT_SHOW_UPSTREAM=1` and upstream exists)
5. **Remote Tracking Status** (`GIT_PROMPT_REMOTE` + divergence or no-remote-tracking symbol + Color Reset, only if `GIT_PROMPT_SHOW_TRACKING != 0` and tracking status is non-empty)
6. **Status Separator** (`GIT_PROMPT_SEPARATOR`, omitted only when repository is Clean and `GIT_PROMPT_CLEAN` is empty)
7. **Staged Indicator** (`GIT_PROMPT_STAGED` + optional count + Color Reset, when staged > 0)
8. **Conflicts Indicator** (`GIT_PROMPT_CONFLICTS` + optional count + Color Reset, when conflicts > 0)
9. **Changed Indicator** (`GIT_PROMPT_CHANGED` + optional count + Color Reset, when unstaged modified > 0)
10. **Untracked Indicator** (`GIT_PROMPT_UNTRACKED` + optional count + Color Reset, when untracked > 0)
11. **Stashed Indicator** (`GIT_PROMPT_STASHED` + optional count + Color Reset, when stashed > 0)
12. **Clean Indicator** (`GIT_PROMPT_CLEAN` + Color Reset, never with count, only when repository is Clean and `GIT_PROMPT_CLEAN` is non-empty)
13. **Closing Suffix** (Color Reset + `GIT_PROMPT_SUFFIX`)

### 4.3 Default Visual Symbols & Color Mapping (`Default` Theme)

| UI Element | Default Symbol / Text | Default Color / Style | Meaning |
| :--- | :--- | :--- | :--- |
| Last Command Succeeded | `✔` | Green | Preceding command exited with `0` |
| Last Command Failed | `✘-<state>` | Red | Preceding command exited non-zero (`<state>` = exit code or signal name) |
| Working Directory | Home-abbreviated path (`~` for home) | Yellow | Current working directory in Prompt Start |
| Prompt Second Line | `HH:MM $ ` (user) / `HH:MM # ` (root) | White time, default `$`/`#` | 24-hour clock timestamp + privilege prompt symbol |
| Virtual Environment | `(<env_name>) ` | Default parens, Blue `<env_name>` | Active Python, Node.js, or Conda environment |
| Git Block Delimiters | `[` and `]` | Default terminal color | Encloses the Git Status Block |
| Git Block Separator | `\|` | Default terminal color | Separates branch/tracking section from local file status section |
| Branch / Master / Detached | `<name>` | Magenta | Active branch, primary branch, or detached tag/hash |
| Detached Hash Prefix | `:` | Inherits detached/branch color | Indicates the following identifier is a short commit SHA rather than a branch |
| Detached Tag Prefix | *(empty)* | Inherits detached/branch color | Prefix before exact tag name in detached HEAD |
| Upstream Tracking Block | ` {<upstream>}` | Default braces, Blue `<upstream>` | Remote-tracking branch name (when `GIT_PROMPT_SHOW_UPSTREAM=1`) |
| Ahead of Remote | ` ↑·<N>` | Default terminal color | Local branch is ahead of upstream by `N` commits |
| Behind Remote | ` ↓·<M>` | Default terminal color | Local branch is behind upstream by `M` commits |
| Diverged from Remote | ` ↓·<M>↑·<N>` | Default terminal color | Behind upstream by `M` commits and ahead by `N` commits |
| No Remote Tracking | ` L` | Default terminal color | Local branch has no configured upstream remote-tracking branch |
| Staged Files | `● <N>` | Red | `N` files staged in the Git index |
| Conflicted Files | `✖ <N>` | Red | `N` files with unresolved merge/rebase/cherry-pick conflicts |
| Changed (Unstaged) Files | `✚ <N>` | Blue | `N` tracked files modified in working tree but unstaged |
| Untracked Files | `…<N>` | Cyan | `N` untracked files/directories |
| Stashed Entries | `⚑ <N>` | Bold Blue | `N` stash entries in the repository stash stack |
| Clean Repository | `✔` | Bold Green | Zero staged, conflicted, changed, untracked, or stashed items |

### 4.4 Template Placeholder Tokens
All placeholder tokens must undergo literal string replacement with pathname expansion (globbing) disabled so wildcard characters (`*`, `?`, `[...]`) in branch names, environment names, or custom symbols never expand into filesystem paths:

| Placeholder Token | Valid Placement Scope | Substitution Behavior |
| :--- | :--- | :--- |
| `_LAST_COMMAND_INDICATOR_` | Prompt Start, Prompt End, Callback Output | Replaced with formatted `GIT_PROMPT_COMMAND_OK` or `GIT_PROMPT_COMMAND_FAIL` (followed by color reset in Git prompts). |
| `_LAST_COMMAND_STATE_` | `GIT_PROMPT_COMMAND_OK`, `GIT_PROMPT_COMMAND_FAIL` | Replaced with numeric exit code (`<= 128`) or symbolic signal name (`> 128`). |
| `_VIRTUALENV_` | `GIT_PROMPT_VIRTUALENV` | Replaced with the resolved name of each active Python, Node, or Conda environment. |
| `_UPSTREAM_` | `GIT_PROMPT_UPSTREAM` | Replaced with the trimmed remote-tracking branch name (when `GIT_PROMPT_SHOW_UPSTREAM=1`). |
| `_USERNAME_REPO_` | `GIT_PROMPT_PREFIX` | Replaced with `<owner>/<repo>` + color reset + optional `GIT_PROMPT_USERNAME_REPO_SEPARATOR` when `GIT_PROMPT_WITH_USERNAME_AND_REPO=1` and remote exists; otherwise replaced with color reset alone. |
| `_AHEAD_`, `_BEHIND_`, `_NO_REMOTE_TRACKING_`, `_PRETAG_`, `_PREHASH_` | Custom status command interface (if `GIT_PROMPT_STATUS_COMMAND` is used) | Replaced with the corresponding `GIT_PROMPT_SYMBOLS_*` values without glob expansion. |

### 4.5 Illustrative Visual Prompt Examples (`Default` Theme)

| Rendered Git Status Block | Repository State Represented |
| :--- | :--- |
| `[master ↑·3\|✚ 1]` | On branch `master`, ahead of upstream by 3 commits, 1 unstaged modified file |
| `[status\|● 2]` | On branch `status` (in sync with upstream), 2 files staged in index |
| `[master\|✚ 7…4]` | On branch `master`, 7 unstaged modified files and 4 untracked files |
| `[master\|✖ 2✚ 3]` | On branch `master`, 2 files with merge conflicts and 3 unstaged modified files |
| `[master\|⚑ 2]` | On branch `master`, clean working tree/index, 2 entries in stash |
| `[experimental ↓·2↑·3\|✔]` | On branch `experimental`, behind upstream by 2 commits and ahead by 3 commits, working tree and stash completely clean |
| `[:70c2952\|✔]` | Detached HEAD at commit `70c2952` (no exact tag), repository clean |
| `[v2.4.0\|✔]` | Detached HEAD matching exact tag `v2.4.0` (with empty default pretag), repository clean |
| `[extra-features L\|✚ 2…4]` | On local branch `extra-features` with no remote tracking (`L`), 2 unstaged modified files and 4 untracked files |
| `[feature\|REBASE-i 1/3 L\|● 1]` | Interactive rebase step 1 of 3 in progress, 1 staged file |
| `[main {origin/main} ↑·1\|✔]` | `GIT_PROMPT_SHOW_UPSTREAM=1` enabled: on `main` tracking `origin/main`, 1 commit ahead, clean |

### 4.6 Named Color Palette System
- **Readline Width Safety**: Every named color variable intended for prompt strings must wrap its ANSI SGR terminal escape sequence inside Bash Readline's non-printing start and end markers so Bash accurately calculates visible prompt character width and wraps long input lines without cursor corruption.
- **Direct Terminal Printing Stripping**: Whenever interactive helper commands (`git_prompt_help`, `git_prompt_examples`, `git_prompt_color_samples`, `git_prompt_list_themes`, `git_prompt_make_custom_theme`) print colored strings directly to standard output rather than assigning them to `PS1`, Readline's non-printing markers must be stripped so literal escape-marker characters never appear on screen.
- **Complete Set of 98 Named Color Variables**:
  - **Base Color Names (`ColorNames` array, 8 colors)**: `Black`, `Red`, `Green`, `Yellow`, `Blue`, `Magenta`, `Cyan`, `White`.
  - **Attribute Prefixes (4 variants)**:
    - *(No prefix)*: Standard normal attribute (`0`)
    - `Bold`: Bold / bright intensity attribute (`1`)
    - `Bright`: Alias for bold / bright intensity attribute (`1`)
    - `Dim`: Dim / faint intensity attribute (`2`)
  - **Foreground & Background Suffixes (3 forms per attribute-color pair = 96 variables)**:
    - `<Attr><Color>`: Foreground color (e.g., `Red`, `BoldRed`, `BrightRed`, `DimRed`)
    - `<Attr><Color>Fg`: Explicit foreground color alias (e.g., `RedFg`, `BoldRedFg`, `BrightRedFg`, `DimRedFg`)
    - `<Attr><Color>Bg`: Background color (e.g., `RedBg`, `BoldRedBg`, `BrightRedBg`, `DimRedBg`)
  - **Special Color Variables (2 variables)**:
    - `IntenseBlack`: High-intensity black / dark gray foreground (`90`)
    - `ResetColor`: Full terminal attribute and color reset (`0`)
- **User Color File Override Discovery**:
  - If the user provides a custom color definitions file at `~/.prompt-colors.sh`, `~/prompt-colors.sh`, or `~/lib/prompt-colors.sh` (checked in that precedence order before falling back to the installation directory), the user's file is used.
  - Color definitions are initialized once per session and cached unless cleared via `git_prompt_reset`.

---

## 5. Theming System & Exhaustive Built-in Theme Catalog

### 5.1 Theme Selection & Fallback Rules
The active theme is determined according to the following strict precedence:
1. **Custom Theme File Path Resolution**: Uses `GIT_PROMPT_THEME_FILE` if set and non-empty; otherwise defaults to `~/.git-prompt-colors.sh`.
2. **When `GIT_PROMPT_THEME` is Unset**:
   - If the resolved custom theme file exists and is readable: automatically activates the `Custom` theme from that file.
   - Otherwise: activates the built-in `Default` theme.
3. **When `GIT_PROMPT_THEME` is Set to `"Custom"`**:
   - If the resolved custom theme file exists and is readable: activates the `Custom` theme from that file.
   - Otherwise: falls back cleanly to the built-in `Default` theme (updating `GIT_PROMPT_THEME` to `"Default"`).
4. **When `GIT_PROMPT_THEME` is Set to `<ThemeName>`**:
   - Searches built-in themes for an exact name match `<ThemeName>`.
   - If found and readable: activates `<ThemeName>`.
   - If not found: falls back cleanly to the built-in `Default` theme (updating `GIT_PROMPT_THEME` to `"Default"`).

### 5.2 Theme Inheritance, Partial Overrides & Caching
- **Partial Override Inheritance**: Every built-in and custom theme inherits from the `Default` theme baseline. A theme only needs to define the specific visual variables, symbols, helper variables (`Time12a`, `PathShort`, `NewLine`), or `prompt_callback` function it wishes to customize; all omitted theme variables automatically receive the `Default` theme's standard values.
- **Clean State Transitions**: Switching from one theme to another (followed by `git_prompt_reset` or theme reload) clears previously applied theme variables before applying the new theme's overrides and filling defaults, preventing variable bleed-through between themes.
- **Session Caching**: Once resolved and loaded, the active theme is cached across prompt cycles and only reloaded if the resolved theme file changes or `git_prompt_reset` is executed.

### 5.3 Exhaustive Catalog of All 40 Built-in Themes
All 40 built-in themes from the existing product must be available out of the box, selectable by setting `GIT_PROMPT_THEME` to the exact theme name below:

| # | Theme Name (`GIT_PROMPT_THEME`) | Layout | Key Visual, Font & Behavioral Specifications |
| :--- | :--- | :--- | :--- |
| 1 | `Default` | Two-line | Canonical default: Line 1 shows exit indicator (`✔` / `✘-code`), yellow home-shortened path, and `[branch\|status]`; Line 2 shows white `HH:MM` and `$ ` (user) or `# ` (root). |
| 2 | `Default_NoExitState` | Two-line | Identical to `Default`, except omits `_LAST_COMMAND_INDICATOR_` from Prompt Start and omits numeric exit code from `GIT_PROMPT_COMMAND_FAIL`. |
| 3 | `Default_Ubuntu` | Two-line | `Default` tuned with trailing spaces after `● `, `✔ `, and `✔ ` (OK) to prevent glyph overlap in standard Ubuntu terminal fonts. |
| 4 | `Default_NoExitState_Ubuntu` | Two-line | Combines `Default_NoExitState` with Ubuntu terminal font trailing-space adjustments. |
| 5 | `BlackOrWhite` | Multi-line (2 or 3 lines) | Highly configurable dark/light theme (`black` or `white` base) supporting 3 frame styles (`bubbles` `┌─(...)──(...)` / `└─•`, `bubbles_with_double_line` `╔═(...)` / `╠═(git)` / `╚═>`, and `powerline` `┌─ ...  ...` / `└─•`), configurable visible sections (`os`, `os_icon`, `user`, `hostname`, `user_and_hostname`, `time`, `path`, `last_command_state`), optional Nerd Font icon injection/replacement across 10 section/icon groups (including OS detection for macOS, Arch Linux, CentOS, Debian, Fedora, Gentoo, Linux Mint, openSUSE, Red Hat, Ubuntu), optional extra icon spacing, and distinct root indicator `(!)`. Controlled by 5 dedicated `GIT_PROMPT_BLACK_OR_WHITE_THEME_*` settings (Section 7.4). |
| 6 | `Chmike` | Two-line | Dark-scheme Crunch-inspired theme with green branch names, active Ruby version detection (RVM / rbenv), and distinctive Unicode/emoji symbols (`⭐` untracked branch, `❗` changed, `▸` staged, `…` untracked, `❓` conflicts, `>` stashed, `✔` clean/OK, `✘` fail without code). |
| 7 | `Crunch` | Single-line | Dark-scheme clone of oh-my-zsh Crunch prompt: `_LAST_COMMAND_INDICATOR_{HH:MM}[RubyVersion]path:[git] ➭ ` (or `# ` for root), no leading space before green `[` `]` git block, `✭` untracked-branch symbol, RVM/rbenv Ruby detection. |
| 8 | `Evermeet` | Single-line | High-DPI/Retina dark theme enclosing the entire prompt in brackets: `[user@host <exit_code> path git]$ ` (green `user@host` for user, red for root; numeric last command exit code in bold yellow; unbracketed git block; `⭑` untracked-branch symbol; magenta upstream `{...}`). |
| 9 | `Evermeet_Lowres` | Single-line | `Evermeet` adjusted with trailing spaces after wide Unicode glyphs (`✖ `, `✚ `, `⭑ `) for non-Retina / low-resolution displays. |
| 10 | `Evermeet_Ubuntu` | Single-line | `Evermeet` adjusted with trailing spaces after `● `, `✖ `, `✚ `, `⚑ `, `✔ `, and `⭑ ` for Ubuntu terminal fonts. |
| 11 | `Evermeet_return_prompt` | Two-line | Box-drawn dark Retina theme (`┌──[HH:MM user <exit_code> path git]` / `└─$ `, omitting time for root) with expressive emoji status icons: `🪵` branch prefix, `👆` staged, `😨` conflicts, `⌛` changed, `🤔` untracked, `📌` stashed, `👍` clean, `👇` behind, `🔥` no remote tracking, space separator. |
| 12 | `Minimal` | Two-line | Uses `prompt_callback` to compute the path relative to the enclosing Git repository's top-level directory (`<repo_name>/<subpath>`, or current path outside repo), sets the terminal window title to it, and prints it in bold yellow; unbracketed space-prefixed git symbols without separator; exit indicator at end of line 1; `HH:MM:SS ▶ ` (user) or `HH:MM:SS /!!!\ ` (root) on line 2. |
| 13 | `Minimal_Chevron` | Two-line | Chevron-styled variant of `Minimal` with leading blank line, chevron exit indicators (`❯❯` OK / `❮❮ code` fail) at start of line 1, cyan repo-relative path + window title, bracketed git block without separator using `⬆.` ahead, `⬇.` behind, `❮❮` conflicts, `✚.` changed, `❯❯` clean, red `✭` untracked branch, and `HH:MM ❯❯ ` on line 2. |
| 14 | `Minimal_UserHost` | Two-line | Variant of `Minimal` adding `user@host` (bold green for user, bold red for root) after `HH:MM:SS` on line 2 before `▶ ` / `/!!!\ `. |
| 15 | `Multi_line_NoExitState_Gentoo` | Two-line | Gentoo-styled multi-line prompt without exit state: line 1 shows bold green `user@host` (or bold red `host` for root) + bright blue path; line 2 shows cyan-branch git block + bright blue ` $ `. |
| 16 | `Plague_Doctor` | Two-line | Repository-only (`GIT_PROMPT_ONLY_IN_REPO=1`) Nerd Font theme with no leading space: line 1 shows bold blue ` ` (user) or bold red `❖ ` (root) + `[ branch \| status ]` (`✭` untracked branch); line 2 shows exit indicator + `HH:MM user@host path $ ` (or `# ` in bold red for root). |
| 17 | `Single_line` | Single-line | Single-line counterpart to `Default`: exit indicator + white `HH:MM` + bold yellow path + git status + `$ ` (or bold red `# ` for root). |
| 18 | `Single_line_Dark` | Single-line | Dark openSUSE-styled single-line prompt: exit indicator + green/red `host:` + blue path + cyan-branch git status + `> ` (or ` # ` for root). |
| 19 | `Single_line_Minimalist` | Single-line | Compact single-line prompt setting terminal window title to `gp_truncate_pwd`; shows `✔`/`✘` (no exit code) + `HH:MM:SS` + cyan current directory basename + bracketed space-separated git status + `$ ` / `# `. |
| 20 | `Single_line_Minimalist_robbyrussell` | Single-line | Inspired by oh-my-zsh `robbyrussell`: sets window title to `gp_truncate_pwd`; shows green/red `➜` exit arrow + bold cyan current directory basename + `[branch\|status]` + trailing space (`# ` for root). |
| 21 | `Single_line_Minimalist_robbyrussell_kube-ps1` | Single-line | Extends `Single_line_Minimalist_robbyrussell` by appending dynamic Kubernetes context via `kube_ps1` immediately after the directory basename when `kube_ps1` is defined in the shell. |
| 22 | `Single_line_NoExitState` | Single-line | Variant of `Single_line` that omits the numeric exit status on command failure (displays `✘` instead of `✘-code`). |
| 23 | `Single_line_NoExitState_Gentoo` | Single-line | Single-line Gentoo default style without exit indicator: `user@host path` (or `host path` for root) + cyan-branch git status + bright blue ` $ `. |
| 24 | `Single_line_NoExitState_openSUSE` | Single-line | Single-line openSUSE default style without exit indicator: `user@host:path` (or bold red `host:path` for root) + cyan-branch git status + `> ` (or ` # `). |
| 25 | `Single_line_openSUSE` | Single-line | Single-line openSUSE style prefixed with `_LAST_COMMAND_INDICATOR_ `. |
| 26 | `Single_line_Solarized` | Single-line | Tuned for Solarized Dark/Light & Powerline/Terminus/Ubuntu fonts: exit indicator (`✘` without code on fail) + `user:basename` + `[ branch \| status ]` (`✭` untracked branch) + bold blue ` ➭ ` (or bold red ` # `). |
| 27 | `Single_line_Solarized_Lamda` | Single-line | Variant of `Single_line_Solarized` displaying yellow `[HH:MM]` + cyan path and ending with an orange Greek lambda ` λ ` for users (or bold red ` # ` for root). |
| 28 | `Single_line_Ubuntu` | Single-line | Single-line theme with spaced `[ branch \| status ]` symbols tuned for Ubuntu terminal fonts, `✔ `/`✘ ` exit indicator without code, `HH:MM`, cyan path, and `$ ` / `# `. |
| 29 | `Single_line_username_repo` | Single-line | Variant of `Single_line` enabling `GIT_PROMPT_WITH_USERNAME_AND_REPO=1` with `GIT_PROMPT_USERNAME_REPO_SEPARATOR=" \| "` and prefix `[ <Blue>_USERNAME_REPO_`. |
| 30 | `Solarized` | Two-line | `Default` two-line layout with colors tuned for Solarized Dark and Solarized Light schemes (yellow staged `●`, bold magenta stashed `⚑ `, green clean `✔`, bold blue `HH:MM`). |
| 31 | `Solarized_NoExitState` | Two-line | `Solarized` omitting `_LAST_COMMAND_INDICATOR_` from Prompt Start and numeric exit code from fail indicator. |
| 32 | `Solarized_Ubuntu` | Two-line | `Solarized` with trailing spaces on `● `, `✔ `, and `✔ ` (OK) for Ubuntu terminal fonts. |
| 33 | `Solarized_NoExitState_Ubuntu` | Two-line | Combines `Solarized_NoExitState` with Ubuntu font spacing adjustments. |
| 34 | `Solarized_Extravagant` | Two-line | Rich Solarized two-line prompt: line 1 shows exit indicator (`✔ `/`✘ `), `HH:MM:SS`, green kernel release `‹kernel›`, cyan RVM/rbenv Ruby version, yellow path, and cyan-bracketed git status (`✭` untracked branch); line 2 adapts to `SSH_CLIENT`: bold red ` ➤ ` (user) / ` » ` (root) over SSH vs. bold blue ` ➭ ` (user) / bold red ` # ` (root) locally. |
| 35 | `Solarized_UserHost` | Two-line | Derived from `Solarized_Extravagant`: line 1 shows exit indicator + yellow path + cyan-bracketed git status; line 2 shows `user@host ➤  ` (user) or `user@host #️  ` (root). |
| 36 | `TruncatedPwd_WindowTitle` | Two-line | Debian-style two-line prompt using `prompt_callback` to set window title to `user@host: <truncated_pwd>` and render yellow `[user@host: <truncated_pwd>]`, followed by git status and `_LAST_COMMAND_INDICATOR_` at end of line 1, and `HH:MM $ ` / `# ` on line 2. |
| 37 | `TruncatedPwd_WindowTitle_NoExitState` | Two-line | Debian-style truncated PWD + window title variant (mirrors `TruncatedPwd_WindowTitle` structure). |
| 38 | `TruncatedPwd_WindowTitle_Ubuntu` | Two-line | `TruncatedPwd_WindowTitle` with Ubuntu terminal font spacing adjustments on `● `, `✔ `, and `✔ ` (OK). |
| 39 | `TruncatedPwd_WindowTitle_NoExitState_Ubuntu` | Two-line | Ubuntu-spaced Debian-style truncated PWD + window title variant omitting numeric exit code on command failure (`✘ `). |
| 40 | `Windows_UserHost` | Two-line | Pure ASCII (non-Unicode) variant of `Solarized_UserHost` using 24-bit RGB light blue & crimson red colors and ASCII indicators (`* ` staged, `.. ` untracked, `S ` stashed, `v ` clean/OK, `x ` fail, `L` untracked branch), with `user@host > ` / `# ` on line 2. |

---

## 6. Interactive Commands, Helper Functions & CLI Tooling

### 6.1 Interactive Session User Commands
Once loaded in an interactive Bash session, the software exposes the following user-facing commands:

| Command & Synopsis | Arguments | Behavior & Output Specification |
| :--- | :--- | :--- |
| `git_prompt_help` | None | Prints colorized interactive reference documentation explaining the Git prompt structure (`<PREFIX><BRANCH><TRACKING><SEPARATOR><LOCALSTATUS><SUFFIX>`), branch/tag/hash notation, remote tracking divergence symbols, local status symbols, and a pointer to `git_prompt_examples`. |
| `help_git_prompt` | None | Alias for `git_prompt_help`; produces identical output. |
| `git_prompt_examples` | None | Prints 8 colorized, annotated sample Git prompts covering ahead+changed, staged, changed+untracked, conflicts+changed, stashed, diverged+clean, detached commit hash+clean, and untracked-local-branch+changed+untracked states using the current/default symbols and colors. |
| `git_prompt_color_samples` | None | Prints a preview list of all 32 foreground color/intensity combinations (`<Color>`, `Dim<Color>`, `Bold<Color>`, `Bright<Color>` for each of the 8 base colors), rendering each variable's name in its own terminal color. |
| `git_prompt_list_themes` | None | Lists all available built-in themes in alphabetical order followed by `Custom`. Highlights the active theme: if a built-in theme is active, prefixes it with `*` in Red and prints `Custom` in Blue; if `Custom` is active, prints `*Custom` in Magenta. |
| `git_prompt_make_custom_theme [<base_theme>]` | Optional `<base_theme>` name | Generates `~/.git-prompt-colors.sh` so the user can customize their theme:<br>• If `~/.git-prompt-colors.sh` already exists and is readable: prints a Red error message refusing to overwrite it.<br>• If `<base_theme>` is `"Custom"`: prints a Red error stating `Custom` cannot be used as a base theme.<br>• If `<base_theme>` matches an existing readable built-in theme: copies that theme to `~/.git-prompt-colors.sh`, prints confirmation in Green/Magenta naming `<base_theme>`, and reminds the user to configure `GIT_PROMPT_THEME=Custom`.<br>• If `<base_theme>` is omitted or does not match a built-in theme: generates `~/.git-prompt-colors.sh` from a documented custom theme template containing commented defaults from `Default`, prints confirmation naming `"Default"`, and reminds the user to configure `GIT_PROMPT_THEME=Custom`. |
| `git_prompt_toggle` | None | Toggles `GIT_PROMPT_DISABLE` between `1` (disabled) and `0` (enabled) for the current shell session, taking effect on the immediate prompt render. |
| `git_prompt_reset` | None | Clears cached installation paths, loaded color file state, loaded theme state, and status command state so the next prompt render reloads all files and configuration from scratch. |

### 6.2 Prompt Callback & Customization Helper Commands
Available to user-defined `prompt_callback` hooks and custom themes:

| Function & Synopsis | Arguments | Behavior Specification |
| :--- | :--- | :--- |
| `prompt_callback` | None *(user/theme-defined)* | Optional extension hook function. When defined by the user or active theme, invoked during prompt construction; its standard output is injected immediately after Prompt Start. |
| `gp_truncate_pwd [<max_len>]` | Optional integer `<max_len>` (default: `COLUMNS / 3`, assuming `80` if `COLUMNS` unset) | Substitutes `$HOME` prefix in `PWD` with `~`; if length exceeds `<max_len>`, replaces leading characters with `...` so total length equals `<max_len>`; prints without trailing newline. |
| `gp_set_window_title <title>` | Required `<title>` string | Outputs XTerm window-title escape sequence wrapped in Readline non-printing markers to set the terminal emulator title to `<title>`. |
| `gp_format_exit_status <code>` | Required exit status `<code>` | Outputs symbolic signal name if `<code>` is an integer `> 128` (via `code - 128`), or outputs `<code>` verbatim otherwise. |
| `gp_format_username_repo` | None | Extracts and outputs `<owner>/<repo>` from the active Git repository's `remote.origin.url` setting, or empty output if unset. |

### 6.3 Verification & Performance Benchmarking CLI Utilities
For quality verification and performance regression tracking during development and maintenance, the project includes three standalone command-line utilities:

1. **Automated Test Suite Runner**:
   - Executes all functional test suites and exits with an exit status equal to the number of failed test files (`0` when all pass).
   - Must verify at minimum:
     - Original `PS1` preservation outside Git repos, dynamic activation upon entering a Git repo, and exact restoration upon leaving (`GIT_PROMPT_ONLY_IN_REPO=1`).
     - Pre-prompt hook installation both when `PROMPT_COMMAND` starts unset and when pre-populated with custom user commands (handling both string and Bash 5+ array forms), ensuring exit status capture runs first and prompt rendering runs last.
     - Active rebase state display (`REBASE-i`), non-interference with in-progress rebase state, zero leftover temporary files, and clean recovery once rebase ends.
     - Accurate stash counting inside linked Git worktrees.
2. **Latency Benchmark CLI**:
   - **Command-Line Options**:
     - `[<iterations>]`: Optional positive integer specifying number of timed iterations per benchmark item (default: `20`).
     - `--no-save`: Optional flag to print benchmark metrics to standard output without appending results to the persistent TSV results log.
   - **Behavior**: Displays environment metadata (UTC timestamp, repository short commit SHA, iteration count, Git version, Bash version, in-repo status), measures minimum, average, and maximum execution time in milliseconds (`0.1 ms` resolution) across baseline Git operations, status evaluation, full prompt update pipeline, and core sub-operations, and appends tab-separated records to a persistent benchmark results file unless `--no-save` is passed.
3. **Benchmark Comparison CLI**:
   - **Command-Line Options**:
     - *(No arguments)*: Compares the most recent two recorded benchmark runs side by side (`A avg`, `B avg`, `B min`, and colorized percentage delta: green for faster, red for slower).
     - `--list`: Lists all recorded benchmark runs with their 1-based run index, timestamp, and Git commit SHA.
     - `--all`: Displays a full historical matrix table of average latencies and run-over-run percentage deltas across all recorded runs.
     - `<run_A> [<run_B>]`: Compares two specific recorded runs selected by 1-based index (if `<run_B>` is omitted, compares `<run_A>` against the latest recorded run).

---

## 7. Exhaustive Configuration Settings Reference

### 7.1 Global Session Configuration Variables
Configured by the user in their Bash startup file (or interactive session) prior to or during prompt operation:

| Setting Name | Default Value | Accepted Values | Functional Specification |
| :--- | :--- | :--- | :--- |
| `__GIT_PROMPT_DIR` | *(Auto-detected)* | Valid directory path | Overrides the base installation directory used to locate bundled themes and resources. |
| `GIT_PROMPT_ONLY_IN_REPO` | `0` | `0`, `1` | When `1`, activates the prompt only inside Git working trees and restores the user's original `PS1` outside repositories (and when ignored/disabled). |
| `GIT_PROMPT_DISABLE` | `0` | `0`, `1` | When `1`, suspends Git status inspection and remote fetching, rendering the Non-Git (or original) prompt. Toggled by `git_prompt_toggle`. |
| `GIT_PROMPT_FETCH_REMOTE_STATUS` | `1` | `0`, `1` | Controls whether stale remotes are fetched periodically in the background (`1` = enabled, `0` = disabled). |
| `GIT_PROMPT_FETCH_TIMEOUT` | `5` | Positive integer (minutes) | Minimum age in minutes of the repository's last fetch record before triggering a background remote fetch. |
| `GIT_PROMPT_IGNORE_SUBMODULES` | `0` | `0`, `1` | When `1`, ignores dirty/modified submodules when computing repository status. |
| `GIT_PROMPT_IGNORE_STASH` | `0` | `0`, `1` | When `1`, skips counting Git stash entries (stashed count is always `0`). |
| `GIT_PROMPT_SHOW_UPSTREAM` | `0` | `0`, `1` | When `1`, displays the upstream remote-tracking branch block using `GIT_PROMPT_UPSTREAM`. |
| `GIT_PROMPT_SHOW_TRACKING` | `1` | `0`, `1` | When `0`, suppresses all remote tracking divergence (`↑·`, `↓·`) and untracked-branch (`L`) indicators. |
| `GIT_PROMPT_SHOW_UNTRACKED_FILES` | `normal` | `no`, `normal`, `all` | Controls untracked file counting: `no` skips untracked files; `normal` counts non-ignored untracked files and directories; `all` counts individual files inside untracked directories. |
| `GIT_PROMPT_SHOW_CHANGED_FILES_COUNT` | `1` | `0`, `1` | When `1`, appends numeric counts to staged, conflicted, changed, untracked, and stashed symbols; when `0`, displays only the symbols without counts (remote commit counts remain shown). |
| `GIT_PROMPT_WITH_VIRTUAL_ENV` | `1` | `0`, `1` | When `1`, detects and displays active Python, Node.js, and Conda environments; when `0`, omits virtual environment segments. |
| `GIT_PROMPT_VIRTUAL_ENV_AFTER_PROMPT` | `0` | `0`, `1` | When `0`, places virtual environment segment at the start of the prompt; when `1`, places it after Prompt Start and `prompt_callback` output. |
| `GIT_PROMPT_WITH_USERNAME_AND_REPO` | `0` | `0`, `1` | When `1`, extracts `<owner>/<repo>` from `remote.origin.url` for substitution into `_USERNAME_REPO_` inside `GIT_PROMPT_PREFIX`. |
| `GIT_PROMPT_USERNAME_REPO_SEPARATOR` | *(Unset)* | Any string (e.g., `" \| "`) | Appended after resolved `<owner>/<repo>` when a remote exists, and automatically omitted when no remote exists. |
| `GIT_PROMPT_LEADING_SPACE` | `1` | `0`, `1` | When `1`, inserts a single leading space before `GIT_PROMPT_PREFIX`; when `0`, omits the leading space. |
| `GIT_PROMPT_START` | *(Unset)* | Prompt template string | Global override for the opening prompt segment; takes precedence over both `GIT_PROMPT_START_USER` and `GIT_PROMPT_START_ROOT`. |
| `GIT_PROMPT_END` | *(Unset)* | Prompt template string | Global override for the closing prompt segment; takes precedence over both `GIT_PROMPT_END_USER` and `GIT_PROMPT_END_ROOT`. |
| `GIT_PROMPT_THEME` | *(Unset -> auto)* | `"Default"`, `"Custom"`, or any built-in theme name | Selects the active visual theme (see Section 5.1 for unset/fallback behavior). |
| `GIT_PROMPT_THEME_FILE` | `~/.git-prompt-colors.sh` | Readable file path | Custom theme file path loaded when `GIT_PROMPT_THEME` is `"Custom"` (or unset when this file exists). |
| `GIT_PROMPT_STATUS_COMMAND` | *(Built-in status provider)* | Executable name or path | Optional hook allowing an external/custom status command to supply repository status fields if configured. |

### 7.2 Per-Repository Configuration File (`.bash-git-rc`)
Users may place an optional `.bash-git-rc` file at the root directory of any Git working tree to override performance or visibility settings for that repository alone:

| Allowed `.bash-git-rc` Key | Accepted Values | Per-Repository Effect |
| :--- | :--- | :--- |
| `FETCH_REMOTE_STATUS` | `0`, `1` | Overrides `GIT_PROMPT_FETCH_REMOTE_STATUS` for this repository only. |
| `GIT_PROMPT_SHOW_UNTRACKED_FILES` | `no`, `normal`, `all` | Overrides global `GIT_PROMPT_SHOW_UNTRACKED_FILES` for this repository only. |
| `GIT_PROMPT_IGNORE_SUBMODULES` | `0`, `1` | Overrides global `GIT_PROMPT_IGNORE_SUBMODULES` for this repository only. |
| `GIT_PROMPT_SHOW_TRACKING` | `0`, `1` | Overrides global `GIT_PROMPT_SHOW_TRACKING` for this repository only. |
| `GIT_PROMPT_IGNORE` | `0`, `1` | When `1`, completely skips Git status inspection and remote fetching for this repository, displaying the Non-Git (or original) prompt. |

**Mandatory Security & Scoping Rules for `.bash-git-rc`**:
1. **Strict Allowlist & Format Validation**: Every line in `.bash-git-rc` must strictly match one of the five allowlisted keys above, followed immediately by `=`, followed only by lowercase ASCII letters and digits (`a`–`z`, `0`–`9`), with no whitespace, shell metacharacters, command substitutions, comments, or arbitrary variable names.
2. **Rejection of Invalid Files**: If *any* line in `.bash-git-rc` fails validation, the software must **never execute or apply any part of the file**, must emit a warning message to standard error stating that `.bash-git-rc` may only contain `NAME=value` declarations, and must continue using the user's global settings.
3. **Strict Repository Scoping (No State Leakage)**: Overrides loaded from `.bash-git-rc` must apply solely to the prompt cycle(s) inside that repository. Moving into another repository or directory must automatically revert all overridden settings back to the user's session-level values.

### 7.3 Theme & Visual Customization Settings
Configurable within custom or built-in themes (all unset settings inherit their default value from `Default`):

| Theme Variable | `Default` Theme Value | Purpose |
| :--- | :--- | :--- |
| `GIT_PROMPT_THEME_NAME` | `"Default"` | Unique identifier string of the active theme (used for reload caching). |
| `GIT_PROMPT_PREFIX` | `"["` | Opening delimiter of the Git Status Block (supports `_USERNAME_REPO_`). |
| `GIT_PROMPT_SUFFIX` | `"]"` | Closing delimiter of the Git Status Block. |
| `GIT_PROMPT_SEPARATOR` | `"\|"` | Delimiter separating branch/tracking status from local repository status counts. |
| `GIT_PROMPT_BRANCH` | Magenta | Color/prefix applied to standard branch names. |
| `GIT_PROMPT_MASTER_BRANCH` | Inherits `GIT_PROMPT_BRANCH` | Color/prefix applied to branches matching `GIT_PROMPT_MASTER_BRANCHES`. |
| `GIT_PROMPT_MASTER_BRANCHES` | `"master"` | Pattern matching primary branch names (supports single branch names and Bash extended pattern matching expressions for multiple branch names). |
| `GIT_PROMPT_DETACHED_HEAD` | Inherits `GIT_PROMPT_BRANCH` | Color/prefix applied when in detached HEAD state. |
| `GIT_PROMPT_REMOTE` | `" "` | Prefix/color rendered before remote ahead/behind or untracked-branch indicators. |
| `GIT_PROMPT_UPSTREAM` | Space + `{` + Blue `_UPSTREAM_` + Reset + `}` | Template for upstream remote-tracking branch display (`_UPSTREAM_` placeholder). |
| `GIT_PROMPT_STAGED` | Red + `"● "` | Color and symbol prefix for staged file count. |
| `GIT_PROMPT_CONFLICTS` | Red + `"✖ "` | Color and symbol prefix for conflicted file count. |
| `GIT_PROMPT_CHANGED` | Blue + `"✚ "` | Color and symbol prefix for unstaged modified file count. |
| `GIT_PROMPT_UNTRACKED` | Cyan + `"…"` | Color and symbol prefix for untracked file count. |
| `GIT_PROMPT_STASHED` | Bold Blue + `"⚑ "` | Color and symbol prefix for stashed entry count. |
| `GIT_PROMPT_CLEAN` | Bold Green + `"✔"` | Color and symbol indicating a completely clean repository (if `""`, also hides `GIT_PROMPT_SEPARATOR` when clean). |
| `GIT_PROMPT_COMMAND_OK` | Green + `"✔"` | Indicator substituted for `_LAST_COMMAND_INDICATOR_` on exit status `0` (supports `_LAST_COMMAND_STATE_`). |
| `GIT_PROMPT_COMMAND_FAIL` | Red + `"✘-_LAST_COMMAND_STATE_"` | Indicator substituted for `_LAST_COMMAND_INDICATOR_` on non-zero exit status (supports `_LAST_COMMAND_STATE_`). |
| `GIT_PROMPT_VIRTUALENV` | `"("` + Blue `_VIRTUALENV_` + Reset + `") "` | Template rendered for each active virtual environment (`_VIRTUALENV_` placeholder). |
| `GIT_PROMPT_START_USER` | `"_LAST_COMMAND_INDICATOR_ "` + Yellow `PathShort` + Reset | Opening prompt template for non-root users (`UID != 0`). |
| `GIT_PROMPT_START_ROOT` | Inherits `GIT_PROMPT_START_USER` | Opening prompt template for root (`UID == 0`). |
| `GIT_PROMPT_END_USER` | Space + Newline + White `Time12a` + Reset + `" $ "` | Closing prompt template for non-root users (`UID != 0`). |
| `GIT_PROMPT_END_ROOT` | Space + Newline + White `Time12a` + Reset + `" # "` | Closing prompt template for root (`UID == 0`). |
| `GIT_PROMPT_SYMBOLS_AHEAD` | `"↑·"` | Symbol preceding number of commits ahead of upstream. |
| `GIT_PROMPT_SYMBOLS_BEHIND` | `"↓·"` | Symbol preceding number of commits behind upstream. |
| `GIT_PROMPT_SYMBOLS_PREHASH` | `":"` | Symbol prepended to short commit SHA when in untagged detached HEAD state. |
| `GIT_PROMPT_SYMBOLS_PRETAG` | `""` *(empty)* | Symbol prepended to tag name when in exact-tagged detached HEAD state. |
| `GIT_PROMPT_SYMBOLS_NO_REMOTE_TRACKING` | `"L"` | Symbol rendered when a local branch has no upstream remote-tracking branch. |
| `Time12a`, `PathShort`, `NewLine` | Dynamic `HH:MM`, home-shortened cwd, newline | Predefined theme helper variables initialized prior to theme overrides and overridable by themes. |

### 7.4 `BlackOrWhite` Theme-Specific Configuration Settings
When `GIT_PROMPT_THEME` is set to `BlackOrWhite`, the following additional settings control its modular layout and Nerd Font iconography:

| Setting Name | Default Value | Accepted Values | Specification |
| :--- | :--- | :--- | :--- |
| `GIT_PROMPT_BLACK_OR_WHITE_THEME_PS1_COLOR` | `black` | `black`, `white` | Selects dark (`black`) or light (`white`) foreground/background base palette. |
| `GIT_PROMPT_BLACK_OR_WHITE_THEME_STYLE` | `bubbles` | `bubbles`, `bubbles_with_double_line`, `powerline` | Selects single-line box-drawing bubbles, double-line box-drawing bubbles (placing Git block on an intermediate `╠═(...)` line), or solid Powerline segments (`` / `` with contrasted background fills). |
| `GIT_PROMPT_BLACK_OR_WHITE_THEME_VISIBLE_SECTIONS` | `path` *(fallback when unset/empty)* | Comma-separated list of: `os`, `os_icon`, `user`, `hostname`, `user_and_hostname`, `time`, `path`, `last_command_state` | Renders the listed sections in exact specified order inside Prompt Start. |
| `GIT_PROMPT_BLACK_OR_WHITE_THEME_ADD_OR_REPLACE_ICONS_IN_SECTIONS` | *(Empty — standard symbols)* | Comma-separated list of: `os`, `user`, `hostname`, `time`, `path`, `last_command_state_prompt`, `last_command_state_ok_fail`, `git_branch`, `git_branch_powerline`, `git_status` | Injects Nerd Font icons into specified sections or replaces default command/git symbols with Nerd Font equivalents. `os` detects OS identifier (`macos`, `archlinux`, `centos`, `debian`, `fedora`, `gentoo`, `linuxmint`, `opensuse`, `redhat`, `ubuntu`) and selects the matching distribution Nerd Font glyph. |
| `GIT_PROMPT_BLACK_OR_WHITE_THEME_ADD_EXTRA_SPACE_AFTER_ICONS` | `false` | `true`, `false` | When `true`, appends extra spacing after Nerd Font icons to prevent wide-glyph clipping in terminals. |

### 7.5 External Environment Variables Respected & Exposed

| Variable Name | Direction | Specification |
| :--- | :--- | :--- |
| `PS1` | Read & Written | Primary Bash prompt variable updated on each prompt cycle (and saved/restored verbatim when `GIT_PROMPT_ONLY_IN_REPO=1`). |
| `PROMPT_COMMAND` | Read & Updated | Bash pre-prompt hook variable (string or Bash 5+ indexed array) augmented non-destructively at initialization. |
| `GIT_BRANCH` | Exported | Exported with the active branch/tag/hash + operation state inside Git repos; unset outside Git prompt evaluation. |
| `VIRTUAL_ENV`, `VIRTUAL_ENV_PROMPT`, `VIRTUAL_ENV_DISABLE_PROMPT` | Read | Standard Python virtualenv/venv environment variables honored for virtual environment display and opt-out. |
| `NODE_VIRTUAL_ENV`, `NODE_VIRTUAL_ENV_DISABLE_PROMPT` | Read | Node.js virtual environment variables honored for virtual environment display and opt-out. |
| `CONDA_DEFAULT_ENV` | Read | Conda environment variable honored for virtual environment display. |
| `COPILOT_AGENT` | Read | When equal to `1`, automatically disables Git status evaluation and renders the Non-Git/original prompt. |
| `GIT_INDEX_FILE` | Read (Scoped) | Respected if set in the external shell environment; any temporary index isolation must remain strictly local to prompt evaluation and never pollute the interactive shell's `GIT_INDEX_FILE`. |
| `SSH_CLIENT` | Read | Used by SSH-aware themes (`Solarized_Extravagant`) to distinguish remote SSH sessions from local terminals. |
| `COLUMNS`, `PWD`, `HOME`, `UID`, `TMPDIR` | Read | Standard shell/POSIX variables used for terminal width calculation, directory truncation, user configuration lookup, root privilege detection, and temporary file placement. |

---

## 8. Non-Functional Requirements & Quality Attributes

### 8.1 Performance & Interactive Responsiveness
- **Low Interactive Prompt Latency**: Prompt evaluation must execute rapidly so prompt rendering latency remains imperceptible during normal interactive shell usage.
- **Zero Redundant File Loading**: Static color definitions and theme configurations must be parsed once and cached in memory across prompt cycles until explicitly invalidated or changed.
- **Scalability Controls**: All performance-relief switches (`GIT_PROMPT_FETCH_REMOTE_STATUS=0`, `GIT_PROMPT_SHOW_UNTRACKED_FILES=no`, `GIT_PROMPT_IGNORE_SUBMODULES=1`, `GIT_PROMPT_IGNORE_STASH=1`, and per-repo `GIT_PROMPT_IGNORE=1`) must completely bypass their respective underlying inspections rather than computing and discarding results.

### 8.2 Security & Untrusted Repository Safety
- **Zero Arbitrary Code Execution from Repository Content**: Entering a cloned, untrusted Git repository must **never** execute arbitrary commands—whether via `.bash-git-rc`, crafted branch names, crafted tag names, crafted remote URLs, or crafted filenames containing shell metacharacters, command substitutions, or wildcard globs.
- **Safe Prompt Evaluation**: Branch names or repository paths containing dollar signs, backticks, quotes, or wildcard characters (`*`, `?`, `[`) must be rendered safely without triggering unintended command execution or pathname expansion.
- **Strict `.bash-git-rc` Parsing**: `.bash-git-rc` must be validated against the strict allowlist before processing; invalid files must be rejected without executing any line.

### 8.3 Shell Environment Hygiene & Reliability
- **Non-Pollution of User Shell Options**: Prompt hooks must not permanently alter the user's interactive shell options (such as unset-variable error mode, exit-on-error mode, filename globbing settings, field separators, current working directory, or signal traps). Any temporary shell state adjustments during prompt computation must remain strictly scoped or be restored prior to returning to the interactive prompt.
- **Readline Cursor Integrity**: Every non-printing escape sequence in `PS1` across color palettes, themes, and window-title helpers must be properly enclosed in Readline non-printing delimiters so history navigation (`Up`/`Down` arrows), reverse-i-search, and multi-line command wrapping exhibit zero visual drift.
