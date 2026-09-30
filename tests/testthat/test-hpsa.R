test_that("HPSA counts designations once per area and reports the highest score", {
  real <- hpsa_components
  on.exit(assign("hpsa_components", real, envir = globalenv()))
  assign("hpsa_components", function(discipline) data.frame(id = c("A", "A", "B", "C"), county = c("10001", "10003", "10001", "24001"),
    score = c(12, 12, 20, 5), retrieved = "2026-09-30"), envir = globalenv())
  st <- resolve_settings()
  area <- function(keys) entity("x", "study", "x", data.frame(key = keys, type = sub(":.*$", "", keys), geoid = sub("^[^:]*:", "", keys), name = "x", pop = NA_real_))
  value <- function(metric, keys) compute_metric(metric, list(area(keys)), st)$value
  expect_equal(value("primary_care_hpsa_count_hrsa", "county:10001"), 2)
  expect_equal(value("primary_care_hpsa_count_hrsa", "state:10"), 2)       # A spans two counties but counts once
  expect_equal(value("primary_care_hpsa_count_hrsa", "division:5"), 3)
  expect_equal(value("dental_hpsa_score_hrsa", "county:10001"), 20)
  expect_equal(value("dental_hpsa_score_hrsa", "county:24001"), 5)
})
