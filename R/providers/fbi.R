# FBI Crime Data Explorer (Uniform Crime Reporting): violent and property offenses known to police,
# through the CDE API. The api.data.gov key (DATA_GOV_API_KEY in .env) is sent only as a request
# header, so it never appears in URLs or logs.
#  - The FBI publishes by police agency. A city is its police department ("<Name> Police
#    Department", type City, in the city's state). A county adds up every agency the FBI lists in
#    it (city police, the sheriff, campus, transit and state police posts); agencies it places in
#    no county, such as most state police, are left out.
#  - A city's year needs all 12 months reported. States and the nation are the agencies that
#    reported, with the population they cover (<offense>_POP); POP is the full population, so the
#    coverage is V_POP / POP. A county's year needs agencies serving 75% of its residents.
#  - The FBI advises comparing a city with its state and a state with the nation, not ranking areas.

fbi_years <- 2016:2025
fbi_offenses <- c(V = "violent", P = "property")
fbi_vintage <- 2024L  # Census populations that divide city departments listed in several counties
fbi_min_coverage <- 0.75  # the FBI's rule for metropolitan areas asks for 75% of agencies
fbi_usual_min <- 20  # offenses in an agency's median year before a quarter of it is judged too few

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

# Every police agency of one state: ori, name, type and the counties the FBI lists it in
# ("CASS, CLAY, JACKSON, PLATTE" for the Kansas City Police Department).
fbi_agencies <- function(state_abbr) {
  cached(cache_path("raw", "fbi_cde", "agency-lists", paste0(state_abbr, ".parquet")), source = "fbi_cde", compute = function() {
    a <- unlist(fbi_get(paste0("agency/byStateAbbr/", state_abbr)), recursive = FALSE)
    field <- function(k) vapply(a, function(x) if (is.null(x[[k]])) "" else as.character(x[[k]]), "")
    data.frame(ori = field("ori"), agency = field("agency_name"), type = field("agency_type_name"),
               counties = field("counties"), stringsAsFactors = FALSE)
  })
}

# City police departments of one state, with the city name they are matched by.
fbi_city_agencies <- function(state_abbr) {
  a <- fbi_agencies(state_abbr)
  a <- a[a$type == "City", , drop = FALSE]
  a$city <- normalize_name(sub(" Police Department.*$", "", a$agency))
  a
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
    if (is.null(pop)) stop("The FBI's response for ", path, " has no series named '", name, "'", call. = FALSE)
    months <- names(pop)
    value <- function(l) vapply(months, function(m) if (is.null(l[[m]])) NA_real_ else as.numeric(l[[m]]), 0, USE.NAMES = FALSE)
    data.frame(year = as.integer(substr(months, 4, 7)), offenses = value(x$offenses$actuals[[paste(name, "Offenses")]]),
               population = value(pop), covered = value(x$populations$participated_population[[name]]))
  })
}

# Annual totals: one agency needs every month reported in full; states and the nation use the
# agencies that reported and the population they cover. An agency's year with under a quarter of
# its usual offenses (its median year, when that is at least 20) also counts as not reported: some
# agencies marked months as reported while moving to NIBRS but sent almost nothing.
fbi_annual <- function(s, agency) {
  y <- do.call(rbind, lapply(split(s, s$year), function(y) {
    reported <- nrow(y) == 12 && !anyNA(y$offenses) && !anyNA(y$covered)
    if (agency) reported <- reported && all(y$covered >= y$population)
    data.frame(year = y$year[1], offenses = if (reported) sum(y$offenses) else NA_real_,
               covered = if (reported) mean(y$covered) else NA_real_, population = mean(y$population))
  }))
  if (agency) {
    usual <- stats::median(y$offenses, na.rm = TRUE)
    low <- !is.na(usual) & usual >= fbi_usual_min & !is.na(y$offenses) & y$offenses < usual / 4
    y$offenses[low] <- NA
    y$covered[low] <- NA
  }
  y
}

# "St. Joseph County" and the FBI's "ST JOSEPH" both give "stjoseph"; planning regions and
# independent cities keep their words ("capitolplanningregion", "stlouiscity").
fbi_county_key <- function(x) {
  gsub("[^a-z]", "", sub("\\s+(county|parish|borough|census area|city and borough|municipality)$", "", normalize_name(x)))
}

# Every agency the FBI lists in a county, with the share of it counted there (1 unless the FBI
# lists it in several counties).
fbi_county_agencies <- function(geoid, name) {
  st <- substr(geoid, 1, 2)
  s <- state_table()
  a <- fbi_agencies(s$usps[s$state == st])
  listed <- lapply(strsplit(a$counties, ", "), fbi_county_key)
  here <- vapply(listed, function(k) fbi_county_key(sub(",.*$", "", name)) %in% k, TRUE)
  a <- a[here, , drop = FALSE]
  listed <- listed[here]
  a$share <- 1
  multi <- which(lengths(listed) > 1)
  if (length(multi)) {
    counties <- geo_catalog("county", fbi_vintage)
    counties <- counties[substr(counties$geoid, 1, 2) == st, , drop = FALSE]
    places <- geo_catalog("place", fbi_vintage, paste0("place-", st))
    places <- places[!grepl(" CDP,", places$name), , drop = FALSE]  # departments serve incorporated places
    for (i in multi) a$share[i] <- fbi_county_share(a$agency[i], listed[[i]], geoid, counties, places)
  }
  a
}

# The share of a city police department listed in several counties that falls in county `geoid`:
# where the city's residents live (Census place-by-county populations), or the listed counties'
# populations if the city is not found.
fbi_county_share <- function(agency, listed, geoid, counties, places) {
  pop <- stats::setNames(counties$pop, counties$geoid)
  pop <- pop[fbi_county_key(sub(",.*$", "", counties$name)) %in% listed]
  city <- places$geoid[fbi_city_name(places$name) == normalize_name(sub(" Police Department.*$", "", agency))]
  if (length(city) == 1) {
    parts <- place_parts(city, fbi_vintage)
    if (sum(parts$pop) > 0) pop <- stats::setNames(parts$pop, parts$county)
  }
  sum(pop[names(pop) == geoid]) / sum(pop)
}

# Annual totals of a county's agencies (each counted by its share): offenses and residents of the
# agencies that reported every month, and residents of all of them. A year whose reporting
# agencies serve under 75% of those residents has no offenses (NA); NULL if no agency has residents.
fbi_county_annual <- function(agencies, offense) {
  y <- do.call(rbind, lapply(seq_len(nrow(agencies)), function(i) {
    s <- fbi_series(paste0("summarized/agency/", agencies$ori[i]), agencies$agency[i], offense)
    cbind(fbi_annual(s, agency = TRUE), share = agencies$share[i])
  }))
  total <- function(x) as.vector(tapply(y$share * x, y$year, sum, na.rm = TRUE))
  d <- data.frame(year = sort(unique(y$year)), offenses = total(y$offenses), covered = total(y$covered),
                  population = total(y$population))
  if (!any(d$population > 0)) return(NULL)
  low <- !(d$population > 0 & d$covered >= fbi_min_coverage * d$population)
  d$offenses[low] <- NA
  d$covered[low] <- NA
  d
}

# A city's police department, year by year (NULL if no department matches the place's name).
fbi_city_annual <- function(usps, place_name, offense) {
  a <- fbi_city_agencies(usps)
  a <- a[a$city == fbi_city_name(place_name), , drop = FALSE]
  if (nrow(a) == 1) fbi_annual(fbi_series(paste0("summarized/agency/", a$ori), a$agency, offense), agency = TRUE)
}

# Annual offenses, residents covered by reporting agencies and all residents of one piece (NULL
# when no agency serves it). The part of a city in one county ("Williamson County (part), Austin
# city, Texas") is its department in proportion to the residents there, as in county totals.
fbi_piece_annual <- function(p, offense) {
  s <- state_table()
  s <- s[s$state == substr(p$geoid, 1, 2), , drop = FALSE]
  switch(p$type,
    nation = fbi_annual(fbi_series("summarized/national", "United States", offense), agency = FALSE),
    state = fbi_annual(fbi_series(paste0("summarized/state/", s$usps), s$name, offense), agency = FALSE),
    place = fbi_city_annual(s$usps, p$name, offense),
    place_part = {
      y <- fbi_city_annual(s$usps, sub("^[^,]*, ", "", p$name), offense)
      if (!is.null(y)) {
        parts <- place_parts(sub("-.*$", "", p$geoid), fbi_vintage)
        share <- sum(parts$pop[parts$key == p$key]) / sum(parts$pop)
        y[c("offenses", "covered", "population")] <- y[c("offenses", "covered", "population")] * share
        y
      }
    },
    county = {
      a <- fbi_county_agencies(p$geoid, p$name)
      if (nrow(a)) fbi_county_annual(a, offense)
    })
}

fbi_notes <- c(place = "no city police department in the FBI's data matches this place",
               county = "the FBI lists no police agency serving this county's residents",
               unreported = "not reported to the FBI for every month of this year, or reported with under a quarter of the usual offenses (many agencies missed 2021, when reporting moved to NIBRS)",
               coverage = "the police agencies that reported every month of this year serve less than 75% of the county's residents")

fbi_fetch <- function(variables, pieces, periods, options = list()) {
  years <- as.integer(periods)
  offenses <- intersect(names(fbi_offenses), sub("_POP$", "", variables))
  rows <- list()
  for (i in seq_len(nrow(pieces))) {
    p <- pieces[i, ]
    for (off in if (length(offenses)) offenses else "V") {
      vars <- c(off, paste0(off, "_POP"), "POP")
      y <- fbi_piece_annual(p, off)
      if (is.null(y)) {
        g <- expand.grid(year = years, variable = vars, stringsAsFactors = FALSE)
        rows[[length(rows) + 1]] <- data.frame(geo = p$key, g, estimate = NA_real_, status = "unavailable",
                                               note = fbi_notes[[if (p$type == "county") "county" else "place"]], stringsAsFactors = FALSE)
        next
      }
      y <- y[y$year %in% years, , drop = FALSE]
      ok <- !is.na(y$offenses)
      why <- ifelse(ok, "", fbi_notes[[if (p$type == "county") "coverage" else "unreported"]])
      rows[[length(rows) + 1]] <- data.frame(geo = p$key, year = rep(y$year, 3), variable = rep(vars, each = nrow(y)),
                                             estimate = c(y$offenses, y$covered, y$population),
                                             status = c(ifelse(ok, "ok", "unavailable"), ifelse(ok, "ok", "unavailable"), rep("ok", nrow(y))),
                                             note = c(why, why, rep("", nrow(y))), stringsAsFactors = FALSE)
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
  geo_types = c("nation", "state", "county", "place", "place_part"),
  fetch = fbi_fetch,
  periods = function(settings, recipe) fbi_years,
  period_label = function(period) as.character(period),
  period_kind = "annual",
  availability_note = "The FBI publishes police agencies: here a city is its police department and a county adds up the agencies listed in it; states and the nation cover the agencies that reported."))
