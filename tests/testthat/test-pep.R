test_that("PEP components exist only for the years and areas that have them", {
  real <- pep_long
  on.exit(assign("pep_long", real, envir = globalenv()))
  assign("pep_long", function() data.frame(key = "county:10001", year = 2020:2021, population = c(100, 110), population_prior = c(NA, 100),
    population_avg = c(NA, 105), population_change = c(NA, 10), natural_change = c(NA, 2), domestic_migration = c(NA, 5),
    international_migration = c(NA, 3), series = "s"), envir = globalenv())
  pieces <- data.frame(key = "county:10001", type = "county", geoid = "10001")
  v <- get_provider("census_pep")$fetch(c("population", "natural_change"), pieces, 2020:2021)
  expect_equal(v$estimate[v$variable == "population"], c(100, 110))
  expect_equal(v$period[v$variable == "natural_change"], "2021")
})

test_that("PEP states add up to the nation, regions and divisions, components included", {
  states <- data.frame(key = c("state:10", "state:24"), year = 2021L, population = c(100, 200), population_prior = c(90, 190),
    population_avg = c(95, 195), population_change = c(10, 10), natural_change = c(1, 2), domestic_migration = c(3, 4),
    international_migration = c(5, 6), series = "s")
  long <- add_state_aggregates(states)
  us <- long[long$key == "nation:US", ]
  expect_equal(us$population, 300)
  expect_equal(us$domestic_migration, 7)
  expect_true(all(c("region:3", "division:5") %in% long$key))
})
