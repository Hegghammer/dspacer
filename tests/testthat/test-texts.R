test_that("Markdown conversion preserves source, Unicode and paragraph separation", {
  source <- "## PDF page 1\n\nالعَرَبِيَّة **نص**.\n\nA [link](https://example.org). `code`\n"
  bytes <- charToRaw(source)
  local_mocked_bindings(.ds_transport = function(...) fixture_response(body = bytes))
  out <- ds_get_texts(fixture_connection(), fixture_file(bytes))
  expect_identical(out$source_text, source)
  expect_match(out$text, "العَرَبِيَّة نص", fixed = TRUE)
  expect_match(out$text, "PDF page 1", fixed = TRUE)
  expect_false(grepl("\\*\\*|https://", out$text))
  expect_match(out$text, "\n\n", fixed = TRUE)
  expect_identical(out$bitstream_uuid, fixture_ids[[3]])
  expect_match(out$conversion, "commonmark", fixed = TRUE)
})

test_that("empty, missing and forbidden files remain distinct", {
  local_mocked_bindings(.ds_transport = function(...) fixture_response(body = raw()))
  file <- fixture_file(raw())
  file$mime_type <- "text/plain"
  expect_identical(ds_get_texts(fixture_connection(), file)$text, "")
  expect_equal(nrow(ds_get_texts(fixture_connection(), file[FALSE, ])), 0L)
  local_mocked_bindings(.ds_transport = function(...) fixture_response(status = 403L))
  expect_error(ds_get_texts(fixture_connection(), file), class = "dspacer_access_error")
})

test_that("unsupported selections fail before downloading anything", {
  called <- FALSE
  local_mocked_bindings(.ds_transport = function(...) called <<- TRUE)
  file <- fixture_file()
  file$mime_type <- "application/pdf"
  expect_error(ds_get_texts(fixture_connection(), file), class = "dspacer_unsupported_format")
  expect_false(called)
  expect_identical(.ds_text_format(NA_character_, "document.md"), "markdown")
  expect_identical(.ds_text_format("text/plain", "document.md"), "plain")
  expect_error(.ds_text_format("text/html", "document.md"), class = "dspacer_unsupported_format")
})

test_that("UTF-8 is strict and BOM removal does not change byte checksums", {
  expect_error(.ds_decode_utf8(as.raw(c(255, 254))), class = "dspacer_encoding_error")
  bytes <- c(as.raw(c(239, 187, 191)), charToRaw("text"))
  expect_identical(.ds_decode_utf8(bytes), "text")
  local_mocked_bindings(.ds_transport = function(...) fixture_response(body = bytes))
  file <- fixture_file(bytes)
  file$mime_type <- "text/plain"
  out <- ds_get_texts(fixture_connection(), file)
  expect_identical(out$text, "text")
  expect_identical(out$sha256, digest(bytes, algo = "sha256", serialize = FALSE))
})

test_that("identical filenames on different items never share text", {
  first <- fixture_file(charToRaw("first item"))
  second <- fixture_file(charToRaw("second item"))
  second$item_uuid <- fixture_ids[[4]]
  second$bitstream_uuid <- fixture_ids[[5]]
  second$content_url <- paste0(fixture_base, "/core/bitstreams/", fixture_ids[[5]], "/content")
  local_mocked_bindings(.ds_transport = function(con, method, url, ...) {
    content <- if (identical(url, first$content_url)) "first item" else "second item"
    fixture_response(body = charToRaw(content))
  })
  out <- ds_get_texts(fixture_connection(), bind_rows(first, second))
  expect_identical(out$name, rep("document.md", 2L))
  expect_identical(out$source_text, c("first item", "second item"))
  expect_identical(out$item_uuid, c(first$item_uuid, second$item_uuid))
})

test_that("CommonMark examples have documented, stable basic behavior", {
  render <- function(text) markdown_text(text, width = 0, extensions = FALSE)
  expect_match(render("- first\n- second\n"), "first")
  expect_match(render("```\nx <- 1\n```\n"), "x <- 1", fixed = TRUE)
  expect_match(render("A &amp; B"), "A & B", fixed = TRUE)
  expect_false(grepl("<script>", render("<script>alert('x')</script>"), fixed = TRUE))
  # Tables and footnotes are not extensions enabled by this initial release.
  expect_match(render("a | b\n--|--\nc | d\n"), "|", fixed = TRUE)
  expect_match(render("Text[^1]\n\n[^1]: Note\n"), "Text")
})
