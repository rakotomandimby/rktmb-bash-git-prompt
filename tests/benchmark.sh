#!/usr/bin/env bash
# tests/benchmark.sh - Latency Benchmark CLI (PRD Section 6.3.2)
#
# Usage:
#   ./tests/benchmark.sh [<iterations>] [--no-save]

set -u

TESTS_DIR=$(builtin cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(builtin cd -P "${TESTS_DIR}/.." && pwd)
RESULTS_FILE=${BENCHMARK_RESULTS_FILE:-"${TESTS_DIR}/benchmark-results.tsv"}

ITERATIONS=20
SAVE_RESULTS=1

for arg in "$@"; do
  case $arg in
    --no-save)
      SAVE_RESULTS=0
      ;;
    *)
      if [[ $arg =~ ^[0-9]+$ && $arg -gt 0 ]]; then
        ITERATIONS=$arg
      else
        printf 'Usage: %s [<iterations>] [--no-save]\n' "$0" >&2
        exit 1
      fi
      ;;
  esac
done

GIT_PROMPT_FETCH_REMOTE_STATUS=0
# shellcheck source=../gitprompt.sh
source "${REPO_ROOT}/gitprompt.sh"
__gp_load_theme

UTC_TS=$(LC_ALL=C date -u '+%Y-%m-%dT%H:%M:%SZ')
COMMIT_SHA=$(LC_ALL=C git --no-optional-locks rev-parse --short HEAD 2>/dev/null || printf 'unknown')
GIT_VER=$(LC_ALL=C git --version 2>/dev/null)
GIT_VER=${GIT_VER#git version }
BASH_VER=${BASH_VERSION}
if __gp_discover_repo; then
  IN_REPO="true"
else
  IN_REPO="false"
fi

printf '==================================================================\n'
printf 'Bash Git Prompt Latency Benchmark\n'
printf '==================================================================\n'
printf 'Timestamp (UTC) : %s\n' "$UTC_TS"
printf 'Commit SHA      : %s\n' "$COMMIT_SHA"
printf 'Iterations      : %d\n' "$ITERATIONS"
printf 'Git Version     : %s\n' "$GIT_VER"
printf 'Bash Version    : %s\n' "$BASH_VER"
printf 'In Repository   : %s\n' "$IN_REPO"
printf '==================================================================\n'
printf '%-36s %10s %10s %10s\n' "Operation" "Min (ms)" "Avg (ms)" "Max (ms)"
printf -- '------------------------------------------------------------------\n'

declare -a TSV_RECORDS=()

# run_bench_item <label> <command_string>
run_bench_item() {
  local label=$1
  local cmd=$2
  local -a samples=()
  local i t0 t1

  # Warm-up run
  eval "$cmd" >/dev/null 2>&1

  for (( i = 0; i < ITERATIONS; i++ )); do
    t0=$EPOCHREALTIME
    eval "$cmd" >/dev/null 2>&1
    t1=$EPOCHREALTIME
    samples+=("${t0}:${t1}")
  done

  local stats min_ms avg_ms max_ms
  stats=$(
    LC_ALL=C awk -F: '
      BEGIN { min = -1; max = 0; sum = 0; n = 0 }
      {
        dt = ($2 - $1) * 1000.0
        if (dt < 0) dt = 0
        if (min < 0 || dt < min) min = dt
        if (dt > max) max = dt
        sum += dt
        n++
      }
      END {
        avg = (n > 0) ? (sum / n) : 0
        printf "%.1f\t%.1f\t%.1f\n", min, avg, max
      }
    ' <<< "$(printf '%s\n' "${samples[@]}")"
  )

  IFS=$'\t' read -r min_ms avg_ms max_ms <<< "$stats"
  printf '%-36s %10s %10s %10s\n' "$label" "$min_ms" "$avg_ms" "$max_ms"
  TSV_RECORDS+=("${UTC_TS}"$'\t'"${COMMIT_SHA}"$'\t'"${ITERATIONS}"$'\t'"${label}"$'\t'"${min_ms}"$'\t'"${avg_ms}"$'\t'"${max_ms}")
}

run_bench_item "git rev-parse (repo discovery)" "__gp_discover_repo"
run_bench_item "git status --porcelain=v2" "LC_ALL=C git --no-optional-locks status --porcelain=v2 -z --branch --show-stash"
run_bench_item "in-progress op detection" "__gp_detect_in_progress_op \"\$__GP_GIT_DIR\""
run_bench_item "status engine (__gp_evaluate_git_status)" "__gp_evaluate_git_status \"\$__GP_GIT_DIR\" normal 0 0"
run_bench_item "theme & color cache lookup" "__gp_load_theme"
run_bench_item "full prompt update (__gp_update_prompt)" "__gp_update_prompt"

printf '==================================================================\n'

if (( SAVE_RESULTS == 1 )); then
  if [[ ! -f $RESULTS_FILE ]]; then
    printf 'timestamp\tcommit\titerations\toperation\tmin_ms\tavg_ms\tmax_ms\n' > "$RESULTS_FILE"
  fi
  for rec in "${TSV_RECORDS[@]}"; do
    printf '%s\n' "$rec" >> "$RESULTS_FILE"
  done
  printf 'Saved benchmark results to %s\n' "$RESULTS_FILE"
else
  printf '(--no-save specified; results not written to %s)\n' "$RESULTS_FILE"
fi
