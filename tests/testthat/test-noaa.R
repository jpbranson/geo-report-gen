test_that("NOAA damage strings become dollars", {
  expect_equal(noaa_dollars(c("10.00K", "1.5M", "2B", "0.00K", "300", "", NA, "5x")), c(1e4, 1.5e6, 2e9, 0, 300, 0, 0, 0))
})

test_that("NOAA zone events reach counties in equal shares and states count each event once", {
  real <- list(noaa_events = noaa_events, noaa_event_counties = noaa_event_counties)
  on.exit(for (n in names(real)) assign(n, real[[n]], envir = globalenv()))
  events <- function(unmatched) {
    e <- data.frame(state = "10", type = c("C", "C", "Z", "Z"), code = c(1, 5, 1, 9),
                    deaths = c(2, 0, 4, 1), damage = c(1000, 500, 4000, 100))
    if (unmatched) e else e[-4, ]
  }
  assign("noaa_events", function(year) events(year == 2001), envir = globalenv())
  assign("noaa_event_counties", function(year) data.frame(event = c(1, 2, 3, 3), county = c("10001", "10005", "10001", "10003"),
                                                          share = c(1, 1, .5, .5)), envir = globalenv())
  pieces <- function(...) {
    key <- c(...)
    data.frame(key = key, type = sub(":.*$", "", key), geoid = sub("^[^:]*:", "", key))
  }
  value <- function(v, key, variable) v$estimate[v$geo == key & v$variable == variable]
  matched <- noaa_year_values(2000, pieces("county:10001", "county:10003", "state:10", "county:09110"), 2024)
  expect_equal(value(matched, "county:10001", c("EVENTS")), 2)
  expect_equal(value(matched, "county:10001", "DEATHS"), 4)
  expect_equal(value(matched, "county:10003", "DAMAGE"), 2000)
  expect_equal(value(matched, "state:10", "EVENTS"), 3)
  expect_equal(value(matched, "state:10", "DEATHS"), 6)
  expect_true(all(matched$status[matched$geo == "county:09110"] == "unavailable"))
  expect_match(matched$note[matched$geo == "county:09110"][1], "Connecticut")
  short <- noaa_year_values(2001, pieces("county:10001", "state:10"), 2024)
  expect_equal(short$status[short$geo == "county:10001"], rep("unavailable", 3))
  expect_match(short$note[short$geo == "county:10001"][1], "95%")
  expect_equal(value(short, "state:10", "EVENTS"), 4)
  expect_equal(value(short, "state:10", "DEATHS"), 7)
})

test_that("NOAA years are complete files and series follow event-type coverage", {
  real <- noaa_files
  on.exit(assign("noaa_files", real, envir = globalenv()))
  assign("noaa_files", function() data.frame(year = c(1949, 1950, 2024, 2025, 2026),
    created = c("20200101", "20260323", "20260728", "20260201", "20260918"), file = ""), envir = globalenv())
  expect_equal(noaa_years(), c(1950, 2024))
  expect_equal(unique(noaa_label(c(1950, 1954, 1955, 1995, 1996, 2025))),
               c("NOAA Storm Events, tornadoes only", "NOAA Storm Events, tornadoes, thunderstorm wind and hail only", "NOAA Storm Events, all event types"))
  expect_equal(get_provider("noaa_storm_events")$periods(list(history_start = 2000), list()), 2024)
})
