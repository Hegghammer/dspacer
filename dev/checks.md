# Verification

Verified locally on 2026-11-14 with R 4.5.3 on Debian GNU/Linux 13.

## Package checks

- Source build and temporary-library installation succeeded.
- `R CMD check --no-manual`: **0 errors, 0 warnings, 0 notes**.
- Installed-package tests: **118 passing assertions**, no failures, warnings or
  skipped assertions.
- All three vignettes (authentication, metadata and text/files) built, installed
  and rebuilt successfully; their examples are not evaluated and require no
  credentials.
- Full check output is in
  `/tmp/opencode/dspacer_check_documentation_final/dspacer.Rcheck/`.
- The local documentation tool emitted a pre-existing libxml build/runtime
  version message; it did not produce a package-check warning or note.

## Documentation organisation

- README reduced to 46 lines: overview, installation, a short example,
  documentation links and licence.
- Specialist guidance lives in vignettes and generated function help.
- Design, verification and development notes live under `dev/`, excluded from
  package builds. No `CONTRIBUTING.md` was created.
- Checked local documentation links and parsed all vignette R examples.
- Parsed R expressions were compared with Git HEAD: function definitions are
  unchanged by the documentation edits.

## Package metadata

- MIT licence and licence-file layout follow daiR, with copyright 2026 Thomas
  Hegghammer.
- Thomas Hegghammer is author and maintainer, with email
  `code@hegghammer.net` and ORCID `0000-0001-6253-1518`.
- Author name, roles, ORCID and licence declaration were checked against daiR;
  the maintainer email differs as requested.
- Generated package documentation reflects the updated metadata.

## Tested behaviour

- API root validation, credential-free connection printing and private cookie
  file cleanup.
- CSRF rotation, password login, single-attempt token refresh, logout cleanup and
  refusal to repeat login for an authenticated file-level denial.
- Rejection of unsafe origins, paths, redirects and content-changing methods.
- Discovery item retrieval, direct UUID retrieval, nested HAL search variants,
  multipage results, missing next links and detected pagination drift.
- Preservation of custom and repeated metadata, unknown value properties,
  language, server ordering, missing values and empty strings.
- File-to-item/bundle associations, MIME types and primary-file selection.
- Download size/checksum validation, UUID-based destinations and refusal to
  overwrite conflicting local content.
- Markdown/plaintext conversion, Arabic Unicode, BOM handling, strict UTF-8,
  unsupported formats, empty files, denied access and duplicate filenames
  belonging to different items.

## Real HTTP test

`python3 tools/http_smoke_test.py` passed against a synthetic loopback server.
Unlike the unit tests, this exercises the actual `httr2` transport, including
cookie persistence, rotating CSRF tokens, empty HTTP 204 responses, form login,
authenticated reads, integrity checks, downloads and logout.

It needs no real DSpace account, private content or external service. Python and
`devtools` are optional developer-test dependencies, not package runtime
dependencies.

## Unverified and pending

- The implemented R client has not yet passed acceptance tests against a real
  DSpace repository. Earlier protocol feasibility checks are not package tests.
- Ordinary-reader access, independent deployments, other DSpace versions, SSO,
  external content stores and other operating systems need evaluation.
- GitHub Actions configuration has been written but has not run on GitHub.
- At initial package creation, the local Git repository used branch `main`,
  with no commits or remotes; nothing had been published to GitHub. This is a
  historical record, not a statement of current remote state.
