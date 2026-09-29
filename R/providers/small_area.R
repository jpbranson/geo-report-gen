# Census small area estimates through the Census Data API time series (key required):
#  - SAIPE: people in poverty (all ages, ages 0-17), poverty universes, poverty rates and median
#    household income for the nation, states and counties. Comparable from 2005, when the models
#    switched from Current Population Survey to American Community Survey inputs.
#  - SAHIE: people under 65 without health insurance, all incomes and at or below 138% of
#    poverty. Comparable from 2008, when the models switched to ACS inputs.
# Both are model-based single-year estimates with published 90% margins of error. The model
# errors of different counties cannot be combined, so a combined area gets a value but no margin
# of error (`combine_moe = FALSE`). One request per dataset and scope (the nation, all states, or
# the counties of one state) returns every year.

sae_datasets <- c(census_saipe = "timeseries/poverty/saipe", census_sahie = "timeseries/healthins/sahie")

# Our variable name -> the API's estimate and margin-of-error columns. Poverty universes are
# population estimates without a published margin of error.
sae_vars <- list(
  census_saipe = list(SAEPOVALL = c("SAEPOVALL_PT", "SAEPOVALL_MOE"), SAEPOVU_ALL = c("SAEPOVU_ALL", NA),
                      SAEPOVRTALL = c("SAEPOVRTALL_PT", "SAEPOVRTALL_MOE"),
                      SAEPOV0_17 = c("SAEPOV0_17_PT", "SAEPOV0_17_MOE"), SAEPOVU_0_17 = c("SAEPOVU_0_17", NA),
                      SAEPOVRT0_17 = c("SAEPOVRT0_17_PT", "SAEPOVRT0_17_MOE"), SAEMHI = c("SAEMHI_PT", "SAEMHI_MOE")),
  census_sahie = list(NUI = c("NUI_PT", "NUI_MOE"), NIPR = c("NIPR_PT", "NIPR_MOE"), PCTUI = c("PCTUI_PT", "PCTUI_MOE")))

# SAHIE rows used: people under 65 (AGECAT 0) of both sexes and all races. The income group is
# part of our variable name: all incomes (IPRCAT 0) as is, at or below 138% of poverty
# (IPRCAT 3) with the suffix _LOW.
sahie_income <- c(`0` = "", `3` = "_LOW")

sae_scope <- function(type, geoid) {
  switch(type, nation = "nation", state = "state", county = paste0("county-", substr(geoid, 1, 2)))
}

sae_raw <- function(source_id, scope) {
  cached(cache_path("raw", source_id, paste0(scope, ".parquet")), source = source_id, compute = function() {
    cols <- stats::na.omit(unlist(sae_vars[[source_id]]))
    query <- list(get = paste(c("NAME", cols), collapse = ","), time = "from 1989")
    if (source_id == "census_sahie") {
      query <- list(get = paste(c("NAME", "IPRCAT", cols), collapse = ","), time = "from 2006",
                    AGECAT = "0", SEXCAT = "0", RACECAT = "0")
    }
    geo <- switch(sub("-.*$", "", scope), nation = list(`for` = "us:*"), state = list(`for` = "state:*"),
                  county = list(`for` = "county:*", `in` = paste0("state:", sub("^county-", "", scope))))
    census_parse(http_perform(census_request(sae_datasets[[source_id]], c(query, geo))), paste(source_id, scope))
  })
}

# Long form (geo, name, variable, estimate, moe, year) for one dataset and scope.
sae_long <- function(source_id, scope) {
  memoize(paste("sae", source_id, scope, sep = "|"), function() {
    df <- sae_raw(source_id, scope)
    if (source_id == "census_sahie") df <- df[df$IPRCAT %in% names(sahie_income), , drop = FALSE]
    if (!nrow(df)) return(NULL)
    keys <- census_keys(df, scope)
    vars <- sae_vars[[source_id]]
    do.call(rbind, lapply(names(vars), function(v) {
      moe_col <- vars[[v]][2]
      data.frame(geo = keys, name = df$NAME,
                 variable = if (source_id == "census_sahie") paste0(v, sahie_income[df$IPRCAT]) else v,
                 estimate = suppressWarnings(as.numeric(df[[vars[[v]][1]]])),
                 moe = if (is.na(moe_col)) 0 else suppressWarnings(as.numeric(df[[moe_col]])),
                 year = as.integer(df$time), stringsAsFactors = FALSE)
    }))
  })
}

sae_fetch <- function(source_id, variables, pieces, periods) {
  scopes <- unique(mapply(sae_scope, pieces$type, pieces$geoid))
  d <- do.call(rbind, lapply(scopes, function(s) sae_long(source_id, s)))
  if (is.null(d)) return(empty_values())
  d <- d[d$geo %in% pieces$key & d$variable %in% variables & d$year %in% as.integer(periods), , drop = FALSE]
  if (!nrow(d)) return(empty_values())
  data.frame(geo = d$geo, name = d$name, variable = d$variable, estimate = d$estimate, moe = d$moe,
             status = ifelse(is.na(d$estimate), "missing", "ok"), bound = NA_character_, note = "",
             period = as.character(d$year), period_start = d$year, period_end = d$year,
             source_id = source_id, stringsAsFactors = FALSE)
}

register_provider("census_saipe", list(
  name = "U.S. Census Bureau, Small Area Income and Poverty Estimates (SAIPE; Census Data API)",
  geo_types = c("nation", "state", "county"),
  fetch = function(variables, pieces, periods, options = list()) sae_fetch("census_saipe", variables, pieces, periods),
  periods = function(settings, recipe) seq(max(1989L, as.integer(settings$history_start %||% 1989)), 2024L),
  period_label = function(period) as.character(period),
  period_kind = "annual",
  combine_moe = FALSE,
  series = "SAIPE model-based estimates",
  availability_note = "SAIPE publishes counties, states and the nation (and school districts); not places."))

register_provider("census_sahie", list(
  name = "U.S. Census Bureau, Small Area Health Insurance Estimates (SAHIE; Census Data API)",
  geo_types = c("nation", "state", "county"),
  fetch = function(variables, pieces, periods, options = list()) sae_fetch("census_sahie", variables, pieces, periods),
  periods = function(settings, recipe) seq(max(2006L, as.integer(settings$history_start %||% 2006)), 2024L),
  period_label = function(period) as.character(period),
  period_kind = "annual",
  combine_moe = FALSE,
  series = "SAHIE model-based estimates",
  availability_note = "SAHIE publishes counties, states and the nation; not places."))
