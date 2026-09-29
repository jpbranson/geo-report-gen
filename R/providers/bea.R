# Bureau of Economic Analysis regional accounts from BEA's keyless bulk ZIPs: table CAINC1
# (county personal income, population and per capita personal income, 1969 onward) and the
# county GDP tables CAGDP1 and CAGDP2 (2001 onward).
#
# Caveats handled here: GeoFIPS values carry a leading space and quotes; "(NA)" marks
# unavailable values and "(D)" values withheld to avoid disclosing confidential information;
# BEA combines some Virginia independent cities with counties (51 9xx codes), so those
# counties are not published separately; Connecticut switches from counties (through 2023) to
# planning regions (2024 only) with no overlap. The U.S. total is the sum of states and DC.
# Census regions are summed from states (additive dollars and persons); BEA's own regions
# differ from Census regions and are not used.

# The ALL_AREAS table of one regional ZIP (e.g. "CAINC1"), with area keys.
bea_table <- function(table) {
  zip <- cached_download(paste0("https://apps.bea.gov/regional/zip/", table, ".zip"), cache_path("raw", "bea", paste0(table, ".zip")), "bea")
  inner <- grep("ALL_AREAS.*\\.csv$", utils::unzip(zip, list = TRUE)$Name, value = TRUE)[1]
  if (is.na(inner)) stop(table, ".zip has no ALL_AREAS file (BEA may have changed the layout).")
  con <- unz(zip, inner)
  d <- utils::read.csv(con, colClasses = "character", check.names = FALSE, encoding = "latin1")
  d <- d[!is.na(d$LineCode) & nzchar(d$LineCode), , drop = FALSE]
  fips <- gsub("[^0-9]", "", d$GeoFIPS)
  d$key <- ifelse(fips == "00000", "nation:US",
                  ifelse(substr(fips, 3, 5) == "000", paste0("state:", substr(fips, 1, 2)), paste0("county:", fips)))
  d$key[substr(fips, 1, 1) == "9"] <- NA  # BEA regions
  d
}

bea_cainc1 <- function() {
  memoize("bea_cainc1", function() cached(derived_path("bea", "cainc1_long", "bea.R"), source = "bea", compute = function() {
    d <- bea_table("CAINC1")
    d <- d[d$LineCode %in% c("1", "2", "3"), , drop = FALSE]
    key <- d$key
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

# County GDP, 2001 onward: CAGDP1 line 2 (chain-type quantity index of real GDP, 2017 = 100) and
# CAGDP2 (current-dollar GDP by industry, here the all-industry total and twelve industry groups
# that add up to it and are withheld less often than single sectors). Current dollars add up
# across areas, so regions and combined areas are sums; real GDP indexes do not, so real growth
# is shown only for areas BEA publishes. POPULATION comes from CAINC1.
bea_gdp_lines <- c(CAGDP1_2 = "REAL_GDP_INDEX", CAGDP2_1 = "GDP_ALL", CAGDP2_87 = "GDP_NATURAL", CAGDP2_11 = "GDP_CONSTRUCTION",
                   CAGDP2_12 = "GDP_MANUFACTURING", CAGDP2_88 = "GDP_TRADE", CAGDP2_89 = "GDP_TRANSPORT_UTILITIES",
                   CAGDP2_45 = "GDP_INFORMATION", CAGDP2_50 = "GDP_FIRE", CAGDP2_59 = "GDP_BUSINESS_SERVICES",
                   CAGDP2_68 = "GDP_EDUCATION_HEALTH", CAGDP2_75 = "GDP_LEISURE", CAGDP2_82 = "GDP_OTHER_SERVICES",
                   CAGDP2_83 = "GDP_GOVERNMENT")

bea_gdp_notes <- c(`(D)` = "withheld by BEA to avoid disclosing confidential information",
                   `(NA)` = "not available from BEA for this area and year", `(NM)` = "not meaningful (BEA)")

bea_cagdp <- function() {
  memoize("bea_cagdp", function() cached(derived_path("bea", "cagdp_long", "bea.R"), source = "bea", compute = function() {
    long <- do.call(rbind, lapply(c("CAGDP1", "CAGDP2"), function(table) {
      d <- bea_table(table)
      d <- d[paste0(table, "_", d$LineCode) %in% names(bea_gdp_lines) & !is.na(d$key), , drop = FALSE]
      var <- unname(bea_gdp_lines[paste0(table, "_", d$LineCode)])
      years <- grep("^[0-9]{4}$", names(d), value = TRUE)
      do.call(rbind, lapply(years, function(y) {
        flag <- trimws(d[[y]])
        scale <- ifelse(var == "REAL_GDP_INDEX", 1, 1000)   # dollar lines are in thousands
        data.frame(key = d$key, variable = var, year = as.integer(y), value = scale * suppressWarnings(as.numeric(flag)),
                   flag = ifelse(flag %in% names(bea_gdp_notes), flag, ""), stringsAsFactors = FALSE)
      }))
    }))
    # Census regions and divisions: sums of current-dollar GDP of their states (50 + DC); one
    # withheld state withholds the sum.
    st <- state_table()
    s <- long[startsWith(long$key, "state:") & long$variable != "REAL_GDP_INDEX", ]
    s$state <- sub("^state:", "", s$key)
    s <- merge(s, st[st$in_nation == "TRUE", c("state", "region", "division")], by = "state")
    agg <- function(level, codes) {
      g <- split(s, list(codes, s$variable, s$year), drop = TRUE)
      do.call(rbind, lapply(g, function(x) {
        flags <- setdiff(unique(x$flag), "")
        data.frame(key = paste0(level, ":", x[[level]][1]), variable = x$variable[1], year = x$year[1],
                   value = if (length(flags)) NA_real_ else sum(x$value), flag = if (length(flags)) flags[1] else "",
                   stringsAsFactors = FALSE)
      }))
    }
    rbind(long, agg("region", s$region), agg("division", s$division))
  }))
}

bea_gdp_fetch <- function(variables, pieces, periods, options = list()) {
  d <- bea_cagdp()
  d <- d[d$key %in% pieces$key & d$year %in% as.integer(periods) & d$variable %in% variables, , drop = FALSE]
  if ("POPULATION" %in% variables) {
    p <- bea_cainc1()
    p <- p[p$key %in% pieces$key & p$year %in% as.integer(periods) & p$variable == "population", , drop = FALSE]
    d <- rbind(d, data.frame(key = p$key, variable = rep("POPULATION", nrow(p)), year = p$year, value = p$value,
                             flag = rep("", nrow(p)), stringsAsFactors = FALSE))
  }
  # States' real GDP indexes cannot be combined into one for a region or division.
  groups <- pieces$key[pieces$type %in% c("region", "division")]
  if ("REAL_GDP_INDEX" %in% variables && length(groups)) {
    g <- expand.grid(key = groups, year = as.integer(periods), stringsAsFactors = FALSE)
    d <- rbind(d, data.frame(key = g$key, variable = "REAL_GDP_INDEX", year = g$year, value = NA_real_, flag = "sum", stringsAsFactors = FALSE))
  }
  if (!nrow(d)) return(empty_values())
  status <- ifelse(d$flag == "(D)", "suppressed", ifelse(d$flag == "sum", "not_aggregable",
                   ifelse(is.na(d$value), "unavailable", "ok")))
  note <- ifelse(d$flag == "sum", "BEA's real GDP indexes of states cannot be combined into one for a region",
                 ifelse(d$flag %in% names(bea_gdp_notes), bea_gdp_notes[d$flag], ""))
  data.frame(geo = d$key, name = "", variable = d$variable, estimate = d$value, moe = NA_real_, status = status,
             bound = NA_character_, note = unname(note), period = as.character(d$year), period_start = d$year,
             period_end = d$year, source_id = "bea_cagdp", series = "BEA GDP by county", stringsAsFactors = FALSE)
}

register_provider("bea_cagdp", list(
  name = "U.S. Bureau of Economic Analysis, GDP by county (tables CAGDP1 and CAGDP2)",
  geo_types = c("nation", "region", "division", "state", "county"),
  fetch = bea_gdp_fetch,
  periods = function(settings, recipe) seq(max(2001L, as.integer(settings$history_start %||% 2001)), 2024L),
  period_label = function(period) as.character(period),
  period_kind = "annual",
  availability_note = paste("BEA publishes GDP for counties, states and the nation (no cities); some Virginia independent cities",
                            "are combined with counties, and Connecticut appears as planning regions in 2024 and as its former",
                            "counties before.")))
