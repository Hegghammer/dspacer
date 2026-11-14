# dspacer

An R client for downloading metadata and text from DSpace repositories.

**Early development.** The initial interface is implemented and tested against
synthetic API responses. No cross-version or independent-repository compatibility
claim is made yet.

See the [authentication vignette](vignettes/authentication.Rmd) for a short login
example.

## Author and licence

Thomas Hegghammer ([ORCID](https://orcid.org/0000-0001-6253-1518)) is the author and
maintainer; contact `code@hegghammer.net`. Licensed under the
[MIT licence](LICENSE.md), copyright 2026 Thomas Hegghammer.

## Install locally

From the package directory:

```sh
R CMD INSTALL .
```

Dependencies must already be installed. Development tooling can install them
from `DESCRIPTION` if needed.

## Retrieve metadata and text

```r
library(dspacer)
library(dplyr)

con <- ds_connect("https://repository.example.org/server/api")

# Omit this for anonymous access to public content.
ds_login(
  con,
  user = Sys.getenv("DSPACE_USER"),
  password = Sys.getenv("DSPACE_PASSWORD")
)

collections <- ds_get_collections(con)
collections

# Choose a collection after inspecting the table.
items <- ds_get_items(con, scope = collections$collection_uuid[[1]])
metadata <- ds_get_metadata(items)
files <- ds_get_files(con, items)

# Inspect the inventory: Markdown can be provenance or documentation.
# These illustrative filenames should be replaced with your own selection.
selected <- files |>
  filter(name %in% c("transcription.md", "translation.md"))

texts <- ds_get_texts(con, selected)

saveRDS(
  list(items = items, metadata = metadata, files = files, texts = texts),
  "repository_dataset.rds"
)

ds_disconnect(con)
```

Other retrieval patterns:

- `ds_get_items(con)` retrieves all visible archived search results.
- `ds_get_items(con, query = "your query")` uses the repository's Discovery syntax.
- `ds_get_items(con, ids = item_uuids)` retrieves known UUIDs directly.
- `ds_get_files(con, items, bundles = NULL)` inventories all visible bundles.
- `ds_download(con, selected, "downloads")` saves verified original bytes and
  returns a manifest with local paths.

The public API uses `ds_` and verb-led names. Server URLs, languages, schema
fields, filename conventions and group names are never built into the client.

## Returned data

- **Items:** one row per item UUID; complete metadata stays in a list column.
- **Metadata:** one row per value, preserving field name, language, authority,
  confidence, ordering and additional properties. Repeated values are retained.
- **Files:** one row per item–bundle–bitstream association, with format, size,
  checksum, primary selection, content link and file-level metadata.
- **Texts:** decoded `source_text` plus derived plaintext `text`, file identifiers,
  SHA-256, retrieval time and conversion information.

Join tables using repository URL and UUIDs, not titles or filenames. Dates in
metadata remain strings: the package does not silently turn years, uncertainty
or non-Gregorian dates into Gregorian dates.

Network result tables carry a `dspacer` attribute recording the repository and
package versions, selection and retrieval start/end times. `ds_download()` adds
per-file hashes. These are bounded retrieval records, not atomic snapshots of a
changing repository.

## Text conversion

`ds_get_texts()` accepts `text/markdown`, `text/x-markdown` and `text/plain`.
Unknown or `application/octet-stream` files may use `.md` or `.txt` as a fallback.
An explicit non-text MIME type is not overridden by a filename.

Markdown is rendered with `commonmark`, with no line wrapping, smart punctuation,
Unicode normalization or optional Markdown extensions. Headings become ordinary
text, link labels remain while destinations are omitted, code text is retained,
and raw HTML is omitted. Tables and footnotes do not get extension-specific
interpretation. Paragraph separation follows the renderer, not a guarantee of
one output paragraph per source block. Original decoded Markdown remains in
`source_text`; use `ds_download()` to preserve exact bytes.

UTF-8 is required. A UTF-8 BOM is removed from decoded text but included in byte
checksums. Invalid encoding is an error, not silently replaced text.

No OCR, translation, stemming, language inference or automatic removal of page
markers occurs. A missing attachment, an inaccessible attachment and a valid
empty file are distinct conditions.

## Authentication and safety

- Supports anonymous access and DSpace username/password authentication.
  Browser SSO is not implemented.
- Uses Discovery for item enumeration rather than the administrator-only
  `/core/items` list endpoint.
- Retains session cookies and CSRF state; it does not retain the login password.
  A failed read may trigger one token refresh, never a repeated password login.
- Requires HTTPS by default. For a deliberate local test, use
  `ds_connect(url, allow_insecure = TRUE)`.
- Refuses API links and redirects outside the configured API origin/path.
  External storage download redirects are not supported yet.
- Makes no content-changing calls. Authentication uses POST; content retrieval
  uses GET.
- Validates downloaded size and advertised MD5, SHA-1, SHA-256 or SHA-512 checksum,
  and computes local SHA-256. Unsupported algorithms are reported as errors.
- Uses UUID-based local filenames and refuses conflicting existing content.
  Remote names are retained as metadata, never treated as filesystem paths.
- Does not persistently cache text or credentials. Its temporary private cookie
  file is removed on disconnect or when the connection is garbage-collected.
- Do not save a connection with `saveRDS()` or include it in a dataset:
  connection objects contain sensitive session state.
- Downloaded restricted documents remain sensitive local copies. Secure their
  storage and do not commit them or credentials.

Progress is printed per item or file and survives redirected output. Use
`quiet = TRUE` in `ds_connect()` to suppress it.

## Current limits

- Modern DSpace REST API only; no legacy DSpace 6 API adapter.
- Ordinary-reader, independent-repository and cross-version acceptance testing
  is still required before release.
- Content downloads are buffered in memory; avoid very large attachments.
- Serial retrieval only; no resume engine, incremental synchronization, or
  authorization-aware persistent cache.
- No submission, metadata editing, deletion, permissions administration, PDF
  extraction, page segmentation or automatic corpus selection.
- A changing search index can invalidate pagination. Detected count changes or
  duplicate UUIDs stop retrieval rather than silently claiming completeness.

## Development

```r
library(devtools)

document()
test()
```

Then build the package and run `R CMD check --no-manual` on the source archive.
The standard tests use only synthetic data and mocked HTTP boundaries: they need
no real server, account, private documents or inference service. GitHub Actions
runs the same package checks without repository credentials.

An optional real-HTTP smoke test uses a synthetic loopback server, including
cookies, rotating CSRF tokens, empty HTTP 204 responses and verified text
downloads:

```sh
python3 tools/http_smoke_test.py
```

This developer test needs Python and `devtools`; neither is a runtime dependency
of the R package.

See [DESIGN.md](DESIGN.md) for the original proposal. It records the intended
direction; this README and function help describe the current implementation.
