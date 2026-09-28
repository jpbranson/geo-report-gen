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
      x <- readxl::read_excel(f, col_names = FALSE, col_types = "text")
      head_row <- which(toupper(trimws(x[[1]])) == "YEAR")[1]
      if (is.na(head_row)) stop("Unexpected layout in the R-CPI-U-RS file (no YEAR header row).")
      hdr <- toupper(trimws(unlist(x[head_row, ])))
      body <- x[(head_row + 1):nrow(x), ]
      avg_col <- which(hdr %in% c("AVG", "ANNUAL", "ANNUAL AVERAGE"))[1]
      yr <- suppressWarnings(as.integer(body[[1]]))
      val <- suppressWarnings(as.numeric(body[[avg_col]]))
      keep <- !is.na(yr) & !is.na(val)
      return(data.frame(year = yr[keep], index = val[keep]))
    }
    stop("Unknown price_index '", index, "' (use r_cpi_u_rs or cpi_u).", call. = FALSE)
  })
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
# (15 characters) + measure: 03 unemployment rate, 04 unemployed, 05 employed, 06 labor force.
# Area codes: ST{ss}00000000000 (state), CN{ss}{ccc}00000000 (county),
# CT{ss}{ppppp}000000 (cities of 25,000+), RD9{r}00000000000 (Census region),
# RD8{d}00000000000 (Census division). LAUS has no U.S. series (national data come from
# the CPS), so the nation is the sum of the 50 states and DC. The 2015 redesign was carried
# back only to 2010 for counties and cities, so substate series break between 2009 and 2010.

laus_measures <- c(rate = "03", unemployed = "04", employed = "05", labor_force = "06")

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

laus_fetch <- function(variables, pieces, periods, options = list()) {
  out <- list()
  measures <- laus_measures[intersect(names(laus_measures), variables)]
  for (i in seq_len(nrow(pieces))) {
    type <- pieces$type[i]
    geoid <- pieces$geoid[i]
    if (type == "nation") {
      states <- state_table()$state[state_table()$in_nation == "TRUE"]
      d <- laus_annual("la.data.2.AllStatesU")
      ids <- unlist(lapply(states, function(s) paste0("LAU", laus_area_code("state", s), measures[c("unemployed", "labor_force")])))
      d <- d[d$series_id %in% ids & d$year %in% as.integer(periods), ]
      d$measure <- names(laus_measures)[match(substr(d$series_id, 19, 20), laus_measures)]
      agg <- stats::aggregate(value ~ measure + year, data = d, FUN = sum)
      rows <- agg[agg$measure %in% names(measures), ]
      out[[length(out) + 1]] <- data.frame(geo = pieces$key[i], variable = rows$measure, year = rows$year, value = rows$value,
                                           footnote = "", series = "LAUS (sum of states)", stringsAsFactors = FALSE)
      next
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
