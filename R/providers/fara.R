# USDA Economic Research Service, Food Access Research Atlas: tract-level measures of distance to
# food retailers, summed up to counties, metro areas, states and the nation (places do not line up
# with tracts, so they have no values).
#  - 2025 SNAP-authorized Retailer Access Map (SRAM): every SNAP-authorized retailer of June 2025
#    (convenience and dollar stores included), straight-line (SD_) and driving (DD_) distance,
#    2020 tracts and population. Access is low beyond 1 mile in urban and 10 miles in rural tracts;
#    a low-income, low-access (LILA) tract is a low-income tract with a large share of residents far
#    from a retailer.
#  - 2019 Large Retailer Access Map (LRAM, formerly the Food Access Research Atlas): supermarkets,
#    supercenters and large grocery stores, straight-line distance, 2010 tracts. Its tract codes
#    differ from 2020, so it has no tract-level values. The 2015 and 2010 editions are not read.
# The two maps use different store universes and are never compared or joined.
#
# Variables: SD_LILA, DD_LILA, SD_LAPOP, DD_LAPOP, POP, TRACTS (SRAM, 2025) and LRAM_LILA,
# LRAM_LAPOP, LRAM_POP, LRAM_TRACTS (LRAM, 2019); *_LILA counts LILA tracts, *_LAPOP the residents
# of low-access areas (1 mile urban, 10 miles rural).

fara_sram_url <- "https://www.ers.usda.gov/media/29395/2025-snap-authorized-retailer-access-map-sram-data.zip"
fara_lram_url <- "https://www.ers.usda.gov/media/5627/2019-large-retailer-access-map-lram-formerly-known-as-the-food-access-research-atlas-fara-data.zip"

fara_member <- function(url, member) {
  zip <- cached_download(url, cache_path("raw", "usda_ers_fara", basename(url)), "usda_ers_fara")
  dir <- tempfile("fara")
  on.exit(unlink(dir, recursive = TRUE))
  path <- utils::unzip(zip, files = member, exdir = dir)
  d <- readr::read_csv(path, col_types = readr::cols(.default = readr::col_character()), progress = FALSE)
  names(d)[1] <- "tract"
  d$tract <- paste0(strrep("0", 11 - nchar(d$tract)), d$tract)   # the SRAM files drop the leading zero
  d
}

# One row per tract of each edition: year (2025 SRAM, 2019 LRAM), tract, county and state FIPS, and the measures.
fara_tracts <- function() {
  memoize("fara_tracts", function() cached(derived_path("usda_ers_fara", "tracts", "fara.R"), source = "usda_ers_fara", compute = function() {
    num <- function(x) suppressWarnings(as.numeric(x))
    sram <- function(file) fara_member(fara_sram_url, file)
    sd <- sram("SRAM Straight Line Distance Data.csv")
    dd <- sram("SRAM Driving Distance Data.csv")
    gc <- sram("SRAM General Tract Characteristics Data.csv")
    in_sd <- match(gc$tract, sd$tract)
    in_dd <- match(gc$tract, dd$tract)
    s <- data.frame(year = 2025L, tract = gc$tract, SD_LILA = num(sd$SD_SRAM_LILATracts_1And10[in_sd]), DD_LILA = num(dd$DD_SRAM_LILATracts_1And10[in_dd]),
                    SD_LAPOP = num(sd$SD_SRAM_LAPOP1_10[in_sd]), DD_LAPOP = num(dd$DD_SRAM_LAPOP1_10[in_dd]), POP = num(gc$POP2020),
                    stringsAsFactors = FALSE)
    lr <- fara_member(fara_lram_url, "Food Access Research Atlas.csv")
    l <- data.frame(year = 2019L, tract = lr$tract, LRAM_LILA = num(lr$LILATracts_1And10), LRAM_LAPOP = num(lr$LAPOP1_10),
                    LRAM_POP = num(lr$Pop2010), stringsAsFactors = FALSE)
    d <- rbind(cbind(s, LRAM_LILA = NA_real_, LRAM_LAPOP = NA_real_, LRAM_POP = NA_real_),
               cbind(l[, c("year", "tract")], SD_LILA = NA_real_, DD_LILA = NA_real_, SD_LAPOP = NA_real_, DD_LAPOP = NA_real_, POP = NA_real_,
                     l[, c("LRAM_LILA", "LRAM_LAPOP", "LRAM_POP")]))
    d$county <- substr(d$tract, 1, 5)
    d$state <- substr(d$tract, 1, 2)
    d
  }))
}

# The variables of each edition; TRACTS and LRAM_TRACTS count the tracts of an area.
fara_variables <- list(`2025` = c("SD_LILA", "DD_LILA", "SD_LAPOP", "DD_LAPOP", "POP", "TRACTS"),
                       `2019` = c("LRAM_LILA", "LRAM_LAPOP", "LRAM_POP", "LRAM_TRACTS"))

fara_fetch <- function(variables, pieces, periods, options = list()) {
  d <- fara_tracts()
  vintage <- as.integer(options$settings$boundary_vintage %||% 2024)
  out <- list()
  for (yr in as.integer(periods)) {
    x <- d[d$year == yr, , drop = FALSE]
    for (i in seq_len(nrow(pieces))) {
      type <- pieces$type[i]
      geoid <- pieces$geoid[i]
      sel <- switch(type,
        tract = if (yr == 2025L) x$tract == geoid else FALSE,   # LRAM's 2010 tract codes are not those of 2020
        county = x$county == geoid,
        cbsa = x$county %in% cbsa_counties(geoid, vintage),
        state = x$state == geoid,
        region = , division = x$state %in% member_states(type, geoid),
        nation = x$state %in% member_states("nation"),
        stop("Food Access Research Atlas: unsupported geography type '", type, "'.", call. = FALSE))
      rows <- x[sel, , drop = FALSE]
      value <- function(v) if (!nrow(rows)) NA_real_ else if (v %in% c("TRACTS", "LRAM_TRACTS")) nrow(rows) else sum(rows[[v]], na.rm = TRUE)
      why <- if (nrow(rows)) "" else if (type == "tract") "the 2019 map uses 2010 tracts" else "the Food Access Research Atlas has no tracts for this area"
      for (v in intersect(variables, fara_variables[[as.character(yr)]])) {
        out[[length(out) + 1]] <- data.frame(geo = pieces$key[i], name = "", variable = v, estimate = value(v), moe = NA_real_,
          status = if (nrow(rows)) "ok" else "unavailable", bound = NA_character_, note = why, period = as.character(yr),
          period_start = yr, period_end = yr, source_id = "usda_ers_fara",
          series = if (yr == 2025L) "SNAP-authorized Retailer Access Map (2025)" else "Large Retailer Access Map (2019)", stringsAsFactors = FALSE)
      }
    }
  }
  if (!length(out)) return(empty_values())
  do.call(rbind, out)
}

register_provider("usda_ers_fara", list(
  name = "USDA Economic Research Service, Food Access Research Atlas (SRAM 2025, LRAM 2019)",
  geo_types = c("nation", "region", "division", "state", "county", "cbsa", "tract"),
  fetch = fara_fetch,
  periods = function(settings, recipe) if (any(grepl("^LRAM", recipe_vars(recipe$numerator)))) 2019L else 2025L,
  period_label = function(period) as.character(period),
  period_kind = "point",
  series = "Food Access Research Atlas",
  availability_note = paste("The Food Access Research Atlas is published by census tract and summed here to counties, metro areas,",
                            "states and the nation; cities do not line up with tracts. The 2019 map uses 2010 tracts, so it has no tract values.")))
