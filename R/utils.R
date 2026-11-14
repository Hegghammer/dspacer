.ds_abort <- function(message, subclass = "error", ...) {
  abort(message, class = paste0("dspacer_", subclass), ...)
}

.ds_string <- function(x, name) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) {
    .ds_abort(paste0("`", name, "` must be a nonempty string."), "input_error")
  }
  x
}

.ds_value <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0L) default else x
}

.ds_now <- function() {
  format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
}

.ds_uuid <- function(x) {
  .ds_string(x, "UUID")
  if (!grepl("^[[:xdigit:]]{8}-([[:xdigit:]]{4}-){3}[[:xdigit:]]{12}$", x)) {
    .ds_abort("Expected a DSpace object UUID.", "input_error")
  }
  x
}

.ds_bind <- function(rows, prototype) {
  if (!length(rows)) return(prototype)
  bind_rows(c(list(prototype), rows))
}

.ds_finish <- function(x, con, selection, started_at) {
  attr(x, "dspacer") <- list(
    repository = con$base_url,
    dspace_version = con$version,
    package_version = as.character(packageVersion("dspacer")),
    selection = selection,
    started_at = started_at,
    finished_at = .ds_now()
  )
  x
}

.ds_progress <- function(con, label, n, total) {
  if (!con$quiet) cli_inform("{label}: {n}/{total}")
}

.ds_require_columns <- function(x, columns) {
  if (!is.data.frame(x) || !all(columns %in% names(x))) {
    .ds_abort(paste0("Expected a table containing: ", paste(columns, collapse = ", "), "."), "input_error")
  }
}

.ds_check_repository <- function(con, x) {
  .ds_require_columns(x, "repository")
  if (anyNA(x$repository) || any(x$repository != con$base_url)) {
    .ds_abort("The table contains objects from a different repository.", "input_error")
  }
}

.ds_link <- function(object, relation) {
  link <- object[["_links"]][[relation]]
  if (is.null(link)) return(NULL)
  if (is.null(link$href) || isTRUE(link$templated)) {
    .ds_abort(paste0("Unsupported HAL link: ", relation, "."), "protocol_error")
  }
  link$href
}
