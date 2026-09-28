# Batch builds. Phase 1 composes each report in turn in this process: the shared cache means
# a benchmark or table used by many reports is fetched and computed once (and each report's
# own requests run with bounded concurrency). Phase 2 renders the reports whose inputs
# changed, running up to `workers` Quarto processes at a time. A failing report is recorded
# and skipped; the rest continue. Re-running resumes: composed data come from the cache and
# reports whose render inputs are unchanged are not re-rendered.

batch_build <- function(ids = NULL, workers = 4, offline = FALSE, refresh = character(), force = FALSE,
                        formats = "html") {
  all <- expand_reports()
  ids <- ids %||% all$report_id
  unknown <- setdiff(ids, all$report_id)
  if (length(unknown)) stop("Unknown report id(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  started <- Sys.time()
  note("Batch of ", length(ids), " reports: composing (phase 1)")
  composed <- list()
  for (id in ids) {
    m <- build_report(id, render = FALSE, offline = offline, refresh = refresh, force = force, formats = formats)
    composed[[id]] <- m
  }
  compose_secs <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  todo <- ids[vapply(ids, function(id) {
    m <- composed[[id]]
    identical(m$status, "ok") && (force || isTRUE(m$needs_render) || !all(file.exists(report_outputs(id, formats))))
  }, logical(1))]
  note("Rendering ", length(todo), " of ", length(ids), " reports with up to ", workers, " parallel Quarto processes (phase 2)")
  t_render <- Sys.time()
  render_results <- render_pool(todo, workers, formats)
  render_secs <- as.numeric(difftime(Sys.time(), t_render, units = "secs"))
  # Record render outcomes in each report's manifest.
  for (id in todo) {
    r <- render_results[[id]]
    path <- file.path(report_dir(id), "build.json")
    m <- jsonlite::fromJSON(path, simplifyVector = FALSE)
    m$rendered <- identical(r$status, "ok")
    m$needs_render <- !identical(r$status, "ok")
    if (identical(r$status, "ok")) m$render_inputs_hash <- m$current_inputs_hash else {
      m$status <- "failed"
      m$error <- r$error
    }
    m$timings$render <- round(r$seconds, 2)
    write_json_file(m, path)
  }
  summary <- do.call(rbind, lapply(ids, function(id) {
    m <- jsonlite::fromJSON(file.path(report_dir(id), "build.json"), simplifyVector = FALSE)
    data.frame(report_id = id, status = m$status,
               action = if (!identical(m$status, "ok")) "failed" else if (id %in% todo) "rendered" else "up to date",
               requests = m$requests$total %||% 0, cache_hits = m$cache$hit %||% 0, cache_misses = m$cache$miss %||% 0,
               compose_s = m$timings$compose %||% NA, render_s = render_results[[id]]$seconds %||% NA,
               error = substr(m$error %||% "", 1, 160), stringsAsFactors = FALSE)
  }))
  total <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  log <- list(started = format(started, "%Y-%m-%dT%H:%M:%S%z"), reports = length(ids), rendered = length(todo),
              workers = workers, seconds = list(total = round(total, 1), compose_phase = round(compose_secs, 1),
                                                render_phase = round(render_secs, 1)),
              requests = sum(summary$requests), cache_hits = sum(summary$cache_hits),
              cache_misses = sum(summary$cache_misses), results = summary)
  dir.create(root_path("reports", "_batch"), showWarnings = FALSE, recursive = TRUE)
  write_json_file(log, root_path("reports", "_batch", paste0(format(started, "%Y%m%d-%H%M%S"), ".json")))
  print(summary[, c("report_id", "status", "action", "requests", "cache_hits", "cache_misses", "compose_s", "render_s")], row.names = FALSE)
  note(sprintf("Batch finished in %.1fs (compose %.1fs, render %.1fs); %d requests; %d failed.",
               total, compose_secs, render_secs, sum(summary$requests), sum(summary$status != "ok")))
  invisible(log)
}

# Run Quarto renders as separate processes, at most `workers` at a time.
render_pool <- function(ids, workers, formats) {
  results <- list()
  queue <- ids
  running <- list()
  while (length(queue) || length(running)) {
    while (length(queue) && length(running) < workers) {
      id <- queue[1]
      queue <- queue[-1]
      qmd <- file.path(report_dir(id), "report.qmd")
      args <- c("render", qmd, "--to", paste(formats, collapse = ","))
      proc <- processx::process$new(quarto_bin(), args, env = quarto_env(), wd = report_dir(id),
                                    stdout = file.path(report_dir(id), "render.log"), stderr = "2>&1")
      running[[id]] <- list(proc = proc, started = Sys.time())
    }
    Sys.sleep(0.5)
    for (id in names(running)) {
      p <- running[[id]]$proc
      if (!p$is_alive()) {
        secs <- as.numeric(difftime(Sys.time(), running[[id]]$started, units = "secs"))
        ok <- identical(p$get_exit_status(), 0L)
        err <- if (ok) NULL else paste(utils::tail(readLines(file.path(report_dir(id), "render.log"), warn = FALSE), 8), collapse = " | ")
        results[[id]] <- list(status = if (ok) "ok" else "failed", seconds = secs, error = err)
        note(id, if (ok) sprintf(": rendered (%.1fs)", secs) else paste0(": RENDER FAILED: ", err))
        running[[id]] <- NULL
      }
    }
  }
  results
}
