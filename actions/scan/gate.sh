#!/usr/bin/env bash
# Shared CI gate helpers for the WPAQ GitHub Action.
# Returns 0 when the job should fail.

should_fail_gate() {
  local status="$1"
  local score="${2:-}"
  local fail_on="$3"
  local min_score="${4:-}"

  local fail_status=0
  local fail_score=0

  if [[ "$status" == "failed" ]]; then
    fail_status=1
  fi

  if [[ -n "$min_score" ]]; then
    if [[ -n "$score" && "$score" =~ ^[0-9]+$ ]]; then
      if (( score < min_score )); then
        fail_score=1
      fi
    elif [[ "$status" == "completed" || "$status" == "completed_with_warnings" ]]; then
      # min-score set but score missing after a finished scan
      fail_score=1
    fi
  fi

  case "$fail_on" in
    failed_status)
      (( fail_status == 1 ))
      ;;
    score)
      (( fail_score == 1 ))
      ;;
    both)
      (( fail_status == 1 || fail_score == 1 ))
      ;;
    *)
      echo "error: invalid fail-on: $fail_on" >&2
      return 0
      ;;
  esac
}
