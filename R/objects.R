.ds_items_table <- function() {
  tibble(repository = character(), item_uuid = character(), handle = character(),
         name = character(), last_modified = character(), in_archive = logical(),
         withdrawn = logical(), metadata = list(), retrieved_at = character())
}

.ds_collections_table <- function() {
  tibble(repository = character(), collection_uuid = character(), handle = character(),
         name = character(), metadata = list(), retrieved_at = character())
}

.ds_metadata_map <- function(x) {
  if (is.null(x)) return(list())
  if (!is.list(x) || (length(x) && is.null(names(x)))) {
    .ds_abort("Expected a named metadata map.", "protocol_error")
  }
  x
}

.ds_item_row <- function(con, item) {
  tibble(
    repository = con$base_url, item_uuid = .ds_uuid(item$uuid),
    handle = .ds_value(item$handle), name = .ds_value(item$name),
    last_modified = .ds_value(item$lastModified),
    in_archive = .ds_value(item$inArchive, NA), withdrawn = .ds_value(item$withdrawn, NA),
    metadata = list(.ds_metadata_map(item$metadata)), retrieved_at = .ds_now()
  )
}

#' Retrieve collections visible to the current account
#'
#' @param con A connection from [ds_connect()].
#' @return A tibble with `repository`, `collection_uuid`, `handle`, `name`,
#'   `metadata` (a lossless list column) and `retrieved_at`. Its `dspacer`
#'   attribute records repository/package versions, selection and retrieval bounds.
#' @export
ds_get_collections <- function(con) {
  .ds_check_connection(con)
  started <- .ds_now()
  objects <- .ds_pages(con, .ds_endpoint(con, "collections", "/core/collections"), "collections")
  rows <- lapply(objects, function(x) {
    tibble(repository = con$base_url, collection_uuid = .ds_uuid(x$uuid),
           handle = .ds_value(x$handle), name = .ds_value(x$name),
           metadata = list(.ds_metadata_map(x$metadata)), retrieved_at = .ds_now())
  })
  out <- .ds_bind(rows, .ds_collections_table())
  if (anyDuplicated(out$collection_uuid)) .ds_abort("Duplicate collection UUIDs in paginated results.", "pagination_error")
  .ds_finish(out, con, list(resource = "collections"), started)
}

#' Retrieve DSpace items
#'
#' Uses permission-aware Discovery search, not administrator-only item listing.
#' Search results are not an atomic repository snapshot and depend on the
#' repository's search index. Explicit UUID retrieval does not use that index.
#'
#' @details
#' Uses Discovery rather than the administrator-only `/core/items` list endpoint.
#' Detected count changes or duplicate UUIDs stop retrieval; retry after the
#' repository is stable. Search retrieval is not a database audit or a guarantee
#' of a transactionally consistent snapshot.
#'
#' @param con A connection from [ds_connect()].
#' @param scope Optional collection or community UUID.
#' @param query Optional Discovery query, interpreted by the repository.
#' @param ids Optional character vector of item UUIDs, instead of `scope`/`query`.
#'   Explicit UUIDs may retrieve non-archived items if the account can read them.
#' @return An item tibble with `repository`, `item_uuid`, `handle`, `name`,
#'   `last_modified`, `in_archive`, `withdrawn`, `metadata` (a lossless list column)
#'   and `retrieved_at`. Search excludes withdrawn and non-archived items. No
#'   arguments retrieves all visible search results, not items owned by the
#'   account. Its `dspacer` attribute records repository/package versions, the
#'   selection and retrieval start/end times. Use repository URL and item UUID
#'   as join keys, not titles or handles.
#' @export
ds_get_items <- function(con, scope = NULL, query = NULL, ids = NULL) {
  .ds_check_connection(con)
  if (!is.null(ids) && (!is.null(scope) || !is.null(query))) {
    .ds_abort("Supply `ids` or `scope`/`query`, not both.", "input_error")
  }
  started <- .ds_now()
  selection <- list(scope = scope, query = query, ids = ids)
  if (!is.null(ids)) {
    if (!is.character(ids) || anyNA(ids)) .ds_abort("`ids` must be a character vector of UUIDs.", "input_error")
    ids <- unique(vapply(ids, .ds_uuid, character(1)))
    urls <- paste0(.ds_endpoint(con, "items", "/core/items"), "/", ids)
    if (!length(ids)) urls <- character()
  } else {
    params <- list(dsoType = "item")
    if (!is.null(scope)) params$scope <- .ds_uuid(scope)
    if (!is.null(query)) params$query <- .ds_string(query, "query")
    hits <- .ds_pages(con, paste0(con$base_url, "/discover/search/objects"),
                      "objects", query = params, search = TRUE)
    urls <- vapply(hits, function(hit) {
      link <- .ds_link(hit, "indexableObject")
      if (is.null(link)) .ds_abort("A search hit is missing its item link.", "protocol_error")
      link
    }, character(1))
  }
  rows <- vector("list", length(urls))
  for (i in seq_along(urls)) {
    item <- .ds_json(con, urls[[i]])
    rows[[i]] <- .ds_item_row(con, item)
    .ds_progress(con, "Items", i, length(urls))
  }
  out <- .ds_bind(rows, .ds_items_table())
  if (anyDuplicated(out$item_uuid)) {
    .ds_abort("Duplicate item UUIDs in results; the search may have changed.", "pagination_error")
  }
  if (is.null(ids)) out <- out[which(out$in_archive & !out$withdrawn), , drop = FALSE]
  .ds_finish(out, con, selection, started)
}

.ds_metadata_table <- function() {
  tibble(repository = character(), object_uuid = character(), object_type = character(),
         field = character(), value = character(), language = character(),
         authority = character(), confidence = integer(), place = integer(),
         value_index = integer(), extra = list())
}

#' Extract metadata as a wide or long table
#'
#' Returns one row per object with metadata fields as columns by default.
#' This is a local transformation, not a network request. Date values remain
#' strings and repeated values are preserved.
#'
#' @details
#' In wide format, metadata keys such as `dc.title` become column names, in
#' first-seen order. A field is a character column if it has at most one value
#' per object. If any object has multiple values, that field is a list-column of
#' character vectors for every row. Values retain their received order, including
#' duplicates; they are not collapsed into delimited strings.
#'
#' Missing single values are `NA_character_`; absent values in list-columns are
#' `character()`. Empty strings remain empty. Objects with no metadata still have
#' a row. Repeated file/bundle associations produce one row per object; conflicting
#' metadata for the same object is an error.
#'
#' Wide format contains metadata values only. Use `format = "long"` for
#' per-value language, authority, confidence, server ordering and unknown
#' properties. The original metadata map also remains in `x$metadata`.
#' Years, uncertain dates and non-Gregorian dates are not silently converted.
#'
#' Item and file metadata describe different objects. For file tables,
#' `object_uuid` identifies the bitstream, not the parent item.
#'
#' @param x An item, collection or file tibble returned by dspacer.
#' @param format Output layout: `"wide"` (default) or `"long"`.
#' @return A tibble retaining the input's `dspacer` attribute.
#'   * Wide: `repository`, `object_uuid`, `object_type`, followed by one column per
#'     observed metadata field. Objects retain their first appearance order.
#'   * Long: one row per metadata value, with `repository`, `object_uuid`,
#'     `object_type`, `field`, `value`, `language`, `authority`, `confidence`,
#'     `place`, `value_index` (one-based received position), and `extra`.
#' @export
ds_get_metadata <- function(x, format = c("wide", "long")) {
  format <- match.arg(format)
  .ds_require_columns(x, c("repository", "metadata"))
  types <- c(bitstream_uuid = "bitstream", collection_uuid = "collection", item_uuid = "item")
  id_column <- intersect(names(types), names(x))[1]
  if (is.na(id_column)) .ds_abort("Expected item, collection or bitstream identifiers.", "input_error")
  if (format == "wide") {
    return(.ds_metadata_wide(x, id_column, unname(types[[id_column]])))
  }
  rows <- list()
  for (i in seq_len(nrow(x))) {
    metadata <- .ds_metadata_map(x$metadata[[i]])
    for (field in names(metadata)) {
      values <- metadata[[field]]
      if (!is.list(values)) .ds_abort("Expected metadata value arrays.", "protocol_error")
      for (j in seq_along(values)) {
        entry <- values[[j]]
        if (!is.list(entry)) .ds_abort("Expected metadata value objects.", "protocol_error")
        known <- c("value", "language", "authority", "confidence", "place")
        rows[[length(rows) + 1L]] <- tibble(
          repository = x$repository[[i]], object_uuid = x[[id_column]][[i]],
          object_type = unname(types[[id_column]]), field = field,
          value = .ds_value(entry$value), language = .ds_value(entry$language),
          authority = .ds_value(entry$authority),
          confidence = as.integer(.ds_value(entry$confidence, NA_integer_)),
          place = as.integer(.ds_value(entry$place, NA_integer_)), value_index = j,
          extra = list(entry[setdiff(names(entry), known)])
        )
      }
    }
  }
  out <- .ds_bind(rows, .ds_metadata_table())
  attr(out, "dspacer") <- attr(x, "dspacer")
  out
}

.ds_metadata_wide <- function(x, id_column, object_type) {
  out <- tibble(repository = x$repository, object_uuid = x[[id_column]],
                object_type = rep(object_type, nrow(x)))
  metadata <- lapply(x$metadata, .ds_metadata_map)
  duplicates <- duplicated(out)
  for (i in which(duplicates)) {
    first <- which(out$repository == out$repository[[i]] &
                   out$object_uuid == out$object_uuid[[i]])[[1]]
    if (!identical(metadata[[i]], metadata[[first]])) {
      .ds_abort("Conflicting metadata for the same object; use a single snapshot.", "input_error")
    }
  }
  out <- out[!duplicates, , drop = FALSE]
  metadata <- metadata[!duplicates]
  fields <- unique(unlist(lapply(metadata, names), use.names = FALSE))
  if (any(fields %in% names(out))) {
    .ds_abort("A metadata field conflicts with a reserved identifier column.", "input_error")
  }
  for (field in fields) {
    values <- lapply(metadata, function(map) {
      entries <- map[[field]]
      if (!is.null(entries) && !is.list(entries)) {
        .ds_abort("Expected metadata value arrays.", "protocol_error")
      }
      vapply(entries, function(entry) {
        if (!is.list(entry)) .ds_abort("Expected metadata value objects.", "protocol_error")
        .ds_value(entry$value)
      }, character(1), USE.NAMES = FALSE)
    })
    if (any(lengths(values) > 1L)) {
      out[[field]] <- values
    } else {
      out[[field]] <- vapply(values, function(value) {
        if (length(value)) value[[1]] else NA_character_
      }, character(1))
    }
  }
  attr(out, "dspacer") <- attr(x, "dspacer")
  out
}
