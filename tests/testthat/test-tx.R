test_that("Texas licensing counts operations by type, subsidy acceptance and capacity per child", {
  real <- list(tx_capacity = tx_capacity, acs_fetch = acs_fetch)
  on.exit(for (n in names(real)) assign(n, real[[n]], envir = globalenv()))
  assign("tx_capacity", function() data.frame(key = c("county:48453", "county:48453", "county:48453", "county:48491"),
    county = c("TRAVIS", "TRAVIS", "TRAVIS", "WILLIAMSON"), accepts_child_care_subsidies = c("Y", "N", "N", "Y"),
    operation_type = c("Licensed Center", "Licensed Center", "Licensed Child-Care Home", "Licensed Center"),
    capacity = c(100, 50, 12, 80), operations = c(2, 1, 1, 1), retrieved = "2026-09-30"), envir = globalenv())
  assign("acs_fetch", function(variables, pieces, releases) data.frame(geo = "county:48453", variable = c("B01001_003", "B01001_027"),
    estimate = c(20, 30)), envir = globalenv())
  st <- resolve_settings()
  area <- function(keys) entity("x", "study", "x", data.frame(key = keys, type = sub(":.*$", "", keys), geoid = sub("^[^:]*:", "", keys), name = "x", pop = NA_real_))
  value <- function(metric, keys) compute_metric(metric, list(area(keys)), st)$value
  expect_equal(value("childcare_licensed_centers_tx_hhsc", "county:48453"), 3)
  expect_equal(value("childcare_licensed_homes_tx_hhsc", "county:48453"), 1)
  expect_equal(value("childcare_registered_homes_tx_hhsc", "county:48453"), 0)
  expect_equal(value("childcare_centers_accepting_subsidy_share_tx_hhsc", "county:48453"), 100 * 2 / 3)
  expect_equal(value("childcare_centers_accepting_subsidy_share_tx_hhsc", "state:48"), 75)
  expect_equal(value("childcare_capacity_per_100_under5_tx", "county:48453"), 100 * 162 / 50)
})
