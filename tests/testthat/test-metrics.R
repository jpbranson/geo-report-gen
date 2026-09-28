test_that("counts sum over pieces, with root-sum-of-squares MOEs", {
  r <- aggregate_entity(recipe(numerator = "X"), long(c("a", "b"), "X", c(100, 200), c(30, 40)), c("a", "b"), 2024)
  expect_equal(r$value, 300)
  expect_equal(r$moe, 50)
})

test_that("shares are recomputed from summed numerators and denominators, never averaged", {
  d <- long(c("a", "a", "b", "b"), c("N", "D", "N", "D"), c(10, 100, 90, 300))
  r <- aggregate_entity(recipe(stat_type = "share", numerator = "N", denominator = "D", scale = "100"), d, c("a", "b"), 2024)
  expect_equal(r$value, 25)   # 100 / 400, not the average of 10% and 30%
})

test_that("zero denominators never produce a value", {
  r <- aggregate_entity(recipe(stat_type = "share", numerator = "N", denominator = "D"),
                        long(c("a", "a"), c("N", "D"), c(0, 0)), "a", 2024)
  expect_true(is.na(r$value))
  expect_equal(r$status, "invalid_denominator")
})

test_that("a piece without data makes a combined value unavailable, not a partial sum", {
  r <- aggregate_entity(recipe(numerator = "X"), long("a", "X", 100), c("a", "b"), 2024)
  expect_true(is.na(r$value))
  expect_equal(r$status, "unavailable")
  expect_match(r$method, "no published data for b")
})

test_that("suppressed components make the result suppressed", {
  d <- long(c("a", "b"), "X", c(100, NA), status = c("ok", "suppressed"))
  expect_equal(aggregate_entity(recipe(numerator = "X"), d, c("a", "b"), 2024)$status, "suppressed")
})

test_that("single areas use published estimates; medians and indexes are not combined", {
  d <- long(c("a", "b"), "MED", c(50000, 60000))
  single <- aggregate_entity(recipe(stat_type = "median", published_var = "MED"), d, "a", 2024)
  expect_equal(single$value, 50000)
  expect_equal(single$method, "published estimate")
  expect_equal(aggregate_entity(recipe(stat_type = "median", published_var = "MED"), d, c("a", "b"), 2024)$status,
               "not_aggregable")
  expect_equal(aggregate_entity(recipe(stat_type = "value", numerator = "I"), long(c("a", "b"), "I", c(120, 130)),
                                c("a", "b"), 2024)$status, "not_aggregable")
})

test_that("a share without a published estimate is rebuilt from its counts", {
  # LAUS publishes no U.S. rate, but unemployment and the labor force sum over the states.
  d <- long(c("us", "us"), c("unemployed", "labor_force"), c(5, 100))
  r <- aggregate_entity(recipe(stat_type = "share", numerator = "unemployed", denominator = "labor_force",
                               published_var = "rate", scale = "100"), d, "us", 2024)
  expect_equal(r$value, 5)
})

test_that("constant dollars keep nominal values and flag years the price index does not cover", {
  assign("price_index_r_cpi_u_rs", data.frame(year = c(2000, 2024), index = c(100, 150)), envir = memo)
  on.exit(rm("price_index_r_cpi_u_rs", envir = memo))
  res <- data.frame(value = c(100, 100), moe = c(10, 10), period_end = c(2000L, 1970L), status = "ok", method = "")
  out <- apply_inflation(res, list(dollars = "period_end"), list(dollar_year = "2024", price_index = "r_cpi_u_rs"))
  expect_equal(out$value, c(150, NA))
  expect_equal(out$value_nominal, c(100, 100))
  expect_equal(out$status, c("ok", "unavailable"))
  expect_equal(apply_inflation(res, list(dollars = "period_end"), list(), adjust = FALSE)$value, c(100, 100))
})

test_that("ACS special values become statuses, never numbers", {
  d <- acs_decode(c("100", "-666666666", "-888888888", "250001"),
                  c("10", "-222222222", "-888888888", "-333333333"),
                  c(NA, NA, NA, "250,000+"))
  expect_equal(d$status, c("ok", "insufficient_sample", "not_applicable", "open_interval"))
  expect_true(is.na(d$estimate[2]))
  expect_equal(d$estimate[4], 250000)
  expect_equal(d$bound[4], "lower")
})

test_that("ACS tables come back in the provider's long form", {
  d <- acs_table(2024, "B01003", "state")
  expect_true(all(c("geo", "name", "variable", "estimate", "moe", "status") %in% names(d)))
  expect_equal(d$name[d$geo == "state:18"], "Indiana")
})
