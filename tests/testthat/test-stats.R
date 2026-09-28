test_that("MOEs of derived estimates follow the ACS handbook formulas", {
  expect_equal(moe_sum(c(30, 40)), 50)
  expect_equal(moe_prop(20, 100, 5, 10), sqrt(25 - 0.2^2 * 10^2) / 100)
  # A negative radicand falls back to the ratio formula; P = 1 uses MOE(X) / Y.
  expect_equal(moe_prop(90, 100, 2, 10), sqrt(2^2 + 0.9^2 * 10^2) / 100)
  expect_equal(moe_prop(50, 50, 5, 5), 5 / 50)
  expect_equal(moe_ratio(20, 100, 5, 10), sqrt(25 + 0.2^2 * 10^2) / 100)
})

test_that("significance tests account for overlapping periods and part-whole dependence", {
  se1 <- Z90  # MOEs that correspond to standard errors of 1
  expect_equal(diff_test(10, se1, 14, se1)$z, -4 / sqrt(2))
  expect_true(diff_test(10, se1, 14, se1)$significant)
  # Overlapping 5-year periods: Var(A - B) is multiplied by (1 - C).
  expect_equal(diff_test(10, se1, 14, se1, overlap = 0.8)$z, -4 / sqrt(0.2 * 2))
  # A study area holding 30% of its benchmark: Var(A - B) = Var(A)(1 - 2w) + Var(B).
  expect_equal(diff_test(10, se1, 14, se1, part_share = 0.3)$z, -4 / sqrt(0.4 + 1))
  # If that variance would be negative, the conservative independent form is used.
  expect_equal(diff_test(10, 2 * Z90, 12, sqrt(0.5) * Z90, part_share = 0.9)$z, -2 / sqrt(4.5))
  # Census counts (MOE 0) differ exactly; a missing MOE makes the test unavailable.
  expect_true(diff_test(5, 0, 6, 0)$significant)
  expect_false(diff_test(5, NA, 6, 1)$testable)
})

test_that("medians are interpolated inside the bin that holds the 50th percentile", {
  m <- median_from_bins(c(10, 20, 30, 40), c(0, 10, 20, 30), c(10, 20, 30, Inf))
  expect_equal(m$value, 20 + (50 - 30) / 30 * 10)
  expect_equal(m$status, "ok")
  expect_equal(median_from_bins(c(1, 1, 10), c(0, 10, 20), c(10, 20, Inf))$status, "open_interval")
  expect_equal(median_from_bins(c(0, 0), c(0, 10), c(10, 20))$status, "invalid_denominator")
  expect_error(median_from_bins(c(1, 1), c(10, 0), c(20, 10)), "ordered")
})

test_that("ACS distribution labels become numeric bins", {
  expect_equal(parse_bin_label("Estimate!!Total:!!Less than $10,000"), c(0, 10000))
  expect_equal(parse_bin_label("Estimate!!Total:!!$10,000 to $14,999"), c(10000, 15000))
  expect_equal(parse_bin_label("Estimate!!Total:!!$200,000 or more"), c(200000, Inf))
})

test_that("period overlap, growth rates, reliability and inflation factors", {
  expect_equal(period_overlap(2016, 2020, 2020, 2024), 0.2)
  expect_equal(period_overlap(2015, 2019, 2020, 2024), 0)
  expect_equal(annual_rate(100, 121, 2), 0.1)
  expect_equal(reliability(cv_percent(100, Z90 * 40)), "unreliable")
  expect_equal(reliability(cv_percent(100, Z90 * 20)), "caution")
  expect_equal(reliability(cv_percent(100, Z90 * 5)), "reliable")
  idx <- data.frame(year = c(2000, 2024), index = c(100, 150))
  expect_equal(inflation_factor(c(2000, 1999), 2024, idx), c(1.5, NA))
})
