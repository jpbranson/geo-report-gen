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

test_that("a metric's cache key includes the code of the provider that registers its source", {
  expect_equal(provider_code_version("census_cbp"), code_version("R/providers/cbp.R"))
  expect_equal(provider_code_version("census_saipe"), code_version("R/providers/small_area.R"))
})

test_that("retrieval times come from the record written at retrieval, not the file's time", {
  path <- file.path(tempdir(), "cache-test", "raw.parquet")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  unlink(paste0(path, ".meta.json"))
  cached(path, function() data.frame(a = 1), source = "test")
  recorded <- retrieved_at(path)
  Sys.setFileTime(path, as.POSIXct("2001-01-01"))   # as after copying the cache
  expect_equal(retrieved_at(path), recorded)
  unlink(paste0(path, ".meta.json"))
  expect_equal(format(retrieved_at(path), "%Y"), "2001")
})

test_that("cache prune deletes only replaced derived files that no build lists", {
  withr::local_envvar(GR_CACHE = file.path(tempdir(), "prune-cache"))
  reports <- file.path(tempdir(), "prune-reports")
  unlink(c(cache_root(), reports), recursive = TRUE)
  dir <- cache_path("raw", "src")
  dir.create(dir, recursive = TRUE)
  files <- c("t-aaaaaaaa.parquet", "t-bbbbbbbb.parquet", "t-cccccccc.parquet", "u-dddddddd.parquet",
             "download.zip")
  for (i in seq_along(files)) {
    write_text_file("x", file.path(dir, files[i]))
    Sys.setFileTime(file.path(dir, files[i]), as.POSIXct("2026-01-01") + i * 60)
  }
  write_text_file("x", file.path(dir, "t-bbbbbbbb.parquet.meta.json"))
  write_text_file("", file.path(dir, "t-bbbbbbbb.parquet.lock"))
  # A report on disk still lists the oldest version of t; c is the newest; u has one version.
  dir.create(file.path(reports, "r1"), recursive = TRUE)
  write_json_file(list(sources = list(list(file = "raw/src/t-aaaaaaaa.parquet"))),
                  file.path(reports, "r1", "build.json"))
  expect_equal(cache_prune(reports = reports), "raw/src/t-bbbbbbbb.parquet")
  expect_true(file.exists(file.path(dir, "t-bbbbbbbb.parquet")))  # a dry run deletes nothing
  cache_prune(delete = TRUE, reports = reports)
  expect_setequal(list.files(dir), files[-2])
})
