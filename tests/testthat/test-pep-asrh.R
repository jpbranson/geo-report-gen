test_that("PEP county characteristics add up to states and the nation; medians are county-only", {
  real <- pep_asrh_long
  on.exit(assign("pep_asrh_long", real, envir = globalenv()))
  assign("pep_asrh_long", function() data.frame(key = c("county:10001", "county:10003", "county:24001"), year = 2025L, POP = c(100, 300, 600),
    AGE65PLUS = c(20, 30, 90), MEDIAN_AGE = c(40, 38, 41), RACE_TOTAL = c(100, 300, 600), HISPANIC = c(10, 30, 60), NH_WHITE = c(50, 150, 300),
    NH_BLACK = c(30, 90, 180), NH_ASIAN = 5, NH_MULTI = 3, NH_OTHER = 2), envir = globalenv())
  st <- resolve_settings()
  area <- function(keys) entity("x", "study", "x", data.frame(key = keys, type = sub(":.*$", "", keys), geoid = sub("^[^:]*:", "", keys), name = "x", pop = NA_real_))
  value <- function(metric, keys) compute_metric(metric, list(area(keys)), st, periods = 2025L)
  expect_equal(value("population_65plus_share_pep", "state:10")$value, 100 * 50 / 400)
  expect_equal(value("population_65plus_share_pep", "division:5")$value, 100 * 140 / 1000)
  expect_equal(value("hispanic_share_pep", "nation:US")$value, 10)
  expect_equal(value("median_age_pep", "county:10003")$value, 38)
  expect_equal(value("median_age_pep", "state:10")$status, "unavailable")
})
