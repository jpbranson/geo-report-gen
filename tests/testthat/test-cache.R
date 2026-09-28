test_that("cached() computes once and then reuses the stored value", {
  path <- file.path(tempdir(), "cache-test", "value.rds")
  unlink(path)
  calls <- 0
  compute <- function() {
    calls <<- calls + 1
    data.frame(a = 1)
  }
  cached(path, compute)
  expect_equal(cached(path, compute), data.frame(a = 1))
  expect_equal(calls, 1)
})

test_that("cache keys change with their inputs and are stable otherwise", {
  expect_equal(hash_value(list(a = 1, b = "x")), hash_value(list(a = 1, b = "x")))
  expect_false(hash_value(2024, "B01003", "county") == hash_value(2023, "B01003", "county"))
})

test_that("offline mode never touches the network", {
  expect_error(http_request("https://example.org", "test"), "Offline")
})
