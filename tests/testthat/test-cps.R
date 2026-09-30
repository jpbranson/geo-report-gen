test_that("CPS annual averages are national and flag the 11-month 2025 average", {
  real <- cps_values
  on.exit(assign("cps_values", real, envir = globalenv()))
  assign("cps_values", function() data.frame(variable = "UNEMPLOYMENT_RATE", year = c(2024L, 2025L), value = c(4.0, 4.3), footnote = c(NA, "11")), envir = globalenv())
  pieces <- data.frame(key = "nation:US", type = "nation", geoid = "US")
  v <- get_provider("bls_cps_ln")$fetch("UNEMPLOYMENT_RATE", pieces, 2024:2025)
  expect_equal(v$estimate, c(4.0, 4.3))
  expect_equal(v$note, c("", "11-month average (October 2025 not collected)"))
})
