#!/usr/bin/env bash
# WPAQ CI scan gate — create scan, poll, fail on status/score thresholds.
set -euo pipefail

ACTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gate.sh
source "${ACTION_DIR}/gate.sh"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

require_cmd curl
require_cmd jq

API_KEY="${WPAQ_API_KEY:-}"
URL="${WPAQ_URL:-}"
API_BASE="${WPAQ_API_BASE:-https://wpaq.com}"
MIN_SCORE="${WPAQ_MIN_SCORE:-}"
FAIL_ON="${WPAQ_FAIL_ON:-both}"
TIMEOUT_MINUTES="${WPAQ_TIMEOUT_MINUTES:-20}"
POLL_INTERVAL="${WPAQ_POLL_INTERVAL_SECONDS:-15}"

API_BASE="${API_BASE%/}"

if [[ -z "$API_KEY" ]]; then
  echo "error: api-key input is required" >&2
  exit 1
fi

if [[ -z "$URL" ]]; then
  echo "error: url input is required" >&2
  exit 1
fi

if [[ ! "$URL" =~ ^https?:// ]]; then
  echo "error: url must start with http:// or https://" >&2
  exit 1
fi

case "$FAIL_ON" in
  score|failed_status|both) ;;
  *)
    echo "error: fail-on must be score, failed_status, or both (got: $FAIL_ON)" >&2
    exit 1
    ;;
esac

if [[ -n "$MIN_SCORE" ]]; then
  if ! [[ "$MIN_SCORE" =~ ^[0-9]+$ ]] || (( MIN_SCORE > 100 )); then
    echo "error: min-score must be an integer 0–100" >&2
    exit 1
  fi
fi

if ! [[ "$TIMEOUT_MINUTES" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT_MINUTES" -lt 1 ]]; then
  echo "error: timeout-minutes must be a positive integer" >&2
  exit 1
fi

if ! [[ "$POLL_INTERVAL" =~ ^[0-9]+$ ]] || [[ "$POLL_INTERVAL" -lt 1 ]]; then
  echo "error: poll-interval-seconds must be a positive integer" >&2
  exit 1
fi

set_output() {
  local name="$1"
  local value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "${name}<<WPAQ_EOF"
      echo "${value}"
      echo "WPAQ_EOF"
    } >>"$GITHUB_OUTPUT"
  fi
}

echo "Starting WPAQ scan for ${URL}"
echo "API base: ${API_BASE}"

CREATE_BODY="$(jq -n --arg url "$URL" '{url: $url}')"
CREATE_TMP="$(mktemp)"
POLL_TMP=""
cleanup() {
  rm -f "$CREATE_TMP"
  if [[ -n "${POLL_TMP}" ]]; then
    rm -f "$POLL_TMP"
  fi
}
trap cleanup EXIT

HTTP_CODE=""
HTTP_CODE="$(
  curl -sS -o "$CREATE_TMP" -w "%{http_code}" \
    -X POST "${API_BASE}/api/v1/scans" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    --data "$CREATE_BODY"
)" || {
  echo "error: could not reach ${API_BASE}/api/v1/scans" >&2
  exit 1
}

if [[ "$HTTP_CODE" == "401" || "$HTTP_CODE" == "403" ]]; then
  echo "error: authentication/plan rejected (HTTP ${HTTP_CODE}). Check the API key and that the account is Pro or Agency." >&2
  cat "$CREATE_TMP" >&2 || true
  rm -f "$CREATE_TMP"
  exit 1
fi

if [[ "$HTTP_CODE" == "429" ]]; then
  echo "error: quota exhausted or queue busy (HTTP 429). Retry later." >&2
  cat "$CREATE_TMP" >&2 || true
  rm -f "$CREATE_TMP"
  exit 1
fi

if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "201" ]]; then
  echo "error: failed to create scan (HTTP ${HTTP_CODE})" >&2
  cat "$CREATE_TMP" >&2 || true
  rm -f "$CREATE_TMP"
  exit 1
fi

SCAN_ID="$(jq -r '.id // empty' "$CREATE_TMP")"
rm -f "$CREATE_TMP"
CREATE_TMP=""

if [[ -z "$SCAN_ID" ]]; then
  echo "error: create response missing scan id" >&2
  exit 1
fi

REPORT_URL="${API_BASE}/scan/${SCAN_ID}"
echo "Scan id: ${SCAN_ID}"
echo "Report: ${REPORT_URL}"

DEADLINE=$((SECONDS + TIMEOUT_MINUTES * 60))
STATUS="queued"
OVERALL_SCORE=""
ERROR_MESSAGE=""

while (( SECONDS < DEADLINE )); do
  POLL_TMP="$(mktemp)"
  HTTP_CODE="$(
    curl -sS -o "$POLL_TMP" -w "%{http_code}" \
      "${API_BASE}/api/v1/scans/${SCAN_ID}" \
      -H "Authorization: Bearer ${API_KEY}" \
      -H "Accept: application/json"
  )" || {
    echo "warning: poll request failed; retrying…" >&2
    rm -f "$POLL_TMP"
    POLL_TMP=""
    sleep "$POLL_INTERVAL"
    continue
  }

  if [[ "$HTTP_CODE" != "200" ]]; then
    echo "warning: poll HTTP ${HTTP_CODE}; retrying…" >&2
    cat "$POLL_TMP" >&2 || true
    rm -f "$POLL_TMP"
    POLL_TMP=""
    sleep "$POLL_INTERVAL"
    continue
  fi

  STATUS="$(jq -r '.status // empty' "$POLL_TMP")"
  OVERALL_SCORE="$(jq -r 'if .overall_score == null then "" else (.overall_score|tostring) end' "$POLL_TMP")"
  ERROR_MESSAGE="$(jq -r '.error_message // empty' "$POLL_TMP")"
  rm -f "$POLL_TMP"
  POLL_TMP=""

  echo "status=${STATUS} overall_score=${OVERALL_SCORE:-n/a}"

  case "$STATUS" in
    completed|completed_with_warnings|failed)
      break
      ;;
  esac

  sleep "$POLL_INTERVAL"
done

if [[ "$STATUS" != "completed" && "$STATUS" != "completed_with_warnings" && "$STATUS" != "failed" ]]; then
  echo "error: timed out after ${TIMEOUT_MINUTES}m waiting for scan ${SCAN_ID} (last status: ${STATUS:-unknown})" >&2
  echo "Report (may still be running): ${REPORT_URL}" >&2
  set_output "scan-id" "$SCAN_ID"
  set_output "status" "${STATUS:-timeout}"
  set_output "overall-score" "$OVERALL_SCORE"
  set_output "report-url" "$REPORT_URL"
  exit 1
fi

set_output "scan-id" "$SCAN_ID"
set_output "status" "$STATUS"
set_output "overall-score" "$OVERALL_SCORE"
set_output "report-url" "$REPORT_URL"

if should_fail_gate "$STATUS" "$OVERALL_SCORE" "$FAIL_ON" "$MIN_SCORE"; then
  echo "error: CI gate failed (fail-on=${FAIL_ON}, status=${STATUS}, overall_score=${OVERALL_SCORE:-n/a}, min-score=${MIN_SCORE:-none})" >&2
  if [[ -n "${ERROR_MESSAGE}" ]]; then
    echo "scan error: ${ERROR_MESSAGE}" >&2
  fi
  echo "Report: ${REPORT_URL}" >&2
  exit 1
fi

echo "CI gate passed (status=${STATUS}, overall_score=${OVERALL_SCORE:-n/a})"
echo "Report: ${REPORT_URL}"
exit 0
