# Child care sources. These measure different things and are never substituted for one
# another:
#   dol_ndcp   prices charged by providers (median weekly full-time price), counties, 2008-2022
#   census_cbp child day care establishments with paid employees (NAICS 624410), 1998-2023
#              (County Business Patterns, all industries, in cbp.R)
#   tx_hhsc    licensed capacity of Texas child care operations (current snapshot only)
#   in_fssa    Indiana child care provider listings and capacity (current snapshot only)
# Preschool enrollment (ACS) and estimated need (ACS B23008) are separate ACS metrics.

# ---- DOL Women's Bureau, National Database of Childcare Prices ----------------------------

ndcp_long <- function() {
  memoize("ndcp_long", function() cached(derived_path("dol_ndcp", "ndcp_long", "childcare.R"), source = "dol_ndcp", compute = function() {
    f <- cached_download("https://www.dol.gov/sites/dolgov/files/WB/NDCP2022.xlsx",
                         cache_path("raw", "dol_ndcp", "NDCP2022.xlsx"), "dol_ndcp")
    x <- readxl::read_excel(f, col_types = "text")
    keep <- c("COUNTY_FIPS_CODE", "STUDYYEAR", "MCINFANT", "MCTODDLER", "MCPRESCHOOL", "MCSA",
              "MFCCINFANT", "MFCCTODDLER", "MFCCPRESCHOOL", "MFCCSA", "_75CINFANT", "_75FCCINFANT", "MFI",
              "FLFPR_20to64_UNDER6", "FLFPR_20to64_UNDER6_STATE")
    x <- as.data.frame(x[, keep])
    num <- function(v) suppressWarnings(as.numeric(v))
    d <- data.frame(key = paste0("county:", pad(num(x$COUNTY_FIPS_CODE), 5)), year = as.integer(num(x$STUDYYEAR)),
                    stringsAsFactors = FALSE)
    for (v in keep[-(1:2)]) d[[sub("^_", "P", v)]] <- num(x[[v]])   # _75CINFANT -> P75CINFANT
    # Annual full-time price as a share of median family income (both nominal, same year).
    d$SHARE_MFI_CINFANT <- 100 * 52 * d$MCINFANT / d$MFI
    d$SHARE_MFI_CPRESCHOOL <- 100 * 52 * d$MCPRESCHOOL / d$MFI
    # The file repeats each state's labor force rate on its county rows: keep it once, under the state.
    state <- d[, c("key", "year", "FLFPR_20to64_UNDER6_STATE")]
    state$key <- paste0("state:", substr(state$key, 8, 9))
    state <- state[!duplicated(state[, c("key", "year")]), , drop = FALSE]
    names(state)[3] <- "FLFPR_20to64_UNDER6"
    d$FLFPR_20to64_UNDER6_STATE <- NULL
    state[setdiff(names(d), names(state))] <- NA_real_
    rbind(d, state[, names(d)])
  }))
}

register_provider("dol_ndcp", list(
  name = "U.S. Department of Labor Women's Bureau, National Database of Childcare Prices (2008-2022)",
  geo_types = c("county", "state"),
  fetch = function(variables, pieces, periods, options = list()) {
    d <- ndcp_long()
    d <- d[d$key %in% pieces$key & d$year %in% as.integer(periods), , drop = FALSE]
    if (!nrow(d)) return(empty_values())
    out <- do.call(rbind, lapply(intersect(variables, names(d)), function(v) {
      x <- d[startsWith(d$key, "county:") | v == "FLFPR_20to64_UNDER6", , drop = FALSE]   # states have only the labor force rate
      if (!nrow(x)) return(NULL)
      data.frame(geo = x$key, name = "", variable = v, estimate = x[[v]], moe = NA_real_,
                 status = ifelse(is.na(x[[v]]), "unavailable", "ok"), bound = NA_character_, note = "",
                 period = as.character(x$year), period_start = x$year, period_end = x$year,
                 source_id = "dol_ndcp", series = "NDCP county prices", stringsAsFactors = FALSE)
    }))
    if (is.null(out)) empty_values() else out
  },
  periods = function(settings, recipe) seq(max(2008L,as.integer(settings$history_start %||% 2008)), 2022L),
  period_label = function(period) as.character(period),
  period_kind = "annual",
  availability_note = paste("NDCP prices are county-level only (the labor force rate also has state values); there are no price data",
                            "for Indiana or New Mexico in any year, and some states have gaps.")))

# ---- Texas HHSC Child Care Regulation: licensed capacity (current) ------------------------

# Aggregated through the open Socrata API: capacity and number of operations by county, operation
# type and whether the operation accepts child care subsidies, for operations in operation
# (operation_status Y). Listed family homes (capacity is a placeholder of 3) and residential
# operations are excluded. Records carry county names (no FIPS) and few coordinates, so values are
# county totals; a facility's "city" is its mailing city, not a census place.
tx_capacity_path <- function() cache_path("raw", "tx_hhsc", "capacity_by_county_type.parquet")

tx_capacity <- function() {
  memoize("tx_capacity", function() cached(tx_capacity_path(), source = "tx_hhsc", compute = function() {
    types <- c("Licensed Center", "Licensed Child-Care Home", "Registered Child-Care Home")
    where <- paste0("operation_status='Y' AND operation_type in(", paste0("'", types, "'", collapse = ","), ")")
    req <- http_request("https://data.texas.gov/resource/bc5r-88dy.json", "tx_hhsc",
                        query = list(`$select` = "county,operation_type,accepts_child_care_subsidies,sum(total_capacity) as capacity,count(*) as operations",
                                     `$where` = where, `$group` = "county,operation_type,accepts_child_care_subsidies", `$limit` = "5000"))
    resp <- http_perform(req)
    check_status(resp, "Texas HHSC child care operations")
    x <- jsonlite::fromJSON(httr2::resp_body_string(resp))
    counties <- geo_catalog("county", 2024)
    counties <- counties[startsWith(counties$geoid, "48"), ]
    base <- toupper(sub(" County, Texas$", "", counties$name))
    x$key <- counties$key[match(toupper(trimws(x$county)), base)]
    x$capacity <- as.numeric(x$capacity)
    x$operations <- as.numeric(x$operations)
    as.data.frame(x[, c("key", "county", "operation_type", "accepts_child_care_subsidies", "capacity", "operations")])
  }))
}

# One row per county and for the state: capacity, operations, and operations by type.
tx_areas <- function() {
  x <- tx_capacity()
  x <- x[!is.na(x$key), ]
  sums <- function(key, d) data.frame(key = key, capacity = sum(d$capacity), operations = sum(d$operations),
    centers = sum(d$operations[d$operation_type == "Licensed Center"]),
    centers_subsidy = sum(d$operations[d$operation_type == "Licensed Center" & d$accepts_child_care_subsidies == "Y"]),
    licensed_homes = sum(d$operations[d$operation_type == "Licensed Child-Care Home"]),
    registered_homes = sum(d$operations[d$operation_type == "Registered Child-Care Home"]), stringsAsFactors = FALSE)
  rbind(do.call(rbind, lapply(split(x, x$key), function(d) sums(d$key[1], d))), sums("state:48", x))
}

tx_fetch <- function(variables, pieces, periods, options = list()) {
  d <- tx_areas()
  d <- d[d$key %in% pieces$key, , drop = FALSE]
  if (!nrow(d)) return(empty_values())
  yr <- snapshot_year(tx_capacity_path())
  counts <- c("capacity", "operations", "centers", "centers_subsidy", "licensed_homes", "registered_homes")
  out <- lapply(intersect(variables, counts), function(v) {
    data.frame(geo = d$key, name = "", variable = v, estimate = d[[v]], moe = NA_real_, status = "ok",
               bound = NA_character_, note = "", period = as.character(yr), period_start = yr, period_end = yr,
               source_id = "tx_hhsc", series = "Current licensing records", stringsAsFactors = FALSE)
  })
  # Children under 5 of the latest ACS 5-year release, the denominator of capacity per 100 children.
  if ("UNDER5" %in% variables) {
    release <- as.integer(options$settings$acs_release %||% 2024)
    a <- acs_fetch(c("B01001_003", "B01001_027"), pieces, release)
    under5 <- if (nrow(a)) tapply(a$estimate, a$geo, sum) else numeric()
    out[[length(out) + 1]] <- data.frame(geo = d$key, name = "", variable = "UNDER5", estimate = as.numeric(under5[d$key]), moe = NA_real_,
      status = ifelse(is.na(under5[d$key]), "unavailable", "ok"), bound = NA_character_,
      note = paste0("children under 5 from the ", release - 4, "-", release, " ACS, not a count at the date of the licensing records"),
      period = as.character(yr), period_start = yr, period_end = yr, source_id = "tx_hhsc", series = "Current licensing records", stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}

register_provider("tx_hhsc", list(
  name = "Texas Health and Human Services Commission, Child Care Regulation operations data (data.texas.gov)",
  geo_types = c("county", "state"),
  fetch = tx_fetch,
  periods = function(settings, recipe) snapshot_year(tx_capacity_path()),
  period_label = function(period) paste0(period, " (current records)"),
  period_kind = "snapshot",
  availability_note = "Texas licensing data are a current snapshot (no history) and cover Texas only."))

# ---- Indiana FSSA child care provider listings (current) ------------------------------------

# One web page with three HTML tables: licensed child care centers, licensed child care homes and
# registered child care ministries (which report no capacity). It is read with base R, so a change of
# the page layout stops the build with a message rather than returning wrong numbers. Addresses of
# homes are left out by law, so values are county totals; the state total is the sum of the counties.
fssa_url <- "https://www.in.gov/fssa/carefinder/family-resources/forms/child-care-provider-listings"
fssa_raw_path <- function() cache_path("raw", "in_fssa", "provider-listings.html")
fssa_types <- c("Licensed Center", "Licensed Home", "Registered Ministry")

fssa_cells <- function(row) {
  cells <- regmatches(row, gregexpr("(?s)<td.*?</td>", row, perl = TRUE))[[1]]
  cells <- gsub("(?i)<br\\s*/?>", "; ", cells, perl = TRUE)
  cells <- gsub("<[^>]+>", "", cells)
  trimws(gsub("&nbsp;", " ", gsub("&amp;", "&", cells, fixed = TRUE), fixed = TRUE))
}

# One row per provider: table (1 centers, 2 homes, 3 registered ministries), county name, PTQ level, capacity.
fssa_parse <- function(html) {
  tables <- regmatches(html, gregexpr("(?s)<table.*?</table>", html, perl = TRUE))[[1]]
  if (length(tables) != length(fssa_types)) stop("The Indiana FSSA provider page has ", length(tables), " tables, not ", length(fssa_types), call. = FALSE)
  out <- lapply(seq_along(tables), function(i) {
    rows <- lapply(regmatches(tables[i], gregexpr("(?s)<tr.*?</tr>", tables[i], perl = TRUE))[[1]], fssa_cells)
    header <- tolower(gsub("[^A-Za-z0-9]+", "_", rows[[1]]))
    body <- Filter(function(r) length(r) == length(header), rows[-1])
    d <- as.data.frame(do.call(rbind, body), stringsAsFactors = FALSE)
    names(d) <- header
    if (!"county" %in% header) stop("The Indiana FSSA provider table ", i, " has no County column", call. = FALSE)
    data.frame(type = fssa_types[i], county = d$county, ptq = if ("ptq_level" %in% header) d$ptq_level else NA_character_,
               capacity = if ("capacity" %in% header) suppressWarnings(as.numeric(d$capacity)) else NA_real_, stringsAsFactors = FALSE)
  })
  do.call(rbind, out)
}

fssa_listings <- function() {
  memoize("fssa_listings", function() cached(derived_path("in_fssa", "listings", "childcare.R"), source = "in_fssa_provider_listings", compute = function() {
    page <- cached_download(fssa_url, fssa_raw_path(), "in_fssa_provider_listings")
    d <- fssa_parse(paste(readLines(page, warn = FALSE, encoding = "UTF-8"), collapse = "\n"))
    counties <- geo_catalog("county", 2024)
    counties <- counties[startsWith(counties$geoid, "18"), ]
    simple <- function(x) gsub("[^A-Z]", "", toupper(x))
    d$key <- counties$key[match(simple(d$county), simple(sub(" County, Indiana$", "", counties$name)))]
    if (anyNA(d$key)) stop("Indiana FSSA counties not recognized: ", paste(unique(d$county[is.na(d$key)]), collapse = ", "), call. = FALSE)
    d
  }))
}

# One row per county and for the state: providers by type, capacity, and capacity at Paths to QUALITY levels 3 and 4.
fssa_areas <- function() {
  d <- fssa_listings()
  sums <- function(key, x) data.frame(key = key, centers = sum(x$type == "Licensed Center"), homes = sum(x$type == "Licensed Home"),
    ministries = sum(x$type == "Registered Ministry"), capacity = sum(x$capacity, na.rm = TRUE),
    capacity_ptq34 = sum(x$capacity[x$ptq %in% c("Level 3", "Level 4")], na.rm = TRUE), stringsAsFactors = FALSE)
  rbind(do.call(rbind, lapply(split(d, d$key), function(x) sums(x$key[1], x))), sums("state:18", d))
}

fssa_fetch <- function(variables, pieces, periods, options = list()) {
  d <- fssa_areas()
  d <- d[d$key %in% pieces$key, , drop = FALSE]
  if (!nrow(d)) return(empty_values())
  yr <- snapshot_year(fssa_raw_path())
  row <- function(v, estimate, status = "ok", note = "") data.frame(geo = d$key, name = "", variable = v, estimate = estimate, moe = NA_real_,
    status = status, bound = NA_character_, note = note, period = as.character(yr), period_start = yr, period_end = yr,
    source_id = "in_fssa_provider_listings", series = "Current provider listings", stringsAsFactors = FALSE)
  out <- lapply(intersect(variables, c("centers", "homes", "ministries", "capacity", "capacity_ptq34")), function(v) row(v, d[[v]]))
  if ("UNDER5" %in% variables) {
    release <- as.integer(options$settings$acs_release %||% 2024)
    a <- acs_fetch(c("B01001_003", "B01001_027"), pieces, release)
    under5 <- if (nrow(a)) tapply(a$estimate, a$geo, sum) else numeric()
    out[[length(out) + 1]] <- row("UNDER5", as.numeric(under5[d$key]), ifelse(is.na(under5[d$key]), "unavailable", "ok"),
                                  paste0("children under 5 from the ", release - 4, "-", release, " ACS, not a count at the date of the listings"))
  }
  do.call(rbind, out)
}

register_provider("in_fssa_provider_listings", list(
  name = "Indiana Family and Social Services Administration, Child Care Provider Listings",
  geo_types = c("county", "state"),
  fetch = fssa_fetch,
  periods = function(settings, recipe) snapshot_year(fssa_raw_path()),
  period_label = function(period) paste0(period, " (current listings)"),
  period_kind = "snapshot",
  availability_note = "Indiana's provider listings are a current snapshot (no history) and cover Indiana only; registered ministries report no capacity."))
