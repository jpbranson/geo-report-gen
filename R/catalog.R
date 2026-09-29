# Catalog: subjects, sources, metrics (documentation), recipes (how implemented metrics are
# computed), history coverage, and the block library. All are plain CSV tables in catalog/.
#
# A metric is *operational* only when it has a recipe AND its source has a registered
# provider. Documentation status, sample retrieval and adapter status are tracked
# separately (sources.csv records the first two with dates and evidence; adapter status is
# derived from the code so it cannot go stale).

catalog_table <- function(name) {
  memoize(paste0("catalog_", name), function() read_table(root_path("catalog", paste0(name, ".csv"))))
}

recipes <- function() catalog_table("recipes")
metrics_doc <- function() catalog_table("metrics")
sources_doc <- function() catalog_table("sources")
subjects <- function() catalog_table("subjects")

recipe_for <- function(metric_id) {
  r <- recipes()
  row <- r[r$metric_id == metric_id, , drop = FALSE]
  if (!nrow(row)) {
    doc <- metrics_doc()
    if (metric_id %in% doc$metric_id) {
      stop("Metric '", metric_id, "' is cataloged but not operational (no recipe/adapter). ",
           "See catalog/metrics.csv for its documentation status.", call. = FALSE)
    }
    stop("Unknown metric '", metric_id, "'.", call. = FALSE)
  }
  as.list(row[1, ])
}

metric_doc <- function(metric_id) {
  doc <- metrics_doc()
  row <- doc[doc$metric_id == metric_id, , drop = FALSE]
  if (!nrow(row)) stop("Metric '", metric_id, "' has a recipe but no documentation row in catalog/metrics.csv.")
  as.list(row[1, ])
}

# Operational status of every cataloged metric, derived from recipes + provider registry.
metric_status <- function() {
  doc <- metrics_doc()
  src <- sources_doc()
  has_recipe <- doc$metric_id %in% recipes()$metric_id
  has_adapter <- vapply(doc$source_id, function(s) exists(s, envir = provider_registry, inherits = FALSE), logical(1))
  doc_status <- src$doc_status[match(doc$source_id, src$source_id)]
  data.frame(metric_id = doc$metric_id, subject_id = doc$subject_id, source_id = doc$source_id,
             documentation = ifelse(is.na(doc_status), "unverified", doc_status),
             adapter = ifelse(has_adapter, "implemented", "none"),
             status = ifelse(has_recipe & has_adapter, "operational",
                             ifelse(doc_status %in% "verified", "documented", "candidate")),
             stringsAsFactors = FALSE)
}

# Structural checks run by tests and `gr.R catalog --check`.
validate_catalog <- function() {
  problems <- character()
  doc <- metrics_doc()
  rec <- recipes()
  src <- sources_doc()
  dup <- doc$metric_id[duplicated(doc$metric_id)]
  if (length(dup)) problems <- c(problems, paste("Duplicate metric ids:", paste(unique(dup), collapse = ", ")))
  orphan <- setdiff(rec$metric_id, doc$metric_id)
  if (length(orphan)) problems <- c(problems, paste("Recipes without documentation:", paste(orphan, collapse = ", ")))
  unknown_src <- setdiff(doc$source_id, src$source_id)
  if (length(unknown_src)) problems <- c(problems, paste("Metrics citing unknown sources:", paste(unknown_src, collapse = ", ")))
  bad_type <- rec$metric_id[!rec$stat_type %in% c("count", "share", "ratio", "median", "value")]
  if (length(bad_type)) problems <- c(problems, paste("Unknown stat_type in recipes:", paste(bad_type, collapse = ", ")))
  subj <- subjects()
  bad_subj <- setdiff(unique(doc$subject_id), subj$subject_id)
  if (length(bad_subj)) problems <- c(problems, paste("Unknown subject ids:", paste(bad_subj, collapse = ", ")))
  bad_sub <- setdiff(unique(paste(doc$subject_id, doc$subtopic_id)), paste(subj$subject_id, subj$subtopic_id))
  if (length(bad_sub)) problems <- c(problems, paste("Unknown subtopics:", paste(bad_sub, collapse = ", ")))
  problems
}

# Check that every ACS variable used by a recipe exists in each release the recipe uses (its
# periods from the metric's history_start on; live check, recorded as evidence in the
# verification log). Returns one row per recipe x release.
verify_acs_recipes <- function(settings) {
  rec <- recipes()
  rec <- rec[rec$source_id == "census_acs5", , drop = FALSE]
  out <- list()
  for (i in seq_len(nrow(rec))) {
    r <- as.list(rec[i, ])
    vars <- unique(c(recipe_vars(r$numerator), recipe_vars(r$denominator), if (!is_blank(r$published_var)) r$published_var))
    tables <- unique(sub("_.*$", "", vars))
    for (rel in metric_periods(r, settings)) {
      known <- unlist(lapply(tables, function(t) acs_variables(rel, t)$variable))
      missing <- setdiff(vars, known)
      bins_ok <- if (is_blank(r$bins_table)) NA else nrow(acs_bins(r$bins_table, rel)) > 0
      out[[length(out) + 1]] <- data.frame(metric_id = r$metric_id, release = rel,
                                           variables_found = length(vars) - length(missing),
                                           variables_missing = paste(missing, collapse = ";"),
                                           bins_parsed = bins_ok, stringsAsFactors = FALSE)
    }
  }
  do.call(rbind, out)
}

# Sources used by the engine itself rather than as metric providers (price indexes for
# constant dollars; boundaries and relationship files for geography; curated history).
support_adapters <- c("bls_r_cpi_u_rs", "bls_cpi_u", "census_geo", "history_events")

source_status <- function() {
  src <- sources_doc()
  is_provider <- vapply(src$source_id, function(s) exists(s, envir = provider_registry, inherits = FALSE), TRUE)
  src$adapter <- ifelse(is_provider, "provider", ifelse(src$source_id %in% support_adapters, "support", "none"))
  src
}

# gr.R catalog --check validates the tables; --html writes catalog/catalog.html.
catalog_command <- function(flags) {
  problems <- validate_catalog()
  st <- metric_status()
  cat(sprintf("Catalog: %d subtopics, %d sources, %d metrics (%d operational, %d documented, %d candidate).\n",
              nrow(subjects()), nrow(sources_doc()), nrow(st), sum(st$status == "operational"),
              sum(st$status == "documented"), sum(st$status == "candidate")))
  if (length(problems)) {
    cat("Problems:\n", paste0("  - ", problems, collapse = "\n"), "\n")
    if (isTRUE(flags$check)) quit(status = 1)
  } else cat("No structural problems found.\n")
  if (isTRUE(flags$html)) {
    res <- processx::run(quarto_bin(), c("render", root_path("catalog", "catalog.qmd")), env = quarto_env(),
                         error_on_status = FALSE, wd = root_path("catalog"))
    if (res$status != 0) stop("Rendering the catalog page failed:\n", res$stderr, call. = FALSE)
    note("Wrote ", root_path("catalog", "catalog.html"))
  }
  invisible(problems)
}

# ---- Live verification of operational sources ---------------------------------------------

# Small live retrievals (bypassing the cache) showing that each operational source still
# answers as its adapter expects. Results are appended to catalog/verification_log.csv with
# the date and evidence. Deterministic tests use fixtures and never touch the network.
verify_sources <- function() {
  run_reset()
  census_check <- function(path, query, label, column) {
    function() {
      d <- census_parse(http_perform(census_request(path, query)), label)
      paste0(label, ": ", format(as.numeric(d[[column]]), big.mark = ","))
    }
  }
  head_check <- function(url, source) {
    function() {
      resp <- http_perform(httr2::req_method(http_request(url, source), "HEAD"))
      check_status(resp, source)
      paste0("reachable (HTTP ", httr2::resp_status(resp), "): ", basename(url))
    }
  }
  checks <- list(
    census_acs5 = census_check("2024/acs/acs5", list(get = "NAME,B01003_001E", `for` = "us:1"), "2020-2024 ACS U.S. population", "B01003_001E"),
    census_dec = census_check("2020/dec/dhc", list(get = "NAME,P1_001N", `for` = "us:1"), "2020 Census U.S. population", "P1_001N"),
    census_cbp = census_check("2023/cbp", list(get = "ESTAB", `for` = "us:*", NAICS2017 = "624410"), "2023 U.S. child day care establishments", "ESTAB"),
    census_saipe = census_check("timeseries/poverty/saipe", list(get = "NAME,SAEPOVRTALL_PT", `for` = "us:*", time = "2024"),
                                "2024 SAIPE U.S. poverty rate", "SAEPOVRTALL_PT"),
    census_sahie = census_check("timeseries/healthins/sahie",
                                list(get = "NAME,PCTUI_PT", `for` = "us:*", time = "2024", AGECAT = "0", IPRCAT = "0",
                                     SEXCAT = "0", RACECAT = "0"), "2024 SAHIE U.S. uninsured rate under 65", "PCTUI_PT"),
    tx_hhsc = function() {
      resp <- http_perform(http_request("https://data.texas.gov/resource/bc5r-88dy.json", "tx_hhsc", query = list(`$select` = "count(*) as n")))
      check_status(resp, "Texas HHSC")
      paste0("Texas HHSC operations records: ", jsonlite::fromJSON(httr2::resp_body_string(resp))$n)
    },
    census_pep = head_check(paste0(pep_base, pep_files$file[1]), "census_pep"),
    census_hist = head_check("https://data.nber.org/census/population/cencounts/cencounts.csv", "census_hist"),
    bea_cainc = head_check("https://apps.bea.gov/regional/zip/CAINC1.zip", "bea"),
    fhfa_hpi = head_check("https://www.fhfa.gov/hpi/download/annual/hpi_at_county.xlsx", "fhfa"),
    census_bps = head_check("https://www2.census.gov/econ/bps/County/co2025a.txt", "census_bps"),
    dol_ndcp = head_check("https://www.dol.gov/sites/dolgov/files/WB/NDCP2022.xlsx", "dol_ndcp"),
    census_geo = head_check("https://www2.census.gov/geo/tiger/GENZ2024/shp/cb_2024_us_county_500k.zip", "census_geo"),
    bls_laus = head_check("https://download.bls.gov/pub/time.series/la/la.area", "bls"),
    bls_r_cpi_u_rs = head_check("https://www.bls.gov/cpi/research-series/r-cpi-u-rs-allitems.xlsx", "bls"))
  rows <- lapply(names(checks), function(id) {
    ev <- tryCatch(list(result = "ok", evidence = checks[[id]]()),
                   error = function(e) list(result = "failed", evidence = substr(conditionMessage(e), 1, 200)))
    note(sprintf("%-16s %-6s %s", id, ev$result, ev$evidence))
    data.frame(date = format(Sys.time(), "%Y-%m-%d %H:%M"), source_id = id, result = ev$result,
               evidence = ev$evidence, stringsAsFactors = FALSE)
  })
  # Every ACS variable a recipe uses exists in each release the recipe uses (from the variable
  # lists the API publishes per release); any gap is a recipe to fix.
  acs <- verify_acs_recipes(resolve_settings())
  gaps <- acs[nzchar(acs$variables_missing), , drop = FALSE]
  rows[[length(rows) + 1]] <- data.frame(
    date = format(Sys.time(), "%Y-%m-%d %H:%M"), source_id = "census_acs5_recipes", result = "checked",
    evidence = paste0(nrow(acs), " recipe x release checks; releases lacking a recipe's variables: ",
                      if (nrow(gaps)) paste(unique(paste(gaps$metric_id, gaps$release)), collapse = ", ") else "none"),
    stringsAsFactors = FALSE)
  log <- do.call(rbind, rows)
  path <- root_path("catalog", "verification_log.csv")
  if (file.exists(path)) log <- rbind(read_table(path), log)
  write_table(log, path)
  invisible(log)
}
