# EAC Election Administration and Voting Survey (EAVS): registration and participation reported by
# each election jurisdiction for the 2020 and 2024 general elections.
#  - Jurisdictions are counties in most states, towns in New England and municipalities in
#    Wisconsin, and some cities run their own elections (Chicago, Kansas City). A county's total
#    is the sum of its jurisdictions: county jurisdictions, New England towns (Connecticut's are
#    coded by former county and moved to their planning region by town code) and a city's
#    jurisdiction when at least 99% of the city's residents live in the county. Counties that a
#    city's jurisdiction splits get no value, nor do counties in Wisconsin and Alaska (reported
#    by municipality and statewide). States are sums of all their jurisdictions.
#  - "-88" (does not apply, e.g. North Dakota has no voter registration) counts as zero unless it
#    applies to the whole area; "-99" or blank (not reported) leaves the area without a total.
#    Regions, divisions and the nation are sums of the states that have a total.
#  - Rates divide by the citizen voting-age population (ACS table B29001, 5-year estimates ending
#    in the election year) of the same areas: CVAP_A1b for registration, CVAP_F1a for turnout.
#  - Voting methods (mail, early, election day) are not used: some states' counts do not add up
#    (Indiana's 2024 methods sum to 146% of voters), and all-mail jurisdictions report apart.
# Counts are administrative, so no margin of error is attached.

eavs_cycles <- list(
  `2020` = c(url = "https://www.eac.gov/sites/default/files/2023-12/2020_EAVS_for_Public_Release_nolabel_V1.2_CSV.zip",
             file = "2020_EAVS_for_Public_Release_nolabel_V1.2_CSV.csv"),
  `2024` = c(url = "https://www.eac.gov/sites/default/files/2026-02/2024_EAVS_for_Public_Release_nolabel_V2_csv.zip",
             file = "2024_EAVS_for_Public_Release_nolabel_V2.csv"))
eavs_vintage <- 2024L   # geography used to place jurisdictions in counties
new_england <- c("09", "23", "25", "33", "44", "50")

# One row per jurisdiction in the 50 states and DC: state, county (NA if it has none), the
# counties a city's jurisdiction splits, and items A1b (active registrants) and F1a (voters):
# NA = not reported; "<item>_applies" is FALSE for "-88".
eavs_jurisdictions <- function(year) {
  memoize(paste0("eavs_", year), function() cached(derived_path("eac_eavs", paste0("jurisdictions_", year), "eavs.R"), source = "eac_eavs", compute = function() {
    cycle <- eavs_cycles[[as.character(year)]]
    zip <- cached_download(cycle[["url"]], cache_path("raw", "eac_eavs", basename(cycle[["url"]])), "eac_eavs")
    x <- utils::read.csv(unz(zip, cycle[["file"]]), colClasses = "character", check.names = FALSE)
    st <- state_table()
    x$state <- st$state[match(x$State_Abbr, st$usps)]
    x <- x[x$state %in% st$state[st$in_nation == "TRUE"], , drop = FALSE]
    code <- ifelse(nchar(x$FIPSCode) == 9, paste0("0", x$FIPSCode), x$FIPSCode)  # leading zero lost
    out <- data.frame(state = x$state, eavs_counties(code, x$state), stringsAsFactors = FALSE)
    for (item in c("A1b", "F1a")) {
      v <- suppressWarnings(as.numeric(x[[item]]))
      out[[item]] <- ifelse(v %in% -88, 0, ifelse(is.na(v) | v < 0, NA, v))
      out[[paste0(item, "_applies")]] <- !(v %in% -88)
    }
    out
  }))
}

# The county of each jurisdiction code (state 2 + county 3 + town 5 digits), or of the city it
# names (state 2 + place 5 + "000"); `split` lists the counties of a city that has no main county.
eavs_counties <- function(code, state) {
  counties <- geo_catalog("county", eavs_vintage)$geoid
  first5 <- substr(code, 1, 5)
  last5 <- substr(code, 6, 10)
  full <- nchar(code) == 10
  county <- ifelse(full & last5 == "00000" & first5 %in% counties, first5, NA_character_)
  town <- full & is.na(county) & state %in% new_england
  county[town & first5 %in% counties] <- first5[town & first5 %in% counties]
  ct <- town & state == "09"
  if (any(ct)) county[ct] <- ct_town_regions(eavs_vintage)[last5[ct]]
  split <- rep("", length(code))
  for (i in which(full & is.na(county) & !town)) {
    parts <- tryCatch(place_parts(substr(code[i], 1, 7), eavs_vintage), error = function(e) NULL)
    if (is.null(parts) || !nrow(parts) || !sum(parts$pop)) next
    share <- parts$pop / sum(parts$pop)
    if (max(share) >= 0.99) county[i] <- parts$county[which.max(share)] else split[i] <- paste(parts$county, collapse = ";")
  }
  data.frame(county = county, split = split, stringsAsFactors = FALSE)
}

# Totals of a group of jurisdictions. code: 0 = total, 1 = does not apply, 2 = not reported by
# every jurisdiction (or no jurisdiction matches the area).
eavs_group <- function(j) {
  total <- function(item) {
    if (!nrow(j)) return(c(NA, 2))
    if (!any(j[[paste0(item, "_applies")]])) return(c(NA, 1))
    if (anyNA(j[[item]])) return(c(NA, 2))
    c(sum(j[[item]]), 0)
  }
  a <- total("A1b")
  f <- total("F1a")
  data.frame(variable = c("A1b", "F1a"), estimate = c(a[1], f[1]), code = c(a[2], f[2]), stringsAsFactors = FALSE)
}

eavs_notes <- c("", "does not apply in this state's election system (North Dakota has no voter registration)",
                "not reported by every election jurisdiction in this area, or no jurisdiction in the survey matches it")

eavs_fetch <- function(variables, pieces, periods, options = list()) {
  st <- state_table()
  st <- st[st$in_nation == "TRUE", ]
  rows <- list()
  for (yr in as.integer(periods)) {
    j <- eavs_jurisdictions(yr)
    split <- unlist(strsplit(j$split[nzchar(j$split)], ";"))
    by_state <- lapply(stats::setNames(st$state, st$state), function(s) eavs_group(j[j$state == s, , drop = FALSE]))
    cvap <- acs_fetch("B29001_001", data.frame(key = paste0("state:", st$state), type = "state", geoid = st$state), yr)
    state_cvap <- stats::setNames(cvap$estimate, sub("^state:", "", cvap$geo))
    for (i in seq_len(nrow(pieces))) {
      p <- pieces[i, ]
      if (p$type %in% c("nation", "region", "division")) {
        members <- st$state[switch(p$type, nation = TRUE, region = st$region == p$geoid, division = st$division == p$geoid)]
        g <- eavs_sum_states(by_state[members], state_cvap[members])
      } else {
        g <- if (p$type == "state") by_state[[p$geoid]] else if (p$geoid %in% split) eavs_group(j[0, ]) else
          eavs_group(j[j$county %in% p$geoid, , drop = FALSE])
        area_cvap <- if (p$type == "state") state_cvap[[p$geoid]] else acs_fetch("B29001_001", p[, c("key", "type", "geoid")], yr)$estimate[1]
        g <- rbind(g, data.frame(variable = c("CVAP_A1b", "CVAP_F1a"), estimate = area_cvap, code = ifelse(is.na(area_cvap), 2, 0)))
      }
      rows[[length(rows) + 1]] <- data.frame(geo = p$key, g, period = yr, stringsAsFactors = FALSE)
    }
  }
  d <- do.call(rbind, rows)
  d <- d[d$variable %in% variables, , drop = FALSE]
  data.frame(geo = d$geo, name = "", variable = d$variable, estimate = d$estimate, moe = NA_real_,
             status = c("ok", "not_applicable", "unavailable")[d$code + 1], bound = NA_character_, note = eavs_notes[d$code + 1],
             period = as.character(d$period), period_start = d$period, period_end = d$period, source_id = "eac_eavs",
             stringsAsFactors = FALSE)
}

# A larger area as the sum of its states that have a total for each item, with the citizen
# voting-age population of the same states.
eavs_sum_states <- function(groups, cvap) {
  total <- function(var) {
    v <- vapply(groups, function(g) g$estimate[g$variable == var], 0)
    list(value = sum(v, na.rm = TRUE), with = !is.na(v))
  }
  a <- total("A1b")
  f <- total("F1a")
  data.frame(variable = c("A1b", "F1a", "CVAP_A1b", "CVAP_F1a"),
             estimate = c(a$value, f$value, sum(cvap[a$with]), sum(cvap[f$with])),
             code = 0, stringsAsFactors = FALSE)
}

register_provider("eac_eavs", list(
  name = "U.S. Election Assistance Commission, Election Administration and Voting Survey (EAVS)",
  geo_types = c("nation", "region", "division", "state", "county"),
  fetch = eavs_fetch,
  periods = function(settings, recipe) as.integer(names(eavs_cycles)),
  period_label = function(period) paste(period, "election"),
  period_kind = "point",
  availability_note = "The EAVS reports election jurisdictions (counties, New England towns, Wisconsin municipalities, a few cities); values are for counties, states and larger areas."))
