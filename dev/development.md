# Development

Run these commands from the repository root:

```r
library(devtools)

document()
test()
```

Build the package and run `R CMD check --no-manual` on the source archive,
including vignette building and checks.

The standard tests use synthetic data and mocked HTTP boundaries. They need no
real server, account, private documents or inference service. GitHub Actions
runs package checks without repository credentials.

## HTTP smoke test

An optional test uses a synthetic loopback server to exercise the real HTTP
transport, including cookies, rotating CSRF tokens, empty HTTP 204 responses,
login, retrieval, verified downloads and logout:

```sh
python3 tools/http_smoke_test.py
```

This test needs Python and `devtools`; neither is a runtime dependency of the
R package.

## Scope and limitations

- Modern DSpace REST API only; no legacy DSpace 6 adapter.
- Ordinary-reader, independent-repository and cross-version acceptance testing
  is still required before release.
- Content downloads are buffered in memory and retrieved serially.
- No resume engine, incremental synchronization or authorization-aware
  persistent cache is implemented.
- No submissions, metadata editing, deletion, permissions administration, PDF
  extraction, OCR, translation, page segmentation or automatic corpus selection.

See [design.md](design.md) for the original proposal and [checks.md](checks.md)
for verification records. Everything in `dev/` is excluded from package builds.
