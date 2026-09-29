# CDC PLACES: model-based estimates of adult health measures (BRFSS survey data, multilevel
# regression and poststratification) for counties, places, census tracts and ZCTAs. Only the
# latest release is used: CDC cautions that the model cannot track local change over time, and
# inputs and methods change with each release. Values are crude prevalence; age-adjusted values
# exist only for counties and places and cannot be combined.
#
# For each measure (e.g. DIABETES) the provider returns three variables:
#   DIABETES    published crude prevalence (%), with a 90% margin of error converted from
#               CDC's 95% interval (half its width x 1.645 / 1.96)
#   DIABETES_N  estimated adults with the condition (prevalence x adults / 100)
#   ADULTS      adults 18 and over, as published with the estimates
# As CDC advises for groups of areas, a combined area is the sum of DIABETES_N over the sum of
# ADULTS. PLACES publishes no state values, so a state is the sum of its counties (when every
# county has a value); the nation is the United States row of the county table.

places_tables <- c(county = "swc5-untb", place = "eav7-hnsx", tract = "cwsq-ngmh", zcta = "qnzd-25i4")
places_year <- 2023L     # BRFSS year of the 2025 release (its five biennial measures are from 2022)
places_vintage <- 2024L  # county list that a state sum must cover (2020 Census geography)

# One measure from one table: nationwide (counties with the U.S. row, ZCTAs) or for one state
# (places, tracts). Each request returns a few thousand to about 30,000 rows.
places_raw <- function(table, measure, state = "") {
  file <- paste0(measure, if (nzchar(state)) paste0("-", state), ".parquet")
  cached(cache_path("raw", "cdc_places", places_tables[[table]], file), source = "cdc_places", compute = function() {
    where <- sprintf("measureid='%s' AND datavaluetypeid='CrdPrv'", measure)
    if (nzchar(state)) where <- paste0(where, sprintf(" AND starts_with(locationid,'%s')", state))
    resp <- http_perform(http_request(paste0("https://data.cdc.gov/resource/", places_tables[[table]], ".csv"), "cdc_places",
      query = list(`$select` = "locationid,year,data_value,low_confidence_limit,high_confidence_limit,totalpop18plus",
                   `$where` = where, `$limit` = "50000")))
    check_status(resp, paste("CDC PLACES", table, measure))
    x <- utils::read.csv(text = httr2::resp_body_string(resp), colClasses = "character")
    if (nrow(x) == 50000) stop("CDC PLACES returned 50,000 rows for ", measure, " (", table, "); the query needs paging.")
    x
  })
}

# Long rows for one measure: the published rate, the estimated number of adults, and adults.
places_rows <- function(x, type, measure) {
  if (any(x$year != places_year)) {
    stop("CDC PLACES measure ", measure, " is from BRFSS ", x$year[1], ", not ", places_year, " (see places_year).", call. = FALSE)
  }
  keys <- if (type == "nation") rep("nation:US", nrow(x)) else sprintf("%s:%s", type, x$locationid)
  num <- function(v) suppressWarnings(as.numeric(v))
  rate <- num(x$data_value)
  moe <- (num(x$high_confidence_limit) - num(x$low_confidence_limit)) / 2 * 1.645 / 1.96
  adults <- num(x$totalpop18plus)
  status <- ifelse(is.na(rate), "suppressed", "ok")
  data.frame(geo = rep(keys, 3), variable = rep(c(measure, paste0(measure, "_N"), "ADULTS"), each = length(keys)),
             estimate = c(rate, rate * adults / 100, adults), moe = c(moe, moe * adults / 100, rep(0, length(keys))),
             status = c(status, status, rep("ok", length(keys))), stringsAsFactors = FALSE)
}

# A state is the sum of its counties, computed only when every county is in the table. Counties
# suppressed for having fewer than 50 people are left out of both sums. The model errors of
# counties cannot be combined, so the sum has no margin of error.
places_states <- function(counties, measure, states) {
  all <- geo_catalog("county", places_vintage)
  do.call(rbind, lapply(states, function(st) {
    mine <- counties[startsWith(counties$locationid, st), , drop = FALSE]
    if (!nrow(mine) || nrow(mine) < sum(startsWith(all$geoid, st))) return(NULL)
    rate <- suppressWarnings(as.numeric(mine$data_value))
    adults <- as.numeric(mine$totalpop18plus)[!is.na(rate)]
    rate <- rate[!is.na(rate)]
    data.frame(geo = paste0("state:", st), variable = c(paste0(measure, "_N"), "ADULTS"),
               estimate = c(sum(rate * adults / 100), sum(adults)), moe = c(NA, 0), status = "ok", stringsAsFactors = FALSE)
  }))
}

# Why a requested area has no value.
places_notes <- c(ok = "", suppressed = "suppressed by CDC for areas with fewer than 50 people",
                  unavailable = paste("no PLACES estimate for this area in this release (Kentucky and Pennsylvania lack most",
                                      "measures; the social needs questions were asked in only some states)"))

places_fetch <- function(variables, pieces, periods, options = list()) {
  types <- unique(pieces$type)
  rows <- list()
  for (m in unique(sub("_N$", "", setdiff(variables, "ADULTS")))) {
    if (any(types %in% c("nation", "state", "county"))) {
      x <- places_raw("county", m)
      us <- x$locationid == "59"
      rows <- c(rows, list(places_rows(x[us, ], "nation", m), places_rows(x[!us, ], "county", m),
                           places_states(x[!us, ], m, pieces$geoid[pieces$type == "state"])))
    }
    if ("zcta" %in% types) rows <- c(rows, list(places_rows(places_raw("zcta", m), "zcta", m)))
    for (type in intersect(types, c("place", "tract"))) {
      for (st in unique(substr(pieces$geoid[pieces$type == type], 1, 2))) {
        rows <- c(rows, list(places_rows(places_raw(type, m, st), type, m)))
      }
    }
  }
  d <- do.call(rbind, rows)
  d <- d[d$geo %in% pieces$key, , drop = FALSE]
  absent <- setdiff(pieces$key, d$geo)
  if (length(absent)) {
    d <- rbind(d, data.frame(geo = rep(absent, each = length(variables)), variable = variables, estimate = NA_real_,
                             moe = NA_real_, status = "unavailable", stringsAsFactors = FALSE))
  }
  data.frame(d, name = "", bound = NA_character_, note = unname(places_notes[d$status]), period = as.character(places_year),
             period_start = places_year, period_end = places_year, source_id = "cdc_places", stringsAsFactors = FALSE)
}

register_provider("cdc_places", list(
  name = "CDC PLACES: Local Data for Better Health (2025 release; model-based estimates)",
  geo_types = c("nation", "state", "county", "place", "tract", "zcta"),
  fetch = places_fetch,
  periods = function(settings, recipe) places_year,
  period_label = function(period) as.character(period),
  period_kind = "annual",
  combine_moe = FALSE,
  series = "PLACES model-based estimates (2025 release)",
  availability_note = paste("PLACES publishes counties, places, census tracts and ZCTAs (a state value here is the sum of its counties);",
                            "Kentucky and Pennsylvania lack most measures in this release, and questions on social needs were asked in only some states.")))
