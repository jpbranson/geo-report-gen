test_that("BPS serves units by structure size and PEP population for the rate", {
  real <- list(bps_long = bps_long, pep_long = pep_long)
  on.exit(for (n in names(real)) assign(n, real[[n]], envir = globalenv()))
  assign("bps_long", function() data.frame(key = "county:10001", year = c(1999L, 2000L), units = c(100, 120), units_1 = c(80, 90),
                                           units_5plus = c(10, 20), months = 12), envir = globalenv())
  assign("pep_long", function() data.frame(key = "county:10001", year = 2000L, population = 60000), envir = globalenv())
  pieces <- data.frame(key = "county:10001", type = "county", geoid = "10001")
  v <- get_provider("census_bps")$fetch(c("units", "units_1", "units_5plus", "POPULATION"), pieces, 1999:2000)
  expect_equal(v$estimate[v$variable == "units_5plus"], c(10, 20))
  expect_equal(v$estimate[v$variable == "POPULATION"], 60000)   # no 1999 estimate
  area <- entity("x", "study", "x", data.frame(key = "county:10001", type = "county", geoid = "10001", name = "x", pop = NA_real_))
  r <- compute_metric("permitted_units_per_1000_residents_bps", list(area), resolve_settings(), periods = 2000L)
  expect_equal(r$value, 1000 * 120 / 60000)
  expect_equal(get_provider("census_bps")$periods(list(), list())[1], 1990)
})
