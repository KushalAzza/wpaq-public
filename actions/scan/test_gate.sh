#!/usr/bin/env bash
# Offline assertions for should_fail_gate.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=gate.sh
source "${ROOT}/gate.sh"

assert_fail() {
  local label="$1"
  shift
  if should_fail_gate "$@"; then
    echo "ok  fail — ${label}"
  else
    echo "FAIL expected fail — ${label}" >&2
    exit 1
  fi
}

assert_pass() {
  local label="$1"
  shift
  if should_fail_gate "$@"; then
    echo "FAIL expected pass — ${label}" >&2
    exit 1
  else
    echo "ok  pass — ${label}"
  fi
}

assert_pass "completed above min both" completed 80 both 70
assert_pass "warnings above min both" completed_with_warnings 70 both 70
assert_fail "completed below min both" completed 60 both 70
assert_fail "failed status both" failed "" both ""
assert_fail "failed status only" failed 90 failed_status ""
assert_pass "failed ignored when score-only" failed 90 score ""
assert_pass "low score ignored when status-only" completed 10 failed_status 90
assert_fail "missing score with min-score" completed "" score 50
assert_pass "no min-score on completed" completed "" both ""

echo "All gate tests passed."
