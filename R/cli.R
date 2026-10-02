# Command-line interface (Rscript gr.R <command> ...). Every command is a thin wrapper
# around an ordinary function, so the same steps can be run from an R session.

gr_usage <- "
Usage: Rscript gr.R <command> [arguments] [options]

Reports
  build <report_id>...        harvest inline edits, compose and render (skips render if unchanged)
  batch [report_id...]        build many reports in parallel (default: all enabled in config/reports.csv)
  preview <report_id>         live preview while editing reports/<id>/report.qmd (quarto preview)
  new <report_id> --geo <spec> [--mode single|union|compare|separate] [--profile general]
                              [--subjects a,b] [--metrics m1,m2] [--label text]
                              add a report to config/reports.csv (and a manifest when subjects/metrics are given)

Editing
  harvest <report_id>         fold inline edits in report.qmd into content/text.csv
  text-export <report_id> <file.csv>   write all text fields of a report for bulk editing
  text-import <file.csv>      apply edited rows (conflicts are reported, nothing is overwritten)

Geography and catalog
  find \"<name>\"               look up geography IDs by name (ambiguous names list all matches)
  catalog [--check] [--html]  validate the catalog (--check: exit 1 on problems; --html: write catalog/catalog.html)
  verify                      live checks of operational sources (appends to catalog/verification_log.csv)
  test                        run the automated tests (offline, with fixtures in tests/fixtures)

Cache
  cache prune [--yes]         list (--yes: delete) derived files that newer versions replaced
                              and no report's build.json lists; downloads are never deleted

Options
  --offline                   use the cache only; never touch the network
  --refresh <source,...>      re-download raw data for these sources (e.g. census_acs5)
  --force                     recompose and re-render even if inputs are unchanged
  --no-render                 compose only (snapshot + report.qmd)
  --workers <n>               parallel compose and render processes for batch (default 4)
  --formats html,typst        output formats (typst = PDF, experimental)
"

usage_text <- function() sub("Rscript gr.R", gr_command(), gr_usage, fixed = TRUE)

# Options that are switches, and options that take a value (`--key value` or `--key=value`).
# Anything else is an error, so a mistyped option never runs a build with the defaults.
cli_switches <- c("offline", "force", "no-render", "check", "html", "yes", "help")
cli_valued <- c("refresh", "workers", "formats", "geo", "mode", "profile", "subjects", "metrics", "label")

parse_cli <- function(args) {
  flags <- list()
  pos <- character()
  i <- 1
  while (i <= length(args)) {
    a <- args[i]
    if (startsWith(a, "--")) {
      key <- sub("^--", "", a)
      value <- NULL
      if (grepl("=", key, fixed = TRUE)) {
        value <- sub("^[^=]*=", "", key)
        key <- sub("=.*$", "", key)
      }
      if (key %in% cli_switches) {
        if (!is.null(value)) stop("--", key, " takes no value", call. = FALSE)
        flags[[key]] <- TRUE
      } else if (key %in% cli_valued) {
        if (is.null(value)) {
          value <- args[i + 1]
          if (is.na(value) || startsWith(value, "--")) stop("--", key, " needs a value (see ", gr_command(), " help)", call. = FALSE)
          i <- i + 1
        }
        flags[[key]] <- value
      } else {
        stop("Unknown option --", key, " (see ", gr_command(), " help)", call. = FALSE)
      }
    } else pos <- c(pos, a)
    i <- i + 1
  }
  list(cmd = pos[1], args = pos[-1], flags = flags)
}

gr_main <- function(args) {
  p <- parse_cli(args)
  f <- p$flags
  refresh <- split_list(f$refresh, ",")
  formats <- split_list(f$formats %||% "html", ",")
  if (!length(formats) || !all(formats %in% c("html", "typst"))) {
    stop("--formats takes html, typst or html,typst", call. = FALSE)
  }
  workers <- suppressWarnings(as.integer(f$workers %||% 4))
  if (is.na(workers) || workers < 1) stop("--workers needs a whole number of 1 or more", call. = FALSE)
  check_refresh(refresh)
  run_reset(offline = isTRUE(f$offline), refresh = refresh)   # for find, new and the catalog too
  cmd <- if (isTRUE(f$help)) "help" else p$cmd %||% "help"
  need_args <- function(n, usage) {
    if (length(p$args) < n) stop("Usage: ", gr_command(), " ", usage, call. = FALSE)
  }
  switch(cmd,
    build = {
      need_args(1, "build <report_id>... (ids are in config/reports.csv)")
      for (id in p$args) report_config(id)   # stop on an unknown id before building anything
      ok <- vapply(p$args, function(id) {
        m <- build_report(id, render = !isTRUE(f[["no-render"]]), offline = isTRUE(f$offline),
                          refresh = refresh, force = isTRUE(f$force), formats = formats)
        identical(m$status, "ok")
      }, logical(1))
      if (!all(ok)) quit(status = 1)
    },
    batch = batch_build(if (length(p$args)) p$args else NULL, workers = workers,
                        offline = isTRUE(f$offline), refresh = refresh, force = isTRUE(f$force), formats = formats,
                        render = !isTRUE(f[["no-render"]])),
    preview = {
      need_args(1, "preview <report_id>")
      preview_report(report_config(p$args[1])$report_id)
    },
    new = new_report(p$args[1], f),
    harvest = {
      need_args(1, "harvest <report_id>")
      cat(harvest_report(report_config(p$args[1])$report_id)$status, "\n")
    },
    `text-export` = {
      need_args(2, "text-export <report_id> <file.csv>")
      text_export(p$args[1], p$args[2])
    },
    `text-import` = {
      need_args(1, "text-import <file.csv>")
      text_import(p$args[1])
    },
    find = {
      need_args(1, "find \"<name>\"")
      hits <- find_geographies(p$args[1], as.integer(resolve_settings()$boundary_vintage))
      if (!nrow(hits)) cat("No matches.\n") else print(hits[, c("key", "name", "pop")], row.names = FALSE)
    },
    catalog = catalog_command(f),
    verify = {
      if (isTRUE(f$offline)) stop("verify checks the live sources, so it cannot run with --offline", call. = FALSE)
      verify_sources()
    },
    test = testthat::test_dir(root_path("tests", "testthat")),
    cache = {
      if (!identical(p$args[1], "prune")) stop("cache: the only subcommand is `cache prune [--yes]`", call. = FALSE)
      cache_prune(delete = isTRUE(f$yes))
    },
    help = cat(usage_text()),
    { cat("Unknown command '", cmd, "'\n", sep = ""); cat(usage_text()); quit(status = 2) })
  invisible(TRUE)
}

preview_report <- function(report_id) {
  qmd <- file.path(report_dir(report_id), "report.qmd")
  if (!file.exists(qmd)) stop("Build the report first: ", gr_command(), " build ", report_id, call. = FALSE)
  note("Previewing ", qmd, " (edit the file; the browser refreshes). Stop with Ctrl+C, then rebuild to save edits.")
  # In the container (GR_PREVIEW_PORT is set by the Dockerfile) Quarto must listen on all
  # interfaces at the port compose.yaml publishes; the host's browser opens it.
  port <- Sys.getenv("GR_PREVIEW_PORT")
  if (nzchar(port)) note("Open http://localhost:", port, " in your browser.")
  args <- c("preview", qmd, if (nzchar(port)) c("--host", "0.0.0.0", "--port", port, "--no-browser"))
  processx::run(quarto_bin(), args, env = quarto_env(), echo = TRUE, error_on_status = FALSE)
}
