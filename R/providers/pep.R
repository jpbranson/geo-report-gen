# Census Bureau Population Estimates Program (annual July 1 estimates, CSV files) and
# historical decennial county counts 1900-1990.
#
# Each estimates series is kept separate and labeled, because a vintage uses one set of
# boundaries for all its years and series are revised: 2000-2010 intercensal, 2010-2020
# intercensal (2020 boundaries), and Vintage 2025 (2020-2025, boundaries of January 1, 2025).
# Charts draw them as separate lines; nothing is spliced. PEP publishes incorporated
# places and county subdivisions, not census designated places (CDPs).

pep_base <- "https://www2.census.gov/programs-surveys/popest/datasets/"

pep_files <- data.frame(
  file = c("2020-2025/state/totals/NST-EST2025-ALLDATA.csv",
           "2020-2025/counties/totals/co-est2025-alldata.csv",
           "2020-2025/cities/totals/sub-est2025.csv",
           "2010-2020/intercensal/cities/sub-est2020int.csv",
           "2000-2010/intercensal/county/co-est00int-tot.csv",
           "2000-2010/intercensal/cities/sub-est00int.csv"),
  first = c(2020, 2020, 2020, 2010, 2000, 2000),
  last = c(2025, 2025, 2025, 2019, 2009, 2009),
  series = c(rep("Estimates 2020–2025 (Vintage 2025)", 3), "Estimates 2010–2019 (intercensal)",
             rep("Estimates 2000–2009 (intercensal)", 2)),
  stringsAsFactors = FALSE)

pep_read <- function(file) {
  path <- cached_download(paste0(pep_base, file), cache_path("raw", "census_pep", basename(file)), "census_pep")
  # PEP files are Latin-1 encoded (e.g. "Dona Ana" with a tilde).
  as.data.frame(readr::read_csv(path, col_types = readr::cols(.default = "c"), locale = readr::locale(encoding = "latin1"),
                                progress = FALSE, show_col_types = FALSE))
}

pad <- function(x, n) formatC(as.integer(x), width = n, flag = "0")

# Geography keys for one PEP file's rows (summary levels differ between files).
pep_keys <- function(d) {
  lev <- pad(d$SUMLEV, 3)
  st <- pad(d$STATE, 2)
  key <- rep(NA_character_, nrow(d))
  if ("REGION" %in% names(d)) {
    key[lev == "010"] <- "nation:US"
    key[lev == "020"] <- paste0("region:", as.integer(d$REGION[lev == "020"]))
    key[lev == "030"] <- paste0("division:", as.integer(d$DIVISION[lev == "030"]))
  }
  key[lev == "040"] <- paste0("state:", st[lev == "040"])
  if ("COUNTY" %in% names(d)) {
    co <- pad(d$COUNTY, 3)
    key[lev == "050"] <- paste0("county:", st[lev == "050"], co[lev == "050"])
  }
  if ("PLACE" %in% names(d)) {
    pl <- pad(d$PLACE, 5)
    co <- pad(d$COUNTY, 3)
    key[lev == "162"] <- paste0("place:", st[lev == "162"], pl[lev == "162"])
    key[lev == "157"] <- paste0("place_part:", st[lev == "157"], pl[lev == "157"], "-", st[lev == "157"], co[lev == "157"])
    key[lev == "061"] <- paste0("cousub:", st[lev == "061"], co[lev == "061"], pad(d$COUSUB[lev == "061"], 5))
  }
  key
}

# All PEP series as one long table (key, year, population, series), built once from the raw
# files and cached. Nation, regions and divisions are summed from states where a file has
# no national rows (the intercensal files): estimates are additive counts.
pep_long <- function() {
  path <- derived_path("census_pep", "pep_long", "pep.R")
  memoize("pep_long", function() cached(path, source = "census_pep", compute = function() {
    out <- list()
    for (i in seq_len(nrow(pep_files))) {
      d <- pep_read(pep_files$file[i])
      d$key <- pep_keys(d)
      d <- d[!is.na(d$key) & !duplicated(d$key), , drop = FALSE]
      for (yr in pep_files$first[i]:pep_files$last[i]) {
        col <- paste0("POPESTIMATE", yr)
        if (!col %in% names(d)) next
        out[[length(out) + 1]] <- data.frame(key = d$key, year = yr, population = as.numeric(d[[col]]),
                                             series = pep_files$series[i], stringsAsFactors = FALSE)
      }
    }
    long <- do.call(rbind, out)
    long <- long[!duplicated(long[, c("key", "year")]), ]
    add_state_aggregates(long)
  }))
}

# Sum states (50 + DC) to nation, regions and divisions for years that lack them.
add_state_aggregates <- function(long) {
  st <- state_table()
  states <- long[startsWith(long$key, "state:"), , drop = FALSE]
  states$state <- sub("^state:", "", states$key)
  states <- merge(states, st[st$in_nation == "TRUE", c("state", "region", "division")], by = "state")
  agg <- function(level, codes) {
    a <- stats::aggregate(states$population, by = list(code = codes, year = states$year, series = states$series), FUN = sum)
    data.frame(key = if (level == "nation") "nation:US" else paste0(level, ":", a$code), year = a$year,
               population = a$x, series = a$series, stringsAsFactors = FALSE)
  }
  extra <- rbind(agg("nation", rep("US", nrow(states))), agg("region", states$region), agg("division", states$division))
  extra <- extra[!paste(extra$key, extra$year) %in% paste(long$key, long$year), , drop = FALSE]
  rbind(long, extra)
}

pep_fetch <- function(variables, pieces, periods, options = list()) {
  long <- pep_long()
  d <- long[long$key %in% pieces$key & long$year %in% as.integer(periods), , drop = FALSE]
  if (!nrow(d)) return(empty_values())
  data.frame(geo = d$key, name = "", variable = "population", estimate = d$population, moe = NA_real_,
             status = ifelse(is.na(d$population), "missing", "ok"), bound = NA_character_, note = "",
             period = as.character(d$year), period_start = d$year, period_end = d$year,
             source_id = "census_pep", series = d$series, stringsAsFactors = FALSE)
}

register_provider("census_pep", list(
  name = "U.S. Census Bureau, Population Estimates Program (annual estimates, July 1)",
  geo_types = c("nation", "region", "division", "state", "county", "place", "place_part", "cousub"),
  fetch = pep_fetch,
  periods = function(settings, recipe) seq(max(2000L, as.integer(settings$history_start %||% 2000)), 2025L),
  period_label = function(period) as.character(period),
  period_kind = "annual",
  availability_note = "PEP publishes incorporated places and county subdivisions, not census designated places (CDPs)."))

# ---- Historical decennial county counts, 1900-1990 -----------------------------------------

# "Population of Counties by Decennial Census: 1900 to 1990" (U.S. Census Bureau). The
# original census.gov files now return 404; this is the machine-readable copy maintained by
# NBER (values checked against official totals, e.g. U.S. 1990 = 248,709,873). Counts use
# the county boundaries of each census; counties later created or merged are not harmonized.
hist_counts <- function() {
  memoize("hist_counts", function() cached(derived_path("census_hist", "cencounts_long", "pep.R"), source = "census_hist", compute = function() {
    f <- cached_download("https://data.nber.org/census/population/cencounts/cencounts.csv",
                         cache_path("raw", "census_hist", "cencounts.csv"), "census_hist")
    d <- utils::read.csv(f, colClasses = "character")
    fips <- pad(d$fips, 5)
    key <- ifelse(fips == "00000", "nation:US", ifelse(substr(fips, 3, 5) == "000", paste0("state:", substr(fips, 1, 2)), paste0("county:", fips)))
    long <- do.call(rbind, lapply(seq(1900, 1990, 10), function(yr) {
      data.frame(key = key, year = yr, population = suppressWarnings(as.numeric(d[[paste0("pop", yr)]])),
                 series = "Census count", stringsAsFactors = FALSE)
    }))
    long <- long[!is.na(long$population), ]
    add_state_aggregates(long)
  }))
}

register_provider("census_hist", list(
  name = "U.S. Census Bureau, county population by decennial census 1900-1990 (NBER machine-readable copy)",
  geo_types = c("nation", "region", "division", "state", "county"),
  fetch = function(variables, pieces, periods, options = list()) {
    d <- hist_counts()
    d <- d[d$key %in% pieces$key & d$year %in% as.integer(periods), , drop = FALSE]
    if (!nrow(d)) return(empty_values())
    data.frame(geo = d$key, name = "", variable = "population", estimate = d$population, moe = 0, status = "ok",
               bound = NA_character_, note = "", period = as.character(d$year), period_start = d$year,
               period_end = d$year, source_id = "census_hist", series = d$series, stringsAsFactors = FALSE)
  },
  periods = function(settings, recipe) seq(1900L, 1990L, 10L)[seq(1900L, 1990L, 10L) >= as.integer(settings$history_start %||% 1900)],
  period_label = function(period) as.character(period),
  period_kind = "point"))
