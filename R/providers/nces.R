# NCES Common Core of Data (CCD): public schools, their students, pre-kindergarten students and
# teachers, school years 2017-18 to 2024-25, from the yearly school layers of NCES's EDGE program
# (an ArcGIS service; one row per school with CCD's counts and NCES's geocode). Students are
# counted on October 1 at the schools they attend, not where they live.
#
# Two layers per year, joined by school ID: administrative data (status, virtual status,
# membership = students excluding adult education, pre-kindergarten students, teachers in
# full-time equivalents) and the geocode (state and county codes, coordinates). CCD codes -1
# (missing) and -9 (not reported) are unknown; -2 (not applicable, e.g. no pre-kindergarten)
# is zero.
#
# Schools counted are open, new, added, changed or reopened (status 1, 3, 4, 5, 8). Full-time
# virtual schools count in state and national totals but not in counties, cities or tracts,
# where only their office is. An area's value is shown when at least 95% of its schools
# reported it, and leaves out the rest; otherwise it is unavailable with the count of schools
# that did not report.
#
# Areas: states and counties by NCES's codes; the nation, regions, divisions and metro areas as
# sums; places, their county parts and tracts by the school's coordinates in full-resolution
# TIGER/Line boundaries of the report's boundary year.
#
# Variables: SCHOOLS, STUDENTS, PREK_STUDENTS, TEACHERS, and STUDENTS_WITH_TEACHERS (students at
# schools that reported their teachers, the numerator of students per teacher).

nces_base <- "https://nces.ed.gov/opengis/rest/services/K12_School_Locations/"
nces_years <- 2017:2024        # fall of each school year: 2024 is 2024-25
nces_open <- c("1", "3", "4", "5", "8")
nces_full_virtual <- c("A virtual school", "Full Virtual")
nces_min_reported <- 0.95

nces_suffix <- function(year) sprintf("%02d%02d", year %% 100, (year + 1) %% 100)

nces_json <- function(req, what) {
  resp <- http_perform(req)
  check_status(resp, what)
  x <- jsonlite::fromJSON(httr2::resp_body_string(resp))
  if (!is.null(x$error)) stop(what, ": ", x$error$message, call. = FALSE)
  x
}

# Every row of one EDGE layer, in pages of the size the service allows (1,000 or 2,000 rows).
nces_layer <- function(service, fields) {
  base <- paste0(nces_base, service, "/MapServer")
  info <- nces_json(http_request(base, "nces_ccd", query = list(f = "json")), service)
  url <- paste0(base, "/", info$layers$id[1], "/query")
  size <- info$maxRecordCount %||% 1000
  n <- nces_json(http_request(url, "nces_ccd", query = list(where = "1=1", returnCountOnly = "true", f = "json")), service)$count
  reqs <- lapply(seq(0, n - 1, by = size), function(offset) http_request(url, "nces_ccd", query = list(
    where = "1=1", outFields = paste(fields, collapse = ","), returnGeometry = "false", orderByFields = "OBJECTID",
    resultOffset = offset, resultRecordCount = size, f = "json")))
  pages <- lapply(http_perform_many(reqs), function(resp) {
    check_status(resp, service)
    x <- jsonlite::fromJSON(httr2::resp_body_string(resp))
    if (!is.null(x$error)) stop(service, ": ", x$error$message, call. = FALSE)
    x$features$attributes[, fields, drop = FALSE]
  })
  d <- do.call(rbind, pages)
  if (nrow(d) != n || anyDuplicated(d$NCESSCH)) stop(service, ": expected ", n, " distinct schools, got ", nrow(d), call. = FALSE)
  d[] <- lapply(d, as.character)
  d
}

nces_raw <- function(kind, year) {
  # The 2018-19 ArcGIS geocode service serves 2017-18 records. Use the dated NCES
  # archive instead; a separate cache name leaves the original response intact for review.
  if (kind == "geocode" && year == 2018L) {
    file <- "EDGE_GEOCODE_PUBLICSCH_1819.zip"
    zip <- cached_download(paste0("https://nces.ed.gov/programs/edge/data/", file),
                           cache_path("raw", "nces_ccd", file), "nces_ccd")
    return(cached(cache_path("raw", "nces_ccd", "geocode_archive_1819.parquet"), source = "nces_ccd", compute = function() {
      dir <- tempfile("nces-"); dir.create(dir); on.exit(unlink(dir, recursive = TRUE))
      path <- unzip(zip, files = "EDGE_GEOCODE_PUBLICSCH_1819.xlsx", exdir = dir)
      d <- as.data.frame(readxl::read_xlsx(path, col_types = "text"))
      d[, c("NCESSCH", "STFIP", "CNTY", "LAT", "LON"), drop = FALSE]
    }))
  }
  service <- paste0("EDGE_", if (kind == "admin") "ADMINDATA" else "GEOCODE", "_PUBLICSCH_", nces_suffix(year))
  fields <- if (kind == "admin") c("NCESSCH", "STATUS", "VIRTUAL", "MEMBER", "PK", "FTE") else c("NCESSCH", "STFIP", "CNTY", "LAT", "LON")
  cached(cache_path("raw", "nces_ccd", paste0(kind, "_", nces_suffix(year), ".parquet")), source = "nces_ccd",
         compute = function() nces_layer(service, fields))
}

# One school year's open schools: state, county, coordinates, virtual status and counts (NA unknown).
nces_schools <- function(year) {
  memoize(paste0("nces_", year), function() cached(derived_path("nces_ccd", paste0("schools_", year), "nces.R"), source = "nces_ccd", compute = function() {
    a <- nces_raw("admin", year)
    g <- nces_raw("geocode", year)
    a <- a[a$STATUS %in% nces_open, , drop = FALSE]
    if (any(!a$NCESSCH %in% g$NCESSCH)) stop("NCES ", nces_label(year),
      ": school geocodes do not cover every operating school; refusing a partial total", call. = FALSE)
    g <- g[match(a$NCESSCH, g$NCESSCH), , drop = FALSE]
    count <- function(v) { v <- suppressWarnings(as.numeric(v)); ifelse(v == -2, 0, ifelse(v < 0, NA_real_, v)) }
    data.frame(id = a$NCESSCH, state = g$STFIP, county = g$CNTY, lat = as.numeric(g$LAT), lon = as.numeric(g$LON),
               virtual = a$VIRTUAL %in% nces_full_virtual, students = count(a$MEMBER), prek = count(a$PK),
               teachers = count(a$FTE), stringsAsFactors = FALSE)
  }))
}

# The place and tract of each school of one state and year.
nces_locate <- function(year, state, vintage) {
  cached(derived_path("nces_ccd", file.path("located", paste0(year, "_", state, "_", vintage)), "nces.R"), source = "nces_ccd", compute = function() {
    s <- nces_schools(year)
    s <- s[s$state %in% state & !is.na(s$lat), , drop = FALSE]
    data.frame(id = s$id, place = locate_points(s$lon, s$lat, "place", state, vintage),
               tract = locate_points(s$lon, s$lat, "tract", state, vintage), stringsAsFactors = FALSE)
  })
}

# Sum a count over the selected schools when at least 95% of the schools in each state part of
# the area reported it (so a state that reported nothing cannot vanish from a national total).
nces_sum <- function(x, state, what, year) {
  reported <- !is.na(x)
  short <- names(which(tapply(reported, state, mean) < nces_min_reported))
  if (!length(short)) return(list(estimate = sum(x[reported]), status = "ok", note = ""))
  missing <- sum(!reported[state %in% short])
  list(estimate = NA_real_, status = "unavailable",
       note = sprintf("%d of %d public schools in %s did not report %s for %s", missing, sum(state %in% short),
                      if (length(unique(state)) == 1) "the area" else paste(state_table()$name[match(short, state_table()$state)], collapse = ", "),
                      what, nces_label(year)))
}

nces_label <- function(year) {
  year <- as.integer(year)
  sprintf("%d–%02d", year, (year + 1) %% 100)
}

# Values of one school year for the requested pieces: rows (geo, variable, estimate, status, note).
nces_year_values <- function(year, pieces, vintage) {
  s <- nces_schools(year)
  st <- state_table()
  nation <- st$state[st$in_nation == "TRUE"]
  # States whose schools NCES placed in counties that no longer exist (Connecticut's former
  # counties before planning regions): their current counties have no values that year.
  recoded <- unique(substr(setdiff(s$county, geo_catalog("county", vintage)$geoid), 1, 2))
  out <- list()
  for (i in seq_len(nrow(pieces))) {
    type <- pieces$type[i]
    geoid <- pieces$geoid[i]
    note <- ""
    sel <- switch(type,
      nation = s$state %in% nation,
      region = , division = s$state %in% st$state[st[[type]] == geoid & st$in_nation == "TRUE"],
      state = s$state == geoid,
      county = if (!geoid %in% s$county && substr(geoid, 1, 2) %in% recoded) {
        note <- "NCES placed this state's schools in its former counties that year"
        NULL
      } else s$county %in% geoid,
      cbsa = {
        counties <- cbsa_counties(geoid, vintage)
        if (any(!counties %in% s$county & substr(counties, 1, 2) %in% recoded)) {
          note <- "NCES county codes do not match all current counties in this metropolitan area"
          NULL
        } else s$county %in% counties
      },
      place = , place_part = , tract = {
        loc <- nces_locate(year, substr(geoid, 1, 2), vintage)
        ids <- switch(type,
          tract = loc$id[loc$tract %in% geoid],
          place = loc$id[loc$place %in% geoid],
          place_part = loc$id[loc$place %in% sub("-.*$", "", geoid)])
        ok <- s$id %in% ids
        if (type == "place_part") {
          county <- sub("^.*-", "", geoid)
          if (!county %in% s$county && substr(county, 1, 2) %in% recoded) {
            note <- "NCES placed this state's schools in its former counties that year"
            ok <- NULL
          } else ok <- ok & s$county %in% county
        }
        ok
      },
      stop("NCES CCD: unsupported geography type '", type, "'.", call. = FALSE))
    if (!is.null(sel) && !type %in% c("nation", "region", "division", "state")) sel <- sel & !s$virtual
    rows <- if (is.null(sel)) {
      lapply(c("SCHOOLS", "STUDENTS", "PREK_STUDENTS", "TEACHERS", "STUDENTS_WITH_TEACHERS"),
             function(v) list(variable = v, estimate = NA_real_, status = "unavailable", note = note))
    } else {
      x <- s[sel, , drop = FALSE]
      staffed <- x[!is.na(x$students) & x$students > 0, , drop = FALSE]   # teachers are expected where students are
      teachers <- nces_sum(staffed$teachers, staffed$state, "teachers", year)
      with_teachers <- teachers
      with_teachers$estimate <- if (teachers$status == "ok") sum(staffed$students[!is.na(staffed$teachers)]) else NA_real_
      list(c(variable = "SCHOOLS", list(estimate = nrow(x), status = "ok", note = "")),
           c(variable = "STUDENTS", nces_sum(x$students, x$state, "enrollment", year)),
           c(variable = "PREK_STUDENTS", nces_sum(x$prek, x$state, "pre-kindergarten enrollment", year)),
           c(variable = "TEACHERS", teachers),
           c(variable = "STUDENTS_WITH_TEACHERS", with_teachers))
    }
    out[[i]] <- data.frame(geo = pieces$key[i], variable = vapply(rows, `[[`, "", "variable"),
                           estimate = vapply(rows, function(r) as.numeric(r$estimate), 0),
                           status = vapply(rows, `[[`, "", "status"), note = vapply(rows, `[[`, "", "note"),
                           stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}

nces_fetch <- function(variables, pieces, periods, options = list()) {
  vintage <- as.integer(options$settings$boundary_vintage %||% 2024)
  out <- lapply(as.integer(periods), function(yr) {
    v <- nces_year_values(yr, pieces, vintage)
    v <- v[v$variable %in% variables, , drop = FALSE]
    data.frame(geo = v$geo, name = "", variable = v$variable, estimate = v$estimate, moe = NA_real_, status = v$status,
               bound = NA_character_, note = v$note, period = as.character(yr), period_start = yr, period_end = yr,
               source_id = "nces_ccd", stringsAsFactors = FALSE)
  })
  if (!length(out)) return(empty_values())
  do.call(rbind, out)
}

register_provider("nces_ccd", list(
  name = "National Center for Education Statistics, Common Core of Data (CCD)",
  geo_types = c("nation", "region", "division", "state", "county", "cbsa", "place", "place_part", "tract"),
  fetch = nces_fetch,
  periods = function(settings, recipe) nces_years[nces_years >= as.integer(settings$history_start %||% min(nces_years))],
  period_label = nces_label,
  period_kind = "annual",
  series = "Common Core of Data",
  fixed_boundaries = 2024L,
  availability_note = paste("The Common Core of Data counts students on October 1 at public schools located in the area, not the",
                            "children who live there. Cities and tracts come from school coordinates; full-time virtual schools",
                            "count only in state and national totals.")))
