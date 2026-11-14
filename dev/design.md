# An R client for DSpace

Original design draft, 2026-11-14, retained as development background.
See [the README](../README.md), [vignettes](../vignettes/) and function help for
current behaviour; repository-state statements below describe initial creation.

Metadata layout revised on 2026-11-14: `ds_get_metadata()` now defaults to one
row per object, with single-valued fields as character columns and repeated
fields as list-columns. `format = "long"` preserves the detailed per-value layout.
This supersedes the original long-table-first proposal below.

Working name: `dspacer`. Name availability has not been checked.

## Purpose and scope

A general-purpose R interface to DSpace, initially focused on downloading metadata
and text for computational research. It must work independently of any particular
repository's domain, metadata schema, languages, naming rules or access groups.

The first release should be deliberately read-only, apart from authentication.
Repository administration, submissions, metadata editing, OCR, translation and
search indexing are outside its initial scope.

Target the modern DSpace REST API, initially verifying compatibility with DSpace
10.1. Support for other modern releases is an objective, not a tested claim.
DSpace 6 and earlier use a different API and are outside the initial scope.

Success means a researcher can:

- Connect anonymously or authenticate with their own account.
- Retrieve all readable items in a chosen scope, or a selected set of item UUIDs.
- Preserve every metadata value, including custom fields and repeated values.
- Inventory attached files and explicitly select files to download.
- Obtain original Markdown and derived plaintext in joinable tibbles.
- Save a reproducible local dataset without modifying the repository.

## Generality is a requirement

- Require the REST base URL; never default to a private repository.
- Discover the server version and resource links from the API root.
- Treat metadata keys as data. Do not require Dublin Core or a local schema.
- Do not infer identifiers, dates, numbering or languages from titles.
- Never assume one item has one PDF, one language, or any text attachment.
- Treat filenames as labels, not unique identifiers or reliable language tags.
- Do not assume `.md` means transcription: it may be a provenance note or README.
- Do not depend on administrator-only enumeration or bypass permissions.
- Keep deployment-specific recipes and live credentials outside shipped fixtures.
- Do not add an instance-profile framework until multiple real uses justify one.

The initial API covers retrieval and preparation of research data. A package
described as a DSpace client need not wrap every administrative endpoint in v0.1.

## Proposed user interface

The initial interface below is implemented; later sections also contain proposals
for subsequent work.

```r
library(dspacer)
library(dplyr)

con <- ds_connect("https://repository.example.org/server/api")

# Optional: public repositories can be read anonymously.
ds_login(
  con,
  user = Sys.getenv("DSPACE_USER"),
  password = Sys.getenv("DSPACE_PASSWORD")
)

collections <- ds_get_collections(con)

# Choose the collection after inspecting the returned table.
items <- ds_get_items(con, scope = collections$collection_uuid[[1]])
metadata <- ds_get_metadata(items)
files <- ds_get_files(con, items)

# Illustrative selection only: inspect the inventory and choose the desired files.
# Filename-based conventions belong in user code, not in the client.
selected_files <- files |>
  filter(
    bundle_name == "ORIGINAL",
    name %in% c("transcription.md", "translation.md")
  )

texts <- ds_get_texts(con, files = selected_files)

dataset <- list(items = items, metadata = metadata, files = files, texts = texts)
saveRDS(dataset, "repository_dataset.rds")
```

Initial exported functions:

Use the `ds_` prefix and verb-led names consistently throughout the public API.

- `ds_connect(base_url)`: validate the API root and create an anonymous,
  opaque connection with server information and isolated session state.
- `ds_login(con, user, password)`: authenticate that connection. Return it
  invisibly; reject missing credentials rather than sending an empty login.
- `ds_disconnect(con)`: end the session and remove local authentication state.
- `ds_get_collections(con)`: list collections exposed to the current account.
- `ds_get_items(con, scope = NULL, query = NULL, ids = NULL)`: retrieve items.
  `scope` accepts a community or collection UUID. Explicit `ids` are an alternative
  to search; reject combinations of `ids` with `scope` or `query`. No arguments
  means all visible, archived, non-withdrawn search results, not all owned items.
- `ds_get_metadata(x)`: convert the retained metadata from an item, collection or
  file table to a lossless long table. This makes no network requests.
- `ds_get_files(con, items, bundles = "ORIGINAL")`: inventory files belonging to
  the supplied items. `bundles = NULL` explicitly requests all visible bundles.
- `ds_download(con, files, directory)`: download selected bytes with integrity
  checks and return a download manifest. This underlies text retrieval too.
- `ds_get_texts(con, files)`: download explicitly selected Markdown/plaintext
  files and return both source text and analysis plaintext. Reject unsupported
  formats; do not extract PDF text or fall back to OCR.

Start without a single function that automatically downloads an entire corpus.
The separate item, inventory and selection steps make scope, transfer cost and
text selection inspectable. A convenience wrapper can follow real usage.

## Data model

Use ordinary tibbles with stable, documented column types. Retain raw metadata
in list columns rather than forcing every repository into a fixed crosswalk.
Empty results must return the same typed columns as nonempty results.

### Items and collections

- Items: `repository`, `item_uuid`, `handle`, `name`, `last_modified`,
  `in_archive`, `withdrawn`, `metadata` and `retrieved_at`.
- Collections: `repository`, `collection_uuid`, `handle`, `name`, `metadata`
  and `retrieved_at`.
- `repository` is the normalized REST base URL. Combine it with an object UUID
  when joining exports from different installations.
- Handles may be absent. Names may repeat. Neither is the primary key.
- `metadata` retains the complete metadata map, including unrecognised keys
  and value properties. Collection relationships must not multiply item rows.
- Do not fabricate public item URLs from assumed frontend routes.

### Metadata

One row per metadata value:

- `repository`, `object_uuid`, `object_type`, `field`, `value`.
- `language`, `authority`, `confidence`, `place`, and `value_index`.
- Retain unknown value properties in an `extra` list column.

`value_index` records the received array position; `place` retains the server's
value. Do not silently sort, deduplicate, collapse repeated values or select only
the first. Distinguish missing values from empty strings.

Dates remain the original strings. A field may contain only a year, uncertain
dates, or a non-Gregorian calendar. Typed date conversion is an explicit analysis
step, never an automatic consequence of a field name.

A later wide-table helper should use list columns by default and require an
explicit rule for collapsing multivalued fields. No silent first-value shortcut.

### File inventory

One row per item–bundle–bitstream association:

- `repository`, `item_uuid`, `bundle_uuid`, `bundle_name`, `bitstream_uuid`.
- `name`, `mime_type`, `size_bytes`, `checksum_algorithm`, `checksum`.
- `is_primary`, `metadata`, `content_url`, `retrieved_at`.

The association matters: do not assume a bitstream occurs in only one bundle.
Use `NA` if a MIME type or primary selection cannot be determined. Preserve file
metadata separately from item metadata; they describe different objects.
Content URLs must be canonical API links, never signed download URLs or tokens.

### Texts

One row per selected file association:

- The repository, item, bundle and bitstream identifiers.
- `name`, `mime_type`, `source_text`, `text`.
- `sha256`, `retrieved_at`, `conversion`, `conversion_version`.

`source_text` is decoded UTF-8 Markdown or plaintext. `text` is a derived
plaintext representation. Original bytes remain available through
`ds_download()`; text decoding is not a byte-preserving archival format.

Do not manufacture a missing text row as `""`. An absent file is an inventory
fact, a forbidden download is an error, and a successfully downloaded empty file
is genuinely empty. Keep these cases distinguishable.

Do not copy an item's language onto every file. File-level language metadata,
where present, remains available through `ds_get_metadata(files)`. Filename
language suffixes may be interpreted by an explicitly chosen user recipe.

## Markdown conversion and optional segmentation

- Use a Markdown parser, not regular expressions, to remove markup.
- Proposed renderer: `commonmark`'s `markdown_text()`, with `width = 0` to avoid
  inserting analysis-dependent line wrapping. Freeze and document other options.
- Keep Unicode characters, Arabic diacritics and paragraph boundaries. No
  stemming, transliteration, stop-word removal or Unicode normalization.
- Define fixtures for headings, links, images, code, lists, entities, raw HTML,
  tables and footnotes before promising their exact plaintext representation.
- Do not fetch linked images, execute HTML, or follow links found in documents.
- Validate UTF-8 strictly initially. Report a decoding error rather than silently
  replacing characters. Other encodings require an explicit future option.

Page and paragraph segmentation should be pure, optional helpers, added after
basic retrieval works. Arbitrary Markdown need not contain pages.

A repository recipe can split markers such as `## PDF page 1`, validate the
sequence, retain `pdf_page`, and remove only those marker lines from analysis
text. Those are PDF-page indices, not printed page numbers. This convention must
not be imposed on other repositories or guessed from arbitrary headings.

## REST and authentication

- Default item discovery uses `/discover/search/objects` with item type and
  optional scope/query. `/core/items` is administrator-only according to the
  REST contract and cannot be the normal retrieval path.
- Follow each result's item link as necessary for full, current metadata.
  Deduplicate by repository plus item UUID, not by title or PDF filename.
- Explicit UUID retrieval uses the item resource directly and is independent
  of search-index freshness.
- Item listing is a search result, not a database audit or an atomic snapshot.
  Detect duplicate UUIDs and changing page totals; flag drift rather than claim
  guaranteed completeness while a repository is changing.
- Page through collections, search results, bundles and bitstreams, including
  embedded collections that are themselves paginated. Do not assume one HAL
  response layout: live 10.1 uses `searchResult`, whereas documentation examples
  also show `searchResults`. Support only layouts covered by fixtures.
- Constrain followed API links and redirects to the configured API origin and
  permitted path. Do not leak authentication to arbitrary content hosts.
  External object storage needs a separately tested, credential-safe design.
- Require HTTPS for credentials; permit HTTP only through an explicit
  development/loopback opt-in. Never disable TLS verification by default.

Authentication needs a cookie session, the current CSRF token and the bearer
token. Watch for CSRF updates on every response; login is form-encoded and needs
the matching cookie and header. A connection is not simply an API URL plus a JWT.

Keep passwords only for the duration of login. Retain bearer/session state only
in the live connection; do not include it in returned data, caches, fixtures or
diagnostics. If a temporary cookie file is used, make it private and clean it up.
Redact authentication bodies and headers, and print only safe connection details.
Document that connection objects must not be serialized with research datasets.

Attempt token refresh only when appropriate and at most once per failed request.
Do not repeatedly log in for a file-level 401/403 or misrepresent an edge/proxy
error as a repository permissions decision.

## Download integrity, failures and reproducibility

- Serial downloads first, with bounded timeouts and bounded retries for
  idempotent reads affected by transient failures or rate limits.
- Check returned bytes against the advertised size and supported repository
  checksum; compute local SHA-256 independently. A mismatch is an error.
- Use UUID-based local storage paths and preserve names in the manifest.
  Never trust a remote filename as a path or overwrite a different file.
- Write to a temporary file and rename only after successful verification.
- Default to stopping on denied access, checksum failures or decoding errors.
  Never quietly turn an incomplete export into a successful one.
- Report progress, including files/items completed, with useful log messages
  when running noninteractively. No progress bar that disappears into redirects.
- No persistent cache by default: restricted downloads are sensitive copies.
  Explicit local snapshots may be saved by the user, with access implications
  documented. Refresh must reauthorize; local files are not current permission
  evidence.
- Record repository URL/version, package version, selection parameters,
  UTC start/end timestamps, selected UUIDs and downloaded checksums in an export
  manifest. Never record passwords, tokens or full authenticated requests.
- A snapshot is bounded by those timestamps, not a transactionally consistent
  view of a live repository.

## Implementation approach

Keep a small conventional R package: `R/`, `man/`, `tests/testthat/`, and
`vignettes/`. Separate HTTP/session handling, pagination, object normalization,
downloads and text conversion internally without building a general framework.

Candidate runtime dependencies:

- `httr2`: HTTP, cookie handling, request construction and bounded retry support.
- `tibble` and `dplyr`: typed tabular outputs and assembly.
- `commonmark`: Markdown-to-plaintext rendering.
- `digest`: byte checksums.
- `cli` and `rlang`: progress, diagnostics and structured errors.

Use native pipes and tidyverse style. Keep package calls unprefixed, with explicit
namespace imports generated from documentation. Avoid pulling in the entire
tidyverse, a database, Java, Pandoc, Python, or any OCR/LLM service.

Development dependencies can include `testthat`, `roxygen2` and an HTTP mocking
tool. Pick the mocking tool after a small authentication test, not by habit.

## Verification and release stages

1. **Offline package skeleton and data contracts.** Agree the proposed API;
   implement normalization and Markdown conversion against synthetic fixtures.
   Preserve repeated/custom metadata, unknown properties, Unicode, empty tables
   and multiple files per item.
2. **Read-only HTTP implementation.** Cover anonymous and password sessions,
   rotating CSRF tokens/cookies, expiration, denied access, malicious links,
   HAL variants, all pagination levels, interrupted downloads and bad checksums.
   Assert that content-changing HTTP operations are never issued.
3. **Opt-in live acceptance tests.** Read a small, explicitly selected set from
   a private deployment. Test both an ordinary reader and an administrator;
   verify non-admin item discovery and download-byte equality. Do not run a
   whole-repository download as a test or store real restricted text in fixtures.
4. **Portability and documentation.** Test against at least one independent
   repository before making general compatibility claims. Document tested
   DSpace versions and authentication methods, data shapes and failure behaviour.
   Add recipes for metadata widening and user-supplied Markdown selection.
5. **GitHub preparation.** Add README, installation instructions, changelog,
   contribution guidance and CI with `R CMD check`. Credentials are absent from
   CI; live tests are opt-in. Authorship and MIT licensing now follow daiR.
   Add repository URLs when the GitHub repository exists; publication still
   requires approval.

Start offline. SSO, OIDC, Shibboleth, API tokens supplied by the caller and
custom object-storage delivery need separate evaluation; password authentication
must not be described as universal DSpace authentication.

## Evidence and remaining decisions

Checked on 2026-11-14:

- A live private deployment identifies itself as DSpace 10.1.
- Its authenticated search, collection listing, item metadata, bundle inventory
  and Markdown content endpoints were read successfully.
- Two selected Markdown files passed advertised size/checksum checks, decoded
  as UTF-8 and each contained 25 explicit PDF-page markers.
- The live search response uses the singular `searchResult` HAL relation.
- Installed `commonmark` exposes `markdown_text()`; a small Arabic/Markdown
  example retained Arabic characters and removed heading/emphasis/link markup.

These are feasibility checks, not a tested package or cross-version guarantee.
Ordinary-reader authentication, public-edge authentication from R, arbitrary
Markdown conversion cases and independent repositories remain untested.

Decisions and remaining work:

- Local package name: `dspacer`. The eventual GitHub repository has not been
  created.
- The initial implementation is read-only, apart from authentication.
- Licence and authorship follow daiR: MIT, copyright 2026 Thomas Hegghammer;
  Thomas Hegghammer is author and maintainer, using `code@hegghammer.net` and
  the same ORCID as daiR.

No repository-specific metadata fields or filename rules need to be settled to
implement the generic client.

## Technical references

- [DSpace REST contract](https://github.com/DSpace/RestContract)
- [Items](https://github.com/DSpace/RestContract/blob/main/items.md)
- [Search](https://github.com/DSpace/RestContract/blob/main/search-endpoint.md)
- [Bundles](https://github.com/DSpace/RestContract/blob/main/bundles.md)
- [Bitstreams](https://github.com/DSpace/RestContract/blob/main/bitstreams.md)
- [Authentication](https://github.com/DSpace/RestContract/blob/main/authentication.md)
- [CSRF](https://github.com/DSpace/RestContract/blob/main/csrf-tokens.md)
- [httr2](https://httr2.r-lib.org/)
- [commonmark](https://docs.ropensci.org/commonmark/)
