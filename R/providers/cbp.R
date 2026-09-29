# County Business Patterns (Census Data API, key): establishments with paid employees,
# mid-March employment and annual payroll by NAICS industry for counties, states and the
# nation, 1998 onward. Variables are named <measure>_<NAICS code>: ESTAB_00 (establishments,
# all industries), EMP_31-33 (employment in manufacturing), PAYANN_624410 (annual payroll of
# child day care services, in $1,000).
#
# Small cells: before 2017, employment and payroll that would disclose a business were
# withheld (published as 0 with a flag); from 2017 they are published with noise, and cells
# with fewer than 3 establishments are not published at all. So a missing row means no
# establishments before 2017, and "fewer than 3 establishments or none" from 2017.

# Flags of withheld values: D (would disclose a business), S (below publication standards) and,
# before 2018, the employment-size range (a-m) shown in place of withheld employment. Other flags
# mark published values (r = revised; G, H, J = noise).
cbp_withheld <- c("D", "S", letters[1:13])

# The industry variable name changes with each NAICS revision.
cbp_naics_var <- function(year) {
  if (year <= 2002) "NAICS1997" else if (year <= 2007) "NAICS2002" else if (year <= 2011) "NAICS2007" else if (year <= 2016) "NAICS2012" else "NAICS2017"
}

# One industry for all counties, all states or the nation in one year. Only totals over all
# establishment sizes (EMPSZES 001) and, from 2008, all legal forms of organization (LFO 001).
cbp_raw <- function(year, scope, code) {
  cached(cache_path("raw", "census_cbp", year, paste0(code, "-", scope, ".parquet")), source = "census_cbp", compute = function() {
    q <- list(get = "ESTAB,EMP,EMP_F,PAYANN,PAYANN_F", `for` = switch(scope, county = "county:*", state = "state:*", nation = "us:*"),
              EMPSZES = "001")
    if (year >= 2008) q$LFO <- "001"
    q[[cbp_naics_var(year)]] <- code
    df <- census_parse(http_perform(census_request(paste0(year, "/cbp"), q)), paste("CBP", year, code, scope))
    if (!ncol(df)) data.frame(ESTAB = character(), EMP = character(), EMP_F = character(), PAYANN = character(),
                              PAYANN_F = character(), state = character(), county = character()) else df
  })
}

cbp_fetch <- function(variables, pieces, periods, options = list()) {
  wanted <- data.frame(variable = variables, measure = sub("_.*$", "", variables), code = sub("^[^_]*_", "", variables),
                       stringsAsFactors = FALSE)
  out <- list()
  for (yr in as.integer(periods)) {
    for (code in unique(wanted$code)) {
      for (scope in unique(pieces$type)) {
        df <- cbp_raw(yr, scope, code)
        want <- pieces$key[pieces$type == scope]
        row <- match(want, if (nrow(df)) census_keys(df, scope) else character())
        for (measure in wanted$measure[wanted$code == code]) {
          est <- suppressWarnings(as.numeric(df[[measure]]))[row]
          withheld <- if (measure == "ESTAB") FALSE else df[[paste0(measure, "_F")]][row] %in% cbp_withheld
          status <- ifelse(withheld, "suppressed", ifelse(is.na(row) & yr >= 2017, "suppressed", "ok"))
          est[is.na(row) & yr < 2017] <- 0
          est[status == "suppressed"] <- NA
          note <- ifelse(withheld, "withheld by the Census Bureau to avoid disclosing data of individual businesses",
                         ifelse(status == "suppressed", "fewer than 3 establishments or none (not published from 2017)", ""))
          out[[length(out) + 1]] <- data.frame(geo = want, name = "", variable = paste0(measure, "_", code), estimate = est,
                                               moe = NA_real_, status = status, bound = NA_character_, note = note,
                                               period = as.character(yr), period_start = yr, period_end = yr,
                                               source_id = "census_cbp", stringsAsFactors = FALSE)
        }
      }
    }
  }
  if (!length(out)) return(empty_values())
  do.call(rbind, out)
}

register_provider("census_cbp", list(
  name = "U.S. Census Bureau, County Business Patterns (Census Data API)",
  geo_types = c("nation", "state", "county"),
  fetch = cbp_fetch,
  periods = function(settings, recipe) seq(max(1998L, as.integer(settings$history_start %||% 1998)), 2023L),
  period_label = function(period) as.character(period),
  period_kind = "annual",
  series = "County Business Patterns (NAICS)",
  availability_note = "CBP publishes counties, states and the nation (no places); it counts establishments with paid employees where they are located."))
