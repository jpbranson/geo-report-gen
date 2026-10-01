# Census Bureau Population Estimates Program (annual July 1 estimates, CSV files).
#
# Each estimates series is kept separate and labeled, because a vintage uses one set of
# boundaries for all its years and series are revised: 2000-2010 intercensal, 2010-2020
# intercensal (2020 boundaries), and Vintage 2025 (2020-2025, boundaries of January 1, 2025).
# Charts draw them as separate lines; nothing is spliced. PEP publishes incorporated
# places and county subdivisions, not census designated places (CDPs).
#
# Vintage 2025 state and county files also carry the components of change for 2021-2025 (natural
# change, domestic and international migration, total change). They come with the previous
# July 1 estimate and the average of the two, the denominators of the yearly change percent and
# of the rates per 1,000 residents (the Census Bureau's rates use that average).

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

# The count columns of pep_long (all but the key, year and series): they add up across areas.
pep_counts <- c("population", "population_prior", "population_avg", "population_change", "natural_change",
                "domestic_migration", "international_migration")

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
      num <- function(col) if (col %in% names(d)) as.numeric(d[[col]]) else rep(NA_real_, nrow(d))
      for (yr in pep_files$first[i]:pep_files$last[i]) {
        if (!paste0("POPESTIMATE", yr) %in% names(d)) next
        # A file's first year changes from April 1, not July 1, so it has no yearly components.
        part <- function(...) if (yr == pep_files$first[i]) rep(NA_real_, nrow(d)) else num(...)
        pop <- num(paste0("POPESTIMATE", yr))
        prior <- part(paste0("POPESTIMATE", yr - 1))
        out[[length(out) + 1]] <- data.frame(key = d$key, year = yr, population = pop, population_prior = prior,
          population_avg = (prior + pop) / 2,
          population_change = part(if (paste0("NPOPCHG_", yr) %in% names(d)) paste0("NPOPCHG_", yr) else paste0("NPOPCHG", yr)),  # state file: NPOPCHG_2021
          natural_change = part(paste0("NATURALCHG", yr)), domestic_migration = part(paste0("DOMESTICMIG", yr)),
          international_migration = part(paste0("INTERNATIONALMIG", yr)), series = pep_files$series[i], stringsAsFactors = FALSE)
      }
    }
    long <- do.call(rbind, out)
    long <- long[!duplicated(long[, c("key", "year")]), ]
    add_state_aggregates(long)
  }))
}

# Sum states (50 + DC) to nation, regions and divisions for years that lack them.
add_state_aggregates <- function(long) {
  states <- long[startsWith(long$key, "state:"), , drop = FALSE]
  states$state <- sub("^state:", "", states$key)
  states <- merge(states, nation_state_table()[, c("state", "region", "division")], by = "state")
  agg <- function(level, codes) {
    a <- stats::aggregate(states[pep_counts], by = list(code = codes, year = states$year, series = states$series), FUN = sum)
    cbind(key = if (level == "nation") "nation:US" else paste0(level, ":", a$code), a[c("year", pep_counts, "series")])
  }
  extra <- rbind(agg("nation", rep("US", nrow(states))), agg("region", states$region), agg("division", states$division))
  extra <- extra[!paste(extra$key, extra$year) %in% paste(long$key, long$year), , drop = FALSE]
  rbind(long, extra)
}

pep_fetch <- function(variables, pieces, periods, options = list()) {
  long <- pep_long()
  d <- long[long$key %in% pieces$key & long$year %in% as.integer(periods), , drop = FALSE]
  if (!nrow(d)) return(empty_values())
  # Components exist only for 2021-2025 and only for states and counties: elsewhere they are absent, not zero.
  out <- do.call(rbind, lapply(intersect(variables, pep_counts), function(v) {
    x <- d[v == "population" | !is.na(d[[v]]), , drop = FALSE]
    if (!nrow(x)) return(NULL)
    data.frame(geo = x$key, name = "", variable = v, estimate = x[[v]], moe = NA_real_,
               status = ifelse(is.na(x[[v]]), "missing", "ok"), bound = NA_character_, note = "",
               period = as.character(x$year), period_start = x$year, period_end = x$year,
               source_id = "census_pep", series = x$series, stringsAsFactors = FALSE)
  }))
  if (is.null(out)) empty_values() else out
}

register_provider("census_pep", list(
  name = "U.S. Census Bureau, Population Estimates Program (annual estimates, July 1)",
  geo_types = c("nation", "region", "division", "state", "county", "place", "place_part", "cousub"),
  fetch = pep_fetch,
  periods = function(settings, recipe) seq(max(2000L, as.integer(settings$history_start %||% 2000)), 2025L),
  period_label = function(period) as.character(period),
  period_kind = "annual",
  availability_note = "PEP publishes incorporated places and county subdivisions, not census designated places (CDPs)."))

# The Vintage 2025 components of change (2021-2025) exist for nation, regions, divisions, states and
# counties only, so they are a second provider: places and county subdivisions are then reported as
# not covered, and their reports show the county and larger areas.
register_provider("census_pep_components", list(
  name = "U.S. Census Bureau, Population Estimates Program, components of change (Vintage 2025)",
  geo_types = c("nation", "region", "division", "state", "county"),
  fetch = function(variables, pieces, periods, options = list()) {
    d <- pep_fetch(variables, pieces, periods, options)
    d$source_id <- rep("census_pep_components", nrow(d))
    d
  },
  periods = function(settings, recipe) seq(max(2021L, as.integer(settings$history_start %||% 2021)), 2025L),
  period_label = function(period) as.character(period),
  period_kind = "annual",
  series = "Estimates 2020–2025 (Vintage 2025)",
  availability_note = "Components of change are published for the nation, regions, divisions, states and counties, not for cities or county subdivisions."))
