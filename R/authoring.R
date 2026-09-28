# Editing workflows. Both update the same canonical records (content/text.csv):
#
# Inline: edit reports/<id>/report.qmd in place - headings, text between ::: fences, and
#   the fig-cap / tbl-cap / fig-alt / gr-* chunk options. `quarto preview` (via
#   `gr.R preview`) shows edits live. The next build (or `gr.R harvest`) compares the file
#   with what was generated (_snapshot/qmd_base.json) and saves changed fields as
#   report-scope records.
# Bulk: `gr.R text-export <report> file.csv` writes every field of a report with the text in
#   effect and a hash; edit in a spreadsheet; `gr.R text-import file.csv` saves changed rows.
#
# Conflicts: an edit is applied only if the canonical text is still what the editor saw
# (three-way check: base, edited, current). Otherwise nothing is written and the conflict is
# reported. Placeholders ({name}) keep numbers live; typed-in numbers that match a current
# value are recorded so later builds can warn when they go stale.

# ---- Parsing report.qmd ----------------------------------------------------------------

parse_qmd_fields <- function(path) {
  lines <- readLines(path, encoding = "UTF-8", warn = FALSE)
  fields <- list()
  order <- character()
  # Front matter title and subtitle.
  if (length(lines) && lines[1] == "---") {
    end <- which(lines == "---")[2]
    fm <- yaml::yaml.load(paste(lines[2:(end - 1)], collapse = "\n"))
    if (!is.null(fm$title)) fields[["report.title"]] <- fm$title
    if (!is.null(fm$subtitle)) fields[["report.subtitle"]] <- fm$subtitle
    i <- end + 1
  } else i <- 1
  in_chunk <- FALSE
  chunk_opts <- character()
  while (i <= length(lines)) {
    ln <- lines[i]
    if (!in_chunk && grepl("^```\\{r", ln)) {
      in_chunk <- TRUE
      chunk_opts <- character()
    } else if (in_chunk && grepl("^```\\s*$", ln)) {
      in_chunk <- FALSE
      fields <- c(fields, chunk_fields(chunk_opts))
    } else if (in_chunk && grepl("^#\\|", ln)) {
      chunk_opts <- c(chunk_opts, sub("^#\\| ?", "", ln))
    } else if (!in_chunk && grepl("^#{1,6} .*\\{#(sec|blk)-[a-z0-9-]+\\}\\s*$", ln)) {
      id <- sub("^.*\\{#(sec|blk)-([a-z0-9-]+)\\}\\s*$", "\\2", ln)
      fields[[paste0(id, ".title")]] <- trimws(sub("\\s*\\{#.*$", "", sub("^#{1,6} ", "", ln)))
      order <- c(order, id)
    } else if (!in_chunk && grepl("^:::+ *\\{[^}]*gr-field=\"[^\"]+\"", ln)) {
      colons <- sub("^(:+).*$", "\\1", ln)
      field <- sub("^.*gr-field=\"([^\"]+)\".*$", "\\1", ln)
      j <- i + 1
      while (j <= length(lines) && lines[j] != colons) j <- j + 1
      if (j > length(lines)) stop(basename(path), ": the text block for '", field, "' (line ", i, ") has no closing ", colons, call. = FALSE)
      body <- if (j > i + 1) lines[(i + 1):(j - 1)] else character()
      fields[[field]] <- paste(body, collapse = "\n")
      i <- j
    }
    i <- i + 1
  }
  attr(fields, "order") <- order
  fields
}

chunk_fields <- function(opt_lines) {
  if (!length(opt_lines)) return(list())
  o <- yaml::yaml.load(paste(opt_lines, collapse = "\n"))
  label <- o$label %||% ""
  if (!grepl("^(fig|tbl)-", label)) return(list())
  id <- sub("^(fig|tbl)-", "", label)
  out <- list()
  map <- c(`fig-cap` = "caption", `tbl-cap` = "caption", `fig-alt` = "alt", `gr-x-label` = "x_label",
           `gr-y-label` = "y_label", `gr-legend-title` = "legend_title")
  for (k in intersect(names(map), names(o))) out[[paste0(id, ".", map[[k]])]] <- as.character(o[[k]])
  if (!is.null(o[["gr-labels"]])) {
    for (m in names(o[["gr-labels"]])) out[[paste0(id, ".label.", m)]] <- as.character(o[["gr-labels"]][[m]])
  }
  out
}

# ---- Canonical records -------------------------------------------------------------------

# The text currently in effect for a field of a report (same resolution as compose).
current_field_text <- function(records, field, kind, report_id, profile, events = NULL, ref = NULL) {
  t <- resolve_text(records, field, kind, report_id, profile, ref)
  if (identical(t$scope, "none") && grepl("^event\\.", field) && !is.null(events)) {
    ev <- events[paste0("event.", events$event_id) == field, , drop = FALSE]
    if (nrow(ev)) return(ev$statement[1])
  }
  if (identical(t$scope, "none") && grepl("\\.label\\.", field)) {
    m <- sub("^.*\\.label\\.", "", field)
    g <- resolve_text(records, paste0("label.", m), NULL, report_id, profile)
    if (!identical(g$scope, "none")) return(g$text)
    rec <- recipes()
    if (m %in% rec$metric_id && nzchar(rec$category[rec$metric_id == m])) return(rec$category[rec$metric_id == m])
    return(tryCatch(metric_doc(m)$label, error = function(e) ""))
  }
  t$text
}

# Insert or update one record (field + scope). Markdown-backed records are updated in their file.
upsert_record <- function(records, field, scope, text, fixed_facts = "", note = "") {
  hit <- which(records$field_id == field & records$scope == scope)
  stamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  if (length(hit)) {
    old <- records$text[hit]
    if (grepl("^@[A-Za-z0-9_./-]+\\.md$", old)) {
      write_text_file(text, root_path("content", sub("^@", "", old)))
    } else {
      records$text[hit] <- text
    }
    records$updated[hit] <- stamp
    records$fixed_facts[hit] <- fixed_facts
  } else {
    records <- rbind(records, data.frame(field_id = field, scope = scope, text = text, updated = stamp,
                                         fixed_facts = fixed_facts, note = note, stringsAsFactors = FALSE))
  }
  records
}

# Save records under a lock so parallel builds never lose each other's edits.
save_text_records <- function(records) {
  lock <- filelock::lock(paste0(text_path(), ".lock"), timeout = 60000)
  on.exit(filelock::unlock(lock))
  records <- records[order(records$field_id, records$scope), , drop = FALSE]
  write_table(records, text_path())
  memo_clear("catalog_")
}

memo_clear <- function(prefix) {
  keys <- ls(memo)
  rm(list = keys[startsWith(keys, prefix)], envir = memo)
}

# Numbers typed into text that equal a current value are "fixed facts": remember which value
# they matched so a later build can warn when the data move but the text does not.
detect_fixed_facts <- function(text, values) {
  nums <- unique(regmatches(text, gregexpr("\\$?[0-9][0-9,]*(\\.[0-9]+)?%?", text))[[1]])
  nums <- nums[grepl("[0-9]{2,}|[0-9]\\.[0-9]|%|\\$", nums)]
  if (!length(nums)) return("")
  flat <- unlist(values)
  hits <- list()
  for (n in nums) {
    match <- names(flat)[flat == n]
    if (length(match)) hits[[n]] <- match[1]
  }
  if (!length(hits)) return("")
  as.character(jsonlite::toJSON(hits, auto_unbox = TRUE))
}

stale_fact_warnings <- function(texts, values) {
  flat <- unlist(values)
  out <- character()
  for (field in names(texts)) {
    ff <- texts[[field]]$fixed_facts %||% ""
    if (!nzchar(ff)) next
    facts <- jsonlite::fromJSON(ff)
    for (lit in names(facts)) {
      now <- flat[[facts[[lit]]]] %||% NA
      if (!identical(now, lit)) {
        out <- c(out, paste0(field, ": the text states \"", lit, "\", which matched {", sub("^[^.]*\\.", "", facts[[lit]]),
                             "} when written; the current value is \"", now, "\". Update the text or use the placeholder."))
      }
    }
  }
  out
}

# ---- Inline harvest ------------------------------------------------------------------------

harvest_report <- function(report_id) {
  qmd <- file.path(report_dir(report_id), "report.qmd")
  base_path <- file.path(snapshot_dir(report_id), "qmd_base.json")
  snap_path <- file.path(snapshot_dir(report_id), "report.rds")
  if (!file.exists(qmd) || !file.exists(base_path) || !file.exists(snap_path)) {
    return(list(status = "nothing to harvest (first build)", applied = list()))
  }
  base <- jsonlite::fromJSON(base_path, simplifyVector = FALSE)
  now <- parse_qmd_fields(qmd)
  snap <- readRDS(snap_path)
  changed <- names(now)[vapply(names(now), function(f) !is.null(base[[f]]) && !identical(now[[f]], base[[f]]), TRUE)]
  removed <- setdiff(names(base), names(now))
  if (length(removed)) {
    warn("Text fields removed from ", report_id, "/report.qmd are not deleted from content (change the manifest to remove blocks): ",
         paste(utils::head(removed, 8), collapse = ", "))
  }
  if (!length(changed)) return(list(status = "no inline edits", applied = list()))
  cfg <- report_config(report_id)
  records <- load_text_records()
  kinds <- stats::setNames(snap$rows$kind, snap$rows$id)
  refs <- stats::setNames(snap$rows$ref, snap$rows$id)
  events_path <- root_path("content", "history_events.csv")
  events <- if (file.exists(events_path)) read_table(events_path) else NULL
  applied <- list()
  conflicts <- list()
  for (f in changed) {
    block <- sub("\\..*$", "", f)
    kind <- if (block == "report") "report" else if (f == paste0(block, ".title") && kinds[[block]] %in% c("section", "subsection")) "section" else unname(kinds[block])
    current <- current_field_text(records, f, if (is.na(kind %||% NA)) NULL else kind, report_id, cfg$profile, events, refs[block])
    if (identical(current, base[[f]])) {
      vals <- c(snap$values["report"], snap$values[block])
      facts <- detect_fixed_facts(now[[f]], vals)
      records <- upsert_record(records, f, paste0("report:", report_id), now[[f]], facts, "inline edit")
      applied[[f]] <- now[[f]]
      if (nzchar(facts)) warn(f, ": contains numbers that match current values (", facts, "); they will not update with the data unless replaced by placeholders.")
    } else if (!identical(current, now[[f]])) {
      conflicts[[length(conflicts) + 1]] <- data.frame(field_id = f, generated = base[[f]], edited_in_qmd = now[[f]],
                                                        canonical_now = current, stringsAsFactors = FALSE)
    }
  }
  if (length(conflicts)) {
    cf <- do.call(rbind, conflicts)
    write_table(cf, file.path(report_dir(report_id), "conflicts.csv"))
    stop(nrow(cf), " edited field(s) in ", report_id, "/report.qmd were also changed in content/text.csv since the ",
         "report was generated: ", paste(cf$field_id, collapse = ", "), ". Nothing was saved. See ",
         file.path("reports", report_id, "conflicts.csv"), ", make the two versions agree (edit either one), then rebuild.",
         call. = FALSE)
  }
  save_text_records(records)
  unlink(file.path(report_dir(report_id), "conflicts.csv"))
  note("Harvested ", length(applied), " inline edit(s) from ", report_id, "/report.qmd")
  list(status = "applied", applied = applied)
}

# ---- Bulk export / import --------------------------------------------------------------------

text_export <- function(report_id, path) {
  snap_path <- file.path(snapshot_dir(report_id), "report.rds")
  if (!file.exists(snap_path)) stop("Build the report first: Rscript gr.R build ", report_id, call. = FALSE)
  snap <- readRDS(snap_path)
  fields <- names(snap$texts)
  block <- sub("\\..*$", "", fields)
  out <- data.frame(report_id = report_id, field_id = fields, block = block,
                    text = unname(unlist(snap$texts)), base_hash = vapply(unname(unlist(snap$texts)), hash_text, ""),
                    edit_scope = paste0("report:", report_id),
                    placeholders = vapply(block, function(b) paste(sort(unique(c(names(snap$values$report), names(snap$values[[b]] %||% list())))), collapse = " "), ""),
                    stringsAsFactors = FALSE)
  write_table(out, path)
  note("Exported ", nrow(out), " text fields of ", report_id, " to ", path)
  invisible(out)
}

text_import <- function(path) {
  x <- read_table(path)
  need <- c("report_id", "field_id", "text", "base_hash", "edit_scope")
  miss <- setdiff(need, names(x))
  if (length(miss)) stop("Import file is missing column(s): ", paste(miss, collapse = ", "), call. = FALSE)
  x <- x[vapply(x$text, hash_text, "") != x$base_hash, , drop = FALSE]
  if (!nrow(x)) {
    note("No changed rows in ", path)
    return(invisible(list(applied = 0, conflicts = 0)))
  }
  bad_scope <- x$edit_scope[!grepl("^(default|profile:[a-z0-9-]+|report:[a-z0-9-]+)$", x$edit_scope)]
  if (length(bad_scope)) stop("Invalid edit_scope value(s): ", paste(unique(bad_scope), collapse = ", "), call. = FALSE)
  records <- load_text_records()
  events_path <- root_path("content", "history_events.csv")
  events <- if (file.exists(events_path)) read_table(events_path) else NULL
  conflicts <- list()
  for (i in seq_len(nrow(x))) {
    r <- x[i, ]
    cfg <- report_config(r$report_id)
    snap <- readRDS(file.path(snapshot_dir(r$report_id), "report.rds"))
    kinds <- stats::setNames(snap$rows$kind, snap$rows$id)
  refs <- stats::setNames(snap$rows$ref, snap$rows$id)
    block <- sub("\\..*$", "", r$field_id)
    kind <- if (block == "report") "report" else if (grepl("\\.title$", r$field_id) && isTRUE(kinds[block] %in% c("section", "subsection"))) "section" else unname(kinds[block])
    current <- current_field_text(records, r$field_id, if (is.na(kind %||% NA)) NULL else kind, r$report_id, cfg$profile, events, refs[block])
    if (hash_text(current) != r$base_hash) {
      conflicts[[length(conflicts) + 1]] <- data.frame(report_id = r$report_id, field_id = r$field_id,
                                                        imported = r$text, canonical_now = current, stringsAsFactors = FALSE)
      next
    }
    vals <- c(snap$values["report"], snap$values[block])
    records <- upsert_record(records, r$field_id, r$edit_scope, r$text, detect_fixed_facts(r$text, vals), "bulk import")
  }
  if (length(conflicts)) {
    cf <- do.call(rbind, conflicts)
    out <- sub("\\.csv$", "-conflicts.csv", path)
    write_table(cf, out)
    stop(nrow(cf), " row(s) changed in content since export (", paste(cf$field_id, collapse = ", "),
         "). Nothing was imported. Details: ", out, ". Re-export, re-apply your edits, and import again.", call. = FALSE)
  }
  save_text_records(records)
  note("Imported ", nrow(x), " changed text field(s) from ", path)
  invisible(list(applied = nrow(x), conflicts = 0))
}
