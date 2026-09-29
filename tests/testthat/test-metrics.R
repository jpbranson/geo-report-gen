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
  census <- data.frame(value = 100, moe = NA_real_, period_end = 2001L, status = "ok", method = "")  # income of the year before
  expect_equal(apply_inflation(census, list(dollars = "prior_year"), list(dollar_year = "2024", price_index = "r_cpi_u_rs"))$value, 150)
})

test_that("NHGIS census years: areas match by current codes; missing and untabulated values say why", {
  # The fixture is a made-up extract in NHGIS's file layout (the NHGIS terms forbid
  # redistributing real extracts); the tables' census years are real metadata.
  d <- nhgis_values()
  expect_setequal(unique(d$key), c("nation:US", "state:10", "county:10001", "county:10003", "place:1021200"))
  place <- function(geoid, name) data.frame(key = paste0("place:", geoid), type = "place", geoid = geoid, name = name, pop = NA_real_)
  dover <- entity("dover", "study", "Dover city, Delaware", place("1021200", "Dover city, Delaware"))
  st <- resolve_settings()
  r <- compute_metric("poverty_rate_census", list(dover), st)
  expect_equal(r$period, c("1970", "1980", "1990", "2000"))
  expect_equal(r$period_label[2], "1980 census")
  expect_equal(r$value, c(NA, 15, 14, 15))
  expect_match(r$method[1], "did not exist then")                                    # no 1970 row for Dover
  counties <- entity("kent-nc", "study", "Kent and New Castle counties", data.frame(
    key = c("county:10001", "county:10003"), type = "county", geoid = c("10001", "10003"),
    name = c("Kent County, Delaware", "New Castle County, Delaware"), pop = NA_real_))
  expect_equal(compute_metric("poverty_rate_census", list(counties), st, periods = 1990L)$value, 100 * (12 + 36) / (100 + 400))
  income <- compute_metric("median_household_income_census", list(dover), st, constant_dollars = FALSE)
  expect_equal(income$period, c("1980", "1990", "2000"))                             # B79 starts in 1980
  expect_equal(income$value, c(15000, 28000, NA))
  expect_match(income$method[3], "not tabulated")
})

test_that("NHGIS population: counties from 1790, places from 1970; a table missing at a level says so", {
  county <- entity("kent", "study", "Kent County, Delaware", data.frame(key = "county:10001", type = "county", geoid = "10001",
                                                                       name = "Kent County, Delaware", pop = NA_real_))
  dover <- entity("dover", "study", "Dover city, Delaware", data.frame(key = "place:1021200", type = "place", geoid = "1021200",
                                                                      name = "Dover city, Delaware", pop = NA_real_))
  st <- resolve_settings()
  k <- compute_metric("pop_census_nhgis", list(county), st, periods = c(1790L, 1810L, 1970L))  # A00 until 1960, then AV0
  expect_equal(k$value, c(1000, NA, 81000))
  expect_match(k$method[2], "did not exist then")
  d <- compute_metric("pop_census_nhgis", list(dover), st, periods = c(1790L, 1980L))
  expect_equal(d$status, c("not_applicable", "ok"))
  expect_match(d$method[1], "only for the nation, states and counties")
  expect_equal(d$value[2], 23500)
})

test_that("NHGIS County Business Patterns 1970-1997: withheld totals, missing files, years without payroll", {
  # Made-up extract in NHGIS's dataset layout; one file per dataset, year and level.
  area <- function(id, key, type) entity(id, "study", id, data.frame(key = key, type = type, geoid = sub("^.*:", "", key), name = id, pop = NA_real_))
  kent <- area("kent", "county:10001", "county")
  nc <- area("nc", "county:10003", "county")
  us <- area("us", "nation:US", "nation")
  st <- resolve_settings()
  jobs <- compute_metric("employment_cbp_sic", list(kent, nc), st, periods = c(1970L, 1976L))
  expect_equal(jobs$value[jobs$entity_id == "kent"], c(18000, 20000))
  expect_equal(jobs$status[jobs$entity_id == "nc" & jobs$period == "1976"], "suppressed")   # flagged total
  expect_match(jobs$method[jobs$entity_id == "nc" & jobs$period == "1976"], "withheld")
  expect_equal(compute_metric("establishments_cbp_sic", list(nc), st, periods = 1976L)$value, 7000)  # always published
  pay <- compute_metric("annual_payroll_per_employee_cbp_sic", list(kent), st, periods = c(1970L, 1976L), constant_dollars = FALSE)
  expect_equal(pay$value, c(NA, 200000000 / 20000))
  expect_match(pay$method[1], "no annual payroll")
  nation <- compute_metric("employment_cbp_sic", list(us), st, periods = c(1976L, 1977L))
  expect_equal(nation$status, c("unavailable", "ok"))
  expect_match(nation$method[1], "national files start in 1977")
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

test_that("FBI: an agency's year with under a quarter of its usual offenses counts as not reported", {
  months <- function(year, per_month) data.frame(year = year, offenses = per_month, population = 1000, covered = 1000)[rep(1, 12), ]
  s <- rbind(months(2022, 10), months(2023, 0.5), months(2024, 9))                  # 120, 6 and 108 offenses
  expect_equal(fbi_annual(s, agency = TRUE)$offenses, c(120, NA, 108))
  expect_equal(fbi_annual(s, agency = FALSE)$offenses, c(120, 6, 108))              # states and the nation are not screened
  small <- rbind(months(2022, 1), months(2023, 0), months(2024, 1))                 # a usual year of 12 is too few to judge
  expect_equal(fbi_annual(small, agency = TRUE)$offenses, c(12, 0, 12))
})

test_that("FBI: a county adds up every agency listed in it, dividing departments that serve several counties", {
  expect_equal(fbi_county_key(c("St. Joseph County", "ST JOSEPH", "LaPorte County", "LA PORTE", "Capitol Planning Region", "St. Louis city")),
               c("stjoseph", "stjoseph", "laporte", "laporte", "capitolplanningregion", "stlouiscity"))
  a <- fbi_county_agencies("10001", "Kent County, Delaware")
  expect_equal(nrow(a), 22)                                                         # towns, state police post, campus, state agencies
  parts <- place_parts("1047420", 2024)                                             # Milford: Kent and Sussex
  expect_equal(a$share[a$agency == "Milford Police Department"], parts$pop[parts$county == "10001"] / sum(parts$pop))
  kent <- entity("kent", "study", "Kent County, Delaware", data.frame(key = "county:10001", type = "county", geoid = "10001",
                                                                     name = "Kent County, Delaware", pop = NA_real_))
  expect_equal(compute_metric("violent_crime_rate_fbi", list(kent), resolve_settings(), periods = 2023L)$value, 460.4321, tolerance = 1e-6)
  # A year counts only when the agencies that reported every month serve 75% of the residents:
  # Frederica (1,111 residents) missed 2016, leaving Felton (1,361) alone.
  y <- fbi_county_annual(a[a$agency %in% c("Frederica Police Department", "Felton Police Department"), ], "V")
  expect_true(is.na(y$offenses[y$year == 2016]))
  expect_false(is.na(y$offenses[y$year == 2017]))
  expect_null(fbi_county_annual(a[a$agency %in% c("Park Rangers", "Fish and Wildlife"), ], "V"))  # no residents
  # Kent County plus Milford's part in Sussex County counts Milford's department once.
  kent_milford <- entity("u", "study", "Kent County and Milford", data.frame(
    key = c("county:10001", "place_part:1047420-10005"), type = c("county", "place_part"), geoid = c("10001", "1047420-10005"),
    name = c("Kent County, Delaware", "Sussex County (part), Milford city, Delaware"), pop = NA_real_))
  whole <- a
  whole$share[whole$agency == "Milford Police Department"] <- 1
  y <- fbi_county_annual(whole, "V")
  expect_equal(compute_metric("violent_crime_rate_fbi", list(kent_milford), resolve_settings(), periods = 2023L)$value,
               1e5 * y$offenses[y$year == 2023] / y$covered[y$year == 2023])
})

test_that("LODES: areas sum their census blocks; state-years without job data and the nation are unavailable", {
  # Real Delaware 2023 rows for a few blocks in Dover, rural Kent County and Wilmington, plus
  # crosswalk rows of Magnolia, a town without jobs or residents in the fixture.
  area <- function(id, keys) entity(id, "study", id, data.frame(key = keys, type = sub(":.*$", "", keys),
                                                                geoid = sub("^[^:]*:", "", keys), name = id, pop = NA_real_))
  dover <- area("dover", "place:1021200")
  st <- resolve_settings()
  jobs <- function(...) compute_metric("jobs_total_lodes", list(...), st, periods = 2023L)
  expect_equal(jobs(dover)$value, 263)
  expect_equal(jobs(area("kent", "county:10001"), area("de", "state:10"))$value, c(263 + 43, 263 + 43 + 14))
  expect_equal(jobs(area("part", "place_part:1021200-10001"))$value, 263)                  # Dover lies in Kent County
  expect_equal(jobs(area("u", c("place:1021200", "county:10003")))$value, 263 + 14)        # a union of pieces
  expect_equal(jobs(area("magnolia", "place:1044430"))[, c("value", "status")], data.frame(value = 0, status = "ok"))
  none <- jobs(area("nowhere", "place:1099999"))
  expect_equal(none$status, "unavailable")
  expect_match(none$method, "not an area in the LODES crosswalk")
  expect_equal(compute_metric("jobs_to_employed_residents_ratio_lodes", list(dover), st, periods = 2023L)$value, 100 * 263 / 405)
  expect_equal(compute_metric("jobs_low_earnings_share_lodes", list(dover), st, periods = 2023L)$value, 100 * 82 / 263)
  # Washington, DC, supplied no job data before 2010: nothing is downloaded (the tests run offline).
  dc <- area("dc", "county:11001")
  expect_equal(compute_metric("jobs_total_lodes", list(dc), st, periods = 2005L)$status, "unavailable")
  res <- compute_metric("employed_residents_lodes", list(dc), st, periods = 2005L)
  expect_match(res$method, "no job data from District of Columbia for 2005 \\(only residents working in other states")
  us <- jobs(area("us", "nation:US"))
  expect_equal(us$status, "not_applicable")
  expect_match(us$method, "does not publish data for the nation")
})

test_that("QCEW: counties, states and the nation; regions sum states; withheld and missing rows are not zeros", {
  # Real rows of the 2024 and 2023 files: Delaware, Loving County (Texas), Connecticut,
  # the nation and every state's total.
  area <- function(id, keys) entity(id, "study", id, data.frame(key = keys, type = sub(":.*$", "", keys),
                                                                geoid = sub("^[^:]*:", "", keys), name = id, pop = NA_real_))
  st <- resolve_settings()
  jobs <- function(e, year = 2024L) compute_metric("covered_employment_qcew", list(e), st, periods = year)
  expect_equal(jobs(area("kent", "county:10001"))$value, 71071)
  expect_equal(jobs(area("ks", c("county:10001", "county:10005")))$value, 71071 + 94273)
  expect_equal(jobs(area("de", "state:10"))$value, 477336)
  expect_equal(jobs(area("us", "nation:US"))$value, 154990441)
  expect_equal(jobs(area("south", "region:3"))$value, 58068944)                           # 16 states and DC
  pay <- compute_metric("average_annual_pay_qcew", list(area("kent", "county:10001")), st, periods = 2024L, constant_dollars = FALSE)
  expect_equal(pay$value, 4084038467 / 71071)
  private <- compute_metric("average_annual_pay_private_qcew", list(area("kent", "county:10001")), st, periods = 2024L)
  expect_equal(private$status, "suppressed")                                              # flagged N in 2024
  expect_match(private$method, "withheld by BLS")
  # A row the file lacks is not a zero: Loving County has no private health care row.
  health <- compute_metric("jobs_health_share_qcew", list(area("loving", "county:48301")), st, periods = 2024L)
  expect_equal(health$status, "suppressed")
  expect_match(health$method, "or no such employers")
  # Connecticut's planning regions start in 2024.
  capitol <- area("capitol", "county:09110")
  expect_equal(jobs(capitol)$value, 522687)
  old <- jobs(capitol, 2023L)
  expect_equal(old$status, "unavailable")
  expect_match(old$method, "not in the QCEW files for 2023")
  expect_equal(jobs(area("dover", "place:1021200"))$status, "not_applicable")
})

test_that("BEA GDP: current dollars add up, chained dollars do not; withheld groups and Connecticut's switch", {
  # Real lines of the CAGDP1, CAGDP2 and CAINC1 files: Delaware, the South Atlantic states,
  # Connecticut and the nation.
  area <- function(id, keys) entity(id, "study", id, data.frame(key = keys, type = sub(":.*$", "", keys),
                                                                geoid = sub("^[^:]*:", "", keys), name = id, pop = NA_real_))
  st <- resolve_settings()
  gdp <- function(m, ...) compute_metric(m, list(...), st, periods = 2024L, constant_dollars = FALSE)
  kent <- area("kent", "county:10001")
  both <- area("ks", c("county:10001", "county:10005"))
  sa <- area("sa", "division:5")
  g <- gdp("gdp_current_dollars_bea", kent, both, sa, area("us", "nation:US"))
  expect_equal(g$value, 1000 * c(11652246, 11652246 + 23355694, 5519008299, 29298013000))   # thousands of dollars
  r <- gdp("real_gdp_index_bea", kent, both, sa)
  expect_equal(r$value[1], 118.816)                                                          # 2017 = 100
  expect_equal(r$status[2:3], c("not_aggregable", "not_aggregable"))
  expect_match(r$method[3], "cannot be combined")
  expect_equal(gdp("gdp_per_capita_bea", kent)$value, 1000 * 11652246 / 192690)
  expect_equal(gdp("gdp_government_share_bea", kent)$value, 100 * 3024989 / 11652246)
  m <- gdp("gdp_manufacturing_share_bea", kent)
  expect_equal(m$status, "suppressed")                                                       # (D) in 2024
  expect_match(m$method, "withheld by BEA")
  capitol <- area("capitol", "county:09110")
  ct <- compute_metric("gdp_current_dollars_bea", list(capitol), st, periods = c(2023L, 2024L), constant_dollars = FALSE)
  expect_equal(ct$status, c("unavailable", "ok"))                                            # planning regions in 2024 only
  expect_equal(ct$value[2], 1000 * 110914256)
})

test_that("Nonemployer Statistics: flagged cells are withheld, missing industries are zero, regions sum states", {
  # Real rows of the 2023, 2021 and 2008 county, state and U.S. files: Delaware, Loving County
  # (Texas), Connecticut, every state's total and the nation.
  area <- function(id, keys) entity(id, "study", id, data.frame(key = keys, type = sub(":.*$", "", keys),
                                                                geoid = sub("^[^:]*:", "", keys), name = id, pop = NA_real_))
  st <- resolve_settings()
  nes <- function(m, ..., year = 2023L) compute_metric(m, list(...), st, periods = year, constant_dollars = FALSE)
  kent <- area("kent", "county:10001")
  n <- nes("nonemployer_establishments_nes", kent, area("ks", c("county:10001", "county:10005")), area("de", "state:10"),
           area("us", "nation:US"), area("south", "region:3"))
  expect_equal(n$value, c(17053, 17053 + 23077, 93022, 30427808, 12949620))
  expect_equal(nes("nonemployer_receipts_per_business_nes", kent)$value, 1000 * 1886954 / 17053)
  expect_equal(nes("nonemployers_per_1000_residents_nes", kent)$value, 1000 * 17053 / 190123)   # BEA population
  expect_equal(nes("nonemployer_mining_share_nes", kent)[, c("value", "status")], data.frame(value = 0, status = "ok"))  # no row
  expect_equal(nes("childcare_nonemployer_establishments_nes", area("loving", "county:48301"))$value, 0)
  d <- nes("nonemployer_mining_share_nes", kent, year = 2008L)
  expect_equal(d$status, "suppressed")                                                        # flagged D in 2008
  expect_match(d$method, "avoid disclosing")
  capitol <- nes("nonemployer_establishments_nes", area("capitol", "county:09110"), year = c(2021L, 2023L))
  expect_equal(capitol$status, c("unavailable", "ok"))                                        # planning regions from 2022
  expect_equal(capitol$value[2], 76682)
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
