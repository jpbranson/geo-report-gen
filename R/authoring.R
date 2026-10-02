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

# Returns the editable fields; attribute "skeleton" holds every other non-blank line (the
# generated structure), so harvest can tell when text was typed where it would be lost.
parse_qmd_fields <- function(path) {
  lines <- readLines(path, encoding = "UTF-8", warn = FALSE)
  fields <- list()
  order <- character()
  skeleton <- character()
  # Front matter title and subtitle.
  if (length(lines) && lines[1] == "---") {
    end <- which(lines == "---")[2]
    fm <- yaml::yaml.load(paste(lines[2:(end - 1)], collapse = "\n"))
    if (!is.null(fm$title)) fields[["report.title"]] <- fm$title
    if (!is.null(fm$subtitle)) fields[["report.subtitle"]] <- fm$subtitle
    skeleton <- grep("^(title|subtitle):", lines[1:end], value = TRUE, invert = TRUE)
    i <- end + 1
  } else i <- 1
  in_chunk <- FALSE
  chunk_opts <- character()
  field_option <- "^#\\| ?(fig-cap|tbl-cap|fig-alt|gr-x-label|gr-y-label|gr-legend-title|gr-labels):|^#\\|   "
  while (i <= length(lines)) {
    ln <- lines[i]
    if (!in_chunk && grepl("^```\\{r", ln)) {
      in_chunk <- TRUE
      chunk_opts <- character()
      skeleton <- c(skeleton, ln)
    } else if (in_chunk && grepl("^```\\s*$", ln)) {
      in_chunk <- FALSE
      fields <- c(fields, chunk_fields(chunk_opts))
      skeleton <- c(skeleton, ln)
    } else if (in_chunk && grepl("^#\\|", ln)) {
      chunk_opts <- c(chunk_opts, sub("^#\\| ?", "", ln))
      if (!grepl(field_option, ln)) skeleton <- c(skeleton, ln)
    } else if (!in_chunk && grepl("^#{1,6} .*\\{#(sec|blk)-[a-z0-9-]+\\}\\s*$", ln)) {
      id <- sub("^.*\\{#(sec|blk)-([a-z0-9-]+)\\}\\s*$", "\\2", ln)
      fields[[paste0(id, ".title")]] <- trimws(sub("\\s*\\{#.*$", "", sub("^#{1,6} ", "", ln)))
      order <- c(order, id)
      skeleton <- c(skeleton, sub("^(#+) .*(\\{#.*\\})\\s*$", "\\1 \\2", ln))
    } else if (!in_chunk && grepl("^:::+ *\\{[^}]*gr-field=\"[^\"]+\"", ln)) {
      colons <- sub("^(:+).*$", "\\1", ln)
      field <- sub("^.*gr-field=\"([^\"]+)\".*$", "\\1", ln)
      j <- i + 1
      while (j <= length(lines) && lines[j] != colons) j <- j + 1
      if (j > length(lines)) stop(basename(path), ": the text block for '", field, "' (line ", i, ") has no closing ", colons, call. = FALSE)
      body <- if (j > i + 1) lines[(i + 1):(j - 1)] else character()
      fields[[field]] <- paste(body, collapse = "\n")
      skeleton <- c(skeleton, ln, colons)
      i <- j
    } else if (nzchar(trimws(ln))) {
      skeleton <- c(skeleton, ln)
    }
    i <- i + 1
  }
  attr(fields, "order") <- order
  attr(fields, "skeleton") <- sub("\\s+$", "", skeleton)
  fields
}

# The generated structure of report.qmd as written, kept for the next harvest.
skeleton_path <- function(report_id) file.path(snapshot_dir(report_id), "qmd_skeleton.txt")

save_qmd_skeleton <- function(report_id) {
  fields <- parse_qmd_fields(file.path(report_dir(report_id), "report.qmd"))
  write_text_file(attr(fields, "skeleton"), skeleton_path(report_id))
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

# The text currently in effect for a field of a report, resolved as compose does (field_text)
# with the block kinds, library references and labels of the report snapshot.
current_field_text <- function(records, field, report_id, profile, snap, events) {
  field_text(records, field, report_id, profile, snap$rows, snap$blocks, events)$text
}

# Insert or update one record (field + scope). A Markdown-backed record keeps its reference; the
# new text is written to its file by save_text_records, so a failed edit leaves the file alone.
upsert_record <- function(records, field, scope, text, fixed_facts = "", note = "") {
  hit <- which(records$field_id == field & records$scope == scope)
  stamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  files <- attr(records, "prose_files")
  if (length(hit)) {
    old <- records$text[hit]
    if (grepl("^@[A-Za-z0-9_./-]+\\.md$", old)) {
      files[[root_path("content", sub("^@", "", old))]] <- text
    } else {
      records$text[hit] <- text
    }
    records$updated[hit] <- stamp
    records$fixed_facts[hit] <- fixed_facts
  } else {
    records <- rbind(records, data.frame(field_id = field, scope = scope, text = text, updated = stamp,
                                         fixed_facts = fixed_facts, note = note, stringsAsFactors = FALSE))
  }
  attr(records, "prose_files") <- files
  records
}

# Builds in a batch run in parallel and each may save inline edits, so every change to
# content/text.csv holds its lock from reading the records to writing them back. The lock is
# re-entrant within a process (filelock), so only the outermost call takes and releases it.
text_lock <- new.env()
with_text_lock <- function(code) {
  if (isTRUE(text_lock$held)) return(code)
  lock <- filelock::lock(paste0(text_path(), ".lock"), timeout = 60000)
  if (is.null(lock)) {
    stop("Timed out waiting for the lock on content/text.csv (another gr.R process holds it). ",
         "Try again when it finishes.", call. = FALSE)
  }
  text_lock$held <- TRUE
  on.exit({
    text_lock$held <- FALSE
    filelock::unlock(lock)
  })
  force(code)
}

save_text_records <- function(records) {
  files <- attr(records, "prose_files")
  with_text_lock({
    write_table(records[order(records$field_id, records$scope), , drop = FALSE], text_path())
    for (path in names(files)) write_text_file(files[[path]], path)
  })
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
      now <- if (facts[[lit]] %in% names(flat)) flat[[facts[[lit]]]] else "no longer available"
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
  check_skeleton(report_id, attr(now, "skeleton"))
  snap <- readRDS(snap_path)
  changed <- names(now)[vapply(names(now), function(f) !is.null(base[[f]]) && !identical(now[[f]], base[[f]]), TRUE)]
  removed <- setdiff(names(base), names(now))
  if (length(removed)) {
    warn("Text fields removed from ", report_id, "/report.qmd are not deleted from content (change the manifest to remove blocks): ",
         paste(utils::head(removed, 8), collapse = ", "))
  }
  if (!length(changed)) return(list(status = "no inline edits", applied = list()))
  cfg <- report_config(report_id)
  with_text_lock({
    records <- load_text_records()
    events <- history_events()
    applied <- list()
    conflicts <- list()
    for (f in changed) {
      current <- current_field_text(records, f, report_id, cfg$profile, snap, events)
      if (identical(current, base[[f]])) {
        vals <- c(snap$values["report"], snap$values[sub("\\..*$", "", f)])
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
  })
  unlink(file.path(report_dir(report_id), "conflicts.csv"))
  note("Harvested ", length(applied), " inline edit(s) from ", report_id, "/report.qmd")
  list(status = "applied", applied = applied)
}

# Text typed outside the editable fields (e.g. a paragraph under a heading, not between :::
# fences) would be lost when the report is regenerated, so the build stops before that happens.
# Generated lines that were deleted only come back, so that is a warning.
check_skeleton <- function(report_id, now) {
  if (!file.exists(skeleton_path(report_id))) return(invisible())
  was <- readLines(skeleton_path(report_id), encoding = "UTF-8", warn = FALSE)
  added <- setdiff(now, was)
  if (length(added)) {
    stop("reports/", report_id, "/report.qmd has text outside the editable fields, which the next build would ",
         "overwrite:\n  ", paste(utils::head(added, 5), collapse = "\n  "),
         "\nNothing was saved. Move new prose into a text block between ::: fences (or add a manifest row of type ",
         "text), or remove it, then rebuild.", call. = FALSE)
  }
  if (length(setdiff(was, now))) {
    warn("Generated lines deleted from ", report_id, "/report.qmd come back when it is regenerated; ",
         "change the manifest to remove blocks.")
  }
}

# ---- Bulk export / import --------------------------------------------------------------------

text_export <- function(report_id, path) {
  snap_path <- file.path(snapshot_dir(report_id), "report.rds")
  if (!file.exists(snap_path)) stop("Build the report first: ", gr_command(), " build ", report_id, call. = FALSE)
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
  reports_in_file <- unique(x$report_id)
  x <- x[vapply(x$text, hash_text, "") != x$base_hash, , drop = FALSE]
  if (!nrow(x)) {
    note("No changed rows in ", path)
    return(invisible(list(applied = 0, conflicts = 0)))
  }
  bad_scope <- x$edit_scope[!grepl("^(default|profile:[a-z0-9-]+|report:[a-z0-9-]+)$", x$edit_scope)]
  if (length(bad_scope)) stop("Invalid edit_scope value(s): ", paste(unique(bad_scope), collapse = ", "), call. = FALSE)
  with_text_lock({
    records <- load_text_records()
    events <- history_events()
    snaps <- list()
    conflicts <- list()
    for (i in seq_len(nrow(x))) {
      r <- x[i, ]
      cfg <- report_config(r$report_id)
      if (is.null(snaps[[r$report_id]])) {
        snap_path <- file.path(snapshot_dir(r$report_id), "report.rds")
        if (!file.exists(snap_path)) stop("Build the report first: ", gr_command(), " build ", r$report_id, call. = FALSE)
        snaps[[r$report_id]] <- readRDS(snap_path)
      }
      snap <- snaps[[r$report_id]]
      current <- current_field_text(records, r$field_id, r$report_id, cfg$profile, snap, events)
      if (hash_text(current) != r$base_hash) {
        conflicts[[length(conflicts) + 1]] <- data.frame(report_id = r$report_id, field_id = r$field_id,
                                                          imported = r$text, canonical_now = current, stringsAsFactors = FALSE)
        next
      }
      vals <- c(snap$values["report"], snap$values[sub("\\..*$", "", r$field_id)])
      records <- upsert_record(records, r$field_id, r$edit_scope, r$text, detect_fixed_facts(r$text, vals), "bulk import")
    }
    if (length(conflicts)) {
      cf <- do.call(rbind, conflicts)
      out <- paste0(tools::file_path_sans_ext(path), "-conflicts.csv")   # never the imported file itself
      write_table(cf, out)
      stop(nrow(cf), " row(s) changed in content since export (", paste(cf$field_id, collapse = ", "),
           "). Nothing was imported. Details: ", out, ". Rebuild the report(s), export again, re-apply your edits, ",
           "and import that file.", call. = FALSE)
    }
    save_text_records(records)
  })
  for (i in seq_len(nrow(x))) warn_hidden(records, x$field_id[i], x$edit_scope[i], reports_in_file)
  note("Imported ", nrow(x), " changed text field(s) from ", path)
  invisible(list(applied = nrow(x), conflicts = 0))
}

# Text saved to a broad scope (default or a profile) does not show in a report that has a
# narrower record for the same field: say so, rather than let the import look applied.
warn_hidden <- function(records, field, scope, report_ids) {
  for (id in report_ids) {
    scopes <- text_scopes(id, report_config(id)$profile)
    k <- match(scope, scopes)
    if (is.na(k) || k == 1) next
    narrower <- Filter(function(s) any(records$field_id == field & records$scope == s), scopes[seq_len(k - 1)])
    if (length(narrower)) {
      warn(field, ": imported to ", scope, ", but ", id, " keeps its own ", narrower[1], " record for this field, ",
           "which takes precedence there. Delete that record in content/text.csv, or import to ", narrower[1], ".")
    }
  }
}
