.ds_origin <- function(parts) {
  port <- .ds_value(parts$port, if (parts$scheme == "https") "443" else "80")
  paste(tolower(parts$scheme), tolower(parts$hostname), port, sep = "|")
}

.ds_safe_url <- function(con, url, relative_to = con$base_url) {
  .ds_string(url, "URL")
  parts <- tryCatch(url_parse(url, base_url = relative_to), error = function(e) NULL)
  base <- url_parse(con$base_url)
  if (is.null(parts) || !is.null(parts$username) || !is.null(parts$password) ||
      !is.null(parts$fragment) || .ds_origin(parts) != .ds_origin(base)) {
    .ds_abort("Refusing a URL outside the configured API origin.", "unsafe_url")
  }
  path <- URLdecode(parts$path)
  prefix <- sub("/+$", "", base$path)
  if ((!identical(path, prefix) && !startsWith(path, paste0(prefix, "/"))) ||
      grepl("(^|/)\\.\\.?(/|$)|\\\\|%[[:xdigit:]]{2}", path)) {
    .ds_abort("Refusing a URL outside the configured API path.", "unsafe_url")
  }
  url_build(parts)
}

.ds_transport <- function(con, method, url, form = NULL) {
  req <- request(url) |>
    req_method(method) |>
    req_headers(Accept = "application/hal+json",
                `User-Agent` = paste0("dspacer/", packageVersion("dspacer"))) |>
    req_cookie_preserve(con$cookie_path) |>
    req_timeout(con$timeout) |>
    req_options(followlocation = FALSE) |>
    req_error(is_error = function(resp) FALSE)
  if (!is.null(con$token)) req <- req_headers_redacted(req, Authorization = con$token)
  if (method == "POST" && !is.null(con$csrf)) {
    req <- req_headers_redacted(req, `X-XSRF-TOKEN` = con$csrf)
  }
  if (length(form)) req <- req_body_form(req, !!!form)
  if (method == "GET") {
    req <- req_retry(
      req, max_tries = 3, max_seconds = con$timeout,
      retry_on_failure = TRUE,
      is_transient = function(resp) resp_status(resp) %in% c(429L, 502L, 503L, 504L)
    )
  }
  # Do not attach a parent error: request conditions may contain credentials.
  response <- tryCatch(req_perform(req), error = function(e) {
    .ds_abort("Network request failed; authentication details have been omitted.", "network_error")
  })
  headers <- as.list(resp_headers(response))
  names(headers) <- tolower(names(headers))
  body <- if (resp_has_body(response)) resp_body_raw(response) else raw()
  list(status = resp_status(response), headers = headers, body = body)
}

.ds_request <- function(con, url, method = "GET", form = NULL, refresh = TRUE) {
  .ds_check_connection(con)
  url <- .ds_safe_url(con, url)
  if (!method %in% c("GET", "POST") ||
      (method == "POST" && !url %in% c(.ds_auth_url(con, "login"), .ds_auth_url(con, "logout")))) {
    .ds_abort("Only reads and authentication operations are permitted.", "input_error")
  }
  for (redirect in 0:5) {
    response <- .ds_transport(con, method, url, form)
    csrf <- response$headers[["dspace-xsrf-token"]]
    if (!is.null(csrf)) con$csrf <- csrf
    if (!response$status %in% c(301L, 302L, 303L, 307L, 308L)) break
    if (method != "GET" || redirect == 5L || is.null(response$headers$location)) {
      .ds_abort("Unsupported authentication redirect or redirect loop.", "protocol_error")
    }
    url <- .ds_safe_url(con, response$headers$location, relative_to = url)
  }
  if (response$status == 401L && method == "GET" && refresh && !is.null(con$token)) {
    status <- .ds_json(con, .ds_auth_url(con, "status"), refresh = FALSE)
    if (identical(status$authenticated, FALSE) && .ds_try_refresh(con)) {
      return(.ds_request(con, url, refresh = FALSE))
    }
  }
  if (response$status < 200L || response$status >= 300L) {
    subclass <- if (response$status %in% c(401L, 403L)) "access_error" else "http_error"
    .ds_abort(paste0("DSpace request returned HTTP ", response$status, "."), subclass, status = response$status)
  }
  response
}

.ds_try_refresh <- function(con) {
  tryCatch({
    .ds_ensure_csrf(con)
    response <- .ds_request(con, .ds_auth_url(con, "login"), method = "POST", refresh = FALSE)
    token <- response$headers[["authorization"]]
    if (is.null(token) || !grepl("^Bearer .+", token)) return(FALSE)
    con$token <- token
    TRUE
  }, error = function(e) FALSE)
}

.ds_json <- function(con, url, query = list(), refresh = TRUE) {
  url <- .ds_safe_url(con, url)
  if (length(query)) url <- request(url) |> req_url_query(!!!query) |> (\(req) req$url)()
  response <- .ds_request(con, url, refresh = refresh)
  if (response$status == 204L) return(NULL)
  tryCatch(fromJSON(rawToChar(response$body), simplifyVector = FALSE),
           error = function(e) .ds_abort("Expected a JSON response from the DSpace API.", "protocol_error"))
}

.ds_search_container <- function(document) {
  embedded <- document[["_embedded"]]
  container <- embedded[["searchResult"]]
  if (is.null(container)) container <- embedded[["searchResults"]]
  if (is.null(container)) .ds_abort("Unsupported Discovery search response.", "protocol_error")
  container
}

.ds_pages <- function(con, url, relation, query = list(), search = FALSE) {
  query$page <- 0L
  query$size <- 100L
  url <- request(.ds_safe_url(con, url)) |> req_url_query(!!!query) |> (\(req) req$url)()
  seen <- character()
  output <- list()
  total <- NULL
  expected_page <- 0L
  repeat {
    if (url %in% seen) .ds_abort("Repeated pagination URL.", "pagination_error")
    seen <- c(seen, url)
    document <- .ds_json(con, url)
    page <- if (search) .ds_search_container(document) else document
    info <- page$page
    if (is.null(info$number) || is.null(info$totalPages) || is.null(info$totalElements) ||
        info$number != expected_page || info$totalPages < 0 || info$totalElements < 0) {
      .ds_abort("Missing or inconsistent pagination information.", "pagination_error")
    }
    if (!is.null(total) && info$totalElements != total) {
      .ds_abort("The result count changed during pagination; retry the retrieval.", "pagination_error")
    }
    total <- info$totalElements
    objects <- page[["_embedded"]][[relation]]
    if (is.null(objects)) objects <- list()
    if (!is.list(objects) || (total > 0 && !length(objects))) {
      .ds_abort("Missing objects in a nonempty result page.", "pagination_error")
    }
    output <- c(output, objects)
    if (expected_page + 1L >= info$totalPages) break
    next_url <- .ds_link(page, "next")
    if (is.null(next_url)) {
      url <- request(url) |> req_url_query(page = expected_page + 1L) |> (\(req) req$url)()
    } else {
      url <- .ds_safe_url(con, next_url, relative_to = url)
    }
    expected_page <- expected_page + 1L
  }
  if (length(output) != total) .ds_abort("The retrieved count does not match the server total.", "pagination_error")
  output
}
