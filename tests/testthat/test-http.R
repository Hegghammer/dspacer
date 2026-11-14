test_that("API links cannot leak credentials across origins or paths", {
  con <- fixture_connection()
  expect_identical(.ds_safe_url(con, "/server/api/core/items"), paste0(fixture_base, "/core/items"))
  for (url in c(
    "https://attacker.example/server/api",
    "http://repository.example.org/server/api",
    "https://repository.example.org:8443/server/api",
    "https://secret@repository.example.org/server/api",
    "/outside", "/server/api-other/items",
    "/server/api/%2e%2e/private", "/server/api/%252e%252e/private"
  )) expect_error(.ds_safe_url(con, url), class = "dspacer_unsafe_url")
})

test_that("redirects are checked before the next request", {
  calls <- 0L
  local_mocked_bindings(.ds_transport = function(...) {
    calls <<- calls + 1L
    fixture_response(status = 302L, headers = list(location = "https://attacker.example/steal"))
  })
  con <- fixture_connection()
  expect_error(.ds_request(con, fixture_base), class = "dspacer_unsafe_url")
  expect_identical(calls, 1L)
  expect_error(.ds_request(con, paste0(fixture_base, "/core/items"), method = "POST"), class = "dspacer_input_error")
})

test_that("an authenticated file denial does not cause a login loop", {
  calls <- list()
  local_mocked_bindings(.ds_transport = function(con, method, url, form = NULL) {
    calls[[length(calls) + 1L]] <<- method
    if (endsWith(url, "/authn/status")) return(fixture_response(list(authenticated = TRUE)))
    fixture_response(status = 401L)
  })
  con <- fixture_connection()
  con$token <- "Bearer valid"
  expect_error(.ds_request(con, paste0(fixture_base, "/private-file")), class = "dspacer_access_error")
  expect_identical(unlist(calls), c("GET", "GET"))
})

test_that("expired sessions refresh at most once without retaining passwords", {
  calls <- list()
  local_mocked_bindings(.ds_transport = function(con, method, url, form = NULL) {
    calls[[length(calls) + 1L]] <<- method
    if (endsWith(url, "/authn/status")) return(fixture_response(list(authenticated = FALSE)))
    if (method == "POST") return(fixture_response(headers = list(authorization = "Bearer fresh")))
    if (identical(con$token, "Bearer fresh")) return(fixture_response(list(ok = TRUE)))
    fixture_response(status = 401L)
  })
  con <- fixture_connection()
  con$csrf <- "csrf"
  con$token <- "Bearer expired"
  expect_true(.ds_json(con, paste0(fixture_base, "/resource"))$ok)
  expect_identical(unlist(calls), c("GET", "GET", "POST", "GET"))
})

test_that("pagination supports nested search layouts and missing next links", {
  calls <- character()
  local_mocked_bindings(.ds_json = function(con, url, ...) {
    calls <<- c(calls, url)
    index <- as.integer(url_parse(url)$query$page)
    page <- fixture_page(list(list(uuid = fixture_ids[[index + 1L]])), "objects",
                         number = index, total = 2L, pages = 2L)
    list(`_embedded` = setNames(list(page), if (index == 0L) "searchResult" else "searchResults"))
  })
  out <- .ds_pages(fixture_connection(), paste0(fixture_base, "/discover/search/objects"), "objects", search = TRUE)
  expect_length(out, 2)
  expect_match(calls[[2]], "page=1")
})

test_that("pagination refuses changing totals and malformed empty pages", {
  calls <- 0L
  local_mocked_bindings(.ds_json = function(...) {
    calls <<- calls + 1L
    fixture_page(list(list(uuid = fixture_ids[[1]])), "items",
                 number = calls - 1L, total = calls + 1L, pages = 2L)
  })
  expect_error(.ds_pages(fixture_connection(), fixture_base, "items"), class = "dspacer_pagination_error")
  local_mocked_bindings(.ds_json = function(...) fixture_page(list(), "items", total = 1L))
  expect_error(.ds_pages(fixture_connection(), fixture_base, "items"), class = "dspacer_pagination_error")
})

test_that("JSON errors do not return bodies containing secrets", {
  local_mocked_bindings(.ds_transport = function(...) fixture_response(body = charToRaw("not JSON secret-token")))
  expect_error(.ds_json(fixture_connection(), fixture_base), "Expected a JSON response")
})
