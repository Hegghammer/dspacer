test_that("file inventories keep bundles, format and primary selection separate", {
  con <- fixture_connection()
  bitstream <- list(
    uuid = fixture_ids[[3]], name = "document.md", sizeBytes = 10,
    checkSum = list(checkSumAlgorithm = "MD5", value = "abc"), metadata = list(),
    `_links` = list(content = list(href = paste0(fixture_base, "/content")),
                    format = list(href = paste0(fixture_base, "/format")))
  )
  bundle <- list(
    uuid = fixture_ids[[2]], name = "ORIGINAL",
    `_links` = list(primaryBitstream = list(href = paste0(fixture_base, "/primary")),
                    bitstreams = list(href = paste0(fixture_base, "/files")))
  )
  local_mocked_bindings(
    .ds_pages = function(con, url, relation, ...) {
      if (relation == "bundles") return(list(bundle, list(uuid = fixture_ids[[4]], name = "TEXT")))
      list(bitstream)
    },
    .ds_json = function(con, url, ...) {
      if (endsWith(url, "/primary")) return(list(uuid = fixture_ids[[3]]))
      list(mimetype = "text/markdown")
    }
  )
  items <- .ds_item_row(con, fixture_item())
  out <- ds_get_files(con, items)
  expect_equal(nrow(out), 1)
  expect_identical(out$bundle_name, "ORIGINAL")
  expect_true(out$is_primary)
  expect_identical(out$mime_type, "text/markdown")
  expect_identical(out$bitstream_uuid, fixture_ids[[3]])
  items$repository <- "https://another.example/server/api"
  expect_error(ds_get_files(con, items), class = "dspacer_input_error")
})

test_that("downloaded bytes must pass size and checksum validation", {
  bytes <- charToRaw("content")
  file <- fixture_file(bytes)
  expect_identical(.ds_verify_bytes(bytes, file), digest(bytes, algo = "sha256", serialize = FALSE))
  expect_error(.ds_verify_bytes(charToRaw("changed"), file), class = "dspacer_integrity_error")
  file$size_bytes <- 1
  expect_error(.ds_verify_bytes(bytes, file), class = "dspacer_integrity_error")
  file <- fixture_file(bytes)
  for (algorithm in c("sha1", "sha256", "sha512")) {
    file$checksum_algorithm <- toupper(algorithm)
    file$checksum <- digest(bytes, algo = algorithm, serialize = FALSE)
    expect_identical(.ds_verify_bytes(bytes, file), digest(bytes, algo = "sha256", serialize = FALSE))
  }
  file$checksum_algorithm <- "SHA384"
  expect_error(.ds_verify_bytes(bytes, file), class = "dspacer_integrity_error")
  file$checksum_algorithm <- "unknown"
  expect_error(.ds_verify_bytes(bytes, file), class = "dspacer_integrity_error")
})

test_that("downloads ignore remote path names and refuse conflicting local bytes", {
  bytes <- charToRaw("content")
  local_mocked_bindings(.ds_transport = function(...) fixture_response(body = bytes))
  files <- fixture_file(bytes)
  files$name <- "../../outside.txt"
  directory <- tempfile()
  on.exit(unlink(directory, recursive = TRUE))
  out <- ds_download(fixture_connection(), files, directory)
  expect_true(file.exists(out$local_path))
  expect_identical(basename(out$local_path), paste0(files$bitstream_uuid, ".bin"))
  expect_identical(readBin(out$local_path, "raw", n = 100), bytes)
  expect_identical(ds_download(fixture_connection(), files, directory)$sha256, out$sha256)
  writeBin(charToRaw("different local file"), out$local_path)
  expect_error(ds_download(fixture_connection(), files, directory), class = "dspacer_file_error")
  expect_identical(rawToChar(readBin(out$local_path, "raw", n = 100)), "different local file")
})
