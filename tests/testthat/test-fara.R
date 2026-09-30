test_that("Food Access Research Atlas tracts sum to counties and states; 2019 has no tract values", {
  real <- fara_tracts
  on.exit(assign("fara_tracts", real, envir = globalenv()))
  none <- rep(NA_real_, 3)
  assign("fara_tracts", function() data.frame(year = c(2025L, 2025L, 2025L, 2019L, 2019L, 2019L),
    tract = c("10001040100", "10001040200", "10003000100", "10001040100", "10001040200", "10003000100"),
    SD_LILA = c(1, 0, 1, none), DD_LILA = c(1, 1, 1, none), SD_LAPOP = c(100, 50, 300, none), DD_LAPOP = c(500, 100, 300, none),
    POP = c(1000, 500, 1500, none), LRAM_LILA = c(none, 1, 0, 1), LRAM_LAPOP = c(none, 10, 20, 30), LRAM_POP = c(none, 100, 100, 100),
    county = c("10001", "10001", "10003", "10001", "10001", "10003"), state = "10"), envir = globalenv())
  st <- resolve_settings()
  area <- function(keys) entity("x", "study", "x", data.frame(key = keys, type = sub(":.*$", "", keys), geoid = sub("^[^:]*:", "", keys), name = "x", pop = NA_real_))
  value <- function(metric, keys) compute_metric(metric, list(area(keys)), st)
  expect_equal(value("low_income_low_access_tract_sram", "county:10001")$value, 1)
  expect_equal(value("low_income_low_access_tract_share_sram", "county:10001")$value, 50)
  expect_equal(value("low_access_population_share_sram", "state:10")$value, 100 * 450 / 3000)
  expect_equal(value("low_access_population_share_driving_sram", "tract:10003000100")$value, 20)
  expect_equal(value("low_income_low_access_tract_lram", "state:10")$value, 2)
  expect_equal(value("low_income_low_access_tract_lram", "state:10")$period, "2019")
  expect_equal(value("low_income_low_access_tract_lram", "tract:10001040200")$status, "unavailable")
})
