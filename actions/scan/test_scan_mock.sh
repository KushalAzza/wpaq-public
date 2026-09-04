#!/usr/bin/env bash
# Mocked end-to-end smoke test for scan.sh (no real network).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Fake curl: create once, then return completed score 82.
cat >"$TMP/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out=""
code_fmt=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o) out="${args[$((i+1))]}" ;;
    -w) code_fmt="${args[$((i+1))]}" ;;
  esac
done

if printf '%s\n' "${args[@]}" | grep -q '/api/v1/scans$'; then
  printf '%s' '{"id":"scan-mock-1","status":"queued"}' >"$out"
  if [[ "$code_fmt" == "%{http_code}" ]]; then
    printf '200'
  fi
  exit 0
fi

if printf '%s\n' "${args[@]}" | grep -q '/api/v1/scans/scan-mock-1'; then
  printf '%s' '{"id":"scan-mock-1","status":"completed","overall_score":82,"error_message":null}' >"$out"
  if [[ "$code_fmt" == "%{http_code}" ]]; then
    printf '200'
  fi
  exit 0
fi

echo "unexpected curl: ${args[*]}" >&2
exit 1
EOF
chmod +x "$TMP/curl"

export PATH="$TMP:$PATH"
export GITHUB_OUTPUT="$TMP/github_output"
export WPAQ_API_KEY="wpaq_test_key"
export WPAQ_URL="https://example.com"
export WPAQ_API_BASE="https://wpaq.test"
export WPAQ_MIN_SCORE="70"
export WPAQ_FAIL_ON="both"
export WPAQ_TIMEOUT_MINUTES="1"
export WPAQ_POLL_INTERVAL_SECONDS="1"

bash "$ROOT/scan.sh" >"$TMP/stdout" 2>"$TMP/stderr"

grep -q 'CI gate passed' "$TMP/stdout"
grep -q 'scan-id<<WPAQ_EOF' "$GITHUB_OUTPUT"
grep -q 'scan-mock-1' "$GITHUB_OUTPUT"
grep -q 'overall-score<<WPAQ_EOF' "$GITHUB_OUTPUT"
grep -q '^82$' "$GITHUB_OUTPUT"
grep -q 'https://wpaq.test/scan/scan-mock-1' "$GITHUB_OUTPUT"

# Fail path: score below min
export WPAQ_MIN_SCORE="90"
: >"$GITHUB_OUTPUT"
if bash "$ROOT/scan.sh" >"$TMP/stdout2" 2>"$TMP/stderr2"; then
  echo "expected failure for low score" >&2
  exit 1
fi
grep -q 'CI gate failed' "$TMP/stderr2"

# Fail path: bad URL
export WPAQ_URL="not-a-url"
if bash "$ROOT/scan.sh" >"$TMP/stdout3" 2>"$TMP/stderr3"; then
  echo "expected failure for bad url" >&2
  exit 1
fi
grep -qi 'http:// or https://' "$TMP/stderr3"

echo "Mocked scan.sh smoke tests passed."
