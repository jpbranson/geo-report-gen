# Batch builds. Phase 1 composes the reports in up to `workers` R processes, each building its
# share of the reports in turn: the shared cache (entries are locked and written atomically)
# means a benchmark or table used by many reports is fetched and computed once, and the
# processes divide each source's request rate among them. Phase 2 renders the reports whose
# inputs changed, running up to `workers` Quarto processes at a time. A failing report is
# recorded and skipped; the rest continue. Re-running resumes: composed data come from the cache
# and reports whose render inputs are unchanged are not re-rendered.

batch_build <- function(ids = NULL, workers = 4, offline = FALSE, refresh = character(), force = FALSE,
                        formats = "html", render = TRUE) {
  all <- expand_reports()
  ids <- ids %||% all$report_id
  unknown <- setdiff(ids, all$report_id)
  if (length(unknown)) stop("Unknown report id(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  started <- Sys.time()
  # A refresh composes in this process alone, so each file is downloaded once.
  procs <- if (length(refresh)) 1L else max(1L, min(as.integer(workers), length(ids)))
  note("Batch of ", length(ids), " reports: composing in ", procs, " process", if (procs > 1) "es",
       " (phase 1)")
  composed <- list()
  if (procs == 1) {
    for (id in ids) {
      composed[[id]] <- build_report(id, render = FALSE, offline = offline, refresh = refresh, force = force,
                                     formats = formats)
    }
  } else {
    compose_pool(ids, procs, offline = offline, force = force, formats = formats)
    # A process that stopped early leaves the build.json of an earlier run: not this batch's.
    for (id in ids) {
      m <- previous_build(id)
      built <- as.POSIXct(m$built_at %||% NA_character_, format = "%Y-%m-%dT%H:%M:%S%z")
      composed[[id]] <- if (!is.na(built) && built >= trunc(started, "secs")) m else
        list(status = "failed", error = "its compose process stopped before building it (see the batch output)")
    }
  }
  compose_secs <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  todo <- if (!render) character() else ids[vapply(ids, function(id) {
    m <- composed[[id]]
    identical(m$status, "ok") && (force || isTRUE(m$needs_render) || !all(file.exists(report_outputs(id, formats))))
  }, logical(1))]
  if (render) note("Rendering ", length(todo), " of ", length(ids), " reports with up to ", workers, " parallel Quarto processes (phase 2)")
  t_render <- Sys.time()
  render_results <- render_pool(todo, workers, formats)
  render_secs <- as.numeric(difftime(Sys.time(), t_render, units = "secs"))
  summary <- do.call(rbind, lapply(ids, function(id) {
    m <- if (is.null(composed[[id]]$report_id)) composed[[id]] else previous_build(id)
    data.frame(report_id = id, status = m$status,
               action = if (!identical(m$status, "ok")) "failed" else if (id %in% todo) "rendered" else
                 if (!render) "composed" else "up to date",
               requests = m$requests$total %||% 0, cache_hits = m$cache$hit %||% 0, cache_misses = m$cache$miss %||% 0,
               warnings = length(m$warnings), compose_s = m$timings$compose %||% NA,
               render_s = render_results[[id]]$seconds %||% NA, error = substr(m$error %||% "", 1, 160),
               stringsAsFactors = FALSE)
  }))
  total <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  log <- list(started = format(started, "%Y-%m-%dT%H:%M:%S%z"), reports = length(ids),
              rendered = sum(summary$action == "rendered"),
              workers = workers, seconds = list(total = round(total, 1), compose_phase = round(compose_secs, 1),
                                                render_phase = round(render_secs, 1)),
              requests = sum(summary$requests), cache_hits = sum(summary$cache_hits),
              cache_misses = sum(summary$cache_misses), results = summary)
  dir.create(root_path("reports", "_batch"), showWarnings = FALSE, recursive = TRUE)
  write_json_file(log, root_path("reports", "_batch", paste0(format(started, "%Y%m%d-%H%M%S"), ".json")))
  print(summary[, c("report_id", "status", "action", "requests", "cache_hits", "cache_misses", "warnings", "compose_s",
                    "render_s")], row.names = FALSE)
  note(sprintf(paste("Batch finished in %.1fs (compose %.1fs, render %.1fs); %d requests; %d failed;",
                     "%d with warnings (see build.json)."),
               total, compose_secs, render_secs, sum(summary$requests), sum(summary$status != "ok"), sum(summary$warnings > 0)))
  invisible(log)
}

# Compose `ids` in `procs` R processes (`gr.R build <ids> --no-render`), dealing the reports out
# longest first by their last compose time so the processes finish together; each process builds
# its share in turn, so tables it holds in memory serve all of its reports. Their notes are
# printed as they come.
compose_pool <- function(ids, procs, offline = FALSE, force = FALSE, formats = "html") {
  last <- vapply(ids, function(id) as.numeric(previous_build(id)$timings$compose %||% NA), 0)
  last[is.na(last)] <- if (all(is.na(last))) 1 else stats::median(last, na.rm = TRUE)
  share <- rep(list(character()), procs)
  load <- numeric(procs)
  for (id in ids[order(-last)]) {
    k <- which.min(load)
    share[[k]] <- c(share[[k]], id)
    load[k] <- load[k] + last[[id]]
  }
  flags <- c("--no-render", if (offline) "--offline", if (force) "--force",
             "--formats", paste(formats, collapse = ","))
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  running <- lapply(share, function(s) {
    processx::process$new(rscript, c("gr.R", "build", s, flags), wd = gr_root(),
                          env = c("current", GR_RATE_SHARE = procs), stdout = "|", stderr = "2>&1")
  })
  while (length(running)) {
    processx::poll(running, 1000)
    alive <- vapply(running, function(p) p$is_alive(), TRUE)
    for (i in seq_along(running)) {
      lines <- if (alive[i]) running[[i]]$read_output_lines() else running[[i]]$read_all_output_lines()
      if (length(lines)) cat(lines, sep = "\n")
      # A negative status is the signal that ended the process; the system kills a process that
      # runs out of memory, which several processes building large tables at once can do.
      status <- if (alive[i]) 0L else running[[i]]$get_exit_status()
      if (!is.na(status) && status < 0) {
        note("A compose process was killed (signal ", -status, "), most often for lack of memory; ",
             "its remaining reports are marked failed. Run the batch again with fewer --workers.")
      }
    }
    running <- running[alive]
  }
  invisible()
}

# Record a render outcome in the report's build manifest as soon as it is known, so an
# interrupted batch resumes with only the reports that still need rendering.
record_render <- function(id, r) {
  path <- file.path(report_dir(id), "build.json")
  m <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  m$rendered <- identical(r$status, "ok")
  m$needs_render <- !m$rendered
  if (m$rendered) m$render_inputs_hash <- m$current_inputs_hash else {
    m$status <- "failed"
    m$error <- r$error
  }
  m$timings$render <- round(r$seconds, 2)
  m$warnings <- c(m$warnings, as.list(render_warnings(readLines(file.path(report_dir(id), "render.log"), warn = FALSE))))
  write_json_file(m, path)
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
        record_render(id, results[[id]])
        note(id, if (ok) sprintf(": rendered (%.1fs)", secs) else paste0(": RENDER FAILED: ", err))
        running[[id]] <- NULL
      }
    }
  }
  results
}
