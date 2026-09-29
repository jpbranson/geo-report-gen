# Child care sources. These measure different things and are never substituted for one
# another:
#   dol_ndcp   prices charged by providers (median weekly full-time price), counties, 2008-2022
#   census_cbp child day care establishments with paid employees (NAICS 624410), 1998-2023
#              (County Business Patterns, all industries, in cbp.R)
#   tx_hhsc    licensed capacity of Texas child care operations (current snapshot only)
# Preschool enrollment (ACS) and estimated need (ACS B23008) are separate ACS metrics.

# ---- DOL Women's Bureau, National Database of Childcare Prices ----------------------------

ndcp_long <- function() {
  memoize("ndcp_long", function() cached(derived_path("dol_ndcp", "ndcp_long", "childcare.R"), source = "dol_ndcp", compute = function() {
    f <- cached_download("https://www.dol.gov/sites/dolgov/files/WB/NDCP2022.xlsx",
                         cache_path("raw", "dol_ndcp", "NDCP2022.xlsx"), "dol_ndcp")
    x <- readxl::read_excel(f, col_types = "text")
    keep <- c("COUNTY_FIPS_CODE", "STUDYYEAR", "MCINFANT", "MCTODDLER", "MCPRESCHOOL",
              "MFCCINFANT", "MFCCTODDLER", "MFCCPRESCHOOL", "MFI")
    x <- as.data.frame(x[, keep])
    num <- function(v) suppressWarnings(as.numeric(v))
    d <- data.frame(key = paste0("county:", pad(num(x$COUNTY_FIPS_CODE), 5)), year = as.integer(num(x$STUDYYEAR)),
                    stringsAsFactors = FALSE)
    for (v in keep[-(1:2)]) d[[v]] <- num(x[[v]])
    # Annual full-time price as a share of median family income (both nominal, same year).
    d$SHARE_MFI_CINFANT <- 100 * 52 * d$MCINFANT / d$MFI
    d$SHARE_MFI_CPRESCHOOL <- 100 * 52 * d$MCPRESCHOOL / d$MFI
    d
  }))
}

register_provider("dol_ndcp", list(
  name = "U.S. Department of Labor Women's Bureau, National Database of Childcare Prices (2008-2022)",
  geo_types = c("county"),
  fetch = function(variables, pieces, periods, options = list()) {
    d <- ndcp_long()
    d <- d[d$key %in% pieces$key & d$year %in% as.integer(periods), , drop = FALSE]
    if (!nrow(d)) return(empty_values())
    out <- do.call(rbind, lapply(intersect(variables, names(d)), function(v) {
      data.frame(geo = d$key, name = "", variable = v, estimate = d[[v]], moe = NA_real_,
                 status = ifelse(is.na(d[[v]]), "unavailable", "ok"), bound = NA_character_, note = "",
                 period = as.character(d$year), period_start = d$year, period_end = d$year,
                 source_id = "dol_ndcp", series = "NDCP county prices", stringsAsFactors = FALSE)
    }))
    out
  },
  periods = function(settings, recipe) seq(max(2008L, as.integer(settings$history_start %||% 2008)), 2022L),
  period_label = function(period) as.character(period),
  period_kind = "annual",
  availability_note = "NDCP prices are county-level only; there are no price data for Indiana or New Mexico in any year, and some states have gaps."))

# ---- Texas HHSC Child Care Regulation: licensed capacity (current) ------------------------

# Aggregated through the open Socrata API: total licensed capacity by county and operation
# type. Listed family homes (capacity is a placeholder of 3) and residential operations are
# excluded. Records carry county names (no FIPS) and few coordinates, so values are county
# totals; a facility's "city" is its mailing city, not a census place.
tx_capacity <- function() {
  memoize("tx_capacity", function() cached(cache_path("raw", "tx_hhsc", "capacity_by_county.parquet"), source = "tx_hhsc", compute = function() {
    types <- c("Licensed Center", "Licensed Child-Care Home", "Registered Child-Care Home")
    where <- paste0("operation_type in(", paste0("'", types, "'", collapse = ","), ")")
    req <- http_request("https://data.texas.gov/resource/bc5r-88dy.json", "tx_hhsc",
                        query = list(`$select` = "county,operation_type,sum(total_capacity) as capacity,count(*) as operations",
                                     `$where` = where, `$group` = "county,operation_type", `$limit` = "5000"))
    resp <- http_perform(req)
    check_status(resp, "Texas HHSC child care operations")
    x <- jsonlite::fromJSON(httr2::resp_body_string(resp))
    counties <- geo_catalog("county", 2024)
    counties <- counties[startsWith(counties$geoid, "48"), ]
    base <- toupper(sub(" County, Texas$", "", counties$name))
    x$key <- counties$key[match(toupper(trimws(x$county)), base)]
    x$capacity <- as.numeric(x$capacity)
    x$operations <- as.numeric(x$operations)
    x$retrieved <- format(Sys.Date())
    as.data.frame(x[, c("key", "county", "operation_type", "capacity", "operations", "retrieved")])
  }))
}

register_provider("tx_hhsc", list(
  name = "Texas Health and Human Services Commission, Child Care Regulation operations data (data.texas.gov)",
  geo_types = c("county", "state"),
  fetch = function(variables, pieces, periods, options = list()) {
    x <- tx_capacity()
    x <- x[!is.na(x$key), ]
    by_key <- stats::aggregate(cbind(capacity, operations) ~ key, data = x, FUN = sum)
    state <- data.frame(key = "state:48", capacity = sum(x$capacity), operations = sum(x$operations))
    by_key <- rbind(by_key, state)
    d <- by_key[by_key$key %in% pieces$key, , drop = FALSE]
    if (!nrow(d)) return(empty_values())
    yr <- as.integer(substr(x$retrieved[1], 1, 4))
    do.call(rbind, lapply(c("capacity", "operations"), function(v) {
      data.frame(geo = d$key, name = "", variable = v, estimate = d[[v]], moe = NA_real_, status = "ok",
                 bound = NA_character_, note = "", period = as.character(yr), period_start = yr, period_end = yr,
                 source_id = "tx_hhsc", series = "Current licensing records", stringsAsFactors = FALSE)
    }))
  },
  periods = function(settings, recipe) as.integer(format(Sys.Date(), "%Y")),
  period_label = function(period) paste0(period, " (current records)"),
  period_kind = "snapshot",
  availability_note = "Texas licensing data are a current snapshot (no history) and cover Texas only."))
