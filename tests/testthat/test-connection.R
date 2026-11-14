test_that("connection validates roots, creates private cookies and prints safely", {
  local_mocked_bindings(.ds_transport = function(con, method, url, form = NULL) {
    fixture_response(list(dspaceVersion = "DSpace 10.1", `_links` = list()),
                     headers = list(`dspace-xsrf-token` = "private-csrf"))
  })
  con <- ds_connect(paste0(fixture_base, "/"), quiet = TRUE)
  expect_identical(con$base_url, fixture_base)
  expect_identical(con$version, "DSpace 10.1")
  expect_true(file.exists(con$cookie_path))
  if (.Platform$OS.type == "unix") expect_identical(as.character(file.info(con$cookie_path)$mode), "600")
  con$token <- "Bearer private-token"
  printed <- paste(capture.output(print(con)), collapse = "\n")
  expect_false(grepl("private", printed))
  expect_match(printed, "authenticated")
  con$token <- NULL
  ds_disconnect(con)
  expect_false(file.exists(con$cookie_path))
  expect_null(con$csrf)
  expect_error(ds_get_items(con), class = "dspacer_input_error")
})

test_that("insecure and credential-bearing base URLs require rejection", {
  expect_error(ds_connect("http://localhost/server/api"), class = "dspacer_input_error")
  expect_error(ds_connect("https://user:password@example.org/server/api"), class = "dspacer_input_error")
  expect_error(ds_connect(paste0(fixture_base, "?token=secret")), class = "dspacer_input_error")
  expect_error(ds_connect(fixture_base, timeout = 0), class = "dspacer_input_error")
})

test_that("login follows CSRF rotation and retains no password", {
  calls <- list()
  local_mocked_bindings(.ds_transport = function(con, method, url, form = NULL) {
    calls[[length(calls) + 1L]] <<- list(method = method, url = url, csrf = con$csrf, form = form)
    if (endsWith(url, "/security/csrf")) return(fixture_response(status = 204L, headers = list(`dspace-xsrf-token` = "first")))
    if (endsWith(url, "/authn/login")) {
      expect_identical(con$csrf, "first")
      expect_identical(form, list(user = "reader@example.org", password = "private-password"))
      return(fixture_response(headers = list(authorization = "Bearer test-token", `dspace-xsrf-token` = "second")))
    }
    fixture_response(list(authenticated = TRUE))
  })
  con <- fixture_connection()
  ds_login(con, "reader@example.org", "private-password")
  expect_identical(con$token, "Bearer test-token")
  expect_identical(con$csrf, "second")
  expect_false(any(grepl("password", ls(envir = con), ignore.case = TRUE)))
  expect_length(calls, 3)
  expect_error(ds_login(con, "", "secret"), class = "dspacer_input_error")
})

test_that("failed login never exposes response secrets", {
  local_mocked_bindings(.ds_transport = function(...) fixture_response(
    status = 401L, body = charToRaw("private-password Bearer private-token")
  ))
  con <- fixture_connection()
  con$csrf <- "csrf"
  error <- tryCatch(ds_login(con, "reader", "private-password"), error = identity)
  expect_s3_class(error, "dspacer_access_error")
  expect_false(grepl("private", conditionMessage(error)))
  expect_null(con$token)
})

test_that("disconnect always clears local state if logout fails", {
  con <- fixture_connection()
  con$token <- "Bearer secret"
  con$csrf <- "csrf"
  local_mocked_bindings(.ds_transport = function(...) fixture_response(status = 503L))
  expect_warning(ds_disconnect(con), "logout failed")
  expect_null(con$token)
  expect_true(con$closed)
  expect_false(file.exists(con$cookie_path))
})
