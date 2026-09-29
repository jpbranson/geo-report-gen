# LEHD Origin-Destination Employment Statistics (LODES 8.4), from the Census Bureau's keyless
# bulk files: jobs by the census block of the workplace (WAC files) and of the worker's
# residence (RAC files), 2002-2023. Files are published per state, with a crosswalk from each
# 2020 census block to the areas containing it (codes "current" as of the 2024 TIGER/Line
# files), so summing blocks gives exact values for counties, places and their county parts,
# county subdivisions, tracts, block groups, ZCTAs and metro areas, and for unions of them.
#
# Primary jobs only (job type JT01: each worker's highest-paying job), so workplace and
# residence counts both count workers, and jobs per employed resident is 1 where they balance.
# Variables are named <W|R>_<column>: W_C000 (primary jobs located in the area), W_CE01 (of
# which paying $1,250 a month or less), W_CNS05 (in manufacturing), R_C000 (primary jobs held
# by residents: employed residents). Federal jobs are included from 2010 only.
#
# Some states supplied no job data in some years (technical document 8.4, "Data Coverage and
# Availability"). Their workplace files are missing or hold a few stray jobs, and their
# residence files count only residents working in other states, so both are unavailable for
# those state-years. Other states' residents working there are missing from their residence
# counts, which understates areas next to them (such as the suburbs of Washington, DC, before
# 2010). LODES publishes no national totals, and a sum of states would be incomplete in most
# years, so the nation, regions and divisions are not offered.

lodes_base <- "https://lehd.ces.census.gov/data/lodes/LODES8"
lodes_job_type <- "JT01"
lodes_boundaries <- 2024L
lodes_columns <- c("C000", "CE01", "CE02", "CE03", sprintf("CNS%02d", 1:20))

# States (FIPS) without job data in a year, from the technical document's coverage table.
lodes_no_jobs <- function(year) {
  if (year == 2002) c("04", "05", "11", "25", "28", "33")
  else if (year == 2003) c("04", "11", "25", "28")
  else if (year <= 2009) c("11", "25")
  else if (year == 2010) "25"
  else if (year <= 2016) character()
  else if (year <= 2021) "02"
  else c("02", "26")
}

# The areas of each block in one state's crosswalk, one key vector per geography type (NA
# where a block is in no such area; the crosswalk codes those as all nines).
lodes_block_areas <- function(usps) {
  memoize(paste0("lodes_xwalk_", usps), function() {
    file <- paste0(usps, "_xwalk.csv.gz")
    path <- cached_download(paste(lodes_base, usps, file, sep = "/"), cache_path("raw", "census_lodes", usps, file), "census_lodes")
    cols <- c("tabblk2020", "st", "cty", "trct", "bgrp", "cbsa", "zcta", "stplc", "ctycsub")
    x <- readr::read_csv(path, col_types = do.call(readr::cols_only, stats::setNames(rep(list(readr::col_character()), length(cols)), cols)),
                         progress = FALSE)
    code <- function(type, v) ifelse(is.na(v) | grepl("^9+$", v), NA_character_, paste0(type, ":", v))
    place <- code("place", x$stplc)
    list(block = x$tabblk2020,
         keys = list(state = code("state", x$st), county = code("county", x$cty),
                     place = place, place_part = ifelse(is.na(place), NA_character_, paste0("place_part:", x$stplc, "-", x$cty)),
                     cousub = code("cousub", x$ctycsub), tract = code("tract", x$trct), bg = code("bg", x$bgrp),
                     zcta = code("zcta", x$zcta), cbsa = code("cbsa", x$cbsa)))
  })
}

# One state's workplace ("wac") or residence ("rac") file for a year, summed to every area in
# the state's crosswalk (areas without jobs get zeros). A ZCTA or metro area crossing a state
# line has a partial row in each state's table.
lodes_areas <- function(usps, kind, year) {
  file <- sprintf("%s_%s_S000_%s_%d.csv.gz", usps, kind, lodes_job_type, year)
  cached(derived_path("census_lodes", file.path(usps, sub("\\.csv\\.gz$", "", file)), "lodes.R"), source = "census_lodes", compute = function() {
    raw <- cached_download(paste(lodes_base, usps, kind, file, sep = "/"), cache_path("raw", "census_lodes", usps, kind, file), "census_lodes")
    geocode <- if (kind == "wac") "w_geocode" else "h_geocode"
    types <- c(stats::setNames(list(readr::col_character()), geocode),
               stats::setNames(rep(list(readr::col_double()), length(lodes_columns)), lodes_columns))
    d <- readr::read_csv(raw, col_types = do.call(readr::cols_only, types), progress = FALSE)
    x <- lodes_block_areas(usps)
    row <- match(d[[geocode]], x$block)
    if (anyNA(row)) stop(sum(is.na(row)), " blocks in ", file, " are not in the ", usps, " crosswalk.", call. = FALSE)
    values <- as.matrix(d[, lodes_columns])
    do.call(rbind, lapply(x$keys, function(k) {
      areas <- unique(k[!is.na(k)])
      out <- matrix(0, length(areas), length(lodes_columns), dimnames = list(areas, lodes_columns))
      in_area <- !is.na(k[row])
      if (any(in_area)) {
        s <- rowsum(values[in_area, , drop = FALSE], k[row][in_area])
        out[rownames(s), ] <- s
      }
      data.frame(key = areas, out, row.names = NULL, check.names = FALSE, stringsAsFactors = FALSE)
    }))
  })
}

# States whose files cover a published geography.
lodes_piece_states <- function(type, geoid, vintage) {
  switch(type,
    state = geoid,
    county = , place = , place_part = , cousub = , tract = , bg = substr(geoid, 1, 2),
    zcta = unique(substr(zcta_county_parts(geoid)$county, 1, 2)),
    cbsa = unique(substr(cbsa_counties(geoid, vintage), 1, 2)),
    stop("LODES: unsupported geography type '", type, "'.", call. = FALSE))
}

lodes_fetch <- function(variables, pieces, periods, options = list()) {
  vintage <- as.integer(options$settings$boundary_vintage %||% lodes_boundaries)
  if (vintage != lodes_boundaries) {
    warn("LODES areas are built from 2020 census blocks assigned to ", lodes_boundaries, " boundaries; the report uses ",
         vintage, " boundaries.")
  }
  st <- state_table()
  covered <- st$state[st$in_nation == "TRUE"]  # the 50 states and DC; Puerto Rico is not in LODES
  states <- lapply(seq_len(nrow(pieces)), function(i) lodes_piece_states(pieces$type[i], pieces$geoid[i], vintage))
  prefix <- sub("_.*$", "", variables)
  column <- sub("^[WR]_", "", variables)
  out <- list()
  for (yr in as.integer(periods)) {
    gap <- lodes_no_jobs(yr)
    for (p in unique(prefix)) {
      kind <- c(W = "wac", R = "rac")[[p]]
      cols <- column[prefix == p]
      need <- setdiff(intersect(unique(unlist(states)), covered), gap)
      rows <- do.call(rbind, lapply(need, function(s) {
        a <- lodes_areas(tolower(st$usps[st$state == s]), kind, yr)
        a[a$key %in% pieces$key, c("key", cols), drop = FALSE]
      }))
      for (i in seq_len(nrow(pieces))) {
        hit <- if (is.null(rows)) NULL else rows[rows$key == pieces$key[i], cols, drop = FALSE]
        missing <- setdiff(states[[i]], setdiff(covered, gap))
        note <- if (length(missing)) {
          names <- st$name[st$state %in% missing]
          if (!all(missing %in% covered)) "LODES does not cover Puerto Rico or the Island Areas"
          else paste0("LODES has no job data from ", paste(names, collapse = " or "), " for ", yr,
                      if (kind == "rac") " (only residents working in other states are counted)")
        } else if (is.null(hit) || !nrow(hit)) {
          paste0("not an area in the LODES crosswalk (", lodes_boundaries, " boundaries)")
        } else ""
        ok <- !nzchar(note)
        out[[length(out) + 1]] <- data.frame(
          geo = pieces$key[i], name = "", variable = paste0(p, "_", cols),
          estimate = if (ok) unname(colSums(hit)) else NA_real_, moe = NA_real_,
          status = if (ok) "ok" else "unavailable", bound = NA_character_, note = note,
          period = as.character(yr), period_start = yr, period_end = yr, source_id = "census_lehd_lodes",
          stringsAsFactors = FALSE)
      }
    }
  }
  if (!length(out)) return(empty_values())
  do.call(rbind, out)
}

register_provider("census_lehd_lodes", list(
  name = "U.S. Census Bureau, LEHD Origin-Destination Employment Statistics (LODES 8.4)",
  geo_types = c("state", "county", "place", "place_part", "cousub", "tract", "bg", "zcta", "cbsa"),
  fetch = lodes_fetch,
  periods = function(settings, recipe) seq(max(2002L, as.integer(settings$history_start %||% 2002)), 2023L),
  period_label = function(period) as.character(period),
  period_kind = "annual",
  series = "LODES 8.4 (primary jobs)",
  fixed_boundaries = lodes_boundaries,
  availability_note = paste("LODES is published by state from census blocks, so it covers counties, cities, county subdivisions,",
                            "tracts, ZCTAs and metro areas; it publishes no national or regional totals, and some states",
                            "supplied no job data in some years (Alaska from 2017, Michigan from 2022, Washington, DC,",
                            "before 2010, Massachusetts before 2011).")))
