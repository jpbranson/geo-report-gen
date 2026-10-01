# Census Data API provider: ACS 5-year detailed tables (2009-2024 releases) and the
# decennial census (2000 SF1, 2010 SF1, 2020 PL/DHC).
#
# Requests are grouped into "scopes" that many reports share: all counties nationwide,
# all places in one state, all tracts in one county, the county parts of one place, etc.
# Each (dataset, release, table, scope) is fetched once and cached as parquet in long
# form: geo, name, variable, estimate, moe, status.

# How each geography type is requested from the API. `{st}`, `{co}`, `{pl}` are filled
# from the piece GEOID. Types marked `state_scoped` are fetched one state at a time.
census_geo_types <- list(
  nation   = list(`for` = "us:1"),
  region   = list(`for` = "region:*"),
  division = list(`for` = "division:*"),
  state    = list(`for` = "state:*"),
  county   = list(`for` = "county:*"),
  place    = list(`for` = "place:*", `in` = "state:{st}"),
  cousub   = list(`for` = "county subdivision:*", `in` = "state:{st} county:{co}"),
  tract    = list(`for` = "tract:*", `in` = "state:{st} county:{co}"),
  bg       = list(`for` = "block group:*", `in` = "state:{st} county:{co} tract:*"),
  place_part = list(`for` = "county (or part):*", `in` = "state:{st} place:{pl}"),
  zcta     = list(`for` = "zip code tabulation area:*"),
  cbsa     = list(`for` = "metropolitan statistical area/micropolitan statistical area:*"),
  sdu      = list(`for` = "school district (unified):*", `in` = "state:{st}")
)

# The scope a piece is fetched with, e.g. "county", "place-48", "tract-48453",
# "place_part-4805000". Pieces sharing a scope are fetched together.
census_scope <- function(type, geoid) {
  st <- substr(geoid, 1, 2)
  switch(type,
    nation = "nation", region = "region", division = "division", state = "state",
    county = "county", zcta = "zcta", cbsa = "cbsa",
    place = paste0("place-", st),
    sdu = paste0("sdu-", st),
    cousub = paste0("cousub-", substr(geoid, 1, 5)),
    tract = paste0("tract-", substr(geoid, 1, 5)),
    bg = paste0("bg-", substr(geoid, 1, 5)),
    place_part = paste0("place_part-", sub("-.*$", "", geoid)),
    stop("Census API: unsupported geography type '", type, "'"))
}

census_scope_query <- function(scope) {
  type <- sub("-.*$", "", scope)
  code <- if (grepl("-", scope)) sub("^[^-]*-", "", scope) else ""
  q <- census_geo_types[[type]]
  # A scope without a code (e.g. "place") means nationwide: drop the `in` clause.
  if (!nzchar(code)) q[["in"]] <- NULL
  fill <- function(x) {
    x <- gsub("{st}", substr(code, 1, 2), x, fixed = TRUE)
    x <- gsub("{co}", substr(code, 3, 5), x, fixed = TRUE)
    gsub("{pl}", substr(code, 3, 7), x, fixed = TRUE)
  }
  lapply(q, fill)
}

# Build our geography keys ("county:48453", "place_part:4805000-48209") from the
# geography columns the API returns.
census_keys <- function(df, scope) {
  type <- sub("-.*$", "", scope)
  col <- function(name) df[[name]]
  geoid <- switch(type,
    nation = rep("US", nrow(df)),
    region = col("region"), division = col("division"), state = col("state"),
    county = paste0(col("state"), col("county")),
    place = paste0(col("state"), col("place")),
    cousub = paste0(col("state"), col("county"), col("county subdivision")),
    tract = paste0(col("state"), col("county"), col("tract")),
    bg = paste0(col("state"), col("county"), col("tract"), col("block group")),
    place_part = paste0(col("state"), col("place"), "-", col("state"), col("county (or part)")),
    zcta = col("zip code tabulation area"),
    cbsa = col("metropolitan statistical area/micropolitan statistical area"),
    sdu = paste0(col("state"), col("school district (unified)")))
  paste0(type, ":", geoid)
}

# ACS special values ("jam values") and what they mean. Source: Census Bureau, "Notes on
# ACS Estimate and Annotation Values" (census.gov/data/developers/data-sets/acs-1year/
# notes-on-acs-estimate-and-annotation-values.html) and ACS Accuracy of the Data 2020-2024.
# Estimates carrying one of these codes are never used as numbers.
acs_special_values <- data.frame(
  code = c(-666666666, -999999999, -888888888, -222222222, -333333333, -555555555),
  status = c("insufficient_sample", "insufficient_sample", "not_applicable",
             "moe_unavailable", "open_interval", "controlled"),
  stringsAsFactors = FALSE)

# Convert raw estimate/MOE strings to numbers plus a status. Status vocabulary:
#   ok, controlled (no sampling error), open_interval (median in an open-ended bin;
#   the estimate is a bound), moe_unavailable, insufficient_sample, not_applicable.
acs_decode <- function(est_raw, moe_raw, est_note = NA_character_) {
  est <- suppressWarnings(as.numeric(est_raw))
  moe <- suppressWarnings(as.numeric(moe_raw))
  status <- rep("ok", length(est))
  est_code <- match(est, acs_special_values$code)
  moe_code <- match(moe, acs_special_values$code)
  status[!is.na(moe_code)] <- acs_special_values$status[moe_code[!is.na(moe_code)]]
  status[!is.na(est_code)] <- acs_special_values$status[est_code[!is.na(est_code)]]
  status[is.na(est) & is.na(est_code)] <- "missing"
  est[!is.na(est_code)] <- NA_real_
  moe[status == "controlled"] <- 0
  moe[!is.na(moe_code) & status != "controlled"] <- NA_real_
  # Medians in open-ended intervals carry an annotation such as "250,000+" or "2,500-": the
  # value is that bound (the raw estimate is the bound plus or minus one).
  open <- !is.na(est_note) & grepl("^[0-9,.]+[+-]$", est_note) & !is.na(est)
  status[open] <- "open_interval"
  est[open] <- as.numeric(gsub("[,+-]", "", est_note[open]))
  data.frame(estimate = est, moe = moe, status = status,
             bound = ifelse(open, ifelse(grepl("\\+$", est_note), "lower", "upper"), NA_character_),
             stringsAsFactors = FALSE)
}

acs_dataset <- function(release) paste0(release, "/acs/acs5")

acs_raw_path <- function(release, table, scope) {
  cache_path("raw", "census_acs5", release, toupper(table), paste0(scope, ".parquet"))
}

acs_query <- function(table, scope) {
  c(list(get = paste0("NAME,group(", toupper(table), ")")), census_scope_query(scope))
}

# Raw layer: the API response exactly as returned (all character columns). A table the
# release does not publish is stored as zero rows with a `note` column, so it is not
# requested again. Decoding happens on read (acs_table), so changing the decoding never
# requires re-downloading.
acs_raw_from_response <- function(resp, release, table, scope) {
  if (httr2::resp_status(resp) == 400 &&
      grepl("unknown|not a valid|does not exist", httr2::resp_body_string(resp), ignore.case = TRUE)) {
    return(data.frame(note = character(0)))
  }
  df <- census_parse(resp, paste("ACS", release, table, scope))
  if (!ncol(df)) return(data.frame(note = character(0)))
  df
}

acs_raw <- function(release, table, scope) {
  cached(acs_raw_path(release, table, scope), source = "census_acs5", compute = function() {
    resp <- http_perform(census_request(acs_dataset(release), acs_query(table, scope)))
    acs_raw_from_response(resp, release, table, scope)
  })
}

# The raw table of one scope with each row's area key, read once per session.
acs_scope_table <- function(release, table, scope) {
  memoize(paste("acs_raw", release, table, scope, sep = "|"), function() {
    df <- acs_raw(release, table, scope)
    list(df = df, geo = if (nrow(df)) census_keys(df, scope) else character())
  })
}

# Normalized layer: one ACS table for one scope as long data (geo, name, variable,
# estimate, moe, status, bound), for the areas `keys` (every area when NULL). Decoding is the
# slow step, so the areas are chosen first: a national table has thousands of rows, and a
# report reads a few.
acs_table <- function(release, table, scope, keys = NULL) {
  t <- acs_scope_table(release, table, scope)
  rows <- if (is.null(keys)) seq_along(t$geo) else which(t$geo %in% keys)
  if (!length(rows)) return(empty_census_long())
  df <- t$df[rows, , drop = FALSE]
  geo <- t$geo[rows]
  est_cols <- grep(paste0("^", toupper(table), "_[0-9]+[A-Z]?E$"), names(df), value = TRUE)
  base <- sub("E$", "", est_cols)
  # All variables are decoded in one pass, one block of rows per variable.
  column <- function(cols) unlist(lapply(cols, function(cl) {
    if (cl %in% names(df)) df[[cl]] else rep(NA_character_, nrow(df))
  }), use.names = FALSE)
  dec <- acs_decode(column(est_cols), column(paste0(base, "M")), column(paste0(base, "EA")))
  data.frame(geo = rep(geo, length(base)), name = rep(df$NAME, length(base)),
             variable = rep(base, each = nrow(df)), dec, note = "", stringsAsFactors = FALSE)
}

empty_census_long <- function() {
  data.frame(geo = character(), name = character(), variable = character(),
             estimate = numeric(), moe = numeric(), status = character(),
             bound = character(), note = character(), stringsAsFactors = FALSE)
}

# Variable labels for a table (used for subgroup labels and to parse distribution bins).
acs_variables <- function(release, table) {
  path <- cache_path("raw", "census_acs5", release, toupper(table), "variables.parquet")
  cached(path, source = "census_acs5", compute = function() {
    url <- paste0("https://api.census.gov/data/", acs_dataset(release), "/groups/", toupper(table), ".json")
    resp <- http_perform(http_request(url, "census_api", secret = list(key = census_key())))
    if (httr2::resp_status(resp) >= 400) {
      return(data.frame(variable = character(), label = character(), concept = character()))
    }
    vars <- jsonlite::fromJSON(httr2::resp_body_string(resp), simplifyVector = FALSE)$variables
    est <- names(vars)[grepl("E$", names(vars))]
    data.frame(variable = sub("E$", "", est),
               label = vapply(est, function(v) vars[[v]]$label %||% "", ""),
               concept = vapply(est, function(v) vars[[v]]$concept %||% "", ""),
               stringsAsFactors = FALSE, row.names = NULL)
  })
}

# Fetch ACS variables for a set of geography pieces and releases: one row per
# (geo, release, variable). On a cold cache, missing tables are requested in parallel.
acs_fetch <- function(variables, pieces, releases) {
  tables <- unique(toupper(sub("_.*$", "", variables)))
  scopes <- unique(mapply(census_scope, pieces$type, pieces$geoid))
  jobs <- expand.grid(release = releases, table = tables, scope = scopes, stringsAsFactors = FALSE)
  prefetch_acs(jobs)
  piece_scopes <- mapply(census_scope, pieces$type, pieces$geoid)
  out <- lapply(seq_len(nrow(jobs)), function(i) {
    published <- nrow(acs_scope_table(jobs$release[i], jobs$table[i], jobs$scope[i])$df) > 0
    d <- if (published) acs_table(jobs$release[i], jobs$table[i], jobs$scope[i], pieces$key) else
      acs_unpublished(jobs$release[i], jobs$table[i], variables, pieces$key[piece_scopes == jobs$scope[i]])
    d <- d[d$geo %in% pieces$key & d$variable %in% variables, , drop = FALSE]
    if (nrow(d)) d$period <- as.character(jobs$release[i])
    d
  })
  out <- do.call(rbind, out)
  if (is.null(out) || !nrow(out)) return(empty_values())
  out$period_start <- as.integer(out$period) - 4L
  out$period_end <- as.integer(out$period)
  out$source_id <- "census_acs5"
  out
}

# A table missing from a release (its group metadata is empty: the table was introduced later)
# makes its values unavailable for that reason. An empty response for a published table leaves
# the pieces absent, and the metric engine names them.
acs_unpublished <- function(release, table, variables, keys) {
  published <- tryCatch(nrow(acs_variables(release, table)) > 0, error = function(e) TRUE)
  if (published || !length(keys)) return(empty_census_long())
  vars <- variables[toupper(sub("_.*$", "", variables)) == table]
  d <- expand.grid(geo = keys, variable = vars, stringsAsFactors = FALSE)
  d$name <- ""
  d$estimate <- NA_real_
  d$moe <- NA_real_
  d$status <- "unavailable"
  d$bound <- NA_character_
  d$note <- paste0("the source table is not published in the ", as.integer(release) - 4L, "–", release, " ACS release")
  d
}

# Bounded-concurrency warm-up of the raw cache (4 requests at a time, throttled per source).
prefetch_acs <- function(jobs) {
  paths <- vapply(seq_len(nrow(jobs)), function(i) acs_raw_path(jobs$release[i], jobs$table[i], jobs$scope[i]), "")
  missing <- which(!file.exists(paths) | vapply(paths, wants_refresh, logical(1), source = "census_acs5"))
  if (length(missing) < 2 || isTRUE(run$offline)) return(invisible())
  reqs <- lapply(missing, function(i) census_request(acs_dataset(jobs$release[i]), acs_query(jobs$table[i], jobs$scope[i])))
  resps <- http_perform_many(reqs, max_active = 4)
  for (k in seq_along(missing)) {
    i <- missing[k]
    if (!inherits(resps[[k]], "httr2_response")) next  # acs_raw() retries on the slow path
    value <- tryCatch(acs_raw_from_response(resps[[k]], jobs$release[i], jobs$table[i], jobs$scope[i]),
                      error = function(e) NULL)
    if (is.null(value)) next
    dir.create(dirname(paths[i]), recursive = TRUE, showWarnings = FALSE)
    write_cache_file(value, paths[i])
    run$refreshed <- c(run$refreshed, paths[i])
    run$cache["miss"] <- run$cache["miss"] + 1L
  }
  invisible()
}


# ---- Decennial census -----------------------------------------------------------

# Dataset used for each census year. Counts have no sampling error; they are published
# for the boundaries in effect at each census (a "legal area" history).
decennial_datasets <- c(`2000` = "2000/dec/sf1", `2010` = "2010/dec/sf1", `2020` = "2020/dec/dhc")

# Raw layer: the API response for a variable set and scope; decoded on read.
decennial_raw <- function(year, vars, scope) {
  path <- cache_path("raw", "census_dec", year, hash_value(vars), paste0(scope, ".parquet"))
  cached(path, source = "census_dec", compute = function() {
    query <- c(list(get = paste(c("NAME", vars), collapse = ",")), census_scope_query(scope))
    df <- census_parse(http_perform(census_request(decennial_datasets[[year]], query)),
                       paste("Decennial", year, scope))
    if (!ncol(df)) data.frame(note = character(0)) else df
  })
}

decennial_table <- function(year, variables, scope) {
  vars <- sort(unique(variables))
  memoize(paste("dec", year, paste(vars, collapse = ","), scope, sep = "|"), function() {
    df <- decennial_raw(year, vars, scope)
    if (!nrow(df)) return(empty_census_long())
    keys <- census_keys(df, scope)
    out <- do.call(rbind, lapply(vars, function(v) {
      est <- suppressWarnings(as.numeric(df[[v]]))
      # Census counts have no sampling error: MOE 0 (Census testing guidance).
      data.frame(geo = keys, name = df$NAME, variable = v, estimate = est, moe = 0,
                 status = ifelse(is.na(est), "missing", "ok"), bound = NA_character_,
                 stringsAsFactors = FALSE)
    }))
    out$note <- ""
    out
  })
}

# `var_by_year` maps census year -> variable id(s), because IDs differ between censuses.
decennial_fetch <- function(var_by_year, pieces, years) {
  scopes <- unique(mapply(census_scope, pieces$type, pieces$geoid))
  out <- list()
  for (yr in intersect(as.character(years), names(var_by_year))) {
    vars <- var_by_year[[yr]]
    for (sc in scopes) {
      d <- decennial_table(yr, vars, sc)
      d <- d[d$geo %in% pieces$key, , drop = FALSE]
      if (nrow(d)) d$period <- yr
      out[[length(out) + 1]] <- d
    }
  }
  out <- do.call(rbind, out)
  if (is.null(out) || !nrow(out)) return(empty_values())
  out$period_start <- as.integer(out$period)
  out$period_end <- as.integer(out$period)
  out$source_id <- "census_dec"
  out
}

# ---- Registration ------------------------------------------------------------------

# ACS releases used for a report: the current release (setting `acs_release`) and, for
# trends, earlier releases whose 5-year periods do not overlap it (every 5th release back
# to 2009, the first 5-year release). Overlapping releases are never treated as annual
# observations; `acs_periods = all` must be requested explicitly and is labeled.
acs_releases <- function(settings) {
  current <- as.integer(settings$acs_release %||% 2024)
  first <- max(2009L, as.integer(settings$history_start %||% 2009) + 4L)
  if (identical(settings$acs_periods, "all")) return(seq(first, current))
  rev(seq(current, first, by = -5L))
}

register_provider("census_acs5", list(
  name = "U.S. Census Bureau, American Community Survey 5-year estimates (Census Data API)",
  geo_types = names(census_geo_types),
  fetch = function(variables, pieces, periods, options = list()) acs_fetch(variables, pieces, periods),
  periods = function(settings, recipe) acs_releases(settings),
  period_label = function(period) paste0(as.integer(period) - 4L, "–", period),
  period_kind = "multiyear",
  series = "ACS 5-year estimates"))

register_provider("census_dec", list(
  name = "U.S. Census Bureau, Decennial Census (2000 and 2010 SF1, 2020 DHC; Census Data API)",
  geo_types = setdiff(names(census_geo_types), "place_part"),
  fetch = function(variables, pieces, periods, options = list()) {
    decennial_fetch(options$var_by_period, pieces, periods)
  },
  periods = function(settings, recipe) {
    yrs <- as.integer(names(parse_period_vars(recipe$numerator)))
    yrs[yrs >= as.integer(settings$history_start %||% 1900)]
  },
  period_label = function(period) as.character(period),
  period_kind = "point",
  series = "Census count"))
