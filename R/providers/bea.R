# Bureau of Economic Analysis regional accounts, table CAINC1 (county personal income,
# population and per capita personal income, 1969 onward), from BEA's keyless bulk ZIP.
#
# Caveats handled here: GeoFIPS values carry a leading space and quotes; "(NA)" marks
# unavailable values; BEA combines some Virginia independent cities with counties (51 9xx
# codes), so those counties are not published separately; Connecticut switches from
# counties (through 2023) to planning regions (2024 only) with no overlap. The U.S. total is
# the sum of states and DC. Census regions are summed from states (additive dollars and
# persons); BEA's own regions differ from Census regions and are not used.

bea_cainc1 <- function() {
  memoize("bea_cainc1", function() cached(derived_path("bea", "cainc1_long", "bea.R"), source = "bea", compute = function() {
    zip <- cached_download("https://apps.bea.gov/regional/zip/CAINC1.zip", cache_path("raw", "bea", "CAINC1.zip"), "bea")
    inner <- grep("ALL_AREAS.*\\.csv$", utils::unzip(zip, list = TRUE)$Name, value = TRUE)[1]
    if (is.na(inner)) stop("CAINC1.zip has no ALL_AREAS file (BEA may have changed the layout).")
    con <- unz(zip, inner)
    d <- utils::read.csv(con, colClasses = "character", check.names = FALSE, encoding = "latin1")
    d <- d[!is.na(d$LineCode) & d$LineCode %in% c("1", "2", "3"), , drop = FALSE]
    fips <- gsub("[^0-9]", "", d$GeoFIPS)
    key <- ifelse(fips == "00000", "nation:US",
                  ifelse(substr(fips, 3, 5) == "000", paste0("state:", substr(fips, 1, 2)), paste0("county:", fips)))
    key[substr(fips, 1, 1) == "9"] <- NA  # BEA regions
    var <- c(`1` = "personal_income", `2` = "population", `3` = "per_capita_personal_income")[d$LineCode]
    years <- grep("^[0-9]{4}$", names(d), value = TRUE)
    long <- do.call(rbind, lapply(years, function(y) {
      v <- suppressWarnings(as.numeric(d[[y]]))
      data.frame(key = key, variable = var, year = as.integer(y), value = v, stringsAsFactors = FALSE)
    }))
    long <- long[!is.na(long$key), ]
    long$value[long$variable == "personal_income"] <- 1000 * long$value[long$variable == "personal_income"]
    # Census regions and divisions: sum income and population of states (50 + DC).
    st <- state_table()
    s <- long[startsWith(long$key, "state:") & long$variable %in% c("personal_income", "population"), ]
    s$state <- sub("^state:", "", s$key)
    s <- merge(s, st[st$in_nation == "TRUE", c("state", "region", "division")], by = "state")
    agg <- function(level, codes) {
      a <- stats::aggregate(s$value, by = list(code = codes, variable = s$variable, year = s$year), FUN = sum)
      data.frame(key = paste0(level, ":", a$code), variable = a$variable, year = a$year, value = a$x, stringsAsFactors = FALSE)
    }
    rbind(long, agg("region", s$region), agg("division", s$division))
  }))
}

bea_fetch <- function(variables, pieces, periods, options = list()) {
  d <- bea_cainc1()
  d <- d[d$key %in% pieces$key & d$year %in% as.integer(periods) & d$variable %in% variables, , drop = FALSE]
  if (!nrow(d)) return(empty_values())
  data.frame(geo = d$key, name = "", variable = d$variable, estimate = d$value, moe = NA_real_,
             status = ifelse(is.na(d$value), "unavailable", "ok"), bound = NA_character_, note = "",
             period = as.character(d$year), period_start = d$year, period_end = d$year,
             source_id = "bea_cainc", series = "BEA regional accounts", stringsAsFactors = FALSE)
}

register_provider("bea_cainc", list(
  name = "U.S. Bureau of Economic Analysis, Regional Economic Accounts, table CAINC1",
  geo_types = c("nation", "region", "division", "state", "county"),
  fetch = bea_fetch,
  periods = function(settings, recipe) seq(max(1969L, as.integer(settings$history_start %||% 1969)), 2024L),
  period_label = function(period) as.character(period),
  period_kind = "annual",
  availability_note = "BEA publishes counties, states and the nation (no places); some Virginia independent cities are combined with counties."))
