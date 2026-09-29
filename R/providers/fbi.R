# FBI Crime Data Explorer (Uniform Crime Reporting): violent and property offenses known to police,
# through the CDE API. The api.data.gov key (DATA_GOV_API_KEY in .env) is sent only as a request
# header, so it never appears in URLs or logs.
#  - The FBI publishes by police agency. A city is its police department ("<Name> Police
#    Department", type City, in the city's state). Counties are not computed: a sheriff covers only
#    part of a county, and agencies overlap.
#  - A city's year needs all 12 months reported. States and the nation are the agencies that
#    reported, with the population they cover (<offense>_POP); POP is the full population, so the
#    coverage is V_POP / POP.
#  - The FBI advises comparing a city with its state and a state with the nation, not ranking areas.

fbi_years <- 2016:2025
fbi_offenses <- c(V = "violent", P = "property")

fbi_request <- function(path, query = list()) {
  key <- Sys.getenv("DATA_GOV_API_KEY")
  if (!nzchar(key)) {
    stop("The FBI Crime Data Explorer needs a free api.data.gov key: add DATA_GOV_API_KEY=<key> to .env ",
         "(https://api.data.gov/signup/).", call. = FALSE)
  }
  req <- http_request(paste0("https://api.usa.gov/crime/fbi/cde/", path), "fbi_cde", query = query)
  httr2::req_headers(req, `X-Api-Key` = key, .redact = "X-Api-Key")
}

fbi_get <- function(path, query = list()) {
  resp <- http_perform(fbi_request(path, query))
  check_status(resp, paste("FBI Crime Data Explorer", path))
  jsonlite::fromJSON(httr2::resp_body_string(resp), simplifyVector = FALSE)
}

# City police departments of one state: ori, name and the city name they are matched by.
fbi_city_agencies <- function(state_abbr) {
  cached(cache_path("raw", "fbi_cde", "agencies", paste0(state_abbr, ".parquet")), source = "fbi_cde", compute = function() {
    a <- unlist(fbi_get(paste0("agency/byStateAbbr/", state_abbr)), recursive = FALSE)
    a <- a[vapply(a, function(x) identical(x$agency_type_name, "City"), TRUE)]
    name <- vapply(a, `[[`, "", "agency_name")
    data.frame(ori = vapply(a, `[[`, "", "ori"), agency = name,
               city = normalize_name(sub(" Police Department.*$", "", name)), stringsAsFactors = FALSE)
  })
}

# "Indianapolis city (balance), Indiana" -> "indianapolis", to match "Indianapolis Police Department".
fbi_city_name <- function(place_name) {
  x <- normalize_name(sub(",.*$", "", place_name))
  sub("\\s+(city|town|village|borough|cdp|municipality|(consolidated|unified|metropolitan|metro) government)(\\s+balance)?$", "", x)
}

# Monthly offenses, population and population covered by reporting agencies, 2016-2025. `path` is
# the API path without the offense; `name` labels the series in the response (the agency, state or
# "United States").
fbi_series <- function(path, name, offense) {
  file <- paste0(gsub("/", "-", path), "-", offense, "-", min(fbi_years), "-", max(fbi_years), ".parquet")
  cached(cache_path("raw", "fbi_cde", file), source = "fbi_cde", compute = function() {
    x <- fbi_get(paste0(path, "/", offense), list(from = paste0("01-", min(fbi_years)), to = paste0("12-", max(fbi_years))))
    pop <- x$populations$population[[name]]
    months <- names(pop)
    value <- function(l) vapply(months, function(m) if (is.null(l[[m]])) NA_real_ else as.numeric(l[[m]]), 0, USE.NAMES = FALSE)
    data.frame(year = as.integer(substr(months, 4, 7)), offenses = value(x$offenses$actuals[[paste(name, "Offenses")]]),
               population = value(pop), covered = value(x$populations$participated_population[[name]]))
  })
}

# Annual totals: a city needs every month reported in full; states and the nation use the
# agencies that reported and the population they cover.
fbi_annual <- function(s, city) {
  do.call(rbind, lapply(split(s, s$year), function(y) {
    reported <- nrow(y) == 12 && !anyNA(y$offenses) && !anyNA(y$covered)
    if (city) reported <- reported && all(y$covered >= y$population)
    data.frame(year = y$year[1], offenses = if (reported) sum(y$offenses) else NA_real_,
               covered = if (reported) mean(y$covered) else NA_real_, population = mean(y$population))
  }))
}

fbi_notes <- c(no_agency = "no city police department in the FBI's data matches this place",
               unreported = "not reported to the FBI for every month of this year (many agencies missed 2021, when reporting moved to NIBRS)")

fbi_fetch <- function(variables, pieces, periods, options = list()) {
  st <- state_table()
  years <- as.integer(periods)
  rows <- list()
  for (i in seq_len(nrow(pieces))) {
    p <- pieces[i, ]
    s <- st[st$state == substr(p$geoid, 1, 2), , drop = FALSE]
    source <- switch(p$type, nation = list("summarized/national", "United States", FALSE),
                     state = list(paste0("summarized/state/", s$usps), s$name, FALSE),
                     place = {
                       a <- fbi_city_agencies(s$usps)
                       a <- a[a$city == fbi_city_name(p$name), , drop = FALSE]
                       if (nrow(a) == 1) list(paste0("summarized/agency/", a$ori), a$agency, TRUE) else NULL
                     })
    for (off in names(fbi_offenses)) {
      vars <- c(off, paste0(off, "_POP"), "POP")
      if (is.null(source)) {
        g <- expand.grid(year = years, variable = vars, stringsAsFactors = FALSE)
        rows[[length(rows) + 1]] <- data.frame(geo = p$key, g, estimate = NA_real_, status = "unavailable",
                                               note = fbi_notes[["no_agency"]], stringsAsFactors = FALSE)
        next
      }
      y <- fbi_annual(fbi_series(source[[1]], source[[2]], off), source[[3]])
      y <- y[y$year %in% years, , drop = FALSE]
      ok <- !is.na(y$offenses)
      rows[[length(rows) + 1]] <- data.frame(geo = p$key, year = rep(y$year, 3), variable = rep(vars, each = nrow(y)),
                                             estimate = c(y$offenses, y$covered, y$population),
                                             status = c(ifelse(ok, "ok", "unavailable"), ifelse(ok, "ok", "unavailable"), rep("ok", nrow(y))),
                                             note = c(ifelse(ok, "", fbi_notes[["unreported"]]), ifelse(ok, "", fbi_notes[["unreported"]]), rep("", nrow(y))),
                                             stringsAsFactors = FALSE)
    }
  }
  d <- do.call(rbind, rows)
  d <- d[d$variable %in% variables & !duplicated(d[, c("geo", "year", "variable")]), , drop = FALSE]
  data.frame(geo = d$geo, name = "", variable = d$variable, estimate = d$estimate, moe = NA_real_, status = d$status,
             bound = NA_character_, note = d$note, period = as.character(d$year), period_start = d$year, period_end = d$year,
             source_id = "fbi_cde", stringsAsFactors = FALSE)
}

register_provider("fbi_cde", list(
  name = "FBI Crime Data Explorer, Uniform Crime Reporting (offenses known to law enforcement)",
  geo_types = c("nation", "state", "place"),
  fetch = fbi_fetch,
  periods = function(settings, recipe) fbi_years,
  period_label = function(period) as.character(period),
  period_kind = "annual",
  availability_note = "The FBI publishes police agencies: here a city is its police department; states and the nation cover the agencies that reported. Counties are not published."))
