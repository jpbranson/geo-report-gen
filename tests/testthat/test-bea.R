test_that("BEA earnings groups add their lines and are withheld when any line is", {
  real <- bea_table
  on.exit(assign("bea_table", real, envir = globalenv()))
  keys <- c("county:10001", "county:10003", "state:10")
  table <- function(rows) {   # one column, 2001: the values of each line for the three areas
    do.call(rbind, lapply(names(rows), function(l) data.frame(LineCode = l, Description = "", Unit = "", key = keys, `2001` = rows[[l]], check.names = FALSE)))
  }
  industries <- unique(unlist(bea_earnings_groups))
  five_n <- stats::setNames(rep(list(c("2", "3", "5")), length(industries)), industries)
  five_n[["35"]] <- c("50", "60", "110")
  five_n[["81"]] <- c("5", "6", "11")
  five_n[["100"]] <- c("1", "(D)", "3")          # forestry and fishing withheld for the second county
  tables <- list(
    CAINC1 = table(list(`1` = c("100", "200", "300"), `2` = c("10", "20", "30"), `3` = c("1", "2", "3"))),
    CAINC30 = table(list(`10` = c("100", "200", "300"), `50` = c("10", "20", "30"), `60` = c("1", "2", "3"), `100` = c("10", "20", "30"),
                         `180` = c("50", "60", "110"))),
    CAINC5N = table(five_n))
  assign("bea_table", function(t) tables[[t]], envir = globalenv())
  long <- bea_income_compute()
  value <- function(key, variable) long$value[long$key == key & long$variable == variable]
  flag <- function(key, variable) long$flag[long$key == key & long$variable == variable]
  expect_equal(value("county:10001", "EARN_NATURAL"), 3000)          # lines 100 + 200, in dollars
  expect_true(is.na(value("county:10003", "EARN_NATURAL")))
  expect_equal(flag("county:10003", "EARN_NATURAL"), "(D)")
  expect_equal(value("county:10003", "EARN_FARM"), 6000)
  expect_equal(value("county:10001", "INCOME_MAINTENANCE"), 1000)
  expect_equal(value("county:10001", "POPULATION_30"), 10)           # persons, not thousands
  expect_equal(value("region:3", "EARN_FARM"), 11000)                # Delaware only in this table
})

test_that("BEA region sums are withheld when any state is", {
  states <- data.frame(key = c("state:10", "state:24"), variable = "EARN_FARM", year = 2001L, value = c(5, NA), flag = c("", "(D)"))
  sums <- bea_sum_regions(states, "EARN_FARM")
  expect_true(all(is.na(sums$value)))
  expect_equal(unique(sums$flag), "(D)")
  expect_equal(sort(sums$key), c("division:5", "region:3"))
})
