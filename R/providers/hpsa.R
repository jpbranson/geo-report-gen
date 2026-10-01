# HRSA Health Professional Shortage Areas (HPSAs): the current designations for primary care,
# dental health and mental health, from HRSA's daily data warehouse files (one row per component of a
# designation: a county, county subdivision or census tract, or the site of a facility). Only
# designations with status Designated are counted, as in HRSA's own summaries (those proposed for
# withdrawal are not); a designation counts once in every county in which it has a component, and
# once in a state or larger area, however many components it has there.
#
# Areas: counties by the component's county code (facility designations by the facility's county), and
# states, regions, divisions, metro areas and the nation from the counties (HRSA codes Connecticut by its
# planning regions). Designations change
# every day and HRSA keeps no archive, so the values are a snapshot of the day the file was fetched.
#
# Variables: PC_COUNT, DH_COUNT, MH_COUNT (designated HPSAs), PC_SCORE, DH_SCORE, MH_SCORE (the highest
# HPSA score, 0-25, of the designated HPSAs; higher is worse).

hpsa_base <- "https://data.hrsa.gov/DataDownload/DD_Files/"
hpsa_disciplines <- c(PC = "BCD_HPSA_FCT_DET_PC.csv", DH = "BCD_HPSA_FCT_DET_DH.csv", MH = "BCD_HPSA_FCT_DET_MH.csv")
hpsa_raw_path <- function(discipline) cache_path("raw", "hrsa_hpsa", hpsa_disciplines[[discipline]])

# The designated components of one discipline: HPSA ID, county FIPS code, score.
hpsa_components <- function(discipline) {
  memoize(paste0("hpsa_", discipline), function() cached(derived_path("hrsa_hpsa", paste0("designated_", discipline), "hpsa.R"), source = "hrsa_hpsa", compute = function() {
    file <- hpsa_disciplines[[discipline]]
    path <- cached_download(paste0(hpsa_base, file), hpsa_raw_path(discipline), "hrsa_hpsa")
    d <- suppressMessages(suppressWarnings(readr::read_csv(path, col_types = readr::cols(.default = readr::col_character()), progress = FALSE)))   # the files end each row with a comma
    d <- d[d$`HPSA Status` %in% "Designated", , drop = FALSE]
    county <- ifelse(nzchar(d$`State and County Federal Information Processing Standard Code`) & !is.na(d$`State and County Federal Information Processing Standard Code`),
                     d$`State and County Federal Information Processing Standard Code`, d$`Common State County FIPS Code`)
    data.frame(id = d$`HPSA ID`, county = county, score = suppressWarnings(as.numeric(d$`HPSA Score`)),
               stringsAsFactors = FALSE)
  }))
}

hpsa_fetch <- function(variables, pieces, periods, options = list()) {
  vintage <- as.integer(options$settings$boundary_vintage %||% 2024)
  out <- list()
  for (v in variables) {
    d <- hpsa_components(substr(v, 1, 2))
    d <- d[!is.na(d$county) & nchar(d$county) == 5, , drop = FALSE]
    yr <- snapshot_year(hpsa_raw_path(substr(v, 1, 2)))
    est <- vapply(seq_len(nrow(pieces)), function(i) {
      type <- pieces$type[i]
      geoid <- pieces$geoid[i]
      x <- switch(type, county = d[d$county == geoid, ], state = d[substr(d$county, 1, 2) == geoid, ],
                  region = , division = d[substr(d$county, 1, 2) %in% member_states(type, geoid), ],
                  cbsa = d[d$county %in% cbsa_counties(geoid, vintage), ], nation = d[substr(d$county, 1, 2) %in% member_states("nation"), ])
      if (endsWith(v, "_COUNT")) length(unique(x$id)) else if (nrow(x) && !all(is.na(x$score))) max(x$score, na.rm = TRUE) else NA_real_
    }, 0)
    out[[length(out) + 1]] <- data.frame(geo = pieces$key, name = "", variable = v, estimate = est, moe = NA_real_,
      status = ifelse(is.na(est), "unavailable", "ok"), bound = NA_character_,
      note = ifelse(is.na(est) & endsWith(v, "_SCORE"), "no designated shortage area with a score", ""), period = as.character(yr),
      period_start = yr, period_end = yr, source_id = "hrsa_hpsa", series = "Current designations", stringsAsFactors = FALSE)
  }
  if (!length(out)) return(empty_values())
  do.call(rbind, out)
}

register_provider("hrsa_hpsa", list(
  name = "Health Resources and Services Administration, Health Professional Shortage Areas (current designations)",
  geo_types = c("nation", "region", "division", "state", "county", "cbsa"),
  fetch = hpsa_fetch,
  periods = function(settings, recipe) snapshot_year(hpsa_raw_path(substr(recipe$numerator, 1, 2))),
  period_label = function(period) paste0(period, " (current designations)"),
  period_kind = "snapshot",
  series = "HRSA shortage area designations",
  availability_note = paste("HPSA designations are a current snapshot (HRSA keeps no archive). A designation counts once in each county where it has",
                            "a component; states and larger areas count it once. There are no city or tract values.")))
