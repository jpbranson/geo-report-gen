# NOAA National Centers for Environmental Information, Storm Events Database (NWS Storm Data):
# severe weather events with their direct and indirect deaths and estimated property damage, by
# calendar year of the event, 1950 to the last complete year. Read from NCEI's yearly
# StormEvents_details files; their names carry the file's creation date, so the current names come
# from the directory listing (cached; --refresh noaa_storm_events reads it again).
#
# What an event is: one Storm Data record, which covers a county (CZ_TYPE C) or a National Weather
# Service public forecast zone (CZ_TYPE Z, typical of winter, heat, flood and fog events). A storm
# that crosses several counties or zones is several records. Marine zones (CZ_TYPE M, or Z under
# the water codes 85-99 in place of a state) are left out everywhere.
#
# Zone events reach counties through NWS's county-zone correlation file (weather.gov, current
# zones): a zone event counts as an event in each county of its zone, and its deaths and damage
# are split equally among those counties, so county values add up to the zone's total. A state
# has county values in a year only when at least 95% of its zone events match a current zone.
# Nation, region, division and state values need no zones: each event counts once, in the state
# NCEI records.
#
# Coverage changes over time, so a year belongs to one of three series: 1950-1954 tornadoes only;
# 1955-1995 tornadoes, thunderstorm wind and hail; from 1996 all event types (55 since 2007).
# Damage is the sum of estimates entered by forecasters in the dollars of the event year (K, M and
# B suffixes converted; blank means none entered), and is rough; it is not insured loss.
#
# Variables: EVENTS, DEATHS (direct plus indirect), DAMAGE (property, dollars).

noaa_base <- "https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles/"
noaa_zone_page <- "https://www.weather.gov/gis/ZoneCounty"
noaa_zone_dir <- "https://www.weather.gov/source/gis/Shapefiles/County/"
noaa_first_year <- 1950L
noaa_min_mapped <- 0.95
noaa_complete_after <- 60   # days after the year's end before its file counts as complete
noaa_county_successor <- c(`12025` = "12086", `46113` = "46102", `51515` = "51019", `02270` = "02158")
noaa_vars <- c("EVENTS", "DEATHS", "DAMAGE")

noaa_text <- function(url, what) {
  resp <- http_perform(http_request(url, "noaa_storm_events"))
  check_status(resp, what)
  httr2::resp_body_string(resp)
}

# The yearly details files in NCEI's directory listing: year, creation date and file name.
noaa_list_files <- function() {
  html <- noaa_text(noaa_base, "NOAA Storm Events file list")
  file <- unique(regmatches(html, gregexpr("StormEvents_details-ftp_v1\\.0_d[0-9]{4}_c[0-9]{8}\\.csv\\.gz", html))[[1]])
  if (!length(file)) stop("NOAA Storm Events: no details files in the directory listing", call. = FALSE)
  d <- data.frame(year = as.integer(sub("^.*_d([0-9]{4})_c.*$", "\\1", file)),
                  created = sub("^.*_c([0-9]{8})\\..*$", "\\1", file), file = file, stringsAsFactors = FALSE)
  d[order(d$year), , drop = FALSE]
}

noaa_files <- function() {
  memoize("noaa_files", function() cached(cache_path("raw", "noaa_storm_events", "files.parquet"), source = "noaa_storm_events", compute = noaa_list_files))
}

# Years whose file was created at least 60 days after the year ended.
noaa_years <- function() {
  f <- noaa_files()
  done <- as.Date(f$created, "%Y%m%d") >= as.Date(paste0(f$year, "-12-31")) + noaa_complete_after
  f$year[done & f$year >= noaa_first_year]
}

noaa_label <- function(year) {
  ifelse(year < 1955, "NOAA Storm Events, tornadoes only",
         ifelse(year < 1996, "NOAA Storm Events, tornadoes, thunderstorm wind and hail only", "NOAA Storm Events, all event types"))
}

# Dollars from Storm Data's damage strings ("10.00K", "1.5M", "2B"); blank or unreadable is zero.
noaa_dollars <- function(x) {
  x <- toupper(trimws(x))
  unit <- sub("^[0-9.]*", "", x)
  scale <- c(H = 1e2, K = 1e3, M = 1e6, B = 1e9)
  v <- suppressWarnings(as.numeric(sub("[A-Z]$", "", x))) * ifelse(unit == "", 1, scale[unit])
  ifelse(is.na(v), 0, v)
}

# One year's records: state FIPS, zone or county type and code, deaths and property damage.
noaa_events <- function(year) {
  memoize(paste0("noaa_", year), function() cached(derived_path("noaa_storm_events", paste0("events_", year), "noaa.R"), source = "noaa_storm_events", compute = function() {
    f <- noaa_files()
    file <- f$file[f$year == year]
    if (length(file) != 1) stop("NOAA Storm Events has no details file for ", year, call. = FALSE)
    path <- cached_download(paste0(noaa_base, file), cache_path("raw", "noaa_storm_events", file), "noaa_storm_events")
    d <- readr::read_csv(path, progress = FALSE, col_types = readr::cols_only(
      STATE_FIPS = "c", CZ_TYPE = "c", CZ_FIPS = "c", DEATHS_DIRECT = "n", DEATHS_INDIRECT = "n", DAMAGE_PROPERTY = "c"))
    state <- sprintf("%02d", as.integer(d$STATE_FIPS))
    d <- d[d$CZ_TYPE %in% c("C", "Z") & state %in% state_table()$state, , drop = FALSE]   # marine zones are water (CZ_TYPE M, or Z under state codes 85-99)
    num <- function(v) ifelse(is.na(v), 0, v)
    data.frame(state = sprintf("%02d", as.integer(d$STATE_FIPS)), type = d$CZ_TYPE, code = as.integer(d$CZ_FIPS),
               deaths = num(d$DEATHS_DIRECT) + num(d$DEATHS_INDIRECT), damage = noaa_dollars(d$DAMAGE_PROPERTY),
               stringsAsFactors = FALSE)
  }))
}

# The newest county-zone correlation file on NWS's page (named bp<day><month code><year>.dbx).
noaa_zone_file <- function() {
  html <- noaa_text(noaa_zone_page, "NWS county-zone correlation page")
  file <- unique(regmatches(html, gregexpr("bp[0-9]{2}[a-z]{2}[0-9]{2}\\.dbx", html))[[1]])
  month <- c(ja = 1, fe = 2, mr = 3, ap = 4, my = 5, jn = 6, jl = 7, au = 8, se = 9, oc = 10, no = 11, de = 12)
  date <- as.Date(sprintf("20%s-%02d-%s", substr(file, 7, 8), month[substr(file, 5, 6)], substr(file, 3, 4)))
  if (!length(file) || anyNA(date)) stop("NWS county-zone correlation page lists no readable file", call. = FALSE)
  file[which.max(date)]
}

# The NWS county-zone correlation file: one row per county of each public forecast zone.
noaa_zones <- function() {
  memoize("noaa_zones", function() cached(cache_path("raw", "noaa_storm_events", "zone_counties.parquet"), source = "noaa_storm_events", compute = function() {
    file <- noaa_zone_file()
    d <- readr::read_delim(I(noaa_text(paste0(noaa_zone_dir, file), "NWS county-zone correlation file")), delim = "|", quote = "",
                           col_names = c("usps", "zone", "cwa", "name", "state_zone", "county_name", "fips", "time_zone", "fe_area", "lat", "lon"),
                           col_types = readr::cols(.default = readr::col_character()), progress = FALSE)
    st <- state_table()
    data.frame(state = st$state[match(d$usps, st$usps)], zone = suppressWarnings(as.integer(d$zone)), county = d$fips,
               file = file, stringsAsFactors = FALSE)
  }))
}

# The counties of each zone event, one row per event and county: event row number, county and share
# of the event (1 for county events, 1 over the zone's counties for zone events; zone events that
# match no zone have no rows).
noaa_event_counties <- function(year) {
  memoize(paste0("noaa_counties_", year), function() cached(derived_path("noaa_storm_events", paste0("counties_", year), "noaa.R"), source = "noaa_storm_events", compute = function() {
    e <- noaa_events(year)
    z <- noaa_zones()
    z <- z[!is.na(z$state) & !is.na(z$zone), , drop = FALSE]
    by_zone <- split(z$county, paste(z$state, z$zone))
    rows <- which(e$type == "C")
    county <- paste0(e$state[rows], sprintf("%03d", e$code[rows]))
    out <- data.frame(event = rows, county = ifelse(county %in% names(noaa_county_successor), noaa_county_successor[county], county),
                      share = 1, stringsAsFactors = FALSE)
    zoned <- which(e$type == "Z")
    counties <- by_zone[paste(e$state[zoned], e$code[zoned])]
    size <- lengths(counties)
    if (any(size > 0)) {
      out <- rbind(out, data.frame(event = rep(zoned, size), county = unlist(counties, use.names = FALSE),
                                   share = rep(1 / pmax(size, 1), size), stringsAsFactors = FALSE))
    }
    out
  }))
}

# The share of each state's zone events that match a current zone (NA where it has none).
noaa_zone_match <- function(year) {
  e <- noaa_events(year)
  matched <- e$type == "Z" & seq_len(nrow(e)) %in% noaa_event_counties(year)$event
  tapply(matched[e$type == "Z"], e$state[e$type == "Z"], mean)
}

# Values of one year for the requested pieces: rows (geo, variable, estimate, status, note).
noaa_year_values <- function(year, pieces, vintage) {
  e <- noaa_events(year)
  ec <- noaa_event_counties(year)
  matched <- noaa_zone_match(year)
  nation <- member_states("nation")
  total <- function(rows, share = rep(1, length(rows))) c(EVENTS = length(unique(rows)),
    DEATHS = sum(e$deaths[rows] * share), DAMAGE = sum(e$damage[rows] * share))
  out <- lapply(seq_len(nrow(pieces)), function(i) {
    type <- pieces$type[i]
    geoid <- pieces$geoid[i]
    unavailable <- function(note) list(est = rep(NA_real_, 3), note = note)
    r <- switch(type,
      nation = , region = , division = , state = {
        states <- switch(type, nation = nation, region = , division = member_states(type, geoid), state = geoid)
        list(est = total(which(e$state %in% states)), note = "")
      },
      county = , cbsa = {
        counties <- if (type == "county") geoid else cbsa_counties(geoid, vintage)
        states <- unique(substr(counties, 1, 2))
        short <- states[!is.na(matched[states]) & matched[states] < noaa_min_mapped]
        if (any(substr(counties, 1, 2) == "09" & as.integer(substr(counties, 3, 5)) > 100)) {
          unavailable("NWS and NCEI code Connecticut by the state's former counties, not its planning regions")
        } else if (length(short)) {
          unavailable(sprintf("under %d%% of this state's zone events in %d match a current NWS zone, so county values are not shown",
                              round(100 * noaa_min_mapped), year))
        } else {
          x <- ec[ec$county %in% counties, , drop = FALSE]
          list(est = total(x$event, x$share), note = "")
        }
      },
      stop("NOAA Storm Events: unsupported geography type '", type, "'.", call. = FALSE))
    data.frame(geo = pieces$key[i], variable = noaa_vars, estimate = unname(r$est),
               status = if (anyNA(r$est)) "unavailable" else "ok", note = r$note, stringsAsFactors = FALSE)
  })
  do.call(rbind, out)
}

noaa_fetch <- function(variables, pieces, periods, options = list()) {
  vintage <- as.integer(options$settings$boundary_vintage %||% 2024)
  out <- lapply(as.integer(periods), function(yr) {
    v <- noaa_year_values(yr, pieces, vintage)
    v <- v[v$variable %in% variables, , drop = FALSE]
    data.frame(geo = v$geo, name = "", variable = v$variable, estimate = v$estimate, moe = NA_real_, status = v$status,
               bound = NA_character_, note = v$note, period = as.character(yr), period_start = yr, period_end = yr,
               source_id = "noaa_storm_events", series = noaa_label(yr), stringsAsFactors = FALSE)
  })
  if (!length(out)) return(empty_values())
  do.call(rbind, out)
}

register_provider("noaa_storm_events", list(
  name = "NOAA National Centers for Environmental Information, Storm Events Database",
  geo_types = c("nation", "region", "division", "state", "county", "cbsa"),
  fetch = noaa_fetch,
  periods = function(settings, recipe) {
    years <- noaa_years()
    years[years >= as.integer(settings$history_start %||% noaa_first_year)]
  },
  period_label = function(period) as.character(period),
  period_kind = "annual",
  series = "NOAA Storm Events",
  availability_note = paste("Storm Events records what National Weather Service offices report, so counts follow reporting practice.",
                            "Coverage widened in 1955 and 1996. Events recorded for a forecast zone count in each county of the zone and",
                            "split their deaths and damage among those counties; states have no county values in years when their zones",
                            "cannot be matched. Connecticut's planning regions have no values.")))
