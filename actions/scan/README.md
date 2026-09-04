# WPAQ Scan (GitHub Action)

Composite Action that starts a [WPAQ](https://wpaq.com) scan with your API key, polls until the scan finishes, and fails the job when the scan fails or the overall score is below an optional floor.

Requires **Pro** or **Agency** (API keys). Uses `curl` and `jq` (available on GitHub-hosted `ubuntu-latest` runners).

## Usage

```yaml
name: WPAQ scan

on:
  workflow_dispatch:
  # pull_request:

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - name: Run WPAQ scan
        uses: KushalAzza/wpaq-public/actions/scan@v1
        with:
          api-key: ${{ secrets.WPAQ_API_KEY }}
          url: https://example.com
          min-score: "70"
```

Create a key under **Dashboard → Integrations**, store it as the repository secret `WPAQ_API_KEY`.

Full example: [`examples/github-actions/wpaq-scan.yml`](../../examples/github-actions/wpaq-scan.yml).

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `api-key` | yes | — | `wpaq_…` API key |
| `url` | yes | — | Absolute `http(s)` URL |
| `api-base` | no | `https://wpaq.com` | API origin |
| `min-score` | no | _(none)_ | Fail if `overall_score` &lt; this value |
| `fail-on` | no | `both` | `score`, `failed_status`, or `both` |
| `timeout-minutes` | no | `20` | Poll timeout |
| `poll-interval-seconds` | no | `15` | Poll interval |

## Outputs

`scan-id`, `status`, `overall-score`, `report-url`

## Notes

- `completed_with_warnings` counts as a finished scan; only hard `failed` status and/or `min-score` fail the job (depending on `fail-on`).
- Scans consume plan quota like any other API scan.
- API docs: [wpaq.com/support/api](https://wpaq.com/support/api)

## Tests

```bash
bash actions/scan/test_gate.sh
bash actions/scan/test_scan_mock.sh
```
