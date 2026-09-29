# Census Bureau Nonemployer Statistics (NES), 1997-2023: businesses without paid employees
# (mostly self-employed people filing as sole proprietors, with receipts of at least $1,000 in
# most industries) and their receipts, by NAICS industry, for counties, states and the nation,
# from the keyless yearly bulk files. The sources of jobs (CBP, QCEW, LODES) leave them out.
#
# Variables are named <measure>_<NAICS>: ESTAB_00 (all nonemployer businesses), RCPTOT_48-49
# (receipts in transportation and warehousing, in dollars), ESTAB_62441 (child day care, mostly
# home-based providers). POPULATION gives rates per resident: BEA's population (table CAINC1, one
# series back to 1969), or the Census Bureau's estimates (Vintage 2025) where BEA has none, as for
# Connecticut's planning regions before 2024.
#
# The files list every industry with nonemployers in an area. Cells withheld to avoid disclosing
# a business (D, in older years) or below publication standards (S) are flagged with blank
# values and are "suppressed"; a missing row means no such businesses (in 2008 the sectors of
# every county without a flagged cell add up exactly to its total). State and U.S. files split
# rows by legal form and (U.S.) receipts size; only the all-forms, all-sizes rows are used.
# Census regions and divisions are sums of their states.

nes_base <- "https://www2.census.gov/programs-surveys/nonemployer-statistics/datasets/"
nes_years <- 1997:2023
nes_codes <- c("00", "11", "21", "22", "23", "31-33", "42", "44-45", "48-49", "51", "52", "53", "54", "56", "61", "62",
               "71", "72", "81", "62441")

# File names changed over the years: state files are text until 2007, U.S. files until 2015.
nes_file <- function(year, level) {
  ext <- switch(level, co = "zip", st = if (year <= 2007) "txt" else "zip", us = if (year <= 2015) "txt" else "zip")
  sprintf("nonemp%02d%s.%s", year %% 100, level, ext)
}

nes_level <- function(year, level) {
  file <- nes_file(year, level)
  path <- cached_download(paste0(nes_base, year, "/historical-datasets/", file), cache_path("raw", "census_nes", file), "census_nes")
  d <- readr::read_csv(path, col_types = readr::cols(.default = readr::col_character()), na = character(), progress = FALSE)
  names(d) <- toupper(names(d))
  names(d)[names(d) == "ESTABF"] <- "ESTAB_F"      # 1997-2003 state and U.S. files
  names(d)[names(d) == "COUNTY"] <- "CTY"          # 1997 county file
  names(d)[names(d) == "ECVALUE"] <- "RCPTOT"      # 2002 U.S. file
  missing <- setdiff(c("ST", "NAICS", "ESTAB_F", "ESTAB", "RCPTOT", if (level == "co") "CTY"), names(d))
  if (length(missing)) stop(file, " lacks column(s) ", paste(missing, collapse = ", "), " (the layout changed).", call. = FALSE)
  if ("LFO" %in% names(d)) d <- d[d$LFO == "-", , drop = FALSE]
  if ("RCPTOT_SIZE" %in% names(d)) d <- d[d$RCPTOT_SIZE == "001", , drop = FALSE]
  d <- d[d$NAICS %in% nes_codes, , drop = FALSE]
  key <- switch(level, co = paste0("county:", d$ST, d$CTY), st = paste0("state:", d$ST), us = rep("nation:US", nrow(d)))
  out <- data.frame(key = key, naics = d$NAICS, flag = d$ESTAB_F, ESTAB = suppressWarnings(as.numeric(d$ESTAB)),
                    RCPTOT = 1000 * suppressWarnings(as.numeric(d$RCPTOT)), stringsAsFactors = FALSE)
  out[!duplicated(out[, c("key", "naics")]), , drop = FALSE]   # the files repeat some rows verbatim
}

# One year's counties, states and nation, plus Census regions and divisions summed from states.
nes_year <- function(year) {
  memoize(paste0("nes_", year), function() cached(derived_path("census_nes", paste0("nes_", year), "nes.R"), source = "census_nes", compute = function() {
    d <- do.call(rbind, lapply(c("co", "st", "us"), function(level) nes_level(year, level)))
    st <- state_table()
    st <- st[st$in_nation == "TRUE", , drop = FALSE]
    s <- d[d$key %in% paste0("state:", st$state), , drop = FALSE]
    s$state <- sub("^state:", "", s$key)
    s <- merge(s, st[, c("state", "region", "division")], by = "state")
    groups <- lapply(c("region", "division"), function(level) {
      g <- split(s, list(s[[level]], s$naics), drop = TRUE)
      do.call(rbind, lapply(g, function(x) {
        withheld <- any(nzchar(x$flag))   # a state without a row has no such businesses
        data.frame(key = paste0(level, ":", x[[level]][1]), naics = x$naics[1], flag = if (withheld) "S" else "",
                   ESTAB = if (withheld) NA_real_ else sum(x$ESTAB), RCPTOT = if (withheld) NA_real_ else sum(x$RCPTOT),
                   stringsAsFactors = FALSE)
      }))
    })
    rbind(d, do.call(rbind, groups))
  }))
}

nes_note <- function(flag) {
  ifelse(flag == "D", "withheld by the Census Bureau to avoid disclosing data of individual businesses",
         ifelse(flag == "S", "withheld by the Census Bureau: does not meet publication standards", "not published by the Census Bureau"))
}

nes_fetch <- function(variables, pieces, periods, options = list()) {
  pop <- if ("POPULATION" %in% variables) bea_cainc1() else NULL
  vars <- setdiff(variables, "POPULATION")
  out <- list()
  for (yr in as.integer(periods)) {
    d <- nes_year(yr)
    present <- unique(d$key)
    for (v in vars) {
      measure <- sub("_.*$", "", v)
      code <- sub("^[^_]*_", "", v)
      rows <- d[d$naics == code, , drop = FALSE]
      i <- match(pieces$key, rows$key)
      flag <- ifelse(is.na(i), "", rows$flag[i])
      est <- ifelse(is.na(i), 0, rows[[measure]][i])   # no row: no such businesses
      status <- ifelse(!pieces$key %in% present, "unavailable", ifelse(nzchar(flag), "suppressed", "ok"))
      est[status != "ok"] <- NA
      note <- ifelse(status == "unavailable", paste0("not in the Nonemployer Statistics files for ", yr, " (county boundaries changed)"),
                     ifelse(status == "suppressed", nes_note(flag), ""))
      out[[length(out) + 1]] <- data.frame(geo = pieces$key, variable = v, estimate = est, status = status, note = note,
                                           period = yr, stringsAsFactors = FALSE)
    }
    if (!is.null(pop)) {
      p <- pop[pop$variable == "population" & pop$year == yr, , drop = FALSE]
      est <- p$value[match(pieces$key, p$key)]
      if (anyNA(est)) {
        pep <- tryCatch(pep_long(), error = function(e) NULL)
        if (!is.null(pep)) {
          pep <- pep[pep$year == yr, , drop = FALSE]
          est[is.na(est)] <- pep$population[match(pieces$key[is.na(est)], pep$key)]
        }
      }
      out[[length(out) + 1]] <- data.frame(geo = pieces$key, variable = "POPULATION", estimate = est,
                                           status = ifelse(is.na(est), "unavailable", "ok"), note = "", period = yr,
                                           stringsAsFactors = FALSE)
    }
  }
  if (!length(out)) return(empty_values())
  d <- do.call(rbind, out)
  data.frame(geo = d$geo, name = "", variable = d$variable, estimate = d$estimate, moe = NA_real_, status = d$status,
             bound = NA_character_, note = d$note, period = as.character(d$period), period_start = d$period,
             period_end = d$period, source_id = "census_nes", stringsAsFactors = FALSE)
}

register_provider("census_nes", list(
  name = "U.S. Census Bureau, Nonemployer Statistics",
  geo_types = c("nation", "region", "division", "state", "county"),
  fetch = nes_fetch,
  periods = function(settings, recipe) seq(max(min(nes_years), as.integer(settings$history_start %||% min(nes_years))), max(nes_years)),
  period_label = function(period) as.character(period),
  period_kind = "annual",
  series = "Nonemployer Statistics",
  availability_note = paste("Nonemployer Statistics cover counties, states and the nation (no cities); businesses are located by",
                            "the owner's mailing address.")))
