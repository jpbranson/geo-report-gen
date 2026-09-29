# Core helpers shared by the CLI, the build, and rendered reports:
# project paths, run state (warnings, counters, timings), hashing, and CSV I/O.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

# ---- Paths -------------------------------------------------------------------

# The project root is the directory that contains gr.R. Rendered reports run in
# reports/<id>/, so the build passes GR_ROOT explicitly; otherwise search upward.
gr_root <- function() {
  root <- Sys.getenv("GR_ROOT")
  if (nzchar(root)) return(normalizePath(root, winslash = "/", mustWork = TRUE))
  dir <- normalizePath(getwd(), winslash = "/")
  repeat {
    if (file.exists(file.path(dir, "gr.R"))) return(dir)
    parent <- dirname(dir)
    if (parent == dir) stop("Cannot find the project root (the folder containing gr.R). Set GR_ROOT.")
    dir <- parent
  }
}

root_path <- function(...) file.path(gr_root(), ...)

# The shared cache can live outside the project (e.g. on a team drive) via GR_CACHE.
cache_root <- function() {
  dir <- Sys.getenv("GR_CACHE")
  if (nzchar(dir)) dir else root_path("cache")
}

cache_path <- function(...) file.path(cache_root(), ...)

# ---- Run state ----------------------------------------------------------------

# One environment holds what a build needs to report afterwards: warnings, HTTP
# request counts, cache hits/misses and stage timings. Reset at the start of a build.
run <- new.env(parent = emptyenv())

run_reset <- function(offline = FALSE, refresh = character()) {
  run$offline <- offline
  run$refresh <- refresh           # source ids the user asked to re-download
  run$refreshed <- character()     # cache files already re-downloaded in this run
  run$requests <- list()           # one entry per HTTP request (never includes secrets)
  run$used <- character()          # raw cache files (downloads, API responses) this run read
  run$cache <- c(hit = 0L, miss = 0L)
  run$warnings <- character()
  run$timings <- list()
  invisible(run)
}
run_reset()

# Session-level memo for reference tables that never change during a run.
memo <- new.env(parent = emptyenv())

memoize <- function(key, compute) {
  if (!exists(key, envir = memo, inherits = FALSE)) assign(key, compute(), envir = memo)
  get(key, envir = memo, inherits = FALSE)
}

note <- function(...) {
  message(format(Sys.time(), "%H:%M:%S"), "  ", paste0(...))
}

# Warnings are collected so they appear in the build manifest as well as the console.
warn <- function(...) {
  msg <- paste0(...)
  run$warnings <- unique(c(run$warnings, msg))
  message("WARNING: ", msg)
  invisible(msg)
}

timed <- function(stage, expr) {
  t0 <- Sys.time()
  on.exit(run$timings[[stage]] <- (run$timings[[stage]] %||% 0) +
            as.numeric(difftime(Sys.time(), t0, units = "secs")))
  expr
}

# ---- Hashing ------------------------------------------------------------------

# Hashes are computed on canonical JSON text (not R serialization) so cache keys are
# stable across R versions and readable when debugging.
hash_value <- function(...) {
  json <- jsonlite::toJSON(list(...), auto_unbox = TRUE, digits = NA, null = "null", na = "null")
  digest::digest(as.character(json), algo = "md5", serialize = FALSE)
}

hash_text <- function(text) digest::digest(enc2utf8(as.character(text)), algo = "md5", serialize = FALSE)

hash_files <- function(paths) {
  paths <- sort(paths[file.exists(paths)])
  hash_value(vapply(paths, function(p) digest::digest(file = p, algo = "md5"), ""))
}

# The "transformation version" of a set of code files: any edit to them changes it,
# which invalidates results computed by that code (but not raw downloads).
code_version <- function(files) hash_files(root_path(files))

# ---- Tables (CSV) -------------------------------------------------------------

# Configuration and content tables are read as character columns only: no type
# guessing (GEOIDs keep leading zeros), empty cells stay "", multiline cells survive.
# Line breaks inside cells become "\n" whatever program saved the file, so a spreadsheet
# round trip does not look like an edit.
read_table <- function(path) {
  if (!file.exists(path)) stop("Missing table: ", path)
  df <- readr::read_csv(path, col_types = readr::cols(.default = readr::col_character()),
                        na = character(), trim_ws = FALSE, progress = FALSE,
                        show_col_types = FALSE, locale = readr::locale(encoding = "UTF-8"))
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  df[] <- lapply(df, function(x) gsub("\r\n", "\n", x, fixed = TRUE))
  df
}

# Written as UTF-8 with a byte-order mark so Excel opens Unicode text correctly;
# fields with commas, quotes or line breaks are quoted.
write_table <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp-", Sys.getpid())
  readr::write_excel_csv(df, tmp, na = "", quote = "needed")
  replace_file(tmp, path)
}

# Atomic replacement: write elsewhere, then rename over the target.
replace_file <- function(tmp, path) {
  if (file.exists(path)) unlink(path)
  if (!file.rename(tmp, path)) {
    ok <- file.copy(tmp, path, overwrite = TRUE)
    unlink(tmp)
    if (!ok) stop("Could not write ", path)
  }
  invisible(path)
}

write_text_file <- function(text, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp-", Sys.getpid())
  con <- file(tmp, open = "wb")
  writeBin(charToRaw(enc2utf8(paste0(paste(text, collapse = "\n"), "\n"))), con)
  close(con)
  replace_file(tmp, path)
}

read_text_file <- function(path) {
  paste(readLines(path, encoding = "UTF-8", warn = FALSE), collapse = "\n")
}

write_json_file <- function(x, path) {
  write_text_file(jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, digits = NA,
                                   null = "null", na = "null"), path)
}

# ---- Provider registry ------------------------------------------------------------

# Data providers register themselves here (see R/providers/). A provider is a list with:
#   name       source name for notes and the sources appendix
#   fetch(variables, pieces, periods, options) -> long data: geo, period, period_start,
#       period_end, variable, estimate, moe, status, bound, source_id
#   geo_types  geography types the source publishes
#   periods(settings, recipe) -> the periods available/selected for a metric
#   period_label(period) -> display label (e.g. "2020-2024" for an ACS release)
#   period_kind  "multiyear", "annual", "point" or "snapshot"
#   optional: series (label of the series a value belongs to), availability_note (which
#   geographies are published), combine_moe = FALSE (margins of error of several areas
#   cannot be combined, as for model-based estimates), fixed_boundaries (the year of the boundaries
#   every period is tabulated in, when a source does not follow boundary changes)
provider_registry <- new.env(parent = emptyenv())

register_provider <- function(id, provider) {
  assign(id, provider, envir = provider_registry)
  invisible(provider)
}

get_provider <- function(id) {
  if (!exists(id, envir = provider_registry, inherits = FALSE)) {
    stop("No provider is registered for source '", id, "'. Cataloged sources without an adapter ",
         "cannot be used in reports (see catalog/sources.csv).", call. = FALSE)
  }
  get(id, envir = provider_registry, inherits = FALSE)
}

# Empty long-data frame with the provider contract's columns.
empty_values <- function() {
  data.frame(geo = character(), name = character(), variable = character(), estimate = numeric(),
             moe = numeric(), status = character(), bound = character(), note = character(),
             period = character(), period_start = integer(), period_end = integer(),
             source_id = character(), stringsAsFactors = FALSE)
}

# ---- Small utilities ------------------------------------------------------------

# Split "a; b;c" into c("a", "b", "c"); empty input gives character(0).
split_list <- function(x, sep = ";") {
  if (is.null(x) || length(x) == 0 || is.na(x) || !nzchar(trimws(x))) return(character(0))
  parts <- trimws(strsplit(x, sep, fixed = TRUE)[[1]])
  parts[nzchar(parts)]
}

# Parse "key=value; key2=value2" option strings from manifest cells.
parse_options <- function(x) {
  items <- split_list(x)
  if (!length(items)) return(list())
  bad <- !grepl("=", items, fixed = TRUE)
  if (any(bad)) stop("Options must look like key=value; got: ", paste(items[bad], collapse = ", "))
  keys <- trimws(sub("=.*$", "", items))
  vals <- trimws(sub("^[^=]*=", "", items))
  stats::setNames(as.list(vals), keys)
}

is_blank <- function(x) is.null(x) || length(x) == 0 || all(is.na(x)) || all(!nzchar(trimws(x)))

first_non_blank <- function(...) {
  for (x in list(...)) if (!is_blank(x)) return(x)
  NULL
}

as_flag <- function(x, default = FALSE) {
  if (is_blank(x)) return(default)
  tolower(trimws(as.character(x))) %in% c("true", "t", "yes", "y", "1")
}
