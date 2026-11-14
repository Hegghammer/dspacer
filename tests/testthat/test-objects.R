test_that("metadata retains repeats, custom fields, ordering and unknown properties", {
  metadata <- list(
    "custom.date" = list(list(value = "1440 AH", language = "ar", place = 4L, future = "kept")),
    "dc.title" = list(list(value = "First", place = 1L), list(value = "First", language = "en", place = 0L)),
    "custom.empty" = list(list(value = ""), list(value = NULL))
  )
  x <- .ds_item_row(fixture_connection(), fixture_item(metadata = metadata))
  out <- ds_get_metadata(x)
  expect_equal(nrow(out), 5)
  expect_identical(out$value, c("1440 AH", "First", "First", "", NA_character_))
  expect_identical(out$place[1:3], c(4L, 1L, 0L))
  expect_identical(out$value_index[2:3], c(1L, 2L))
  expect_identical(out$extra[[1]]$future, "kept")
  expect_identical(out$language[1], "ar")
  expect_identical(x$metadata[[1]], metadata)
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
