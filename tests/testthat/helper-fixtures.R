toJSON <- getExportedValue("jsonlite", "toJSON")

fixture_base <- "https://repository.example.org/server/api"
fixture_ids <- sprintf("%08d-0000-0000-0000-000000000000", 1:6)

fixture_response <- function(object = list(), status = 200L, body = NULL, headers = list()) {
  if (is.null(body)) body <- charToRaw(toJSON(object, auto_unbox = TRUE, null = "null", force = TRUE))
  list(status = status, headers = headers, body = body)
}

fixture_connection <- function() {
  con <- new.env(parent = emptyenv())
  class(con) <- "dspacer_connection"
  con$base_url <- fixture_base
  con$version <- "DSpace 10.1"
  con$root <- list()
  con$token <- NULL
  con$csrf <- NULL
  con$timeout <- 5
  con$quiet <- TRUE
  con$closed <- FALSE
  con$cookie_path <- tempfile()
  file.create(con$cookie_path)
  reg.finalizer(con, function(e) unlink(e$cookie_path), onexit = TRUE)
  con
}

fixture_page <- function(objects, relation, number = 0L, total = length(objects), pages = 1L, next_url = NULL) {
  out <- list(
    `_embedded` = setNames(list(objects), relation),
    page = list(number = number, size = length(objects), totalElements = total, totalPages = pages)
  )
  if (!is.null(next_url)) out$`_links` <- list(`next` = list(href = next_url))
  out
}

fixture_item <- function(id = fixture_ids[[1]], metadata = list()) {
  list(uuid = id, name = "A document", handle = NULL, metadata = metadata,
       inArchive = TRUE, withdrawn = FALSE, lastModified = "2026-01-01T00:00:00Z")
}

fixture_file <- function(bytes = charToRaw("## Heading\n\nSome **text**.\n")) {
  out <- .ds_files_table()
  out[1L, ] <- list(
    fixture_base, fixture_ids[[1]], fixture_ids[[2]], "ORIGINAL",
    fixture_ids[[3]], "document.md", "text/markdown", as.double(length(bytes)),
    "MD5", digest(bytes, algo = "md5", serialize = FALSE), TRUE, list(list()),
    paste0(fixture_base, "/core/bitstreams/", fixture_ids[[3]], "/content"), .ds_now()
  )
  out
}
