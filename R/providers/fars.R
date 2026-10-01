# NHTSA Fatality Analysis Reporting System (FARS): a census of fatal crashes on public roads
# (deaths within 30 days), 1982-2023, from NHTSA's keyless national files. Deaths are counted
# where the crash happened, not where the people killed lived.
#
# People come from the auxiliary PER_AUX file, whose person type and injury codes NHTSA
# harmonized from 1982 (the original PER_TYP codes changed in the 1970s and 1980s): A_PERINJ 1 is
# a death, A_PTYPE 3 a pedestrian and 4 a cyclist. Crashes come from ACC_AUX through 2000 and
# from the main accident file from 2001, when crash coordinates begin. NHTSA publishes no
# auxiliary file for 1996; that year uses the main files, whose codes then match (INJ_SEV 4
# killed; PER_TYP 5 pedestrian, 6 and 7 cyclists, as the auxiliary files of 1990 and 1997 group
# them).
#
# Areas: states and counties by the crash's codes (FIPS, with a few retired county codes mapped
# to their successors; Connecticut stays on its former counties); the nation, regions, divisions
# and metro areas as sums; places, their county parts and tracts by locating crash coordinates
# in full-resolution TIGER/Line boundaries of the report's boundary year, from 2001, and only
# for state-years in which at least 95% of crashes have coordinates.
#
# Two providers share the data: nhtsa_fars (deaths by year) and nhtsa_fars_5yr (deaths summed
# over the five years of an ACS 5-year period, with PERSON_YEARS = 5 x the ACS population, for
# rates that are not dominated by chance in small places).
#
# Variables: DEATHS, PED_DEATHS, BIKE_DEATHS (and *_5YR, PERSON_YEARS for the 5-year provider).

fars_base <- "https://static.nhtsa.gov/nhtsa/downloads/FARS/"
fars_years <- 1982:2023
fars_coordinates_from <- 2001L
fars_no_aux <- 1996L
fars_min_located <- 0.95
fars_county_successor <- c(`12025` = "12086", `46113` = "46102", `51515` = "51019")

# One member of a FARS ZIP, as character columns with upper-case names.
fars_member <- function(zip, pattern) {
  files <- utils::unzip(zip, list = TRUE)$Name
  member <- grep(pattern, files, ignore.case = TRUE, value = TRUE)[1]
  if (is.na(member)) stop(basename(zip), " has no file matching ", pattern, call. = FALSE)
  dir <- tempfile("fars")
  on.exit(unlink(dir, recursive = TRUE))
  path <- utils::unzip(zip, files = member, exdir = dir)
  d <- readr::read_csv(path, col_types = readr::cols(.default = readr::col_character()), progress = FALSE)
  names(d) <- toupper(names(d))
  d
}

fars_zip <- function(year, kind) {
  file <- sprintf("FARS%dNational%sCSV.zip", year, if (kind == "aux") "Auxiliary" else "")
  cached_download(paste0(fars_base, year, "/National/", file), cache_path("raw", "nhtsa_fars", file), "nhtsa_fars")
}

# One year's crashes: state and county FIPS, deaths, pedestrians and cyclists killed, coordinates.
fars_crashes <- function(year) {
  memoize(paste0("fars_", year), function() cached(derived_path("nhtsa_fars", paste0("crashes_", year), "fars.R"), source = "nhtsa_fars", compute = function() {
    if (year %in% fars_no_aux) {
      main <- fars_zip(year, "main")
      p <- fars_member(main, "(^|/)person\\.csv$")
      p <- data.frame(ST_CASE = p$ST_CASE, A_PERINJ = ifelse(p$INJ_SEV == "4", "1", "6"),
                      A_PTYPE = ifelse(p$PER_TYP == "5", "3", ifelse(p$PER_TYP %in% c("6", "7"), "4", "0")))
      a <- fars_member(main, "(^|/)accident\\.csv$")
    } else {
      aux <- fars_zip(year, "aux")
      p <- fars_member(aux, "(^|/)PER_AUX\\.CSV$")
      a <- if (year < fars_coordinates_from) fars_member(aux, "(^|/)ACC_AUX\\.CSV$") else fars_member(fars_zip(year, "main"), "(^|/)accident\\.csv$")
    }
    killed <- p[p$A_PERINJ == "1", , drop = FALSE]
    ped <- tapply(killed$A_PTYPE == "3", killed$ST_CASE, sum)
    bike <- tapply(killed$A_PTYPE == "4", killed$ST_CASE, sum)
    num <- function(v) suppressWarnings(as.numeric(v))
    lat <- if ("LATITUDE" %in% names(a)) num(a$LATITUDE) else NA_real_
    lon <- if ("LONGITUD" %in% names(a)) num(a$LONGITUD) else NA_real_
    located <- !is.na(lat) & !is.na(lon) & lat > 17 & lat < 72 & lon > -180 & lon < -64   # 77.., 88.., 99.. mean unknown
    county <- paste0(sprintf("%02d", as.integer(a$STATE)), sprintf("%03d", as.integer(a$COUNTY)))
    county <- ifelse(county %in% names(fars_county_successor), fars_county_successor[county], county)
    killed_by <- function(x) { v <- as.numeric(x[a$ST_CASE]); v[is.na(v)] <- 0; v }   # crashes without such deaths
    data.frame(st_case = a$ST_CASE, state = sprintf("%02d", as.integer(a$STATE)), county = county,
               DEATHS = num(a$FATALS), PED_DEATHS = killed_by(ped), BIKE_DEATHS = killed_by(bike),
               lat = ifelse(located, lat, NA_real_), lon = ifelse(located, lon, NA_real_), stringsAsFactors = FALSE)
  }))
}

# The place and tract of each located crash of one state and year (NA outside any place).
fars_locate <- function(year, state, vintage) {
  cached(derived_path("nhtsa_fars", file.path("located", paste0(year, "_", state, "_", vintage)), "fars.R"), source = "nhtsa_fars", compute = function() {
    d <- fars_crashes(year)
    d <- d[d$state == state & !is.na(d$lat), , drop = FALSE]
    data.frame(st_case = d$st_case, place = locate_points(d$lon, d$lat, "place", state, vintage),
               tract = locate_points(d$lon, d$lat, "tract", state, vintage), stringsAsFactors = FALSE)
  })
}

# Deaths of one year for the requested pieces: rows (geo, variable, estimate, status, note).
fars_year_values <- function(year, pieces, vintage) {
  d <- fars_crashes(year)
  vars <- c("DEATHS", "PED_DEATHS", "BIKE_DEATHS")
  nation <- member_states("nation")
  located_share <- tapply(!is.na(d$lat), d$state, mean)
  out <- list()
  for (i in seq_len(nrow(pieces))) {
    type <- pieces$type[i]
    geoid <- pieces$geoid[i]
    note <- ""
    sel <- switch(type,
      nation = d$state %in% nation,
      region = , division = d$state %in% member_states(type, geoid),
      state = d$state == geoid,
      county = d$county == geoid,
      cbsa = d$county %in% cbsa_counties(geoid, vintage),
      place = , place_part = , tract = {
        state <- substr(geoid, 1, 2)
        share <- located_share[state]
        if (year < fars_coordinates_from || is.na(share) || share < fars_min_located) {
          note <- if (year < fars_coordinates_from) paste0("crash coordinates start in ", fars_coordinates_from)
                  else sprintf("only %d%% of crashes in this state in %d have coordinates", round(100 * share), year)
          NULL
        } else {
          loc <- fars_locate(year, state, vintage)
          cases <- switch(type,
            tract = loc$st_case[loc$tract %in% geoid],
            place = loc$st_case[loc$place %in% geoid],
            place_part = loc$st_case[loc$place %in% sub("-.*$", "", geoid)])
          ok <- d$st_case %in% cases & d$state == state
          if (type == "place_part") ok <- ok & d$county == sub("^.*-", "", geoid)
          ok
        }
      },
      stop("FARS: unsupported geography type '", type, "'.", call. = FALSE))
    if (type == "county" && !any(d$county == geoid) && startsWith(geoid, "09") && as.integer(substr(geoid, 3, 5)) > 100) {
      note <- "FARS codes Connecticut crashes by the state's former counties, not its planning regions"
      sel <- NULL
    }
    est <- if (is.null(sel)) rep(NA_real_, 3) else colSums(d[sel, vars, drop = FALSE])
    out[[i]] <- data.frame(geo = pieces$key[i], variable = vars, estimate = unname(est),
                           status = if (is.null(sel)) "unavailable" else "ok", note = note, stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}

fars_long <- function(values, source_id, period, start) {
  data.frame(geo = values$geo, name = "", variable = values$variable, estimate = values$estimate, moe = NA_real_,
             status = values$status, bound = NA_character_, note = values$note, period = as.character(period),
             period_start = start, period_end = as.integer(period), source_id = source_id, stringsAsFactors = FALSE)
}

fars_fetch <- function(variables, pieces, periods, options = list()) {
  vintage <- as.integer(options$settings$boundary_vintage %||% 2024)
  out <- lapply(as.integer(periods), function(yr) {
    v <- fars_year_values(yr, pieces, vintage)
    fars_long(v[v$variable %in% variables, , drop = FALSE], "nhtsa_fars", yr, yr)
  })
  if (!length(out)) return(empty_values())
  do.call(rbind, out)
}

# Five-year sums ending in an ACS release year, with person-years from the ACS population.
fars_5yr_fetch <- function(variables, pieces, periods, options = list()) {
  vintage <- as.integer(options$settings$boundary_vintage %||% 2024)
  out <- lapply(as.integer(periods), function(end) {
    years <- (end - 4L):end
    per_year <- lapply(years, fars_year_values, pieces = pieces, vintage = vintage)
    v <- per_year[[1]]
    est <- Reduce(`+`, lapply(per_year, `[[`, "estimate"))
    missing <- Reduce(`|`, lapply(per_year, function(x) x$status != "ok"))
    notes <- Reduce(function(a, b) ifelse(nzchar(a), a, b), lapply(per_year, `[[`, "note"))
    v$estimate <- ifelse(missing, NA_real_, est)
    v$status <- ifelse(missing, "unavailable", "ok")
    v$note <- ifelse(missing, notes, "")
    v$variable <- paste0(v$variable, "_5YR")
    # Crashes are located in 2020-based tracts; the ACS used 2010 tracts before its 2020 release.
    old_tract <- pieces$type == "tract" & end < 2020L
    pop <- if (all(old_tract)) empty_values() else acs_fetch("B01003_001", pieces[!old_tract, , drop = FALSE], end)
    py <- data.frame(geo = pieces$key, variable = "PERSON_YEARS", estimate = 5 * pop$estimate[match(pieces$key, pop$geo)],
                     stringsAsFactors = FALSE)
    py$status <- ifelse(is.na(py$estimate), "unavailable", "ok")
    py$note <- ifelse(old_tract, "tract boundaries were redrawn in 2020; ACS populations before 2020 use the old tracts",
                      ifelse(is.na(py$estimate), "no ACS population for this area and period", ""))
    v <- rbind(v, py)
    fars_long(v[v$variable %in% variables, , drop = FALSE], "nhtsa_fars_5yr", end, end - 4L)
  })
  if (!length(out)) return(empty_values())
  do.call(rbind, out)
}

fars_geo_types <- c("nation", "region", "division", "state", "county", "cbsa", "place", "place_part", "tract")
fars_note <- paste("FARS counts deaths where crashes happened. States and counties come from the crash's codes back to 1982;",
                   "cities and tracts from crash coordinates, which start in 2001. Connecticut's planning regions are not coded.")

register_provider("nhtsa_fars", list(
  name = "National Highway Traffic Safety Administration, Fatality Analysis Reporting System (FARS)",
  geo_types = fars_geo_types,
  fetch = fars_fetch,
  periods = function(settings, recipe) seq(max(min(fars_years), as.integer(settings$history_start %||% min(fars_years))), max(fars_years)),
  period_label = function(period) as.character(period),
  period_kind = "annual",
  series = "FARS",
  fixed_boundaries = 2024L,
  availability_note = fars_note))

register_provider("nhtsa_fars_5yr", list(
  name = "National Highway Traffic Safety Administration, Fatality Analysis Reporting System (FARS), 5-year sums",
  geo_types = fars_geo_types,
  fetch = fars_5yr_fetch,
  periods = function(settings, recipe) rev(seq(max(fars_years), max(2009L, as.integer(settings$history_start %||% 2009) + 4L), by = -5L)),
  period_label = function(period) paste0(as.integer(period) - 4L, "–", period),
  period_kind = "multiyear",
  series = "FARS 5-year sums",
  fixed_boundaries = 2024L,
  period_phrase = "note_five_year_totals",
  availability_note = fars_note))
