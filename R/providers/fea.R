# USDA Economic Research Service, Food Environment Atlas (July 2025 release): county indicators
# of access to food stores and of the food environment, each for the latest year the Atlas has
# (low access to stores 2019, stores and restaurants 2020, SNAP-authorized stores 2023).
#  - Values are the Atlas's published county values. It publishes no state or national values
#    for these measures, nor the populations behind its rates, so combined areas are not computed.
#  - Store and restaurant counts come from County Business Patterns, which does not publish
#    fewer than 3 establishments; the Atlas marks those (and other unavailable values) -9999.
#  - The Atlas still uses Connecticut's former counties, so planning regions have no values.

fea_url <- "https://www.ers.usda.gov/media/5570/food-environment-atlas-csv-files.zip"

# Atlas variable codes end with the two-digit year of the data (GROCPTH20 is 2020).
fea_year <- function(code) 2000L + as.integer(sub("^.*([0-9]{2})$", "\\1", code))

# Every county value of every Atlas variable, in long form (key, variable, value).
fea_values <- function() {
  memoize("fea_values", function() cached(derived_path("usda_ers_fea", "fea_values", "fea.R"), source = "usda_ers_fea", compute = function() {
    zip <- cached_download(fea_url, cache_path("raw", "usda_ers_fea", "food-environment-atlas-2025.zip"), "usda_ers_fea")
    x <- utils::read.csv(unz(zip, "StateAndCountyData.csv"), colClasses = "character", check.names = FALSE, encoding = "UTF-8")
    names(x)[1] <- "FIPS"  # the file starts with a byte-order mark
    x <- x[nchar(x$FIPS) == 5, , drop = FALSE]
    data.frame(key = paste0("county:", x$FIPS), variable = x$Variable_Code, value = suppressWarnings(as.numeric(x$Value)),
               stringsAsFactors = FALSE)
  }))
}

fea_fetch <- function(variables, pieces, periods, options = list()) {
  d <- fea_values()
  d <- d[d$variable %in% variables, , drop = FALSE]
  out <- expand.grid(geo = pieces$key, variable = variables, stringsAsFactors = FALSE)
  v <- d$value[match(paste(out$geo, out$variable), paste(d$key, d$variable))]
  out$status <- ifelse(is.na(v) | v == -8888, "unavailable", ifelse(v == -9999, "suppressed", "ok"))
  out$estimate <- ifelse(out$status == "ok", v, NA_real_)
  out$note <- c(ok = "", suppressed = "not available or suppressed in the Food Environment Atlas (store counts under 3 are not published)",
                unavailable = "no Food Environment Atlas value for this county (the Atlas uses older boundaries, such as Connecticut's former counties)")[out$status]
  year <- fea_year(out$variable)
  data.frame(out, name = "", moe = NA_real_, bound = NA_character_, period = as.character(year), period_start = year,
             period_end = year, source_id = "usda_ers_fea", stringsAsFactors = FALSE)
}

register_provider("usda_ers_fea", list(
  name = "USDA Economic Research Service, Food Environment Atlas (July 2025)",
  geo_types = "county",
  fetch = fea_fetch,
  periods = function(settings, recipe) fea_year(recipe_vars(recipe$numerator)[1]),
  period_label = function(period) as.character(period),
  period_kind = "annual",
  availability_note = "The Food Environment Atlas publishes these measures for counties only (Connecticut's former counties, not its planning regions)."))
