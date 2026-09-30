# Fingerprints of every composed report, to show that a change alters only the output it
# should. Run from the project root:
#   Rscript tools/fingerprint.R <out.rds>             compose every report (offline), then record
#   Rscript tools/fingerprint.R <out.rds> --no-compose   record the snapshots as they are
#   Rscript tools/fingerprint.R --compare <a.rds> <b.rds>
# A fingerprint holds each report's placeholder values, resolved text templates, report.qmd
# (without its date line), a digest of every block's data, and the numbers each block shows
# (area, measure, period, value, margin of error, status).
source(file.path("R", "load.R"))
args <- commandArgs(trailingOnly = TRUE)

fingerprint <- function(id) {
  snap_path <- file.path(snapshot_dir(id), "report.rds")
  build <- jsonlite::fromJSON(file.path(report_dir(id), "build.json"))
  if (!identical(build$status, "ok")) return(list(error = build$error))
  snap <- readRDS(snap_path)
  qmd <- readLines(file.path(report_dir(id), "report.qmd"), encoding = "UTF-8", warn = FALSE)
  numbers <- lapply(snap$blocks, function(b) {
    r <- b$data$results
    if (is.null(r) || !all(c("entity_id", "metric_id", "period", "value", "moe", "status") %in% names(r))) return(NULL)
    r <- r[order(r$metric_id, r$entity_id, r$period), ]
    paste(r$entity_id, r$metric_id, r$period, signif(r$value, 10), signif(r$moe, 10), r$status)
  })
  list(values = unlist(snap$values), texts = unlist(snap$texts),
       qmd = qmd[!startsWith(qmd, "date: ")],
       blocks = vapply(snap$blocks, function(b) digest::digest(b$data), ""),
       numbers = Filter(Negate(is.null), numbers))
}

show_diff <- function(a, b, what) {
  keys <- union(names(a), names(b))
  get <- function(x, k) if (k %in% names(x)) x[[k]] else "(none)"
  changed <- keys[vapply(keys, function(k) !identical(get(a, k), get(b, k)), TRUE)]
  for (k in changed) {
    cat(sprintf("  %s %s\n    - %s\n    + %s\n", what, k, substr(get(a, k), 1, 300), substr(get(b, k), 1, 300)))
  }
  length(changed)
}

if (identical(args[1], "--compare")) {
  a <- readRDS(args[2])
  b <- readRDS(args[3])
  total <- 0
  for (id in union(names(a), names(b))) {
    x <- a[[id]]
    y <- b[[id]]
    if (identical(x, y)) next
    cat("==", id, "\n")
    if (!identical(x$error, y$error)) cat("  error:", x$error %||% "none", "->", y$error %||% "none", "\n")
    n <- show_diff(x$values, y$values, "value") + show_diff(x$texts, y$texts, "text") +
      show_diff(x$blocks, y$blocks, "block data")
    for (blk in union(names(x$numbers), names(y$numbers))) {
      gone <- setdiff(x$numbers[[blk]], y$numbers[[blk]])
      new <- setdiff(y$numbers[[blk]], x$numbers[[blk]])
      if (!length(gone) && !length(new)) next
      cat("  numbers", blk, ":", length(gone), "rows changed or removed,", length(new), "new\n")
      cat(paste0("    - ", utils::head(gone, 3), "\n"), paste0("    + ", utils::head(new, 3), "\n"), sep = "")
      n <- n + 1
    }
    qmd_lines <- length(setdiff(y$qmd, x$qmd)) + length(setdiff(x$qmd, y$qmd))
    if (qmd_lines) cat("  report.qmd:", qmd_lines, "lines differ\n")
    total <- total + n + qmd_lines + !identical(x$error, y$error)
  }
  cat(total, "differences\n")
} else {
  ids <- expand_reports()$report_id
  if (!"--no-compose" %in% args) for (id in ids) build_report(id, render = FALSE, offline = TRUE)
  prints <- lapply(stats::setNames(ids, ids), fingerprint)
  saveRDS(prints, args[1])
  note("Fingerprints of ", length(ids), " reports written to ", args[1])
}
