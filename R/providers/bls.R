# Bureau of Labor Statistics bulk files (download.bls.gov/pub/time.series/ and bls.gov):
# price indexes for constant dollars and local unemployment. BLS rejects automated requests
# that do not name a contact in the User-Agent, so downloads need GR_HTTP_CONTACT (see
# user_agent_string() in fetch.R); cached files work offline.

bls_download <- function(url, file) {
  path <- cache_path("raw", "bls", file)
  needs_download <- !file.exists(path) || wants_refresh(path, "bls")
  if (needs_download && !nzchar(Sys.getenv("GR_HTTP_CONTACT"))) {
    stop("BLS rejects automated requests without a contact email. Add GR_HTTP_CONTACT=<email> ",
         "to .env, or run offline from the cache.", call. = FALSE)
  }
  cached_download(url, path, "bls")
}

# Annual average price index, as a table (year, index).
#   r_cpi_u_rs  BLS R-CPI-U-RS (all items, retroactive series using current methods), the
#               index the Census Bureau uses for income comparisons over time
#   cpi_u       BLS CPI-U, U.S. city average, all items (CUUR0000SA0), annual average (M13)
price_index_table <- function(index = "r_cpi_u_rs") {
  memoize(paste0("price_index_", index), function() {
    if (index == "cpi_u") {
      f <- bls_download("https://download.bls.gov/pub/time.series/cu/cu.data.1.AllItems", "cu.data.1.AllItems")
      d <- utils::read.delim(f, colClasses = "character", strip.white = TRUE)
      d <- d[trimws(d$series_id) == "CUUR0000SA0" & d$period == "M13", ]
      return(data.frame(year = as.integer(d$year), index = as.numeric(d$value)))
    }
    if (index == "r_cpi_u_rs") {
      f <- bls_download("https://www.bls.gov/cpi/research-series/r-cpi-u-rs-allitems.xlsx", "r-cpi-u-rs-allitems.xlsx")
      x <- readxl::read_excel(f, col_names = FALSE, col_types = "text", .name_repair = "minimal")
      head_row <- which(toupper(trimws(x[[1]])) == "YEAR")[1]
      if (is.na(head_row)) stop("Unexpected layout in the R-CPI-U-RS file (no YEAR header row).")
      hdr <- toupper(trimws(unlist(x[head_row, ])))
      body <- x[(head_row + 1):nrow(x), ]
      avg_col <- which(hdr %in% c("AVG", "ANNUAL", "ANNUAL AVERAGE"))[1]
      yr <- suppressWarnings(as.integer(body[[1]]))
      val <- suppressWarnings(as.numeric(body[[avg_col]]))
      keep <- !is.na(yr) & !is.na(val)
      rs <- data.frame(year = yr[keep], index = val[keep])
      # The series begins in 1978. Earlier years follow the Census Bureau's historical income
      # index (the CPI-U-X1 for 1967-1977 and the CPI-U before, joined by ratio), scaled to meet
      # the R-CPI-U-RS in 1978, as the Census Bureau joins them.
      early <- tryCatch(census_price_history(), error = function(e) {
        warn("Constant dollars before 1978 are unavailable (", conditionMessage(e), ").")
        NULL
      })
      if (is.null(early)) return(rs)
      first <- min(rs$year)
      k <- rs$index[rs$year == first] / early$index[early$year == first]
      early <- early[early$year < first, ]
      return(rbind(data.frame(year = early$year, index = early$index * k), rs))
    }
    stop("Unknown price_index '", index, "' (use r_cpi_u_rs or cpi_u).", call. = FALSE)
  })
}

# The Census Bureau's index for adjusting historical income (table with its income report, P60),
# 1947 on: only its years before 1978 are used, for their year-to-year changes.
census_price_history <- function() {
  url <- "https://www2.census.gov/programs-surveys/demo/tables/p60/289/annual-index-value_annual-percent-change.xls"
  f <- cached_download(url, cache_path("raw", "census_p60", basename(url)), "census_p60")
  x <- readxl::read_excel(f, col_names = FALSE, col_types = "text", .name_repair = "minimal")
  yr <- suppressWarnings(as.integer(x[[1]]))
  val <- suppressWarnings(as.numeric(x[[2]]))
  keep <- !is.na(yr) & !is.na(val) & yr >= 1900
  if (!any(keep)) stop("Unexpected layout in the Census Bureau's historical price index file.")
  data.frame(year = yr[keep], index = val[keep])
}

price_index_label <- function(index) {
  switch(index %||% "r_cpi_u_rs",
         r_cpi_u_rs = "R-CPI-U-RS (BLS consumer price index retroactive series)",
         cpi_u = "CPI-U (BLS consumer price index for all urban consumers)",
         index)
}

# ---- Local Area Unemployment Statistics (LAUS) ------------------------------------------
#
# Annual averages (period M13), not seasonally adjusted. Series IDs are "LAU" + area code
# (15 characters) + measure: 03 unemployment rate, 04 unemployed, 05 employed, 06 labor force, and for
# states only 09 civilian noninstitutional population (07 and 08, the employment-population ratio and
# participation rate, are these counts over the population).
# Area codes: ST{ss}00000000000 (state), CN{ss}{ccc}00000000 (county),
# CT{ss}{ppppp}000000 (cities of 25,000+), RD9{r}00000000000 (Census region),
# RD8{d}00000000000 (Census division). LAUS has no U.S. series (national data come from
# the CPS), so the nation is the sum of the 50 states and DC. The 2015 redesign was carried
# back only to 2010 for counties and cities, so substate series break between 2009 and 2010.

laus_measures <- c(rate = "03", unemployed = "04", employed = "05", labor_force = "06", population = "09")

laus_area_code <- function(type, geoid) {
  switch(type,
    state = paste0("ST", geoid, "00000000000"),
    county = paste0("CN", geoid, "00000000"),
    place = paste0("CT", geoid, "000000"),
    region = paste0("RD9", geoid, "00000000000"),
    division = paste0("RD8", geoid, "00000000000"),
    NA_character_)
}

laus_url <- function(file) paste0("https://download.bls.gov/pub/time.series/la/", file)

laus_file_for_state <- function(state_fips) {
  index <- memoize("laus_index", function() {
    listing <- bls_download(laus_url(""), "la_index.html")
    html <- readLines(listing, warn = FALSE)
    files <- unique(unlist(regmatches(html, gregexpr("la[.]data[.][0-9]+[.][A-Za-z]+", html))))
    data.frame(file = files, key = tolower(sub("^la[.]data[.][0-9]+[.]", "", files)), stringsAsFactors = FALSE)
  })
  name <- tolower(gsub("[^A-Za-z]", "", state_table()$name[state_table()$state == state_fips]))
  hit <- index$file[index$key == name]
  if (!length(hit)) stop("No LAUS file for state ", state_fips)
  hit[1]
}

laus_annual <- function(file) {
  memoize(paste0("laus_", file), function() cached(derived_path("bls", paste0(file, "_M13"), "bls.R"), source = "bls", compute = function() {
    path <- bls_download(laus_url(file), file)
    d <- utils::read.delim(path, colClasses = "character", strip.white = TRUE)
    names(d) <- trimws(names(d))
    d <- d[d$period == "M13", , drop = FALSE]
    data.frame(series_id = trimws(d$series_id), year = as.integer(d$year), value = suppressWarnings(as.numeric(d$value)),
               footnote = trimws(d$footnote_codes), stringsAsFactors = FALSE)
  }))
}

# Counts add up across states: the nation (LAUS has no U.S. series) and the population of regions and divisions.
laus_state_sums <- function(states, key, measures, periods) {
  d <- laus_annual("la.data.2.AllStatesU")
  ids <- unlist(lapply(states, function(s) paste0("LAU", laus_area_code("state", s), measures)))
  d <- d[d$series_id %in% ids & d$year %in% as.integer(periods), ]
  if (!nrow(d)) return(NULL)
  d$measure <- names(laus_measures)[match(substr(d$series_id, 19, 20), laus_measures)]
  agg <- stats::aggregate(value ~ measure + year, data = d, FUN = sum)
  data.frame(geo = key, variable = agg$measure, year = agg$year, value = agg$value, footnote = "",
             series = "LAUS (sum of states)", stringsAsFactors = FALSE)
}

laus_fetch <- function(variables, pieces, periods, options = list()) {
  out <- list()
  measures <- laus_measures[intersect(names(laus_measures), variables)]
  st <- state_table()
  st <- st[st$in_nation == "TRUE", ]
  for (i in seq_len(nrow(pieces))) {
    type <- pieces$type[i]
    geoid <- pieces$geoid[i]
    if (type == "nation") {
      out[[length(out) + 1]] <- laus_state_sums(st$state, pieces$key[i], measures[setdiff(names(measures), "rate")], periods)
      next
    }
    # LAUS has no regional population: it is the sum of the states'.
    if (type %in% c("region", "division") && "population" %in% names(measures)) {
      out[[length(out) + 1]] <- laus_state_sums(st$state[st[[type]] == geoid], pieces$key[i], measures["population"], periods)
    }
    area <- laus_area_code(type, geoid)
    if (is.na(area)) next
    file <- switch(type, state = "la.data.2.AllStatesU", region = , division = "la.data.4.RegionDivisionU",
                   laus_file_for_state(substr(geoid, 1, 2)))
    d <- laus_annual(file)
    ids <- paste0("LAU", area, measures)
    d <- d[d$series_id %in% ids & d$year %in% as.integer(periods), , drop = FALSE]
    if (!nrow(d)) next
    series <- if (type %in% c("county", "place")) ifelse(d$year < 2010, "LAUS (pre-2010 methods)", "LAUS (2010-onward methods)") else "LAUS"
    out[[length(out) + 1]] <- data.frame(geo = pieces$key[i], variable = names(measures)[match(substr(d$series_id, 19, 20), measures)],
                                         year = d$year, value = d$value, footnote = d$footnote, series = series, stringsAsFactors = FALSE)
  }
  d <- do.call(rbind, out)
  if (is.null(d) || !nrow(d)) return(empty_values())
  data.frame(geo = d$geo, name = "", variable = d$variable, estimate = d$value, moe = NA_real_,
             status = ifelse(is.na(d$value), "unavailable", "ok"), bound = NA_character_,
             note = ifelse(grepl("G", d$footnote), "11-month average (October 2025 not collected)", ""),
             period = as.character(d$year), period_start = d$year, period_end = d$year,
             source_id = "bls_laus", series = d$series, stringsAsFactors = FALSE)
}

register_provider("bls_laus", list(
  name = "U.S. Bureau of Labor Statistics, Local Area Unemployment Statistics (annual averages)",
  geo_types = c("nation", "region", "division", "state", "county", "place"),
  fetch = laus_fetch,
  periods = function(settings, recipe) seq(max(1990L, as.integer(settings$history_start %||% 1990)), 2025L),
  period_label = function(period) as.character(period),
  period_kind = "annual",
  availability_note = "LAUS publishes cities of 25,000 or more (and New England towns); smaller places have no series."))
# Labor force participation and employment-population ratios divide LAUS counts by the civilian
# noninstitutional population, which LAUS publishes for states only (regions and the nation add up
# their states'), so they are a second provider: counties and cities report the state instead.
register_provider("bls_laus_rates", list(
  name = "U.S. Bureau of Labor Statistics, Local Area Unemployment Statistics (annual averages), population-based rates",
  geo_types = c("nation", "region", "division", "state"),
  fetch = function(variables, pieces, periods, options = list()) {
    d <- laus_fetch(variables, pieces, periods, options)
    d$source_id <- rep("bls_laus_rates", nrow(d))
    d
  },
  periods = function(settings, recipe) seq(max(1976L, as.integer(settings$history_start %||% 1976)), 2025L),
  period_label = function(period) as.character(period),
  period_kind = "annual",
  series = "LAUS",
  availability_note = "LAUS publishes the population that participation and employment-population rates need for states only; regions and the nation add up their states."))

# ---- Occupational Employment and Wage Statistics (OEWS) ---------------------------------------
#
# May 2025 estimates of employment and wages from BLS's employer survey (the only release in the
# time-series files), for all occupations in all industries, by workplace, for the nation, states
# and metropolitan areas. Series IDs are "OEU" + area type (N, S, M) + area (7) + industry (6, 000000
# is all) + occupation (6, 000000 is all) + data type (01 employment, 04 annual mean wage, 13 annual
# median wage). States are the state code followed by 00000; metropolitan areas are 00 followed by
# the CBSA code. Wages from $239,200 up are published as "#" (not a number here) and values BLS
# cannot publish as "*" or "-"; both are unavailable. Estimates pool three years of survey panels,
# so they are not a series to trend year over year.

oews_url <- "https://download.bls.gov/pub/time.series/oe/oe.data.0.Current"
oews_types <- c(`01` = "EMPLOYMENT", `04` = "MEAN_WAGE", `13` = "MEDIAN_WAGE")

# The all-occupation, all-industry series of the nation, states and metropolitan areas, read in chunks
# from the 330 MB file: key, variable, value (NA if not published).
oews_values <- function() {
  memoize("oews_values", function() cached(derived_path("bls", "oews_values", "bls.R"), source = "bls", compute = function() {
    path <- bls_download(oews_url, "oe.data.0.Current")
    wanted <- function(x, pos) x[grepl("^OEU[NSM][0-9]{7}000000000000(01|04|13)$", x$series_id), , drop = FALSE]
    d <- readr::read_tsv_chunked(path, readr::DataFrameCallback$new(wanted), chunk_size = 500000, progress = FALSE,
                                 col_types = readr::cols(.default = readr::col_character()))
    area <- substr(d$series_id, 5, 11)
    type <- substr(d$series_id, 4, 4)
    key <- ifelse(type == "N", "nation:US", ifelse(type == "S", paste0("state:", substr(area, 1, 2)), paste0("cbsa:", substr(area, 3, 7))))
    data.frame(key = key, variable = unname(oews_types[substr(d$series_id, 24, 25)]), year = as.integer(d$year),
               value = suppressWarnings(as.numeric(d$value)), stringsAsFactors = FALSE)
  }))
}

oews_fetch <- function(variables, pieces, periods, options = list()) {
  d <- oews_values()
  d <- d[d$key %in% pieces$key & d$variable %in% variables & d$year %in% as.integer(periods), , drop = FALSE]
  if (!nrow(d)) return(empty_values())
  data.frame(geo = d$key, name = "", variable = d$variable, estimate = d$value, moe = NA_real_,
             status = ifelse(is.na(d$value), "unavailable", "ok"), bound = NA_character_,
             note = ifelse(is.na(d$value), "not published (wages of $239,200 or more, or estimates BLS cannot release, are not shown as numbers)", ""),
             period = as.character(d$year), period_start = d$year, period_end = d$year, source_id = "bls_oews",
             series = "OEWS May 2025", stringsAsFactors = FALSE)
}

register_provider("bls_oews", list(
  name = "U.S. Bureau of Labor Statistics, Occupational Employment and Wage Statistics (May 2025)",
  geo_types = c("nation", "state", "cbsa"),
  fetch = oews_fetch,
  periods = function(settings, recipe) 2025L,
  period_label = function(period) paste("May", period),
  period_kind = "point",
  series = "OEWS",
  availability_note = paste("OEWS publishes estimates for the nation, states and metropolitan areas (by workplace, employees only), not for counties or",
                            "cities. Only the May 2025 release is read, and estimates pool three years of survey panels.")))

# ---- Current Population Survey: national labor force statistics (LN) --------------------------
#
# Annual averages (period M13) of the not seasonally adjusted national series: LNU04000000 unemployment
# rate, LNU01300000 labor force participation rate and LNU02300000 employment-population ratio, for
# civilians 16 and over, 1948 on (unemployment from 1947 where BLS has it). The states' LAUS estimates
# are controlled to these totals; there are no sub-national CPS series here.

cps_url <- "https://download.bls.gov/pub/time.series/ln/ln.data.1.AllData"
cps_series <- c(LNU04000000 = "UNEMPLOYMENT_RATE", LNU01300000 = "PARTICIPATION_RATE", LNU02300000 = "EMPLOYMENT_POP_RATIO")

cps_values <- function() {
  memoize("cps_values", function() cached(derived_path("bls", "cps_values", "bls.R"), source = "bls", compute = function() {
    path <- bls_download(cps_url, "ln.data.1.AllData")
    wanted <- function(x, pos) x[x$series_id %in% names(cps_series) & x$period == "M13", , drop = FALSE]
    d <- readr::read_tsv_chunked(path, readr::DataFrameCallback$new(wanted), chunk_size = 500000, progress = FALSE,
                                 col_types = readr::cols(.default = readr::col_character()))
    data.frame(variable = unname(cps_series[d$series_id]), year = as.integer(d$year), value = suppressWarnings(as.numeric(d$value)),
               footnote = d$footnote_codes, stringsAsFactors = FALSE)
  }))
}

cps_fetch <- function(variables, pieces, periods, options = list()) {
  d <- cps_values()
  d <- d[d$variable %in% variables & d$year %in% as.integer(periods), , drop = FALSE]
  if (!nrow(d)) return(empty_values())
  data.frame(geo = pieces$key[1], name = "", variable = d$variable, estimate = d$value, moe = NA_real_,
             status = ifelse(is.na(d$value), "unavailable", "ok"), bound = NA_character_,
             note = ifelse(grepl("(^|,)11(,|$)", d$footnote), "11-month average (October 2025 not collected)", ""),   # footnote 11
             period = as.character(d$year), period_start = d$year, period_end = d$year, source_id = "bls_cps_ln",
             series = "CPS annual averages", stringsAsFactors = FALSE)
}

register_provider("bls_cps_ln", list(
  name = "U.S. Bureau of Labor Statistics, Current Population Survey (national annual averages)",
  geo_types = "nation",
  fetch = cps_fetch,
  periods = function(settings, recipe) seq(max(1948L, as.integer(settings$history_start %||% 1948)), 2025L),
  period_label = function(period) as.character(period),
  period_kind = "annual",
  series = "CPS annual averages",
  availability_note = "The Current Population Survey is read here for the nation only; the states' estimates are in the Local Area Unemployment Statistics."))
