# FEMA National Risk Index (v1.20, December 2025): natural-hazard risk for counties. It is a
# single cross-section; FEMA warns that versions are not comparable.
#  - Scores (composite risk, social vulnerability, community resilience, heat wave risk) are
#    percentile ranks among counties, so they exist only for single counties.
#  - Expected annual losses (in total and by hazard), building value and population add up:
#    states, Census regions and divisions and the nation (50 states and DC) are sums of their
#    counties, and so are combined areas. A hazard without a value does not apply to the county
#    (no loss), as in FEMA's own totals.

nri_url <- "https://www.fema.gov/about/reports-and-data/openfema/nri/v120/NRI_Table_Counties.zip"
nri_year <- 2025L
nri_scores <- c("RISK_SCORE", "SOVI_SCORE", "RESL_SCORE", "HWAV_RISKS")
nri_hazards <- c("AVLN", "CFLD", "CWAV", "DRGT", "ERQK", "HAIL", "HWAV", "HRCN", "ISTM", "IFLD", "LNDS", "LTNG",
                 "SWND", "TRND", "TSUN", "VLCN", "WFIR", "WNTW")

# Long form: key, variable, value for counties (all variables) and summed areas (additive ones).
nri_long <- function() {
  memoize("nri_long", function() cached(derived_path("fema_nri", "nri_long", "nri.R"), source = "fema_nri", compute = function() {
    zip <- cached_download(nri_url, cache_path("raw", "fema_nri", "NRI_Table_Counties_v120.zip"), "fema_nri")
    x <- utils::read.csv(unz(zip, "NRI_Table_Counties.csv"), colClasses = "character", check.names = FALSE)
    st <- state_table()
    st <- st[st$in_nation == "TRUE", ]
    x <- x[x$STATEFIPS %in% st$state, , drop = FALSE]
    additive <- c("POPULATION", "BUILDVALUE", "EAL_VALT", "EAL_VALB", paste0(nri_hazards, "_EALT"))
    num <- function(v) suppressWarnings(as.numeric(v))
    values <- as.data.frame(lapply(x[additive], function(v) ifelse(is.na(num(v)), 0, num(v))))
    long <- function(keys, d) {
      data.frame(key = rep(keys, ncol(d)), variable = rep(names(d), each = length(keys)), value = unlist(d, use.names = FALSE),
                 stringsAsFactors = FALSE)
    }
    total <- function(level, codes) {
      a <- stats::aggregate(values, by = list(code = codes), FUN = sum)
      long(paste0(level, ":", a$code), a[additive])
    }
    parent <- st[match(x$STATEFIPS, st$state), ]
    rbind(long(paste0("county:", x$STCOFIPS), cbind(values, as.data.frame(lapply(x[nri_scores], num)))),
          total("state", x$STATEFIPS), total("region", parent$region), total("division", parent$division),
          total("nation", rep("US", nrow(x))))
  }))
}

# One row per requested area and variable; missing values carry the reason.
nri_fetch <- function(variables, pieces, periods, options = list()) {
  d <- nri_long()
  out <- expand.grid(geo = pieces$key, variable = variables, stringsAsFactors = FALSE)
  out$estimate <- d$value[match(paste(out$geo, out$variable), paste(d$key, d$variable))]
  score_elsewhere <- out$variable %in% nri_scores & !startsWith(out$geo, "county:")
  out$status <- ifelse(!is.na(out$estimate), "ok", ifelse(score_elsewhere, "not_applicable", "unavailable"))
  out$note <- ifelse(out$status == "ok", "",
                     ifelse(score_elsewhere, "National Risk Index scores rank counties against each other; there is no score for other areas",
                            "no National Risk Index value for this county (for a hazard score, the hazard is not rated there)"))
  data.frame(out, name = "", moe = NA_real_, bound = NA_character_, period = as.character(nri_year), period_start = nri_year,
             period_end = nri_year, source_id = "fema_nri", stringsAsFactors = FALSE)
}

register_provider("fema_nri", list(
  name = "FEMA National Risk Index (v1.20, December 2025)",
  geo_types = c("nation", "region", "division", "state", "county"),
  fetch = nri_fetch,
  periods = function(settings, recipe) nri_year,
  period_label = function(period) as.character(period),
  period_kind = "snapshot",
  availability_note = "The National Risk Index is used here for counties (states and the nation are sums of counties); FEMA also publishes census tracts, not places."))
