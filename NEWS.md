# dspacer 0.0.0.9000

- `ds_get_metadata()` now returns wide output by default, with one row per object
  and metadata fields as columns. Repeated fields use list-columns; the detailed
  per-value layout remains available with `format = "long"`.
- Initial local development package with the `ds_` verb-led interface.
- Anonymous and password-authenticated modern REST connections.
- Permission-aware item search, collection retrieval and lossless metadata.
- Bundle-aware file inventory, verified downloads and Markdown/plaintext tables.
- Offline tests, generated function documentation and package-check workflow.
- MIT licence and author/maintainer details follow daiR; live portability testing
  remains pending.
