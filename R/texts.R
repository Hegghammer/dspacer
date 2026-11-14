.ds_texts_table <- function() {
  tibble(repository = character(), item_uuid = character(), bundle_uuid = character(),
         bundle_name = character(), bitstream_uuid = character(), name = character(),
         mime_type = character(), source_text = character(), text = character(),
         sha256 = character(), retrieved_at = character(), conversion = character(),
         conversion_version = character())
}

.ds_text_format <- function(mime_type, name) {
  mime <- tolower(trimws(strsplit(.ds_value(mime_type, ""), ";", fixed = TRUE)[[1]][1]))
  if (is.na(mime)) mime <- ""
  if (mime %in% c("text/markdown", "text/x-markdown")) return("markdown")
  if (mime == "text/plain") return("plain")
  if (mime %in% c("", "application/octet-stream") && !is.na(name)) {
    if (grepl("\\.md$", name, ignore.case = TRUE)) return("markdown")
    if (grepl("\\.txt$", name, ignore.case = TRUE)) return("plain")
  }
  .ds_abort("Select Markdown or plaintext files; PDF/HTML extraction is not supported.", "unsupported_format")
}

.ds_decode_utf8 <- function(bytes) {
  text <- tryCatch(rawToChar(bytes), error = function(e) {
    .ds_abort("The selected file is not valid UTF-8 text.", "encoding_error")
  })
  if (!validUTF8(text)) .ds_abort("The selected file is not valid UTF-8 text.", "encoding_error")
  Encoding(text) <- "UTF-8"
  if (startsWith(text, "\ufeff")) text <- substring(text, 2L)
  text
}

#' Retrieve selected Markdown or plaintext files as analysis text
#'
#' Selection is explicit: Markdown may describe provenance rather than contain
#' document text. This function does not infer language, associate files by name,
#' remove page headings, normalize Unicode, or perform OCR.
#'
#' @section Supported formats:
#' Accepts `text/markdown`, `text/x-markdown` and `text/plain`. Unknown or
#' `application/octet-stream` files can use `.md` or `.txt` as a fallback. An
#' explicit non-text MIME type is not overridden by a filename.
#'
#' @section Plaintext conversion:
#' Markdown is rendered with `commonmark`, with no line wrapping, smart
#' punctuation, Unicode normalization or optional Markdown extensions. Headings
#' become ordinary text, link labels remain while destinations are omitted, code
#' text is retained, and raw HTML is omitted. Tables and footnotes receive no
#' extension-specific interpretation. Paragraph separation follows the renderer,
#' not a guarantee of one output paragraph per source block.
#'
#' `source_text` retains decoded source text, not exact source bytes. UTF-8 is
#' required; a UTF-8 BOM is removed from decoded text but included in checksums.
#' Invalid UTF-8 is an error, not silently replaced text. Use [ds_download()] for
#' exact bytes.
#'
#' @section Integrity and errors:
#' The size/checksum checks in [ds_download()] also apply here. An absent
#' attachment produces no inventory row, an inaccessible attachment is an error,
#' and a successfully downloaded empty file remains empty. No translation,
#' stemming, language inference or automatic page-marker removal is performed.
#'
#' @param con A connection from [ds_connect()].
#' @param files Selected rows from [ds_get_files()]. Text MIME types are used;
#'   `.md`/`.txt` extensions are a fallback only for unknown/octet-stream formats.
#' @return One row per selected file association, with:
#'   * `repository`, `item_uuid`, `bundle_uuid`, `bundle_name`, `bitstream_uuid`:
#'     association identifiers.
#'   * `name`, `mime_type`: file properties.
#'   * `source_text`, `text`: decoded source and derived plaintext.
#'   * `sha256`, `retrieved_at`: original-byte hash and download timestamp.
#'   * `conversion`, `conversion_version`: renderer and version, or `"none"` and
#'     `NA` for plaintext.
#'
#'   Its `dspacer` attribute records repository/package versions, selection and
#'   retrieval bounds. Join using repository URL and UUIDs, not filenames.
#' @seealso [ds_get_files()] to inventory attachments; [ds_download()] to save
#'   original bytes.
#' @export
ds_get_texts <- function(con, files) {
  .ds_check_files(con, files)
  started <- .ds_now()
  # Validate selection before downloading anything.
  formats <- vapply(seq_len(nrow(files)), function(i) {
    .ds_text_format(files$mime_type[[i]], files$name[[i]])
  }, character(1))
  rows <- vector("list", nrow(files))
  for (i in seq_len(nrow(files))) {
    file <- files[i, ]
    result <- .ds_read_file(con, file)
    source <- .ds_decode_utf8(result$bytes)
    markdown <- formats[[i]] == "markdown"
    text <- if (markdown) {
      markdown_text(source, width = 0, hardbreaks = FALSE, smart = FALSE,
                    normalize = FALSE, footnotes = FALSE, extensions = FALSE)
    } else source
    rows[[i]] <- tibble(
      repository = file$repository, item_uuid = file$item_uuid,
      bundle_uuid = file$bundle_uuid, bundle_name = file$bundle_name,
      bitstream_uuid = file$bitstream_uuid, name = file$name, mime_type = file$mime_type,
      source_text = source, text = text, sha256 = result$sha256,
      retrieved_at = result$retrieved_at,
      conversion = if (markdown) "commonmark::markdown_text (CommonMark; width=0)" else "none",
      conversion_version = if (markdown) as.character(packageVersion("commonmark")) else NA_character_
    )
    .ds_progress(con, "Texts", i, nrow(files))
  }
  .ds_finish(.ds_bind(rows, .ds_texts_table()), con,
             list(bitstream_uuids = files$bitstream_uuid), started)
}
