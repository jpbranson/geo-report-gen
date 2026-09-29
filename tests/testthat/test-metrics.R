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

test_that("periods before a metric's first comparable period are never computed", {
  st <- resolve_settings()
  # 5-year releases every 5 years back to 2009, from the first period starting in or after history_start
  expect_equal(metric_periods(recipe_for("pop_total_acs"), st), c(2009L, 2014L, 2019L, 2024L))
  expect_equal(metric_periods(recipe_for("veteran_share_acs"), st), c(2014L, 2019L, 2024L))           # 2006-2010
  expect_equal(metric_periods(recipe_for("uninsured_rate_children_acs"), st), c(2019L, 2024L))        # 2013-2017
  expect_equal(metric_periods(recipe_for("unemployment_rate_laus"), st), 1990:2025)                   # annual, 1990
})

test_that("model-based estimates keep a single area's margin of error; combined areas get none", {
  counties <- function(geoids) data.frame(key = paste0("county:", geoids), type = "county", geoid = geoids,
                                          name = "", pop = NA_real_)
  kent <- entity("kent", "study", "Kent County", counties("10001"))
  both <- entity("both", "study", "Kent and New Castle", counties(c("10001", "10003")))
  r <- compute_metric("poverty_rate_saipe", list(kent, both), resolve_settings(), periods = 2024L)
  expect_equal(r$value[r$entity_id == "kent"], 10.2)                               # published rate
  expect_equal(r$moe[r$entity_id == "kent"], 2.1)
  expect_equal(r$value[r$entity_id == "both"], 100 * (19147 + 58815) / (187036 + 572439))  # from summed counts
  expect_true(is.na(r$moe[r$entity_id == "both"]))
  expect_match(r$method[r$entity_id == "both"], "cannot be combined")
})

test_that("PLACES: published county values, states summed from counties, the U.S. row", {
  counties <- function(geoids) data.frame(key = paste0("county:", geoids), type = "county", geoid = geoids,
                                          name = "", pop = NA_real_)
  kent <- entity("kent", "study", "Kent County", counties("10001"))
  both <- entity("both", "study", "Kent and New Castle", counties(c("10001", "10003")))
  de <- entity("de", "benchmark", "Delaware", data.frame(key = "state:10", type = "state", geoid = "10", name = "", pop = NA_real_))
  us <- entity("us", "benchmark", "United States", data.frame(key = "nation:US", type = "nation", geoid = "US", name = "", pop = NA_real_))
  r <- compute_metric("diabetes_prevalence_places", list(kent, both, de, us), resolve_settings())
  expect_equal(r$period, rep("2023", 4))
  expect_equal(r$value[r$entity_id == "kent"], 14.3)                                   # published crude prevalence
  expect_equal(r$moe[r$entity_id == "kent"], (16.2 - 12.4) / 2 * 1.645 / 1.96)          # 95% interval -> 90% MOE
  expect_equal(r$value[r$entity_id == "both"], (14.3 * 146800 + 12.2 * 456332) / (146800 + 456332))
  expect_true(is.na(r$moe[r$entity_id == "both"]))
  expect_equal(r$value[r$entity_id == "de"], (14.3 * 146800 + 12.2 * 456332 + 14.2 * 216820) / (146800 + 456332 + 216820))
  expect_true(is.na(r$moe[r$entity_id == "de"]))
  expect_equal(r$value[r$entity_id == "us"], 12.0)
  # Kentucky has no county estimates for 2023 measures: no state value, and the reason says why.
  ky <- entity("ky", "benchmark", "Kentucky", data.frame(key = "state:21", type = "state", geoid = "21", name = "", pop = NA_real_))
  k <- compute_metric("diabetes_prevalence_places", list(ky), resolve_settings())
  expect_equal(k$status, "unavailable")
  expect_match(k$method, "no PLACES estimate for this area")
})

test_that("CBP: withheld cells and missing rows follow the publication rules of their year", {
  loving <- data.frame(key = "county:48301", type = "county", geoid = "48301", stringsAsFactors = FALSE)
  d <- cbp_fetch(c("ESTAB_21", "EMP_21", "EMP_62"), loving, 2016)
  expect_equal(d$estimate[d$variable == "ESTAB_21"], 2)                  # establishments are always published
  expect_equal(d$status[d$variable == "EMP_21"], "suppressed")            # employment withheld (flag a)
  expect_match(d$note[d$variable == "EMP_21"], "withheld")
  expect_equal(d$estimate[d$variable == "EMP_62"], 0)                    # no row before 2017: no establishments
  d <- cbp_fetch("EMP_48-49", loving, 2023)
  expect_equal(d$status, "suppressed")                                    # no row from 2017: fewer than 3 or none
  expect_match(d$note, "fewer than 3")
  us <- data.frame(key = "nation:US", type = "nation", geoid = "US", stringsAsFactors = FALSE)
  d <- cbp_fetch("EMP_00", us, 2014)                                      # flag r (revised) is a published value
  expect_equal(d$status, "ok")
  expect_equal(d$estimate, 121069944)
})

test_that("NRI: scores only for single counties; dollar values sum to combined areas and states", {
  counties <- function(geoids) data.frame(key = paste0("county:", geoids), type = "county", geoid = geoids,
                                          name = "", pop = NA_real_)
  kent <- entity("kent", "study", "Kent County", counties("10001"))
  both <- entity("both", "study", "Kent and New Castle", counties(c("10001", "10003")))
  de <- entity("de", "benchmark", "Delaware", data.frame(key = "state:10", type = "state", geoid = "10", name = "", pop = NA_real_))
  r <- compute_metric("nri_risk_score_nri", list(kent, both, de), resolve_settings())
  expect_equal(round(r$value[r$entity_id == "kent"], 2), 84.51)
  expect_equal(r$status[r$entity_id == "both"], "not_aggregable")
  expect_equal(r$status[r$entity_id == "de"], "not_applicable")                      # scores rank counties only
  expect_match(r$method[r$entity_id == "de"], "rank counties")
  e <- compute_metric("nri_eal_per_resident_nri", list(both, de), resolve_settings())
  expect_equal(e$value[e$entity_id == "both"], (55756476.459 + 202209273.318) / (181705 + 570089), tolerance = 1e-6)
  expect_equal(e$value[e$entity_id == "de"], (55756476.459 + 202209273.318 + 119301379.466) / (181705 + 570089 + 237214),
               tolerance = 1e-6)
})

test_that("Food Environment Atlas: published county values, rescaled rates, suppressed and missing counties", {
  county <- function(geoid) entity(geoid, "study", geoid, data.frame(key = paste0("county:", geoid), type = "county",
                                                                     geoid = geoid, name = "", pop = NA_real_))
  st <- resolve_settings()
  r <- compute_metric("grocery_stores_per_10k_fea", list(county("10001"), county("48301"), county("09110")), st)
  expect_equal(r$period, rep("2020", 3))                                                # the year in the Atlas code
  expect_equal(r$value[r$entity_id == "10001"], 1.41579047)                            # 0.1416 per 1,000 -> per 10,000
  expect_equal(r$status[r$entity_id == "48301"], "suppressed")                         # fewer than 3 stores
  expect_equal(r$status[r$entity_id == "09110"], "unavailable")                        # planning region: not in the Atlas
  expect_match(r$method[r$entity_id == "09110"], "Connecticut")
  both <- entity("both", "study", "Kent and Sussex", data.frame(key = c("county:10001", "county:10005"), type = "county",
                                                                geoid = c("10001", "10005"), name = "", pop = NA_real_))
  expect_equal(compute_metric("low_access_population_share_fea", list(both), st)$status, "not_aggregable")
})

test_that("EAVS: totals of election jurisdictions; a city splitting counties; no registration in North Dakota", {
  area <- function(type, geoid) entity(geoid, "study", geoid, data.frame(key = paste0(type, ":", geoid), type = type, geoid = geoid,
                                                                         name = "", pop = NA_real_))
  r <- compute_metric("active_registration_rate_eavs", list(area("county", "10001"), area("county", "29095"), area("state", "38"),
                                                            area("nation", "US")), resolve_settings(), periods = 2024L)
  expect_equal(r$value[r$entity_id == "10001"], 100 * 133534 / 140112)       # A1b / citizen voting-age population
  expect_equal(r$status[r$entity_id == "29095"], "unavailable")              # Kansas City's own jurisdiction splits Jackson County
  expect_equal(r$status[r$entity_id == "38"], "not_applicable")              # North Dakota has no voter registration
  expect_match(r$method[r$entity_id == "38"], "North Dakota")
  # The nation sums the states that have a total and their citizens: in this fixture Delaware and
  # Missouri (only Jackson County and Kansas City are in the file), not North Dakota.
  expect_equal(r$value[r$entity_id == "US"], 100 * (133534 + 411360 + 197476 + 255078 + 200980) / (764112 + 4685986))
  t <- compute_metric("voter_turnout_eavs", list(area("state", "38")), resolve_settings(), periods = 2024L)
  expect_equal(t$status, "ok")                                              # North Dakota reports its voters
})

test_that("Government finance: county governments for counties, city governments for places, states as sums", {
  area <- function(type, geoid) entity(geoid, "study", geoid, data.frame(key = paste0(type, ":", geoid), type = type, geoid = geoid,
                                                                         name = "", pop = NA_real_))
  st <- resolve_settings()
  r <- compute_metric("county_gov_property_tax_per_capita_govfin", list(area("county", "10001"), area("place", "1021200"),
                                                                        area("state", "10")), st, constant_dollars = FALSE)
  expect_equal(r$value[r$entity_id == "10001"], 1000 * 13844 / 183643)                  # $1,000 per resident
  expect_equal(r$status[r$entity_id == "1021200"], "not_applicable")                     # Dover is a city, not a county
  expect_equal(r$value[r$entity_id == "10"], 1000 * (13844 + 146474 + 84242) / (183643 + 561531 + 241635))
  c <- compute_metric("city_gov_property_tax_per_capita_govfin", list(area("county", "10001")), st)
  expect_match(c$method, "describe cities")
})

test_that("FBI: a city is its police department; states cover reporting agencies; no department, no value", {
  place <- function(geoid, name) entity(geoid, "study", name, data.frame(key = paste0("place:", geoid), type = "place", geoid = geoid,
                                                                         name = name, pop = NA_real_))
  de <- entity("de", "benchmark", "Delaware", data.frame(key = "state:10", type = "state", geoid = "10", name = "Delaware", pop = NA_real_))
  st <- resolve_settings()
  r <- compute_metric("violent_crime_rate_fbi", list(place("1021200", "Dover city, Delaware"), place("1099999", "Nowhere CDP, Delaware"), de),
                      st, periods = 2023L)
  expect_equal(r$value[r$entity_id == "1021200"], 1e5 * 381 / 38209)                  # Dover Police Department
  expect_equal(r$status[r$entity_id == "1099999"], "unavailable")
  expect_match(r$method[r$entity_id == "1099999"], "no city police department")
  expect_equal(r$value[r$entity_id == "de"], 1e5 * 4115 / 1031579, tolerance = 1e-6)     # covered population is a mean of months
  expect_equal(compute_metric("ucr_population_coverage_fbi", list(de), st, periods = 2023L)$value, 100 * 1031579 / 1031890, tolerance = 1e-6)
})

test_that("a value the source did not publish carries the source's reason", {
  d <- long("county:1", "ESTAB_00", NA, NA, "suppressed")
  d$note <- "fewer than 3 establishments or none"
  a <- aggregate_entity(recipe(numerator = "ESTAB_00"), d, "county:1", 2023)
  expect_equal(a$status, "suppressed")
  expect_equal(a$method, "fewer than 3 establishments or none")
})

test_that("ACS tables come back in the provider's long form", {
  d <- acs_table(2024, "B01003", "state")
  expect_true(all(c("geo", "name", "variable", "estimate", "moe", "status") %in% names(d)))
  expect_equal(d$name[d$geo == "state:18"], "Indiana")
})
