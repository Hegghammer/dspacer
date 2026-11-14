.ds_files_table <- function() {
  tibble(repository = character(), item_uuid = character(), bundle_uuid = character(),
         bundle_name = character(), bitstream_uuid = character(), name = character(),
         mime_type = character(), size_bytes = double(), checksum_algorithm = character(),
         checksum = character(), is_primary = logical(), metadata = list(),
         content_url = character(), retrieved_at = character())
}

#' Inventory files attached to items
#'
#' Inventories files without downloading their content. Files are identified by
#' UUID and kept within their item and bundle associations, never matched across
#' items by filename.
#'
#' @param con A connection from [ds_connect()].
#' @param items An item tibble from [ds_get_items()].
#' @param bundles Bundle names to include. Defaults to `"ORIGINAL"`; `NULL`
#'   includes all visible bundles. This does not bypass bundle access controls.
#' @return One row per item--bundle--bitstream association. Includes file
#'   metadata, MIME type, checksum, size and primary-file status.
#' @export
ds_get_files <- function(con, items, bundles = "ORIGINAL") {
  .ds_check_connection(con)
  .ds_require_columns(items, c("repository", "item_uuid"))
  .ds_check_repository(con, items)
  if (!is.null(bundles) && (!is.character(bundles) || anyNA(bundles))) {
    .ds_abort("`bundles` must be a character vector or NULL.", "input_error")
  }
  started <- .ds_now()
  rows <- list()
  ids <- unique(items$item_uuid)
  for (i in seq_along(ids)) {
    id <- .ds_uuid(ids[[i]])
    item_url <- paste0(.ds_endpoint(con, "items", "/core/items"), "/", id)
    item_bundles <- .ds_pages(con, paste0(item_url, "/bundles"), "bundles")
    for (bundle in item_bundles) {
      if (!is.null(bundles) && !bundle$name %in% bundles) next
      primary_link <- .ds_link(bundle, "primaryBitstream")
      primary <- if (!is.null(primary_link)) .ds_json(con, primary_link) else NULL
      bitstream_link <- .ds_link(bundle, "bitstreams")
      if (is.null(bitstream_link)) .ds_abort("Missing bundle bitstream link.", "protocol_error")
      bitstreams <- .ds_pages(con, bitstream_link, "bitstreams")
      for (file in bitstreams) {
        format <- file[["_embedded"]][["format"]]
        format_link <- .ds_link(file, "format")
        if (is.null(format) && !is.null(format_link)) format <- .ds_json(con, format_link)
        content_link <- .ds_link(file, "content")
        if (is.null(content_link)) .ds_abort("Missing bitstream content link.", "protocol_error")
        rows[[length(rows) + 1L]] <- tibble(
          repository = con$base_url, item_uuid = id,
          bundle_uuid = .ds_uuid(bundle$uuid), bundle_name = bundle$name,
          bitstream_uuid = .ds_uuid(file$uuid), name = .ds_value(file$name),
          mime_type = .ds_value(format$mimetype),
          size_bytes = as.double(.ds_value(file$sizeBytes, NA_real_)),
          checksum_algorithm = .ds_value(file$checkSum$checkSumAlgorithm),
          checksum = .ds_value(file$checkSum$value),
          is_primary = if (is.null(primary_link)) NA else identical(file$uuid, primary$uuid),
          metadata = list(.ds_metadata_map(file$metadata)),
          content_url = .ds_safe_url(con, content_link), retrieved_at = .ds_now()
        )
      }
    }
    .ds_progress(con, "File inventories", i, length(ids))
  }
  out <- .ds_bind(rows, .ds_files_table())
  key <- out[c("item_uuid", "bundle_uuid", "bitstream_uuid")]
  if (anyDuplicated(key)) .ds_abort("Duplicate file associations in results.", "pagination_error")
  .ds_finish(out, con, list(item_uuids = ids, bundles = bundles), started)
}

.ds_check_files <- function(con, files) {
  .ds_check_connection(con)
  .ds_require_columns(files, names(.ds_files_table()))
  .ds_check_repository(con, files)
  invisible(lapply(files$bitstream_uuid, .ds_uuid))
}

.ds_verify_bytes <- function(bytes, file) {
  if (is.na(file$size_bytes) || length(bytes) != file$size_bytes) {
    .ds_abort("Downloaded size differs from the file inventory; refresh the inventory.", "integrity_error")
  }
  algorithm <- tolower(gsub("-", "", file$checksum_algorithm, fixed = TRUE))
  if (is.na(algorithm) || !algorithm %in% c("md5", "sha1", "sha256", "sha512") ||
      is.na(file$checksum)) {
    .ds_abort("The file has a missing or unsupported repository checksum.", "integrity_error")
  }
  actual <- digest(bytes, algo = algorithm, serialize = FALSE)
  if (!identical(tolower(file$checksum), actual)) {
    .ds_abort("Downloaded checksum differs from the file inventory; refresh the inventory.", "integrity_error")
  }
  digest(bytes, algo = "sha256", serialize = FALSE)
}

.ds_read_file <- function(con, file) {
  response <- .ds_request(con, file$content_url)
  sha256 <- .ds_verify_bytes(response$body, file)
  list(bytes = response$body, sha256 = sha256, retrieved_at = .ds_now())
}

#' Download selected attachments with integrity checks
#'
#' Downloads are stored under UUID-based paths, not untrusted remote filenames.
#' Existing files are verified against a fresh authorized download and are never
#' silently overwritten. Content is currently buffered in memory, so this first
#' implementation is not intended for very large attachments.
#'
#' @param con A connection from [ds_connect()].
#' @param files Selected rows from [ds_get_files()].
#' @param directory Destination directory. Downloads may contain restricted data;
#'   secure this directory appropriately.
#' @return A manifest tibble retaining file associations and adding `local_path`,
#'   local `sha256` and `downloaded_at`. Its `dspacer` attribute records selection,
#'   versions and retrieval bounds without credentials.
#' @export
ds_download <- function(con, files, directory) {
  .ds_check_files(con, files)
  .ds_string(directory, "directory")
  directory <- path.expand(directory)
  if (!dir.exists(directory) && !dir.create(directory, recursive = TRUE, mode = "0700")) {
    .ds_abort("Could not create the download directory.", "file_error")
  }
  started <- .ds_now()
  out <- files
  out$local_path <- rep(NA_character_, nrow(out))
  out$sha256 <- rep(NA_character_, nrow(out))
  out$downloaded_at <- rep(NA_character_, nrow(out))
  # Repository hashing avoids collisions when several repositories share a destination.
  root <- file.path(directory, digest(con$base_url, algo = "sha256", serialize = FALSE))
  if (!dir.exists(root) && !dir.create(root, mode = "0700")) .ds_abort("Could not create repository directory.", "file_error")
  for (i in seq_len(nrow(files))) {
    result <- .ds_read_file(con, files[i, ])
    destination <- file.path(root, paste0(files$bitstream_uuid[[i]], ".bin"))
    if (file.exists(destination)) {
      existing <- digest(file = destination, algo = "sha256")
      if (!identical(existing, result$sha256)) .ds_abort("Refusing to overwrite a different local file.", "file_error")
    } else {
      temporary <- tempfile(".dspacer_", tmpdir = root)
      tryCatch({
        writeBin(result$bytes, temporary)
        Sys.chmod(temporary, mode = "0600")
        if (!file.rename(temporary, destination)) .ds_abort("Could not finalize the download.", "file_error")
      }, finally = unlink(temporary))
    }
    out$local_path[[i]] <- normalizePath(destination, mustWork = TRUE)
    out$sha256[[i]] <- result$sha256
    out$downloaded_at[[i]] <- result$retrieved_at
    .ds_progress(con, "Downloads", i, nrow(files))
  }
  .ds_finish(out, con, list(bitstream_uuids = files$bitstream_uuid), started)
}
