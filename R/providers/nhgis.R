# IPUMS NHGIS (National Historical Geographic Information System, University of Minnesota):
# census tables and County Business Patterns from before the project's other sources, through
# the IPUMS API. The key (IPUMS_API_KEY in .env) is sent only as the Authorization header, so it
# never appears in URLs or logs. The terms forbid redistributing NHGIS data: extracts stay in the
# git-ignored cache, and reports cite NHGIS in their sources.
#  - Census values come from NHGIS "nominally integrated" time series tables: an area is linked
#    across censuses by name and code, on the boundaries of each census. Long-form (sample)
#    values have no margins of error in these tables.
#  - Places and county subdivisions match by their current FIPS codes; areas that no longer
#    exist are dropped. Tracts are not used, because their codes and boundaries change.
#  - Census income and poverty describe the calendar year before the census (recipes mark their
#    dollars "prior_year").
#  - County Business Patterns 1970-1997 (SIC industry codes) come from NHGIS source datasets, as
#    all-industry totals: a separate source (ipums_nhgis_cbp), because they are annual.
#  - Each extract (census tables; CBP) is requested, produced by IPUMS (several minutes),
#    downloaded once and kept in the cache.

nhgis_census_years <- c("1970", "1980", "1990", "2000")  # long-form tables, unless a recipe names years
# NHGIS geographic levels and the project's geography types.
nhgis_levels <- c(nation = "nation", region = "region", division = "division", state = "state",
                  county = "county", cty_sub = "cousub", place = "place")

# County Business Patterns before NAICS: NHGIS datasets, the breakdown for all industries, and
# the source tables used. 1970-1973 have no annual payroll or establishment counts; the national
# files start in 1977 and the state files skip 1971, 1973 and 1976.
nhgis_cbp <- local({
  totals <- c(SIC_EMP = "NT001", SIC_PAYANN = "NT003", SIC_ESTAB = "NT004")
  list(`1970_1971_CBP` = list(breakdown = "bs28.si----", tables = totals["SIC_EMP"]),
       `1972_1973_CBP` = list(breakdown = "bs28.si----", tables = totals["SIC_EMP"]),
       `1974_1987_CBPa` = list(breakdown = "bs29.si----", tables = totals),
       `1974_1987_CBPb` = list(breakdown = "bs29.si----", tables = totals),
       `1988_1997_CBPa` = list(breakdown = "bs30.si----", tables = totals),
       `1988_1997_CBPb` = list(breakdown = "bs30.si----", tables = totals))
})

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

# Census years, geographic levels and table codes of a time series table or a dataset (IPUMS
# metadata API; `kind` is "time_series_tables" or "datasets").
nhgis_info <- function(kind, name) {
  memoize(paste("nhgis_info", kind, name), function() {
    cached(cache_path("raw", "ipums_nhgis", "metadata", kind, paste0(name, ".rds")), source = "ipums_nhgis", compute = function() {
      x <- nhgis_get(paste0("metadata/", kind, "/", name))
      years <- vapply(x$years, function(y) as.character(if (is.list(y)) y$name else y), "")
      tables <- x$dataTables %||% list()
      list(years = years[grepl("^[0-9]{4}$", years)],
           levels = intersect(names(nhgis_levels), vapply(x$geogLevels, `[[`, "", "name")),
           codes = stats::setNames(vapply(tables, `[[`, "", "nhgisCode"), vapply(tables, `[[`, "", "name")))
    })
  })
}

# Census years of each time series table the catalog's NHGIS recipes use: the years a recipe
# names for a variable ("1790:A00AA; ..."), otherwise the table's census years 1970-2000.
nhgis_table_years <- function() {
  r <- recipes()
  exprs <- unlist(r[r$source_id == "ipums_nhgis", c("numerator", "denominator")])
  pairs <- do.call(rbind, lapply(exprs[!is.na(exprs) & nzchar(exprs)], function(e) {
    if (grepl(":", e, fixed = TRUE)) {
      map <- parse_period_vars(e)
      return(data.frame(table = substr(unlist(map), 1, 3), year = rep(names(map), lengths(map))))
    }
    tables <- unique(substr(recipe_vars(e), 1, 3))
    do.call(rbind, lapply(tables, function(t) data.frame(table = t, year = nhgis_default_years(t))))
  }))
  pairs <- unique(pairs)
  split(pairs$year, pairs$table)
}

# Without the table's metadata (no API key and nothing cached), the project's census years stand
# in, so a report still lists those years, unavailable with the reason the data could not be read.
nhgis_default_years <- function(table) {
  years <- tryCatch(nhgis_info("time_series_tables", table)$years, error = function(e) nhgis_census_years)
  intersect(nhgis_census_years, years)
}

# An extract as a zip in the cache (named by its request), requested and downloaded under a file
# lock like any other download.
nhgis_extract <- function(name, body, link = "tableData") {   # link: "tableData" or, for shapefiles, "gisData"
  path <- cache_path("raw", "ipums_nhgis", paste0(name, ".zip"))
  run$used <- c(run$used, path)
  if (file.exists(path) && !wants_refresh(path, "ipums_nhgis")) return(path)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  lock <- filelock::lock(paste0(path, ".lock"), timeout = 60 * 60 * 1000)
  on.exit(filelock::unlock(lock), add = TRUE)
  if (file.exists(path) && !wants_refresh(path, "ipums_nhgis")) return(path)
  x <- nhgis_get("extracts/", body = body)
  note("Requested NHGIS extract ", x$number, " (", name, "); waiting for IPUMS to produce it")
  for (i in 1:180) {  # up to 30 minutes
    if (x$status %in% c("completed", "failed", "canceled")) break
    Sys.sleep(10)
    x <- nhgis_get(paste0("extracts/", x$number))
  }
  if (!identical(x$status, "completed")) {
    stop("NHGIS extract ", x$number, " is ", x$status, "; run the build again later.", call. = FALSE)
  }
  tmp <- paste0(path, ".download-", Sys.getpid())
  resp <- http_perform(nhgis_request(x$downloadLinks[[link]]$url), path = tmp)
  check_status(resp, paste("IPUMS NHGIS extract", x$number))
  replace_file(tmp, path)
  run$refreshed <- c(run$refreshed, path)
  write_json_file(list(extract = x$number, retrieved = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")), paste0(path, ".meta.json"))
  path
}

# Values of one extract file: one row per area and year, keyed like the rest of the project
# ("place:1827000"), one column per variable. Time series variables are a table code ending in
# a digit and a series ("B79AA", unlike "STATE"); dataset columns are renamed by `codes`
# ("C4S001" -> "SIC_EMP"), and their suppression flag is kept as `flag`.
nhgis_read_csv <- function(file, codes = character()) {
  d <- utils::read.csv(file, colClasses = "character", check.names = FALSE)
  level <- sub("^.*_(nation|region|division|state|county|cty_sub|place)\\.csv$", "\\1", basename(file))
  # Places and county subdivisions that no longer exist have codes shorter than FIPS codes.
  if (level == "place") d <- d[nchar(d$PLACEA) == 5, , drop = FALSE]
  if (level == "cty_sub") d <- d[nchar(d$CTY_SUBA) == 5, , drop = FALSE]
  if (!nrow(d)) return(NULL)  # some CBP files have no rows
  st <- d$STATEFP %||% d$STATEA
  co <- d$COUNTYFP %||% d$COUNTYA
  id <- switch(level, nation = rep("US", nrow(d)), region = as.integer(d$REGIONA), division = as.integer(d$DIVISIONA),
               state = st, county = paste0(st, co), cty_sub = paste0(st, co, d$CTY_SUBA), place = paste0(st, d$PLACEA))
  out <- data.frame(key = paste0(nhgis_levels[[level]], ":", id), year = as.integer(d$YEAR))
  for (v in grep("^[A-Z][A-Z0-9][0-9][A-Z]{2}$", names(d), value = TRUE)) out[[v]] <- as.numeric(d[[v]])
  flag <- d$TOTFLAG
  for (v in intersect(names(codes), names(d))) {
    x <- suppressWarnings(as.numeric(d[[v]]))
    letter <- nzchar(d[[v]]) & is.na(x)  # a few 1970 cells hold "D" (withheld) instead of a number
    flag[letter] <- d[[v]][letter]
    out[[codes[[v]]]] <- x
  }
  if (!is.null(flag)) out$flag <- flag
  out[!duplicated(out[c("key", "year")]), , drop = FALSE]  # a few Wisconsin towns are listed twice, identically
}

# Every file of an extract in one table, cached as parquet (rebuilt from the zip when this
# parser changes).
nhgis_read_extract <- function(name, body, codes = character()) {
  name <- paste0(name, "-", substr(digest::digest(body), 1, 8))
  memoize(paste0("nhgis_", name), function() {
    d <- cached(derived_path("ipums_nhgis", name, "nhgis.R"), source = "ipums_nhgis", compute = function() {
      dir <- tempfile("nhgis")
      on.exit(unlink(dir, recursive = TRUE))
      files <- grep("_(nation|region|division|state|county|cty_sub|place)\\.csv$", utils::unzip(nhgis_extract(name, body), exdir = dir), value = TRUE)
      parts <- Filter(Negate(is.null), lapply(files, nhgis_read_csv, codes = codes))
      cols <- unique(unlist(lapply(parts, names)))
      do.call(rbind, lapply(parts, function(p) { p[setdiff(cols, names(p))] <- NA; p[cols] }))
    })
    d$lookup <- paste(d$key, d$year)   # built once per session: nhgis_rows matches on it for every metric
    d
  })
}

# The extract request for the catalog's time series tables (census years, all levels).
nhgis_census_request <- function() {
  years <- nhgis_table_years()
  specs <- lapply(names(years), function(t) {
    list(geogLevels = as.list(nhgis_info("time_series_tables", t)$levels), years = as.list(years[[t]]))
  })
  list(timeSeriesTables = stats::setNames(specs, names(years)), timeSeriesTableLayout = "time_by_row_layout",
       dataFormat = "csv_no_header", breakdownAndDataTypeLayout = "single_file", description = "geo-report-gen: census years")
}

# The extract request for County Business Patterns 1970-1997 (all-industry totals).
nhgis_cbp_request <- function() {
  specs <- lapply(names(nhgis_cbp), function(d) {
    info <- nhgis_info("datasets", d)
    list(dataTables = as.list(unname(nhgis_cbp[[d]]$tables)), geogLevels = as.list(info$levels),
         years = as.list(info$years), breakdownValues = list(nhgis_cbp[[d]]$breakdown))
  })
  list(datasets = stats::setNames(specs, names(nhgis_cbp)), dataFormat = "csv_no_header",
       breakdownAndDataTypeLayout = "single_file", description = "geo-report-gen: County Business Patterns 1970-1997")
}

# CBP dataset columns and what they hold ("C4S001" = "SIC_EMP").
nhgis_cbp_codes <- function() {
  unlist(lapply(names(nhgis_cbp), function(d) {
    t <- nhgis_cbp[[d]]$tables
    stats::setNames(names(t), paste0(nhgis_info("datasets", d)$codes[t], "001"))
  }))
}

nhgis_values <- function() nhgis_read_extract("census", nhgis_census_request())

nhgis_cbp_values <- function() {
  memoize("nhgis_cbp_values", function() {
    d <- nhgis_read_extract("cbp", nhgis_cbp_request(), nhgis_cbp_codes())
    # The 1975 state file gives annual payroll in thousands of dollars (every other file in dollars).
    in_thousands <- grepl("^state:", d$key) & d$year == 1975
    d$SIC_PAYANN[in_thousands] <- 1000 * d$SIC_PAYANN[in_thousands]
    d
  })
}

# Long rows for every piece, period and variable of a table of values, with each value's status
# and the reason for a missing one (`why(row, variable)`).
nhgis_rows <- function(d, variables, pieces, periods, source_id, why) {
  g <- expand.grid(geo = pieces$key, year = as.integer(periods), variable = variables, stringsAsFactors = FALSE)
  row <- match(paste(g$geo, g$year), d$lookup)
  estimate <- mapply(function(r, v) if (is.na(r) || !v %in% names(d)) NA_real_ else d[[v]][r], row, g$variable)
  reason <- why(row, g)
  status <- ifelse(!nzchar(reason$status), ifelse(is.na(estimate), "unavailable", "ok"), reason$status)
  data.frame(geo = g$geo, name = "", variable = g$variable, estimate = ifelse(status == "ok", estimate, NA_real_), moe = NA_real_,
             status = status, bound = NA_character_, note = ifelse(status == "ok", "", reason$note),
             period = as.character(g$year), period_start = g$year, period_end = g$year,
             source_id = source_id, stringsAsFactors = FALSE)
}

nhgis_notes <- c(missing = "not in the NHGIS census tables for this year (the area did not exist then, or had another name or code)",
                 blank = "not tabulated for this area in this census (the 1970 sample tables omit places under 2,500 people)",
                 cbp_missing = "no County Business Patterns file for this area and year (the national files start in 1977; the state files skip 1971, 1973 and 1976)",
                 cbp_blank = "not published for this year (1970-1973 have no annual payroll or establishment counts)",
                 cbp_withheld = "withheld to avoid disclosing data of individual businesses")

# Connecticut's planning regions (county-equivalents from 2022) have no census rows of their own.
# Counts are summed from their towns, which kept their codes; a region-year lacking any town's
# value stays missing. Medians and other published values cannot be summed.
ct_region_rows <- function(d, variables) {
  variables <- intersect(variables, names(d))
  regions <- ct_town_regions()
  towns <- d[startsWith(d$key, "cousub:09"), , drop = FALSE]
  towns$region <- regions[substr(towns$key, nchar(towns$key) - 4, nchar(towns$key))]
  towns <- towns[!is.na(towns$region), , drop = FALSE]
  if (!nrow(towns) || !length(variables)) return(d[0, , drop = FALSE])
  by <- list(region = towns$region, year = towns$year)
  out <- stats::aggregate(towns[variables], by, sum)   # a missing town value makes the sum missing
  n <- stats::aggregate(list(n = towns$key), by, length)$n
  out[n < as.vector(table(regions)[out$region]), variables] <- NA
  rows <- d[rep(NA_integer_, nrow(out)), , drop = FALSE]
  rows$key <- paste0("county:", out$region)
  rows$year <- out$year
  rows[variables] <- out[variables]
  rows$lookup <- paste(rows$key, rows$year)
  rows
}

nhgis_fetch <- function(variables, pieces, periods, options = list()) {
  d <- nhgis_values()
  if (any(grepl("^county:091[1-9]0$", pieces$key)) && isTRUE(options$recipe$stat_type %in% c("count", "share", "ratio"))) {
    d <- rbind(d, ct_region_rows(d, variables))
  }
  nhgis_rows(d, variables, pieces, periods, "ipums_nhgis", function(row, g) {
    # A table NHGIS has only for some levels (A00: the nation, states and counties).
    tables <- substr(g$variable, 1, 3)
    levels <- lapply(stats::setNames(nm = unique(tables)), function(t) nhgis_info("time_series_tables", t)$levels)
    applies <- mapply(`%in%`, names(nhgis_levels)[match(sub(":.*$", "", g$geo), nhgis_levels)], levels[tables])
    only <- vapply(levels[tables], function(l) {
      n <- geo_type_names[nhgis_levels[l]]
      if (length(n) > 1) paste(paste(n[-length(n)], collapse = ", "), "and", n[length(n)]) else n
    }, "")
    list(status = ifelse(applies, "", "not_applicable"),
         note = ifelse(!applies, paste0("NHGIS has this census table only for ", only),
                       ifelse(is.na(row), nhgis_notes[["missing"]], nhgis_notes[["blank"]])))
  })
}

nhgis_cbp_fetch <- function(variables, pieces, periods, options = list()) {
  d <- nhgis_cbp_values()
  nhgis_rows(d, variables, pieces, periods, "ipums_nhgis_cbp", function(row, g) {
    # A flagged total withholds employment and payroll; establishment counts are always published.
    flag <- if (is.null(d$flag)) rep(NA_character_, length(row)) else d$flag[row]
    withheld <- !is.na(flag) & nzchar(flag) & g$variable != "SIC_ESTAB"
    list(status = ifelse(withheld, "suppressed", ""),
         note = ifelse(withheld, nhgis_notes[["cbp_withheld"]], ifelse(is.na(row), nhgis_notes[["cbp_missing"]], nhgis_notes[["cbp_blank"]])))
  })
}

# Census tables: periods are the years a recipe names, or the census years all its tables share.
nhgis_periods <- function(settings, recipe) {
  if (grepl(":", recipe$numerator, fixed = TRUE)) return(as.integer(names(parse_period_vars(recipe$numerator))))
  tables <- unique(substr(unlist(lapply(c(recipe$numerator, recipe$denominator), recipe_vars)), 1, 3))
  as.integer(Reduce(intersect, lapply(tables, nhgis_default_years)))
}

register_provider("ipums_nhgis", list(
  name = "IPUMS NHGIS, University of Minnesota, www.nhgis.org (decennial census tables)",
  geo_types = unname(nhgis_levels),
  fetch = nhgis_fetch,
  periods = nhgis_periods,
  period_label = function(period) paste(period, "census"),
  period_kind = "point",
  series = "Decennial census (IPUMS NHGIS)",
  availability_note = "NHGIS census tables cover the nation, regions, divisions, states, counties, county subdivisions and places, linked across censuses by name and code."))

register_provider("ipums_nhgis_cbp", list(
  name = "U.S. Census Bureau, County Business Patterns 1970-1997 (SIC industry codes), via IPUMS NHGIS",
  geo_types = c("nation", "state", "county"),
  fetch = nhgis_cbp_fetch,
  periods = function(settings, recipe) 1970:1997,
  period_label = function(period) as.character(period),
  period_kind = "annual",
  series = "County Business Patterns, SIC (IPUMS NHGIS)",
  availability_note = "County Business Patterns before 1998 cover the nation, states and counties."))

# ---- Historical boundary files (for maps) ---------------------------------------------------
#
# NHGIS boundary files: the counties of every census from 1790 to 2010 and the tracts of 1910-2000
# (before 1990 only a few cities have tracts), on the TIGER/Line 2008 base. Each file is a shapefile
# extract of its own, requested once and kept in the cache; the geometry is stored as sf, in NAD83
# longitude and latitude.

nhgis_boundaries <- function(level, year) {
  name <- sprintf("us_%s_%d_tl2008", level, year)
  path <- cache_path("geo", "nhgis", paste0(name, ".rds"))
  memoize(paste0("nhgis_shape_", name), function() cached(path, source = "ipums_nhgis", compute = function() {
    zip <- nhgis_extract(paste0("shape-", name), list(shapefiles = list(name), description = paste("geo-report-gen boundaries:", name)), link = "gisData")
    dir <- tempfile("nhgis")
    dir.create(dir)
    on.exit(unlink(dir, recursive = TRUE))
    inner <- grep("[.]zip$", utils::unzip(zip, exdir = dir), value = TRUE)
    if (length(inner) != 1) stop("The NHGIS boundary extract ", name, " holds ", length(inner), " shapefiles, not one.", call. = FALSE)
    shp <- sf::st_transform(sf::st_make_valid(sf::st_read(paste0("/vsizip/", inner), quiet = TRUE)), 4269)
    shp[, intersect(c("GISJOIN", "STATENAM", "NHGISNAM", "NHGISST", "NHGISCTY"), names(shp))]
  }))
}
