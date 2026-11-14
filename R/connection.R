#' Connect to a DSpace REST API
#'
#' Creates an anonymous connection and checks the API root. Connections contain
#' sensitive session state: do not serialize them or include them in datasets.
#'
#' @param base_url REST API root, for example
#'   `"https://repository.example.org/server/api"`. No default is supplied.
#' @param allow_insecure Explicitly allow HTTP, for development or loopback use.
#' @param timeout Per-request timeout in seconds.
#' @param quiet Suppress progress messages.
#' @return An opaque `dspacer_connection`, printed without authentication details.
#' @export
ds_connect <- function(base_url, allow_insecure = FALSE, timeout = 60, quiet = FALSE) {
  .ds_string(base_url, "base_url")
  parts <- tryCatch(url_parse(base_url), error = function(e) NULL)
  if (is.null(parts) || !parts$scheme %in% c("http", "https") ||
      is.null(parts$hostname) || !nzchar(parts$hostname) ||
      !is.null(parts$username) || !is.null(parts$password) ||
      length(parts$query) || !is.null(parts$fragment)) {
    .ds_abort("Supply an HTTP(S) API root without credentials, query or fragment.", "input_error")
  }
  if (!isTRUE(allow_insecure) && parts$scheme != "https") {
    .ds_abort("HTTP requires `allow_insecure = TRUE`; prefer HTTPS.", "input_error")
  }
  if (!is.numeric(timeout) || length(timeout) != 1L || is.na(timeout) ||
      !is.finite(timeout) || timeout <= 0) {
    .ds_abort("`timeout` must be a positive finite number.", "input_error")
  }
  con <- new.env(parent = emptyenv())
  class(con) <- "dspacer_connection"
  con$base_url <- sub("/+$", "", url_build(parts))
  con$version <- NA_character_
  con$root <- list()
  con$token <- NULL
  con$csrf <- NULL
  con$timeout <- timeout
  con$quiet <- isTRUE(quiet)
  con$closed <- FALSE
  con$cookie_path <- tempfile("dspacer_cookies_")
  if (!file.create(con$cookie_path)) .ds_abort("Could not create a private cookie file.")
  Sys.chmod(con$cookie_path, mode = "0600")
  reg.finalizer(con, function(e) unlink(e$cookie_path), onexit = TRUE)
  ok <- FALSE
  on.exit(if (!ok) unlink(con$cookie_path), add = TRUE)
  root <- .ds_json(con, con$base_url)
  if (!is.list(root) || is.null(root$dspaceVersion) || is.null(root$`_links`)) {
    .ds_abort("The API root does not identify a modern DSpace REST API.", "protocol_error")
  }
  con$version <- root$dspaceVersion
  con$root <- root
  ok <- TRUE
  con
}

#' Authenticate a DSpace connection
#'
#' Passwords are used for login only and are not retained in the connection.
#' This implements DSpace password authentication, not browser SSO.
#'
#' @param con A connection from [ds_connect()].
#' @param user Login username or email.
#' @param password Password. Obtain it from a prompt or environment variable,
#'   not a committed script.
#' @return The connection, invisibly.
#' @export
ds_login <- function(con, user, password) {
  .ds_check_connection(con)
  .ds_string(user, "user")
  .ds_string(password, "password")
  con$token <- NULL
  .ds_ensure_csrf(con)
  response <- .ds_request(
    con, .ds_auth_url(con, "login"), method = "POST",
    form = list(user = user, password = password), refresh = FALSE
  )
  token <- response$headers[["authorization"]]
  if (is.null(token) || !grepl("^Bearer .+", token)) {
    .ds_abort("Login did not return a bearer token.", "authentication_error")
  }
  con$token <- token
  status <- tryCatch(.ds_json(con, .ds_auth_url(con, "status")), error = function(e) NULL)
  if (!isTRUE(status$authenticated)) {
    con$token <- NULL
    .ds_abort("The server did not confirm authentication.", "authentication_error")
  }
  invisible(con)
}

#' Disconnect and clear local authentication state
#'
#' Attempts server logout when authenticated. Local cookies and tokens are
#' cleared even if server logout fails. A disconnected connection cannot be reused.
#'
#' @param con A connection from [ds_connect()].
#' @return `NULL`, invisibly.
#' @export
ds_disconnect <- function(con) {
  .ds_check_connection(con)
  on.exit({
    con$token <- NULL
    con$csrf <- NULL
    con$closed <- TRUE
    unlink(con$cookie_path)
  }, add = TRUE)
  if (!is.null(con$token)) {
    tryCatch({
      .ds_ensure_csrf(con)
      .ds_request(con, .ds_auth_url(con, "logout"), method = "POST", refresh = FALSE)
    }, error = function(e) {
      cli_warn("Server logout failed; local authentication state has been cleared.")
    })
  }
  invisible(NULL)
}

#' @export
print.dspacer_connection <- function(x, ...) {
  cat("<dspacer_connection>\n")
  cat("  API:", x$base_url, "\n")
  cat("  Version:", x$version, "\n")
  cat("  State:", if (x$closed) "closed" else if (is.null(x$token)) "anonymous" else "authenticated", "\n")
  invisible(x)
}

.ds_check_connection <- function(con) {
  if (!inherits(con, "dspacer_connection") || !is.environment(con) || isTRUE(con$closed)) {
    .ds_abort("Expected an open connection from `ds_connect()`.", "input_error")
  }
}

.ds_auth_url <- function(con, action) paste0(con$base_url, "/authn/", action)

.ds_ensure_csrf <- function(con) {
  if (is.null(con$csrf)) .ds_request(con, paste0(con$base_url, "/security/csrf"), refresh = FALSE)
  if (is.null(con$csrf)) .ds_abort("The server did not provide a CSRF token.", "authentication_error")
}

.ds_endpoint <- function(con, relation, fallback) {
  .ds_value(.ds_link(con$root, relation), paste0(con$base_url, fallback))
}
