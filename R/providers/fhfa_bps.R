# Housing market series:
#  - FHFA annual House Price Indexes (all-transactions, "developmental", nominal), counties,
#    states and the nation, 1975 onward. Indexes are not additive: combined areas get no value.
#  - Census Bureau Building Permits Survey, annual new housing units authorized, counties
#    (2000 onward) and permit-issuing places (2007 onward, when FIPS place codes appear).

fhfa_read <- function(level) {
  file <- paste0("hpi_at_", level, ".xlsx")
  path <- cached_download(paste0("https://www.fhfa.gov/hpi/download/annual/", file), cache_path("raw", "fhfa", file), "fhfa")
  x <- readxl::read_excel(path, skip = 5, col_types = "text")
  as.data.frame(x)
}

fhfa_long <- function() {
  memoize("fhfa_long", function() cached(derived_path("fhfa", "hpi_long", "fhfa_bps.R"), source = "fhfa", compute = function() {
    co <- fhfa_read("county")
    st <- fhfa_read("state")
    us <- fhfa_read("national")
    rows <- list(
      data.frame(key = paste0("county:", co[["FIPS code"]]), year = co$Year, hpi2000 = co[["HPI with 2000 base"]]),
      data.frame(key = paste0("state:", st$FIPS), year = st$Year, hpi2000 = st[["HPI with 2000 base"]]),
      data.frame(key = "nation:US", year = us$Year, hpi2000 = us[["HPI with 2000 base"]]))
    d <- do.call(rbind, rows)
    d$year <- as.integer(d$year)
    d$hpi2000 <- suppressWarnings(as.numeric(d$hpi2000))
    d[!is.na(d$year), ]
  }))
}

register_provider("fhfa_hpi", list(
  name = "Federal Housing Finance Agency, annual House Price Index (all-transactions, developmental)",
  geo_types = c("nation", "state", "county"),
  fetch = function(variables, pieces, periods, options = list()) {
    d <- fhfa_long()
    d <- d[d$key %in% pieces$key & d$year %in% as.integer(periods), , drop = FALSE]
    if (!nrow(d)) return(empty_values())
    data.frame(geo = d$key, name = "", variable = "hpi2000", estimate = d$hpi2000, moe = NA_real_,
               status = ifelse(is.na(d$hpi2000), "unavailable", "ok"), bound = NA_character_, note = "",
               period = as.character(d$year), period_start = d$year, period_end = d$year,
               source_id = "fhfa_hpi", series = "FHFA all-transactions index", stringsAsFactors = FALSE)
  },
  periods = function(settings, recipe) seq(max(1975L, as.integer(settings$history_start %||% 1975)), 2025L),
  period_label = function(period) as.character(period),
  period_kind = "annual",
  availability_note = "FHFA indexes are published for counties with enough repeat sales, states, metro areas and the nation; not for places."))

# ---- Building permits ----------------------------------------------------------------------

bps_region_files <- c(`1` = "Northeast%20Region/ne", `2` = "Midwest%20Region/mw", `3` = "South%20Region/so", `4` = "West%20Region/we")

bps_read <- function(url, file) {
  path <- cached_download(url, cache_path("raw", "census_bps", file), "census_bps")
  lines <- readLines(path, warn = FALSE)
  body <- lines[-(1:3)]
  body <- body[nzchar(trimws(body))]
  utils::read.csv(text = body, header = FALSE, colClasses = "character", strip.white = TRUE)
}

# Units authorized (estimates with imputation) = 1-unit + 2-unit + 3-4 unit + 5+ unit units.
bps_long <- function() {
  memoize("bps_long", function() cached(derived_path("census_bps", "bps_long", "fhfa_bps.R"), source = "census_bps", compute = function() {
    out <- list()
    for (yr in 2000:2025) {
      d <- tryCatch(bps_read(sprintf("https://www2.census.gov/econ/bps/County/co%da.txt", yr), sprintf("co%da.txt", yr)),
                    error = function(e) NULL)
      if (is.null(d)) next
      units <- rowSums(sapply(c(8, 11, 14, 17), function(j) suppressWarnings(as.numeric(d[[j]]))))
      out[[length(out) + 1]] <- data.frame(key = paste0("county:", pad(d$V2, 2), pad(d$V3, 3)), year = yr,
                                           units = units, months = 12, stringsAsFactors = FALSE)
    }
    for (yr in 2007:2025) {
      for (reg in names(bps_region_files)) {
        url <- sprintf("https://www2.census.gov/econ/bps/Place/%s%da.txt", bps_region_files[[reg]], yr)
        d <- tryCatch(bps_read(url, sprintf("place_%s_%da.txt", reg, yr)), error = function(e) NULL)
        if (is.null(d)) next
        fips_place <- trimws(d$V6)
        ok <- grepl("^[0-9]{5}$", fips_place) & fips_place != "99990"
        d <- d[ok, , drop = FALSE]
        units <- rowSums(sapply(c(19, 22, 25, 28), function(j) suppressWarnings(as.numeric(d[[j]]))))
        out[[length(out) + 1]] <- data.frame(key = paste0("place:", pad(d$V2, 2), trimws(d$V6)), year = yr, units = units,
                                             months = suppressWarnings(as.numeric(d$V16)), stringsAsFactors = FALSE)
      }
    }
    d <- do.call(rbind, out)
    # A place can appear on several rows (parts in several counties): sum the units; the year
    # counts as fully reported only if every part reported all 12 months.
    units <- stats::aggregate(units ~ key + year, data = d, FUN = sum)
    months <- stats::aggregate(months ~ key + year, data = d, FUN = min)
    merge(units, months, by = c("key", "year"))
  }))
}

register_provider("census_bps", list(
  name = "U.S. Census Bureau, Building Permits Survey (annual, units authorized, with imputation)",
  geo_types = c("county", "place"),
  fetch = function(variables, pieces, periods, options = list()) {
    d <- bps_long()
    d <- d[d$key %in% pieces$key & d$year %in% as.integer(periods), , drop = FALSE]
    if (!nrow(d)) return(empty_values())
    # Months reported below 12 mean the Census Bureau imputed part (or all) of the year.
    status <- ifelse(d$months < 12, "imputed", "ok")
    data.frame(geo = d$key, name = "", variable = "units", estimate = d$units, moe = NA_real_, status = status,
               bound = NA_character_, note = ifelse(d$months < 12, paste0(d$months, " months reported"), ""),
               period = as.character(d$year), period_start = d$year, period_end = d$year,
               source_id = "census_bps", series = "Building permits (units authorized)", stringsAsFactors = FALSE)
  },
  periods = function(settings, recipe) seq(max(2000L, as.integer(settings$history_start %||% 2000)), 2025L),
  period_label = function(period) as.character(period),
  period_kind = "annual",
  availability_note = "Permits are published for permit-issuing places (FIPS codes from 2007) and counties; unincorporated remainders are not places."))
