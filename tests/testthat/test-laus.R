test_that("LAUS population sums states for regions and the nation; rates are ratios of sums", {
  real <- laus_annual
  on.exit(assign("laus_annual", real, envir = globalenv()))
  # two states (Delaware 10 and Maryland 24, both South Atlantic) for 2024: labor force, employed, population
  series <- function(state, measure, value) data.frame(series_id = paste0("LAU", laus_area_code("state", state), measure), year = 2024L, value = value, footnote = "")
  assign("laus_annual", function(file) rbind(series("10", "06", 500), series("10", "05", 480), series("10", "09", 800),
                                             series("24", "06", 3000), series("24", "05", 2900), series("24", "09", 5000)), envir = globalenv())
  pieces <- data.frame(key = c("division:5", "state:10"), type = c("division", "state"), geoid = c("5", "10"))
  v <- laus_fetch(c("labor_force", "employed", "population"), pieces, 2024L)
  expect_equal(v$estimate[v$geo == "division:5" & v$variable == "population"], 5800)
  expect_equal(v$estimate[v$geo == "state:10" & v$variable == "labor_force"], 500)
  st <- resolve_settings()
  area <- entity("us", "study", "us", data.frame(key = "nation:US", type = "nation", geoid = "US", name = "us", pop = NA_real_))
  states <- state_table()
  nation_states <- states$state[states$in_nation == "TRUE"]
  assign("laus_annual", function(file) do.call(rbind, lapply(nation_states, function(s) rbind(series(s, "06", 100), series(s, "09", 160)))), envir = globalenv())
  r <- compute_metric("labor_force_participation_rate_laus", list(area), st, periods = 2024L)
  expect_equal(r$value, 100 * 100 / 160)
})
