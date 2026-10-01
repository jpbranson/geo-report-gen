# BLS Quarterly Census of Employment and Wages (QCEW), annual averages 2001-2025, from the
# keyless annual "singlefile" CSVs (one ZIP a year with every area, ownership and industry):
# establishments, employment and total wages of employers covered by state unemployment
# insurance and the federal UCFE program, where the jobs are located. Each year is reduced once
# to the rows reports use: all industries by ownership, private NAICS sectors, and private child
# day care (624410), for counties, states and the nation.
#
# Years start in 2001, the first year BLS coded under NAICS. BLS also publishes 1990-2000 as a
# NAICS reconstruction of SIC-coded records; those files leave withheld cells out and hold
# one-year spikes that no other source shows (Oakland County, Michigan, 1997: 179,334 finance
# jobs paying $57.3 billion, against 38,941 and $1.6 billion in 1996, which also inflates
# Michigan and the nation; New Jersey 1995: average pay 42% above 1994 and 1996), so they are
# not used. County Business Patterns covers earlier jobs and payroll.
#
# Variables are named <measure>_<ownership>_<industry>: EMP_0_10 (annual average employment,
# all ownerships and industries), WAGES_5_62 (total annual wages, private health care and social
# assistance), ESTAB_5_624410 (private child day care establishments). Ownership codes: 0 all,
# 1 federal, 2 state and 3 local government, 5 private.
#
# Nondisclosure: cells withheld to protect employers are flagged "N" (employment and wages shown
# as 0, establishments still counted). A row missing for an area that is in the file means no
# such employers or a withheld cell; it is shown as not published, never as zero. The U.S. row is the 50 states and DC; Census regions and divisions are sums of
# their states. Connecticut appears as its planning regions from 2024 and as its former counties
# before, so each series covers only its own years.

qcew_years <- 2001:2025
qcew_withheld <- "withheld by BLS to avoid disclosing data of individual employers, or no such employers in the area"

# One year's rows that reports use, with area keys (unknown-county rows are left out).
qcew_year <- function(year) {
  memoize(paste0("qcew_", year), function() cached(derived_path("bls_qcew", paste0(year, "_annual"), "qcew.R"), source = "bls_qcew", compute = function() {
    file <- paste0(year, "_annual_singlefile.zip")
    zip <- bls_download(paste0("https://data.bls.gov/cew/data/files/", year, "/csv/", file), file,
                        path = cache_path("raw", "bls_qcew", file), source = "bls_qcew")
    chr <- readr::col_character()
    num <- readr::col_double()
    d <- readr::read_csv(zip, progress = FALSE, col_types = readr::cols_only(
      area_fips = chr, own_code = chr, industry_code = chr, agglvl_code = chr, size_code = chr, disclosure_code = chr,
      annual_avg_estabs = num, annual_avg_emplvl = num, total_annual_wages = num))
    lvl <- d$agglvl_code
    keep <- d$size_code == "0" & (
      (lvl %in% c("10", "11", "50", "51", "70", "71") & d$industry_code == "10") |
      (lvl %in% c("14", "54", "74") & d$own_code == "5") |
      (lvl %in% c("18", "58", "78") & d$own_code == "5" & d$industry_code == "624410"))
    d <- d[keep & !endsWith(d$area_fips, "999"), , drop = FALSE]
    area <- d$area_fips
    key <- ifelse(area == "US000", "nation:US",
                  ifelse(substr(area, 3, 5) == "000", paste0("state:", substr(area, 1, 2)), paste0("county:", area)))
    data.frame(key = key, own = d$own_code, industry = d$industry_code, withheld = d$disclosure_code %in% "N",
               ESTAB = d$annual_avg_estabs, EMP = d$annual_avg_emplvl, WAGES = d$total_annual_wages,
               stringsAsFactors = FALSE)
  }))
}

# Values of one variable for published areas: ok, withheld ("suppressed") or absent (NA row).
qcew_lookup <- function(d, measure, own, industry, keys) {
  rows <- d[d$own == own & d$industry == industry, , drop = FALSE]
  i <- match(keys, rows$key)
  withheld <- !is.na(i) & rows$withheld[i] & measure != "ESTAB"   # establishments are always counted
  est <- rows[[measure]][i]
  est[withheld] <- NA
  data.frame(key = keys, estimate = est, status = ifelse(is.na(i) | withheld, "suppressed", "ok"), stringsAsFactors = FALSE)
}

qcew_fetch <- function(variables, pieces, periods, options = list()) {
  parts <- do.call(rbind, strsplit(variables, "_", fixed = TRUE))
  groups <- pieces$type %in% c("region", "division")
  out <- list()
  for (yr in as.integer(periods)) {
    d <- qcew_year(yr)
    present <- unique(d$key)
    for (v in seq_along(variables)) {
      measure <- parts[v, 1]
      own <- parts[v, 2]
      industry <- parts[v, 3]
      x <- qcew_lookup(d, measure, own, industry, pieces$key)
      # A region or division is the sum of its states; one withheld state withholds the sum.
      for (i in which(groups)) {
        members <- paste0("state:", member_states(pieces$type[i], pieces$geoid[i]))
        s <- qcew_lookup(d, measure, own, industry, members)
        ok <- all(s$status == "ok")
        x$estimate[i] <- if (ok) sum(s$estimate) else NA_real_
        x$status[i] <- if (ok) "ok" else "suppressed"
      }
      absent <- !groups & !(pieces$key %in% present)
      x$status[absent] <- "unavailable"
      note <- ifelse(x$status == "suppressed", qcew_withheld,
                     ifelse(absent, paste0("not in the QCEW files for ", yr, " (county boundaries changed)"), ""))
      out[[length(out) + 1]] <- data.frame(
        geo = pieces$key, name = "", variable = variables[v], estimate = x$estimate, moe = NA_real_, status = x$status,
        bound = NA_character_, note = note, period = as.character(yr), period_start = yr, period_end = yr,
        source_id = "bls_qcew", stringsAsFactors = FALSE)
    }
  }
  if (!length(out)) return(empty_values())
  do.call(rbind, out)
}

register_provider("bls_qcew", list(
  name = "U.S. Bureau of Labor Statistics, Quarterly Census of Employment and Wages",
  geo_types = c("nation", "region", "division", "state", "county"),
  fetch = qcew_fetch,
  periods = function(settings, recipe) seq(max(min(qcew_years), as.integer(settings$history_start %||% min(qcew_years))), max(qcew_years)),
  period_label = function(period) as.character(period),
  period_kind = "annual",
  series = "QCEW (NAICS)",
  availability_note = paste("QCEW publishes counties, states and the nation (no cities); Connecticut appears as planning regions",
                            "from 2024 and as its former counties before. Values that would reveal an employer's data are withheld.")))
