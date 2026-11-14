#' Metadata and text retrieval from DSpace
#'
#' A read-only client for the modern DSpace REST API. Start with
#' [ds_connect()], then retrieve items with [ds_get_items()], inventory their
#' attachments with [ds_get_files()], and select files for [ds_get_texts()].
#'
#' @keywords internal
#' @importFrom cli cli_inform cli_warn
#' @importFrom commonmark markdown_text
#' @importFrom digest digest
#' @importFrom dplyr bind_rows
#' @importFrom httr2 request req_body_form req_cookie_preserve req_error
#'   req_headers req_headers_redacted req_method req_options req_perform
#'   req_retry req_timeout req_url_query resp_body_raw resp_has_body resp_headers resp_status
#'   url_build url_parse
#' @importFrom jsonlite fromJSON
#' @importFrom rlang abort
#' @importFrom tibble tibble
#' @importFrom utils packageVersion URLdecode
"_PACKAGE"
