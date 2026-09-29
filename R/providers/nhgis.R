# IPUMS NHGIS (National Historical Geographic Information System, University of Minnesota):
# decennial census tables from before the ACS, through the IPUMS API. The key (IPUMS_API_KEY in
# .env) is sent only as the Authorization header, so it never appears in URLs or logs. The terms
# forbid redistributing NHGIS data: extracts stay in the git-ignored cache, and reports cite
# NHGIS in their sources.
#  - Values come from NHGIS "nominally integrated" time series tables: an area is linked across
#    censuses by name and code, on the boundaries of each census. Long-form (sample) values have
#    no margins of error in these tables.
#  - Places and county subdivisions match by their current FIPS codes; areas that no longer
#    exist are dropped. Tracts are not used, because their codes and boundaries change.
#  - Census income and poverty describe the calendar year before the census (recipes mark their
#    dollars "prior_year").
#  - One extract covers every table the catalog's NHGIS recipes use: it is requested, produced
#    by IPUMS (usually a few minutes), downloaded once and kept in the cache.

nhgis_census_years <- c("1970", "1980", "1990", "2000")
# NHGIS geographic levels and the project's geography types.
nhgis_levels <- c(nation = "nation", region = "region", division = "division", state = "state",
                  county = "county", cty_sub = "cousub", place = "place")

nhgis_request <- function(url, query = list(), body = NULL) {
  key <- Sys.getenv("IPUMS_API_KEY")
  if (!nzchar(key)) {
    stop("IPUMS NHGIS needs a free IPUMS API key: add IPUMS_API_KEY=<key> to .env ",
         "(https://account.ipums.org/api_keys).", call. = FALSE)
  }
  req <- http_request(url, "ipums_nhgis", query = query)
  req <- httr2::req_headers(req, Authorization = key, .redact = "Authorization")
  if (!is.null(body)) req <- httr2::req_body_json(req, body)
  req
}

nhgis_get <- function(path, body = NULL) {
  resp <- http_perform(nhgis_request(paste0("https://api.ipums.org/", path), list(collection = "nhgis", version = 2), body))
  check_status(resp, paste("IPUMS NHGIS", path))
  jsonlite::fromJSON(httr2::resp_body_string(resp), simplifyVector = FALSE)
}

# Time series tables the catalog's NHGIS recipes use ("B79", "CL6", ...).
nhgis_tables <- function() {
  r <- recipes()
  r <- r[r$source_id == "ipums_nhgis", , drop = FALSE]
  vars <- unlist(lapply(c(r$numerator, r$denominator, r$published_var), recipe_vars))
  sort(unique(substr(vars, 1, 3)))
}

# A table's census years and geographic levels, from the IPUMS metadata API.
nhgis_table_info <- function(table) {
  cached(cache_path("raw", "ipums_nhgis", "metadata", paste0(table, ".rds")), source = "ipums_nhgis", compute = function() {
    x <- nhgis_get(paste0("metadata/time_series_tables/", table))
    list(years = intersect(nhgis_census_years, vapply(x$years, `[[`, "", "name")),
         levels = intersect(names(nhgis_levels), vapply(x$geogLevels, `[[`, "", "name")))
  })
}

# The extract of `tables` (census years, every level they have) as a zip in the cache,
# requested and downloaded under a file lock like any other download.
nhgis_extract <- function(tables) {
  path <- cache_path("raw", "ipums_nhgis", paste0("census-", paste(tables, collapse = "-"), ".zip"))
  run$used <- c(run$used, path)
  if (file.exists(path) && !wants_refresh(path, "ipums_nhgis")) return(path)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  lock <- filelock::lock(paste0(path, ".lock"), timeout = 60 * 60 * 1000)
  on.exit(filelock::unlock(lock), add = TRUE)
  if (file.exists(path) && !wants_refresh(path, "ipums_nhgis")) return(path)
  specs <- lapply(tables, function(t) {
    info <- nhgis_table_info(t)
    list(geogLevels = as.list(info$levels), years = as.list(info$years))
  })
  x <- nhgis_get("extracts/", body = list(
    timeSeriesTables = stats::setNames(specs, tables), timeSeriesTableLayout = "time_by_row_layout",
    dataFormat = "csv_no_header", breakdownAndDataTypeLayout = "single_file",
    description = "geo-report-gen: census years before the ACS"))
  note("Requested NHGIS extract ", x$number, " (", paste(tables, collapse = ", "), "); waiting for IPUMS to produce it")
  for (i in 1:180) {  # up to 30 minutes
    if (x$status %in% c("completed", "failed", "canceled")) break
    Sys.sleep(10)
    x <- nhgis_get(paste0("extracts/", x$number))
  }
  if (!identical(x$status, "completed")) {
    stop("NHGIS extract ", x$number, " is ", x$status, "; run the build again later.", call. = FALSE)
  }
  tmp <- paste0(path, ".download-", Sys.getpid())
  resp <- http_perform(nhgis_request(x$downloadLinks$tableData$url), path = tmp)
  check_status(resp, paste("IPUMS NHGIS extract", x$number))
  replace_file(tmp, path)
  run$refreshed <- c(run$refreshed, path)
  path
}

# Census values of one extract file: one row per area and census year, keyed like the rest of
# the project ("place:1827000"), one column per NHGIS variable ("B79AA").
nhgis_read_csv <- function(file) {
  d <- utils::read.csv(file, colClasses = "character", check.names = FALSE)
  level <- sub("^.*_ts_nominal_(.*)\\.csv$", "\\1", basename(file))
  # Places and county subdivisions that no longer exist have codes shorter than FIPS codes.
  if (level == "place") d <- d[nchar(d$PLACEA) == 5, , drop = FALSE]
  if (level == "cty_sub") d <- d[nchar(d$CTY_SUBA) == 5, , drop = FALSE]
  id <- switch(level, nation = rep("US", nrow(d)), region = as.integer(d$REGIONA), division = as.integer(d$DIVISIONA),
               state = d$STATEFP, county = paste0(d$STATEFP, d$COUNTYFP),
               cty_sub = paste0(d$STATEFP, d$COUNTYFP, d$CTY_SUBA), place = paste0(d$STATEFP, d$PLACEA))
  # Variables are a table code ending in a digit and a series ("B79AA"), unlike "STATE".
  vars <- grep("^[A-Z][A-Z0-9][0-9][A-Z]{2}$", names(d), value = TRUE)
  out <- data.frame(key = paste0(nhgis_levels[[level]], ":", id), year = as.integer(d$YEAR), lapply(d[vars], as.numeric),
                    check.names = FALSE)
  out[!duplicated(out[c("key", "year")]), , drop = FALSE]  # a few Wisconsin towns are listed twice, identically
}

# Every census value of the catalog's NHGIS tables, all levels in one table.
nhgis_values <- function() {
  tables <- nhgis_tables()
  memoize(paste0("nhgis_values_", paste(tables, collapse = "-")), function() {
    cached(derived_path("ipums_nhgis", paste0("census-", paste(tables, collapse = "-")), "nhgis.R"), source = "ipums_nhgis", compute = function() {
      dir <- tempfile("nhgis")
      on.exit(unlink(dir, recursive = TRUE))
      files <- grep("_ts_nominal_[a-z_]+\\.csv$", utils::unzip(nhgis_extract(tables), exdir = dir), value = TRUE)
      parts <- lapply(files, nhgis_read_csv)
      cols <- unique(unlist(lapply(parts, names)))
      do.call(rbind, lapply(parts, function(p) { p[setdiff(cols, names(p))] <- NA_real_; p[cols] }))
    })
  })
}

nhgis_notes <- c(missing = "not in the NHGIS census tables for this year (the area did not exist then, or had another name or code)",
                 blank = "not tabulated for this area in this census (the 1970 sample tables omit places under 2,500 people)")

nhgis_fetch <- function(variables, pieces, periods, options = list()) {
  d <- nhgis_values()
  g <- expand.grid(geo = pieces$key, year = as.integer(periods), variable = variables, stringsAsFactors = FALSE)
  row <- match(paste(g$geo, g$year), paste(d$key, d$year))
  g$estimate <- mapply(function(r, v) if (is.na(r) || !v %in% names(d)) NA_real_ else d[[v]][r], row, g$variable)
  ok <- !is.na(g$estimate)
  data.frame(geo = g$geo, name = "", variable = g$variable, estimate = g$estimate, moe = NA_real_,
             status = ifelse(ok, "ok", "unavailable"), bound = NA_character_,
             note = ifelse(ok, "", ifelse(is.na(row), nhgis_notes[["missing"]], nhgis_notes[["blank"]])),
             period = as.character(g$year), period_start = g$year, period_end = g$year,
             source_id = "ipums_nhgis", stringsAsFactors = FALSE)
}

register_provider("ipums_nhgis", list(
  name = "IPUMS NHGIS, University of Minnesota, www.nhgis.org (decennial census tables)",
  geo_types = unname(nhgis_levels),
  fetch = nhgis_fetch,
  periods = function(settings, recipe) {
    tables <- unique(substr(unlist(lapply(c(recipe$numerator, recipe$denominator, recipe$published_var), recipe_vars)), 1, 3))
    as.integer(Reduce(intersect, lapply(tables, function(t) nhgis_table_info(t)$years)))
  },
  period_label = function(period) paste(period, "census"),
  period_kind = "point",
  series = "Decennial census (IPUMS NHGIS)",
  availability_note = "NHGIS census tables cover the nation, regions, divisions, states, counties, county subdivisions and places, linked across censuses by name and code."))
