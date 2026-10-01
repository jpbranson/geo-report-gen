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
  catalog [--check] [--html]  validate the catalog / write catalog/catalog.html
  verify                      live checks of operational sources (writes catalog/verification_log.csv)
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

parse_cli <- function(args) {
  flags <- list()
  pos <- character()
  i <- 1
  while (i <= length(args)) {
    a <- args[i]
    if (startsWith(a, "--")) {
      key <- sub("^--", "", a)
      if (key %in% c("offline", "force", "no-render", "check", "html", "yes")) {
        flags[[key]] <- TRUE
      } else {
        flags[[key]] <- args[i + 1]
        i <- i + 1
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
  cmd <- p$cmd %||% "help"
  switch(cmd,
    build = {
      if (!length(p$args)) stop("build: give one or more report ids (see config/reports.csv)")
      ok <- vapply(p$args, function(id) {
        m <- build_report(id, render = !isTRUE(f[["no-render"]]), offline = isTRUE(f$offline),
                          refresh = refresh, force = isTRUE(f$force), formats = formats)
        identical(m$status, "ok")
      }, logical(1))
      if (!all(ok)) quit(status = 1)
    },
    batch = batch_build(if (length(p$args)) p$args else NULL, workers = as.integer(f$workers %||% 4),
                        offline = isTRUE(f$offline), refresh = refresh, force = isTRUE(f$force), formats = formats,
                        render = !isTRUE(f[["no-render"]])),
    preview = preview_report(p$args[1]),
    new = new_report(p$args[1], f),
    harvest = print(harvest_report(p$args[1])$status),
    `text-export` = text_export(p$args[1], p$args[2]),
    `text-import` = text_import(p$args[1]),
    find = {
      hits <- find_geographies(p$args[1], as.integer(resolve_settings()$boundary_vintage))
      if (!nrow(hits)) cat("No matches.\n") else print(hits[, c("key", "name", "pop")], row.names = FALSE)
    },
    catalog = catalog_command(f),
    verify = verify_sources(),
    test = testthat::test_dir(root_path("tests", "testthat")),
    cache = {
      if (!identical(p$args[1], "prune")) stop("cache: the only subcommand is `cache prune [--yes]`")
      cache_prune(delete = isTRUE(f$yes))
    },
    help = cat(gr_usage),
    { cat("Unknown command '", cmd, "'\n", sep = ""); cat(gr_usage); quit(status = 2) })
  invisible(TRUE)
}

preview_report <- function(report_id) {
  qmd <- file.path(report_dir(report_id), "report.qmd")
  if (!file.exists(qmd)) stop("Build the report first: Rscript gr.R build ", report_id, call. = FALSE)
  note("Previewing ", qmd, " (edit the file; the browser refreshes). Stop with Ctrl+C, then rebuild to save edits.")
  # In the container (GR_PREVIEW_PORT is set by the Dockerfile) Quarto must listen on all
  # interfaces at the port compose.yaml publishes; the host's browser opens it.
  port <- Sys.getenv("GR_PREVIEW_PORT")
  if (nzchar(port)) note("Open http://localhost:", port, " in your browser.")
  args <- c("preview", qmd, if (nzchar(port)) c("--host", "0.0.0.0", "--port", port, "--no-browser"))
  processx::run(quarto_bin(), args, env = quarto_env(), echo = TRUE, error_on_status = FALSE)
}
