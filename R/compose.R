# Compose a report: resolve geography and benchmarks, compute every block, resolve text,
# and write reports/<id>/report.qmd plus its snapshot (_snapshot/). Rendering reads only the
# snapshot, so a render never fetches or recomputes data.

report_dir <- function(report_id) root_path("reports", report_id)
snapshot_dir <- function(report_id) file.path(report_dir(report_id), "_snapshot")

# Everything a report's blocks need to know about the report.
report_context <- function(report_id) {
  cfg <- report_config(report_id)
  settings <- resolve_settings(report_id, cfg$profile)
  vintage <- as.integer(first_non_blank(cfg$vintage, settings$boundary_vintage))
  members <- timed("resolve", parse_geo_list(cfg$geography, vintage))
  area <- timed("resolve", resolve_area(members, cfg$mode, vintage, cfg$label))
  benchmarks <- if (identical(settings$benchmarks, "none")) list() else
    timed("resolve", choose_benchmarks(area, settings))
  # Compare mode: every listed area is its own entity ("a1", "a2", ...); benchmarks are the
  # ancestors shared by all of them. Otherwise one study entity (a single area or a union).
  studies <- if (area$mode == "compare") {
    lapply(seq_len(nrow(area$pieces)), function(i) {
      entity(paste0("a", i), "study", area$pieces$name[i], area$pieces[i, ])
    })
  } else list(entity("study", "study", area$label, area$pieces))
  list(report_id = report_id, cfg = cfg, profile = cfg$profile, settings = settings,
       area = area, study = studies[[1]], studies = studies, compare = area$mode == "compare",
       benchmarks = benchmarks, benchmark_notes = attr(benchmarks, "notes"), entities = c(studies, benchmarks),
       theme = load_theme(settings$theme), text_records = load_text_records(), events = area_events(area, benchmarks))
}

# Cited history events that apply to the study area, its members, or its benchmarks.
area_events <- function(area, benchmarks) {
  ev <- history_events()
  if (is.null(ev)) return(NULL)
  keys <- unique(c("nation", area$members$key, area$pieces$key,
                   unlist(lapply(benchmarks, function(b) b$pieces$key))))
  keys <- unique(c(keys, sub("^nation:US$", "nation", keys)))
  ev <- ev[ev$geo_scope %in% keys, , drop = FALSE]
  if (!"label" %in% names(ev)) ev$label <- substr(ev$statement, 1, 40)
  ev
}

# Report-level placeholder values available to every text field.
report_values <- function(ctx) {
  bm <- vapply(ctx$benchmarks, `[[`, "", "short")
  list(area = ctx$area$label, area_short = ctx$area$short,
       benchmark_list = if (length(bm)) join_list(bm, ctx) else phrase(ctx, "no_benchmarks", list()),
       n_benchmarks = as.character(length(bm)),
       acs_period = paste0(as.integer(ctx$settings$acs_release) - 4, "–", ctx$settings$acs_release),
       vintage = as.character(ctx$area$vintage),
       area_population = fmt_value(ctx$area$pop, "persons", ctx$theme))
}

compose_report <- function(report_id) {
  ctx <- report_context(report_id)
  rows <- load_manifest(manifest_path(ctx$cfg))
  rows <- rows[rows$enabled, , drop = FALSE]
  blocks <- timed("compute", compute_blocks(rows, ctx))
  blocks <- finish_appendices(blocks, ctx)
  texts <- resolve_block_texts(rows, blocks, ctx)
  values <- c(list(report = report_values(ctx)), lapply(blocks, `[[`, "values"))
  check_placeholders(texts, values)
  for (w in stale_fact_warnings(texts, values)) warn(w)
  write_snapshot(report_id, ctx, rows, blocks, texts, values)
  write_qmd(report_id, ctx, rows, blocks, texts)
  invisible(list(ctx = ctx, blocks = blocks, texts = texts))
}

# Compute every block; a block that fails becomes an error block and the report goes on.
compute_blocks <- function(rows, ctx) {
  blocks <- list()
  for (i in which(!rows$type %in% c("section", "subsection"))) {
    row <- as.list(rows[i, ])
    blocks[[row$id]] <- tryCatch(compute_block(row, ctx), error = function(e) {
      run$incomplete <- TRUE
      warn("Block '", row$id, "' could not be computed: ", conditionMessage(e))
      list(id = row$id, kind = "error", error = conditionMessage(e), fields = "title",
           values = list(block_id = row$id), section = row$section)
    })
  }
  blocks
}

# The sources and availability appendices summarize every other block.
finish_appendices <- function(blocks, ctx) {
  srcs <- do.call(rbind, lapply(blocks, function(b) b$sources))
  unav <- do.call(rbind, lapply(blocks, function(b) b$unavailable))
  for (id in names(blocks)) {
    if (identical(blocks[[id]]$kind, "sources")) {
      blocks[[id]]$markdown <- sources_markdown(srcs, ctx)
      blocks[[id]]$values <- c(blocks[[id]]$values, list(n_sources = as.character(length(unique(srcs$source_id)))))
    }
    if (identical(blocks[[id]]$kind, "availability")) {
      blocks[[id]]$markdown <- availability_markdown(unav, blocks, ctx)
      blocks[[id]]$values <- c(blocks[[id]]$values, list(n_unavailable = as.character(NROW(unav))))
    }
  }
  blocks
}

sources_markdown <- function(srcs, ctx) {
  if (is.null(srcs) || !nrow(srcs)) return("")
  srcs <- unique(srcs)
  cat_src <- sources_doc()
  lines <- vapply(unique(srcs$source_id), function(id) {
    detail <- paste(unique(srcs$detail[srcs$source_id == id]), collapse = "; ")
    row <- cat_src[cat_src$source_id == id, , drop = FALSE]
    if (!nrow(row)) return(paste0("- ", id, ": ", detail))
    paste0("- **", row$name, "** (", row$agency, "). ", detail, ". Documentation: <", row$doc_url, ">.")
  }, "")
  # When the data entered the local cache (downloaded or retrieved from an API).
  times <- do.call(c, lapply(unique(run$used), retrieved_at))
  if (length(times)) {
    span <- unique(format(range(times), "%B %d, %Y"))
    lines <- c(lines, paste0("- **Retrieval**: data files and API responses were retrieved ",
                             if (length(span) == 1) paste("on", span) else paste("between", span[1], "and", span[2]),
                             " and reused from the local cache; build.json lists each file."))
  }
  area <- ctx$area
  geo_note <- paste0("- **Geography**: ", area$label, " (", paste(area$members$key, collapse = ", "), "; ",
                     area$vintage, " boundaries). ", paste(area$notes, collapse = " "),
                     if (length(ctx$benchmark_notes)) paste0(" ", paste(ctx$benchmark_notes, collapse = " ")))
  bm_lines <- vapply(ctx$benchmarks, function(b) paste0("- **Benchmark** ", b$label, ": ", b$relation, "."), "")
  paste(c(geo_note, bm_lines, lines), collapse = "\n")
}

availability_markdown <- function(unav, blocks, ctx) {
  errs <- Filter(function(b) identical(b$kind, "error"), blocks)
  lines <- character()
  if (!is.null(unav) && nrow(unav)) {
    unav <- unique(unav[, c("metric_id", "entity", "period", "status", "reason")])
    unav$metric <- vapply(unav$metric_id, function(m) metric_doc(m)$label, "")
    # Rows that differ only in the measure become one row listing the measures (e.g. every CDC
    # PLACES measure for a region), so the list stays complete but short.
    key <- paste(unav$entity, unav$period, unav$status, unav$reason, sep = "\r")
    tab <- do.call(rbind, lapply(split(unav, factor(key, levels = unique(key))), function(g) {
      data.frame(Measure = paste(unique(g$metric), collapse = "; "), Area = g$entity[1], Period = g$period[1],
                 Status = gsub("_", " ", g$status[1]), Reason = g$reason[1], stringsAsFactors = FALSE)
    }))
    lines <- c(lines, knitr::kable(tab, format = "pipe", row.names = FALSE))
  }
  if (length(errs)) {
    lines <- c(lines, "", paste0("- Block **", names(errs), "** could not be produced: ",
                                 vapply(errs, `[[`, "", "error")))
  }
  paste(lines, collapse = "\n")
}

# ---- Text ------------------------------------------------------------------------------

# Resolve every editable field of every block (plus report and section titles).
resolve_block_texts <- function(rows, blocks, ctx) {
  fields <- c("report.title", "report.subtitle")
  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    if (r$type %in% c("section", "subsection")) {
      fields <- c(fields, paste0(r$id, ".title"))
      next
    }
    b <- blocks[[r$id]]
    fields <- c(fields, paste0(r$id, ".", setdiff(b$fields, "labels")),
                if ("labels" %in% b$fields) paste0(r$id, ".label.", names(b$labels)), b$event_fields)
  }
  stats::setNames(lapply(fields, function(f) {
    field_text(ctx$text_records, f, ctx$report_id, ctx$profile, rows, blocks, ctx$events)
  }), fields)
}

# Every placeholder must resolve; a typo in a template stops the report with a clear list. A
# placeholder whose value is missing (NA) would print as "{name}", so it is a warning.
check_placeholders <- function(texts, values) {
  problems <- character()
  for (field in names(texts)) {
    vals <- c(values[[sub("\\..*$", "", field)]], values$report)   # the block's own values first
    vals <- vals[!duplicated(names(vals))]
    bad <- unknown_placeholders(texts[[field]]$text, names(vals))
    if (length(bad)) {
      problems <- c(problems, paste0(field, ": {", paste(bad, collapse = "}, {"), "} (available: ",
                                     paste(sort(names(vals)), collapse = ", "), ")"))
    }
    for (n in intersect(template_names(texts[[field]]$text), names(vals))) {
      v <- vals[[n]]
      if (length(v) != 1 || is.na(v)) warn(field, ": {", n, "} has no value, so the text would show the placeholder itself.")
    }
  }
  if (length(problems)) {
    stop("Unknown placeholders in text templates:\n  ", paste(problems, collapse = "\n  "), call. = FALSE)
  }
  invisible(TRUE)
}

# ---- Snapshot -------------------------------------------------------------------------------

write_snapshot <- function(report_id, ctx, rows, blocks, texts, values) {
  dir <- snapshot_dir(report_id)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  snap <- list(report_id = report_id, rows = rows, blocks = blocks,
               texts = lapply(texts, `[[`, "text"), values = values, theme = ctx$theme, entities = ctx$entities,
               area = ctx$area[c("label", "short", "mode", "vintage", "members", "pieces", "notes")])
  tmp <- file.path(dir, paste0("report.rds.tmp-", Sys.getpid()))
  saveRDS(snap, tmp)
  replace_file(tmp, file.path(dir, "report.rds"))
  write_json_file(values, file.path(dir, "values.json"))
  write_text_file(theme_scss(ctx$theme), file.path(dir, "theme.scss"))
}

# ---- report.qmd ------------------------------------------------------------------------------

# Double-quoted YAML scalar, safe for any text (quotes, colons, Unicode, line breaks).
yaml_str <- function(x) {
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub("\"", "\\\"", x, fixed = TRUE)
  paste0("\"", gsub("\n", "\\n", x, fixed = TRUE), "\"")
}

chunk_option <- function(name, value) {
  if (is.list(value)) {
    lines <- paste0("#|   ", names(value), ": ", vapply(value, yaml_str, ""))
    return(c(paste0("#| ", name, ":"), lines))
  }
  paste0("#| ", name, ": ", yaml_str(value))
}

text_div <- function(field, text, block, class = "gr-text") {
  c(paste0("::: {.", class, " gr-field=\"", field, "\" gr-block=\"", block, "\"}"), text, ":::", "")
}

write_qmd <- function(report_id, ctx, rows, blocks, texts) {
  # Each text written into report.qmd is kept as the base version for the next harvest.
  base <- list()
  track <- function(field) {
    base[[field]] <<- texts[[field]]$text %||% ""
    base[[field]]
  }
  title <- track("report.title")
  subtitle <- track("report.subtitle")
  out <- qmd_header(report_id, title, subtitle, ctx$theme)
  in_subsection <- FALSE
  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    if (r$type %in% c("section", "subsection")) {
      in_subsection <- r$type == "subsection"
      out <- c(out, paste0(if (in_subsection) "## " else "# ", track(paste0(r$id, ".title")), " {#sec-", r$id, "}"), "")
    } else {
      out <- c(out, block_markdown(r, blocks[[r$id]], if (in_subsection) "###" else "##", track, ctx))
    }
  }
  write_text_file(out, file.path(report_dir(report_id), "report.qmd"))
  write_json_file(base, file.path(snapshot_dir(report_id), "qmd_base.json"))
  save_qmd_skeleton(report_id)
  invisible(out)
}

# YAML header (HTML; PDF through Typst with a basic page layout), the editing note, and the
# setup chunk that opens the snapshot.
qmd_header <- function(report_id, title, subtitle, th) {
  c("---",
    paste0("title: ", yaml_str(title)),
    paste0("subtitle: ", yaml_str(subtitle)),
    "date: today",   # filled in by Quarto when it renders, so a new day alone never re-renders a report
    "format:",
    "  html:",
    "    theme: [default, _snapshot/theme.scss]",
    "    toc: true",
    "    toc-depth: 2",
    "    number-sections: true",
    "    embed-resources: true",
    paste0("    fig-width: ", th$figure_width),
    paste0("    fig-height: ", th$figure_height),
    paste0("    fig-dpi: ", th$figure_dpi),
    "  typst:",
    "    toc: true",
    "    toc-depth: 2",
    "    number-sections: true",
    paste0("    papersize: ", if (th$print_page_size == "letter") "us-letter" else th$print_page_size),
    paste0("    mainfont: ", yaml_str(th$font_family)),
    paste0("    fig-width: ", th$figure_width),
    paste0("    fig-height: ", th$figure_height),
    "    include-in-header:",
    paste0("      text: ", yaml_str("#show table: set text(size: 8pt, hyphenate: false)")),
    "knitr:",
    "  opts_chunk:",
    "    dev: ragg_png",
    "execute:",
    "  echo: false",
    "  warning: false",
    "  message: false",
    "filters:",
    "  - ../../quarto/gr-placeholders.lua",
    "gr-values-file: _snapshot/values.json",
    "params:",
    paste0("  report_id: ", yaml_str(report_id)),
    "---",
    "",
    "<!-- Generated by geo-report-gen. Edit text in place (headings, text between ::: fences,",
    "     and the fig-cap/fig-alt/gr-* chunk options); the next build folds your edits into",
    "     content/text.csv. Change structure in the manifest, not here. -->",
    "",
    "```{r}",
    "#| label: setup",
    "#| include: false",
    "root <- Sys.getenv(\"GR_ROOT\", unset = normalizePath(\"../..\", winslash = \"/\"))",
    "Sys.setenv(GR_ROOT = root)",
    "source(file.path(root, \"R\", \"load.R\"))",
    "gr <- gr_open_snapshot(\"_snapshot/report.rds\")",
    "```",
    "")
}

# One block: heading, text in fenced divs, the figure or table chunk, generated markdown
# (history, appendices), then notes.
block_markdown <- function(r, b, level, track, ctx) {
  field <- function(name) paste0(r$id, ".", name)
  heading <- function() c(paste0(level, " ", track(field("title")), " {#blk-", r$id, "}"), "")
  if (identical(b$kind, "error")) {
    return(c(heading(), paste0("::: {.gr-unavailable}\nThis block could not be produced: ", b$error, "\n:::"), ""))
  }
  out <- if ("title" %in% b$fields) heading()
  for (f in intersect(c("body", "prose", "no_data"), b$fields)) out <- c(out, text_div(field(f), track(field(f)), r$id))
  if (isTRUE(b$figure) || isTRUE(b$table)) out <- c(out, figure_chunk(r, b, track, ctx$theme))
  if (identical(r$kind, "history")) out <- c(out, history_markdown(b, r$id, track, ctx))
  if (!is.null(b$markdown)) out <- c(out, b$markdown, "")
  # The legend (what marks mean, breaks in comparability) is always shown; brief detail leaves
  # out only the note on definitions and methods.
  if ("legend" %in% b$fields) out <- c(out, text_div(field("legend"), track(field("legend")), r$id, "gr-note"))
  if ("note" %in% b$fields && !identical(ctx$settings$detail, "brief")) {
    out <- c(out, text_div(field("note"), track(field("note")), r$id, "gr-note"))
  }
  if ("source_note" %in% b$fields) {
    out <- c(out, text_div(field("source_note"), track(field("source_note")), r$id, "gr-source"))
  }
  out
}

# The chunk that draws a figure or table. Its caption, alt text and axis, legend and series
# labels are chunk options, edited in place like the rest of the text.
figure_chunk <- function(r, b, track, th) {
  field <- function(name) paste0(r$id, ".", name)
  table <- isTRUE(b$table)
  opts <- c(paste0("#| label: ", if (table) "tbl-" else "fig-", r$id),
            chunk_option(if (table) "tbl-cap" else "fig-cap", track(field("caption"))))
  if ("alt" %in% b$fields) opts <- c(opts, chunk_option("fig-alt", track(field("alt"))))
  for (g in intersect(c("x_label", "y_label", "legend_title"), b$fields)) {
    opts <- c(opts, chunk_option(paste0("gr-", gsub("_", "-", g)), track(field(g))))
  }
  if (length(b$labels)) {
    labels <- lapply(names(b$labels), function(m) track(field(paste0("label.", m))))
    opts <- c(opts, chunk_option("gr-labels", stats::setNames(labels, names(b$labels))))
  }
  # Maps and bar charts of many categories get the taller map height.
  if (r$kind %in% c("map", "locator") || (identical(r$kind, "composition") && identical(r$viz, "bar"))) {
    opts <- c(opts, paste0("#| fig-height: ", th$map_height))
  }
  c("```{r}", opts, paste0("gr_block(gr, ", yaml_str(r$id), ")"), "```", "")
}

# Each event statement is its own editable text field; the date, evidence type and citation
# are generated from content/history_events.csv so provenance stays intact.
history_markdown <- function(b, block_id, track, ctx) {
  ev <- b$data$events
  if (is.null(ev) || !nrow(ev)) return(c(phrase(ctx, "no_events", list()), ""))
  out <- character()
  for (i in seq_len(nrow(ev))) {
    field <- paste0("event.", ev$event_id[i])
    y1 <- substr(ev$start_date[i], 1, 4)
    y2 <- substr(ev$end_date[i], 1, 4)
    when <- if (nzchar(y2) && y2 != y1) paste0(y1, "–", y2) else y1
    kind <- phrase(ctx, paste0("evidence_", ev$evidence_type[i]), list())
    out <- c(out, text_div(field, track(field), block_id),
             paste0("[", when, " · ", kind, " · Source: [", ev$source_title[i], "](", ev$source_url[i], "), ",
                    ev$publisher[i], " (accessed ", ev$accessed[i], ").]{.gr-source}"), "")
  }
  out
}
