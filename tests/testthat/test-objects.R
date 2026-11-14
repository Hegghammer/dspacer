test_that("long metadata retains repeats, custom fields, ordering and unknown properties", {
  metadata <- list(
    "custom.date" = list(list(value = "1440 AH", language = "ar", place = 4L, future = "kept")),
    "dc.title" = list(list(value = "First", place = 1L), list(value = "First", language = "en", place = 0L)),
    "custom.empty" = list(list(value = ""), list(value = NULL))
  )
  x <- .ds_item_row(fixture_connection(), fixture_item(metadata = metadata))
  out <- ds_get_metadata(x, format = "long")
  expect_equal(nrow(out), 5)
  expect_identical(out$value, c("1440 AH", "First", "First", "", NA_character_))
  expect_identical(out$place[1:3], c(4L, 1L, 0L))
  expect_identical(out$value_index[2:3], c(1L, 2L))
  expect_identical(out$extra[[1]]$future, "kept")
  expect_identical(out$language[1], "ar")
  expect_identical(x$metadata[[1]], metadata)
})

test_that("metadata is wide by default with scalar and repeated-value columns", {
  con <- fixture_connection()
  first <- .ds_item_row(con, fixture_item(metadata = list(
    "dc.title" = list(list(value = "Jarīdat")),
    "dc.subject" = list(list(value = "History"), list(value = "History"), list(value = "Politics")),
    "local.date" = list(list(value = "1440 AH")),
    "custom.empty" = list(list(value = ""))
  )))
  second <- .ds_item_row(con, fixture_item(fixture_ids[[2]], metadata = list(
    "dc.title" = list(list(value = "Another title")),
    "dc.subject" = list(list(value = "History")),
    "local.field-with-hyphen" = list(list(value = "kept"))
  )))
  third <- .ds_item_row(con, fixture_item(fixture_ids[[3]]))
  items <- bind_rows(first, second, third)
  attr(items, "dspacer") <- list(selection = "original", package_version = "test")
  original <- items$metadata
  out <- ds_get_metadata(items)
  expect_equal(nrow(out), 3L)
  expect_identical(out$object_uuid, fixture_ids[1:3])
  expect_identical(out$object_type, rep("item", 3L))
  expect_identical(names(out), c(
    "repository", "object_uuid", "object_type", "dc.title", "dc.subject",
    "local.date", "custom.empty", "local.field-with-hyphen"
  ))
  expect_identical(out$dc.title, c("Jarīdat", "Another title", NA_character_))
  expect_identical(out$dc.subject, list(c("History", "History", "Politics"), "History", character()))
  expect_identical(out$local.date, c("1440 AH", NA_character_, NA_character_))
  expect_identical(out$custom.empty, c("", NA_character_, NA_character_))
  expect_identical(out[["local.field-with-hyphen"]], c(NA_character_, "kept", NA_character_))
  expect_identical(attr(out, "dspacer"), attr(items, "dspacer"))
  expect_identical(items$metadata, original)
})

test_that("wide metadata retains empty objects and distinguishes missing values", {
  con <- fixture_connection()
  one <- .ds_item_row(con, fixture_item(metadata = list(
    "custom.null" = list(list(value = NULL)), "custom.array" = list()
  )))
  two <- .ds_item_row(con, fixture_item(fixture_ids[[2]]))
  out <- ds_get_metadata(bind_rows(one, two))
  expect_equal(nrow(out), 2L)
  expect_identical(out$custom.null, c(NA_character_, NA_character_))
  expect_identical(out$custom.array, c(NA_character_, NA_character_))
  empty <- ds_get_metadata(.ds_items_table())
  expect_identical(names(empty), c("repository", "object_uuid", "object_type"))
  expect_identical(empty$object_uuid, character())
  expect_identical(names(ds_get_metadata(.ds_items_table(), "long")), names(.ds_metadata_table()))
  expect_error(ds_get_metadata(one, "other"), "arg")
})

test_that("wide metadata deduplicates associations but refuses conflicting snapshots", {
  file <- fixture_file()
  file$metadata[[1]] <- list("dc.title" = list(list(value = "File")))
  other <- file
  other$bundle_uuid <- fixture_ids[[4]]
  out <- ds_get_metadata(bind_rows(file, other))
  expect_equal(nrow(out), 1L)
  expect_identical(out$dc.title, "File")
  expect_identical(out$object_uuid, file$bitstream_uuid)
  other$metadata[[1]] <- list("dc.title" = list(list(value = "Changed")))
  expect_error(ds_get_metadata(bind_rows(file, other)), class = "dspacer_input_error")
})

test_that("wide metadata supports collections and keeps repositories separate", {
  one <- tibble(
    repository = fixture_base, collection_uuid = fixture_ids[[1]],
    metadata = list(list("dc.title" = list(list(value = "Collection"))))
  )
  two <- one
  two$repository <- "https://another.example.org/server/api"
  out <- ds_get_metadata(bind_rows(one, two))
  expect_equal(nrow(out), 2L)
  expect_identical(out$object_type, rep("collection", 2L))
  expect_identical(out$dc.title, rep("Collection", 2L))
})

test_that("metadata uses bitstream identity instead of the parent item", {
  files <- fixture_file()
  files$metadata[[1]] <- list("dc.description" = list(list(value = "File description")))
  out <- ds_get_metadata(files)
  expect_identical(out$object_uuid, fixture_ids[[3]])
  expect_identical(out$object_type, "bitstream")
  expect_equal(nrow(ds_get_metadata(.ds_items_table())), 0L)
})

test_that("explicit item retrieval preserves item identity and rejects ambiguity", {
  con <- fixture_connection()
  local_mocked_bindings(.ds_json = function(con, url, ...) fixture_item(sub(".*/", "", url)))
  out <- ds_get_items(con, ids = fixture_ids[1:2])
  expect_identical(out$item_uuid, fixture_ids[1:2])
  expect_true(all(is.na(out$handle)))
  expect_identical(attr(out, "dspacer")$selection$ids, fixture_ids[1:2])
  expect_error(ds_get_items(con, ids = fixture_ids[[1]], query = "title"), class = "dspacer_input_error")
  expect_error(ds_get_items(con, ids = "../outside"), class = "dspacer_input_error")
  expect_identical(names(ds_get_items(con, ids = character())), names(out))
})

test_that("search uses Discovery rather than admin item enumeration", {
  calls <- character()
  local_mocked_bindings(.ds_transport = function(con, method, url, form = NULL) {
    calls <<- c(calls, url)
    if (grepl("/discover/search/objects", url, fixed = TRUE)) {
      hit <- list(`_links` = list(indexableObject = list(href = paste0(fixture_base, "/core/items/", fixture_ids[[1]]))))
      return(fixture_response(list(`_embedded` = list(searchResult = fixture_page(list(hit), "objects")))))
    }
    fixture_response(fixture_item())
  })
  out <- ds_get_items(fixture_connection(), query = "Arabic & history")
  expect_equal(nrow(out), 1L)
  expect_match(calls[[1]], "/discover/search/objects", fixed = TRUE)
  expect_false(any(calls == paste0(fixture_base, "/core/items")))
})

test_that("duplicate UUIDs flag search drift", {
  local_mocked_bindings(
    .ds_pages = function(...) list(
      list(`_links` = list(indexableObject = list(href = paste0(fixture_base, "/item/1")))),
      list(`_links` = list(indexableObject = list(href = paste0(fixture_base, "/item/1"))))
    ),
    .ds_json = function(...) fixture_item()
  )
  expect_error(ds_get_items(fixture_connection()), class = "dspacer_pagination_error")
})

test_that("empty collection results retain their schema", {
  local_mocked_bindings(.ds_pages = function(...) list())
  out <- ds_get_collections(fixture_connection())
  expect_equal(nrow(out), 0L)
  expect_identical(names(out), names(.ds_collections_table()))
})
