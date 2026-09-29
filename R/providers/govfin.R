# Census Bureau, State and Local Government Finances: individual unit files of the 2022 Census of
# Governments (every government; annual surveys in other years sample only some). Two kinds of
# government are used:
#  - county governments, for counties (Connecticut has none, and consolidated city-counties such
#    as Indianapolis count as cities), with variables CO_*;
#  - city (municipal) governments, for places, matched by FIPS place code (CI_*).
# Per government: property tax (T01), all taxes (T codes), long-term debt outstanding (49U), police
# protection current operations (E62), in $1,000, and the population the Census Bureau assigns it
# (POP). Items a government does not report are zero. States, regions, divisions and the nation
# are sums of all their county (or city) governments. Values include the Census Bureau's
# imputations for governments that did not respond.

govfin_year <- 2022L
govfin_url <- "https://www2.census.gov/programs-surveys/gov-finances/tables/2022/2022_Individual_Unit_File.zip"

# One row per county or city government: key, prefix (CO or CI), state and the variables.
govfin_units <- function() {
  memoize("govfin_units", function() cached(derived_path("census_govfin", "units_2022", "govfin.R"), source = "census_govfin", compute = function() {
    zip <- cached_download(govfin_url, cache_path("raw", "census_govfin", basename(govfin_url)), "census_govfin")
    dir <- "2022_Individual_Unit_files/"
    read <- function(file, widths, names) {
      as.data.frame(readr::read_fwf(unz(zip, paste0(dir, file)), readr::fwf_widths(widths, names),
                                    col_types = readr::cols(.default = "c"), progress = FALSE))
    }
    pid <- read("Fin_PID_2022.txt", c(12, 64, 35, 5, 9), c("id", "name", "county_name", "place", "pop"))
    pid <- pid[substr(pid$id, 3, 3) %in% c("1", "2"), , drop = FALSE]
    items <- read("2022FinEstDAT_07152026modp.txt", c(12, 3, 12), c("id", "item", "amount"))
    items <- items[items$id %in% pid$id, , drop = FALSE]
    amount <- function(keep) {
      a <- tapply(as.numeric(items$amount[keep]), items$id[keep], sum)
      v <- unname(a[pid$id])
      ifelse(is.na(v), 0, v)
    }
    county <- substr(pid$id, 3, 3) == "1"
    data.frame(key = ifelse(county, paste0("county:", substr(pid$id, 1, 2), substr(pid$id, 4, 6)), paste0("place:", substr(pid$id, 1, 2), pid$place)),
               prefix = ifelse(county, "CO", "CI"), state = substr(pid$id, 1, 2),
               T01 = amount(items$item == "T01"), TAX = amount(startsWith(items$item, "T")), DEBT = amount(items$item == "49U"),
               POLICE = amount(items$item == "E62"), POP = as.numeric(pid$pop), stringsAsFactors = FALSE)
  }))
}

govfin_vars <- c("T01", "TAX", "DEBT", "POLICE", "POP")

govfin_fetch <- function(variables, pieces, periods, options = list()) {
  u <- govfin_units()
  u <- u[!is.na(u$POP) & u$POP > 0, , drop = FALSE]
  st <- state_table()
  st <- st[st$in_nation == "TRUE", ]
  u$region <- st$region[match(u$state, st$state)]
  u$division <- st$division[match(u$state, st$state)]
  rows <- lapply(seq_len(nrow(pieces)), function(i) {
    p <- pieces[i, ]
    lapply(c("CO", "CI"), function(prefix) {
      mine <- u[u$prefix == prefix, , drop = FALSE]
      own <- (prefix == "CO" && p$type == "county") || (prefix == "CI" && p$type == "place")
      pick <- switch(p$type, county = , place = mine$key == p$key, state = mine$state == p$geoid,
                     region = mine$region %in% p$geoid, division = mine$division %in% p$geoid, nation = mine$state %in% st$state)
      status <- if (!own && p$type %in% c("county", "place")) "not_applicable" else if (any(pick)) "ok" else "unavailable"
      note <- switch(status, ok = "",
                     not_applicable = if (prefix == "CO") "county government finances describe counties" else "city government finances describe cities (incorporated places)",
                     unavailable = if (prefix == "CO") "no county government in the Census of Governments (Connecticut has none; consolidated city-counties count as cities)" else
                       "no city government in the Census of Governments (census designated places have none)")
      data.frame(geo = p$key, variable = paste0(prefix, "_", govfin_vars),
                 estimate = if (status == "ok") colSums(mine[pick, govfin_vars, drop = FALSE]) else NA_real_,
                 status = status, note = note, stringsAsFactors = FALSE)
    })
  })
  d <- do.call(rbind, unlist(rows, recursive = FALSE))
  d <- d[d$variable %in% variables, , drop = FALSE]
  data.frame(d, name = "", moe = NA_real_, bound = NA_character_, period = as.character(govfin_year), period_start = govfin_year,
             period_end = govfin_year, source_id = "census_govfin", stringsAsFactors = FALSE)
}

register_provider("census_govfin", list(
  name = "U.S. Census Bureau, 2022 Census of Governments: Finance (individual unit files)",
  geo_types = c("nation", "region", "division", "state", "county", "place"),
  fetch = govfin_fetch,
  periods = function(settings, recipe) govfin_year,
  period_label = function(period) paste0("FY", period),
  period_kind = "annual",
  availability_note = "Finances of county governments (for counties) and city governments (for incorporated places); states and the nation sum them."))
