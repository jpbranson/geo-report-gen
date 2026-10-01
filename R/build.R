# Build one report: fold inline edits back into canonical text, compose (data + text ->
# snapshot + report.qmd), render with Quarto when its inputs changed, and write a build
# manifest (reports/<id>/build.json).

quarto_bin <- function() {
  candidates <- c(Sys.getenv("QUARTO_PATH"), Sys.which("quarto"),
                  "C:/Program Files/Quarto/bin/quarto.exe",
                  "C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe",
                  file.path(Sys.getenv("LOCALAPPDATA"), "Programs/Positron/resources/app/quarto/bin/quarto.exe"),
                  "/usr/local/bin/quarto", "/opt/quarto/bin/quarto",
                  "/Applications/quarto/bin/quarto", "/Applications/RStudio.app/Contents/Resources/app/quarto/bin/quarto")
  hit <- candidates[nzchar(candidates) & file.exists(candidates)][1]
  if (is.na(hit)) stop("Quarto not found. Install it (https://quarto.org) or set QUARTO_PATH.", call. = FALSE)
  normalizePath(hit, winslash = "/")
}

# Environment for Quarto's R process: the project root and this session's package library
# (renv), so rendering uses exactly the packages the build used.
quarto_env <- function() {
  c("current", GR_ROOT = gr_root(), R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
    QUARTO_R = normalizePath(R.home("bin"), winslash = "/"))
}

render_report <- function(report_id, to = "html") {
  qmd <- file.path(report_dir(report_id), "report.qmd")
  res <- processx::run(quarto_bin(), c("render", qmd, "--to", to), env = quarto_env(),
                       error_on_status = FALSE, echo = FALSE, timeout = 1800, wd = report_dir(report_id))
  if (res$status != 0) {
    log_path <- file.path(report_dir(report_id), "render.log")
    write_text_file(c(res$stdout, res$stderr), log_path)
    stop("Quarto render failed for ", report_id, " (see ", log_path, "):\n",
         paste(utils::tail(strsplit(res$stderr, "\n")[[1]], 15), collapse = "\n"), call. = FALSE)
  }
  for (w in render_warnings(strsplit(res$stderr, "\n")[[1]])) warn(w)
  invisible(res)
}

# Placeholders the Lua filter could not fill (they would appear as "{name}" in the report).
render_warnings <- function(lines) {
  unique(sub("^.*gr-placeholders: ", "", grep("gr-placeholders: unknown placeholder", lines, value = TRUE)))
}

# Files whose changes should trigger a re-render: the code that runs while Quarto renders
# (drawing, placeholder filling in content.R, custom modules through blocks.R).
render_code_files <- function() c("R/charts.R", "R/maps.R", "R/theme.R", "R/runtime.R", "R/content.R", "R/blocks.R",
                                   "quarto/gr-placeholders.lua",
                                   file.path("modules", list.files(root_path("modules"), pattern = "[.]R$")))

render_inputs_hash <- function(report_id) {
  dir <- report_dir(report_id)
  hash_value(hash_files(c(file.path(dir, "report.qmd"), file.path(snapshot_dir(report_id), c("report.rds", "values.json", "theme.scss")))),
             code_version(render_code_files()))
}

previous_build <- function(report_id) {
  path <- file.path(report_dir(report_id), "build.json")
  if (!file.exists(path)) return(NULL)
  tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
}

report_outputs <- function(report_id, formats) {
  file.path(report_dir(report_id), paste0("report.", ifelse(formats == "typst", "pdf", formats)))
}

# Build one report. With render = FALSE the report is composed only; the manifest then keeps
# the hash of the last successful render and sets needs_render (the batch renders later).
build_report <- function(report_id, render = TRUE, offline = FALSE, refresh = character(), force = FALSE,
                         formats = "html") {
  run_reset(offline = offline, refresh = refresh)
  started <- Sys.time()
  status <- "ok"
  err <- NULL
  rendered <- FALSE
  composed <- NULL
  harvest <- NULL
  reused <- NULL
  inputs_key <- NULL
  result <- tryCatch({
    harvest <- timed("harvest", harvest_report(report_id))
    # Keyed on the inputs as the compose starts reading them: an edit made during the compose
    # changes the key of the next build, so it composes again.
    inputs_key <- compose_inputs_key(report_id)
    prev <- previous_build(report_id)
    if (!force && !length(refresh) && reusable_compose(report_id, prev, compose_key(report_id, inputs_key))) {
      reused <- prev
    } else {
      note(report_id, ": composing (data not yet in cache/ are downloaded first)")
      composed <- timed("compose", compose_report(report_id))
    }
    key <- render_inputs_hash(report_id)
    up_to_date <- !force && !is.null(prev) && identical(prev$render_inputs_hash, key) && all(file.exists(report_outputs(report_id, formats)))
    rendered_hash <- if (up_to_date) key else prev$render_inputs_hash
    if (render && !up_to_date) {
      for (fmt in formats) timed("render", render_report(report_id, fmt))
      rendered <- TRUE
      rendered_hash <- key
    }
    list(key = rendered_hash, current = key, up_to_date = up_to_date, needs_render = !up_to_date && !rendered)
  }, error = function(e) {
    status <<- "failed"
    err <<- conditionMessage(e)
    NULL
  })
  manifest <- build_manifest(report_id, composed, harvest, status, err, result, rendered, started, formats, reused,
                             inputs_key)
  dir.create(report_dir(report_id), recursive = TRUE, showWarnings = FALSE)
  write_json_file(manifest, file.path(report_dir(report_id), "build.json"))
  if (status == "failed") note("FAILED ", report_id, ": ", err) else
    note(report_id, if (rendered) ": rendered" else if (!render) ": composed" else ": up to date (not re-rendered)",
         if (!is.null(reused)) " (inputs unchanged; last compose reused)",
         sprintf(" in %.1fs; %d requests; cache %d hit / %d miss", manifest$timings$total,
                 manifest$requests$total, run$cache[["hit"]], run$cache[["miss"]]))
  invisible(manifest)
}

# Everything a compose reads apart from cached data: code, catalog tables and content; the
# report's own configuration (its row in reports.csv, resolved settings and theme, manifest);
# and the report.qmd the last compose wrote (so an edit there is never skipped).
compose_key <- function(report_id, inputs = compose_inputs_key(report_id)) {
  hash_value(inputs, hash_files(file.path(report_dir(report_id), "report.qmd")))
}

# Everything in the compose key but report.qmd, which a compose both reads (edits are harvested
# first) and writes: a build takes these when its compose starts and report.qmd as written.
compose_inputs_key <- function(report_id) {
  cfg <- report_config(report_id)
  settings <- resolve_settings(report_id, cfg$profile)
  files <- c(list.files(root_path("modules"), full.names = TRUE),
             list.files(root_path("content"), recursive = TRUE, full.names = TRUE),
             manifest_path(cfg))
  hash_value(loaded_inputs_hash(), hash_files(files[!endsWith(files, ".lock")]), cfg, settings,
             load_theme(settings$theme))
}

# The code and catalog tables this process runs with. The code is loaded once, at start, and
# the catalog tables are read once, so they are hashed when the process loads (R/load.R): an
# edit made later changes the key of the next process, never that of a compose run with the
# version this process holds.
loaded_inputs_hash <- function() {
  memoize("loaded_inputs_hash", function() {
    hash_files(c(list.files(root_path("R"), recursive = TRUE, full.names = TRUE),
                 list.files(root_path("catalog"), pattern = "[.]csv$", full.names = TRUE)))
  })
}

# The last compose is still valid when nothing it read has changed: the same compose key, every
# raw file it read unchanged in size and time, its snapshot in place, and no source that failed
# or block that errored (those may succeed now, e.g. online).
reusable_compose <- function(report_id, prev, key = compose_key(report_id)) {
  if (is.null(prev) || !identical(prev$status, "ok") || !isTRUE(prev$complete)) return(FALSE)
  if (!identical(prev$compose_key, key)) return(FALSE)
  snapshot <- file.path(snapshot_dir(report_id), c("report.rds", "values.json", "theme.scss", "qmd_base.json"))
  all(file.exists(snapshot)) &&
    all(vapply(prev$sources, function(s) identical(file_stamp(file.path(cache_root(), s$file)), s$stamp), TRUE))
}

file_stamp <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  paste(file.size(path), format(file.mtime(path), "%Y-%m-%dT%H:%M:%OS3"))
}

build_manifest <- function(report_id, composed, harvest, status, err, result, rendered, started, formats, reused = NULL,
                           inputs_key = NULL) {
  ctx <- composed$ctx
  reqs <- run$requests
  by_source <- if (length(reqs)) as.list(table(vapply(reqs, `[[`, "", "source"))) else list()
  pkgs <- c("dplyr", "ggplot2", "sf", "httr2", "knitr", "rmarkdown", "nanoparquet", "readr", "ragg")
  quarto_version <- tryCatch(processx::run(quarto_bin(), "--version")$stdout, error = function(e) NA)
  m <- list(
    report_id = report_id,
    status = status,
    error = err,
    built_at = format(started, "%Y-%m-%dT%H:%M:%S%z"),
    rendered = rendered,
    needs_render = isTRUE(result$needs_render),
    formats = formats,
    render_inputs_hash = result$key,
    current_inputs_hash = result$current,
    inputs = if (!is.null(ctx)) list(
      geography = hash_value(ctx$cfg$geography, ctx$area$vintage, ctx$cfg$mode),
      manifest = hash_files(manifest_path(ctx$cfg)),
      settings = hash_value(ctx$settings),
      text = hash_files(c(text_path(), list.files(root_path("content"), recursive = TRUE, full.names = TRUE))),
      theme = hash_value(ctx$theme),
      catalog = hash_files(list.files(root_path("catalog"), pattern = "\\.csv$", full.names = TRUE)),
      data = digest::digest(lapply(composed$blocks, `[[`, "data")),
      code = code_version(file.path("R", list.files(root_path("R"), recursive = TRUE)))
    ),
    geography = if (!is.null(ctx)) list(
      label = ctx$area$label, mode = ctx$area$mode, vintage = ctx$area$vintage,
      members = ctx$area$members$key, pieces = ctx$area$pieces$key, notes = ctx$area$notes,
      benchmarks = lapply(ctx$benchmarks, function(b) list(label = b$label, pieces = b$pieces$key, relation = b$relation)),
      benchmark_notes = ctx$benchmark_notes),
    settings = if (!is.null(ctx)) list(values = ctx$settings[names(ctx$settings)], origin = attr(ctx$settings, "origin")),
    # Each block's first year shown and the settings layer it came from.
    history_start = lapply(Filter(function(b) !is.null(b$settings_used), composed$blocks), function(b) {
      paste0(b$settings_used$history_start, " (", attr(b$settings_used, "origin")$history_start, ")")
    }),
    harvest = harvest,
    sources = source_versions(),
    dependencies = list(R = R.version.string,
                        packages = as.list(vapply(pkgs, function(p) tryCatch(as.character(utils::packageVersion(p)),
                                                                             error = function(e) NA_character_), "")),
                        renv_lock = hash_files(root_path("renv.lock")),
                        quarto = trimws(quarto_version)),
    warnings = as.list(run$warnings),
    timings = c(lapply(run$timings, round, 2), list(total = round(as.numeric(difftime(Sys.time(), started, units = "secs")), 2))),
    requests = list(total = length(reqs), by_source = by_source,
                    bytes = sum(vapply(reqs, function(r) as.numeric(r$bytes %||% 0), 0), na.rm = TRUE)),
    cache = as.list(run$cache),
    compose_key = if (!is.null(ctx)) compose_key(report_id, inputs_key),   # with report.qmd as written
    complete = !is.null(ctx) && !isTRUE(run$incomplete))
  # A reused compose keeps the record of the compose that made the snapshot.
  if (!is.null(reused)) {
    for (k in c("inputs", "geography", "settings", "history_start", "sources", "warnings", "compose_key", "complete")) {
      m[k] <- list(reused[[k]])
    }
    m$compose_reused_from <- reused$compose_reused_from %||% reused$built_at
  }
  m
}

# Raw files and API responses this build read, with the time each entered the cache and, for
# downloads, the URL (from the metadata written at download time).
source_versions <- function() {
  paths <- sort(unique(run$used))
  paths <- paths[file.exists(paths)]
  lapply(paths, function(p) {
    meta <- paste0(p, ".meta.json")
    list(file = sub(paste0("^", cache_root(), "/"), "", p),
         cached = format(retrieved_at(p), "%Y-%m-%dT%H:%M:%S"),
         stamp = file_stamp(p),
         url = if (file.exists(meta)) jsonlite::fromJSON(meta)$url else NA)
  })
}
