test_that("OEWS serves the nation, states and metro areas and marks unpublished wages", {
  real <- oews_values
  on.exit(assign("oews_values", real, envir = globalenv()))
  assign("oews_values", function() data.frame(key = c("nation:US", "state:18", "cbsa:26900"), variable = "MEDIAN_WAGE", year = 2025L,
                                              value = c(50000, 47000, NA)), envir = globalenv())
  pieces <- data.frame(key = c("state:18", "cbsa:26900"), type = c("state", "cbsa"), geoid = c("18", "26900"))
  v <- get_provider("bls_oews")$fetch("MEDIAN_WAGE", pieces, 2025L)
  expect_equal(v$estimate, c(47000, NA))
  expect_equal(v$status, c("ok", "unavailable"))
  expect_equal(get_provider("bls_oews")$period_label(2025L), "May 2025")
})

test_that("CPS annual averages are national and flag the 11-month 2025 average", {
  real <- cps_values
  on.exit(assign("cps_values", real, envir = globalenv()))
  assign("cps_values", function() data.frame(variable = "UNEMPLOYMENT_RATE", year = c(2024L, 2025L), value = c(4.0, 4.3), footnote = c(NA, "11")), envir = globalenv())
  pieces <- data.frame(key = "nation:US", type = "nation", geoid = "US")
  v <- get_provider("bls_cps_ln")$fetch("UNEMPLOYMENT_RATE", pieces, 2024:2025)
  expect_equal(v$estimate, c(4.0, 4.3))
  expect_equal(v$note, c("", "11-month average (October 2025 not collected)"))
})
