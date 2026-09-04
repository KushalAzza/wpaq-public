# WPAQ public assets

**Canonical public GitHub home for WPAQ** — GitHub Actions, copy-paste examples, and other artifacts that must stay public while the product app (`wpaq-app`) remains private.

| Asset | Path | Use |
|-------|------|-----|
| **CI scan Action** | [`actions/scan`](./actions/scan/) | Gate PRs/deploys on a live [WPAQ](https://wpaq.com) scan |
| **Example workflow** | [`examples/github-actions/wpaq-scan.yml`](./examples/github-actions/wpaq-scan.yml) | Copy into `.github/workflows/` |

Product, API, and dashboard docs stay on [wpaq.com](https://wpaq.com) / the private app repo. **Do not** put app source, secrets, or private ops scripts here.

## Quick start (GitHub Action)

1. Create an API key at [Dashboard → Integrations](https://wpaq.com/dashboard/integrations) (Pro or Agency).
2. Add repository secret `WPAQ_API_KEY`.
3. Add a workflow step:

```yaml
- uses: KushalAzza/wpaq-public/actions/scan@v1
  with:
    api-key: ${{ secrets.WPAQ_API_KEY }}
    url: https://example.com
    min-score: "70"
```

Prefer a **version tag** (`@v1`) in production workflows. `@main` tracks the latest commit on this repo.

## License

Examples and the Action are provided for use with the WPAQ service. See [wpaq.com/terms](https://wpaq.com/terms).
