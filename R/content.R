# Configuration and editable content.
#
#   config/settings.csv   scoped settings: default < profile:<id> < library block options <
#                         report:<id> < manifest row options
#   config/reports.csv    report instances (geography, mode, profile, optional manifest)
#   profiles/<id>.csv     audience manifests; config/manifests/<report>.csv overrides one report
#   catalog/blocks.csv    block library (what a block shows by default)
#   content/text.csv      every user-visible text, scoped like settings; long prose may live in
#                         content/prose/*.md referenced as "@prose/<file>.md"
#
# Manifest row order is the document order; a block belongs to the section above it.
# Text templates use {placeholders} filled from computed values; they are never evaluated
# as code.

# ---- Settings -------------------------------------------------------------------------

settings_table <- function() read_table(root_path("config", "settings.csv"))

# Resolve settings for a report or one of its blocks. Later layers win: the default scope, the
# profile, the library block's options (catalog/blocks.csv, e.g. a chart's own history_start),
# the report, then the manifest row's options. Keys must be declared in the default scope, so
# a typo in an override is an error rather than a silently ignored setting.
resolve_settings <- function(report_id = NULL, profile = NULL, library = list(), block_options = list()) {
  s <- settings_table()
  scoped <- function(sc) {
    rows <- s[s$scope == sc, , drop = FALSE]
    stats::setNames(as.list(rows$value), rows$key)
  }
  layers <- list(default = scoped("default"))
  if (!is_blank(profile)) layers[[paste0("profile:", profile)]] <- scoped(paste0("profile:", profile))
  layers[["block library"]] <- library
  if (!is_blank(report_id)) layers[[paste0("report:", report_id)]] <- scoped(paste0("report:", report_id))
  layers[["manifest options"]] <- block_options
  unknown <- setdiff(unlist(lapply(layers, names)), names(layers$default))
  if (length(unknown)) {
    stop("Unknown setting(s): ", paste(unique(unknown), collapse = ", "),
         ". Declare new settings in the default scope of config/settings.csv first.", call. = FALSE)
  }
  out <- list()
  origin <- list()
  for (layer in names(layers)) {
    for (k in names(layers[[layer]])) {
      out[[k]] <- layers[[layer]][[k]]
      origin[[k]] <- layer
    }
  }
  attr(out, "origin") <- origin
  out
}

# ---- Reports --------------------------------------------------------------------------

report_table <- function() read_table(root_path("config", "reports.csv"))

# Expand report rows: mode "separate" turns one row listing several areas into one report
# per area (ids "<report_id>-<geoid>"), so a list is never silently merged or split.
expand_reports <- function(reports = report_table()) {
  out <- list()
  for (i in seq_len(nrow(reports))) {
    r <- reports[i, , drop = FALSE]
    if (!as_flag(r$enabled, TRUE)) next
    specs <- trimws(unlist(strsplit(r$geography, "[+;]")))
    specs <- specs[nzchar(specs)]
    if (r$mode == "separate") {
      for (sp in specs) {
        rr <- r
        rr$report_id <- paste0(r$report_id, "-", gsub("[^A-Za-z0-9]", "", sub("^[^:]*:", "", sp)))
        rr$geography <- sp
        rr$mode <- "single"
        rr$label <- ""
        out[[length(out) + 1]] <- rr
      }
    } else {
      if (length(specs) > 1 && !r$mode %in% c("union", "compare")) {
        stop("Report '", r$report_id, "' lists ", length(specs), " geographies; set mode to union, ",
             "compare or separate.", call. = FALSE)
      }
      out[[length(out) + 1]] <- r
    }
  }
  do.call(rbind, out)
}

report_config <- function(report_id) {
  all <- expand_reports()
  row <- all[all$report_id == report_id, , drop = FALSE]
  if (!nrow(row)) stop("Unknown report '", report_id, "' (see config/reports.csv).", call. = FALSE)
  as.list(row[1, ])
}

# `gr.R new <id> --geo <spec> ...` adds a report to config/reports.csv. With --subjects and/or
# --metrics it also writes config/manifests/<id>.csv (see subject_manifest). The geography is
# resolved first, so a bad spec or an invalid union is reported before anything is written.
new_report <- function(report_id, flags) {
  if (is_blank(report_id) || !grepl("^[a-z0-9][a-z0-9-]*$", report_id)) {
    stop("new: give a report id made of lowercase letters, digits and hyphens.", call. = FALSE)
  }
  reports <- report_table()
  if (report_id %in% reports$report_id) stop("Report '", report_id, "' already exists in config/reports.csv.", call. = FALSE)
  if (is_blank(flags$geo)) stop("new: give the geography, e.g. --geo place:1827000", call. = FALSE)
  row <- data.frame(report_id = report_id, geography = flags$geo, mode = flags$mode %||% "single",
                    label = flags$label %||% "", profile = flags$profile %||% "general", manifest = "",
                    vintage = "", enabled = "TRUE", note = "", stringsAsFactors = FALSE)
  vintage <- as.integer(resolve_settings()$boundary_vintage)
  members <- parse_geo_list(row$geography, vintage)
  if (row$mode == "separate") {
    for (i in seq_len(nrow(members))) resolve_area(members[i, ], "single", vintage)
  } else resolve_area(members, row$mode, vintage, row$label)
  subjects <- split_list(flags$subjects, ",")
  metrics <- split_list(flags$metrics, ",")
  if (length(subjects) || length(metrics)) {
    row$manifest <- file.path("config", "manifests", paste0(report_id, ".csv"))
    write_table(subject_manifest(subjects, metrics), root_path(row$manifest))
  }
  write_table(rbind(reports, row[, names(reports)]), root_path("config", "reports.csv"))
  note("Added ", report_id, " to config/reports.csv", if (nzchar(row$manifest)) paste0(" (manifest ", row$manifest, ")"),
       ". Build it with: Rscript gr.R build ", report_id)
  invisible(row)
}

# Manifest for chosen subjects and metrics: the overview, one section per subject holding its
# library blocks (catalog/blocks.csv), a section of individual metrics, and the appendix.
# Section titles default to the subject names and are ordinary editable text records.
subject_manifest <- function(subjects, metrics) {
  subj <- subjects()
  bad <- c(setdiff(subjects, subj$subject_id), setdiff(metrics, recipes()$metric_id))
  if (length(bad)) {
    stop("Unknown subject or non-operational metric: ", paste(bad, collapse = ", "),
         " (see catalog/subjects.csv and catalog/recipes.csv).", call. = FALSE)
  }
  lib <- block_library()
  row <- function(id, type, ref = "") {
    data.frame(id = id, type = type, ref = ref, enabled = "TRUE", compare = "", viz = "", options = "", stringsAsFactors = FALSE)
  }
  rows <- list(row("overview", "section"), row("intro", "text", "intro"), row("locator", "block", "locator"),
               row("key-facts", "block", "key-facts"))
  titles <- c()
  for (s in subjects) {
    blocks <- lib$block_id[lib$subject_id == s]
    if (!length(blocks)) {
      warn("The block library has no blocks for subject '", s, "'; add its metrics with --metrics.")
      next
    }
    id <- gsub("_", "-", s)
    titles[id] <- subj$subject[subj$subject_id == s][1]
    rows <- c(rows, list(row(id, "section")), lapply(blocks, function(b) row(b, "block", b)))
  }
  if (length(metrics)) {
    titles["selected-measures"] <- "Selected measures"
    rows <- c(rows, list(row("selected-measures", "section")), lapply(metrics, function(m) row(gsub("_", "-", m), "metric", m)))
  }
  rows <- c(rows, list(row("appendix", "section"), row("availability", "block", "availability"),
                       row("sources", "block", "sources")))
  records <- load_text_records()
  for (id in names(titles)) {
    field <- paste0(id, ".title")
    if (!any(records$field_id == field)) records <- upsert_record(records, field, "default", titles[[id]], note = "added by gr.R new")
  }
  save_text_records(records)
  do.call(rbind, rows)
}

# ---- Block library and manifests --------------------------------------------------------

block_library <- function() memoize("block_library", function() read_table(root_path("catalog", "blocks.csv")))

manifest_path <- function(report) {
  if (!is_blank(report$manifest)) return(root_path(report$manifest))
  root_path("profiles", paste0(report$profile, ".csv"))
}

# Row types: section/subsection headings; block (a library block, catalog/blocks.csv);
# metric (one cataloged metric, ref = metric id, shown with its recommended comparison);
# text (prose only); custom (a trusted module in modules/<ref>.R).
manifest_types <- c("section", "subsection", "block", "metric", "text", "custom")

# Load a manifest, validate it, and resolve each row against the block library.
load_manifest <- function(path) {
  m <- read_table(path)
  need <- c("id", "type", "ref", "enabled", "compare", "viz", "options")
  miss <- setdiff(need, names(m))
  if (length(miss)) stop(basename(path), ": missing column(s) ", paste(miss, collapse = ", "), call. = FALSE)
  problems <- validate_manifest(m)
  if (length(problems)) stop(basename(path), ":\n  ", paste(problems, collapse = "\n  "), call. = FALSE)
  m$enabled <- vapply(m$enabled, as_flag, logical(1), default = TRUE)
  lib <- block_library()
  # Section membership comes from row order only.
  m$section <- ""
  current <- ""
  for (i in seq_len(nrow(m))) {
    if (m$type[i] == "section") current <- m$id[i]
    m$section[i] <- current
  }
  m$kind <- m$type
  m$metrics <- ""
  m$library_options <- ""   # the library block's options; the row's own `options` override them
  m$kind[m$type == "custom"] <- "custom"
  for (i in which(m$type == "metric")) {
    # A single metric: shown over time with benchmarks when it has history, else vs benchmarks.
    doc <- metric_doc(m$ref[i])
    m$kind[i] <- "metric"
    m$metrics[i] <- m$ref[i]
    if (is_blank(m$compare[i])) m$compare[i] <- if (grepl("time", doc$comparisons)) "time+parents" else "parents"
  }
  for (i in which(m$type == "block")) {
    b <- lib[lib$block_id == m$ref[i], , drop = FALSE]
    m$kind[i] <- b$kind
    m$metrics[i] <- b$metrics
    if (is_blank(m$compare[i])) m$compare[i] <- b$compare
    if (is_blank(m$viz[i])) m$viz[i] <- b$viz
    m$library_options[i] <- b$options
  }
  bad_viz <- m$id[nzchar(m$viz) & !mapply(viz_allowed, m$kind, m$viz, m$compare)]
  if (length(bad_viz)) {
    stop(basename(path), ": `viz` does not match what the block draws in row(s) ", paste(bad_viz, collapse = ", "),
         " (metric blocks: line with compare time, dot otherwise; compositions: stacked_bar or bar).", call. = FALSE)
  }
  m
}

# The chart form (`viz`) each block kind draws; any other value would be silently ignored. A
# metric block draws lines over time and dots when it compares the latest values only.
viz_allowed <- function(kind, viz, compare) {
  allowed <- switch(kind, metric = if (grepl("time", compare)) "line" else "dot", composition = c("stacked_bar", "bar"),
                    distribution = "bar", facts = "table", availability = "table", map = "map", locator = "map", historical_map = "map",
                    history = "list", sources = "list", character())
  viz %in% allowed
}

validate_manifest <- function(m) {
  p <- character()
  bad_id <- m$id[!grepl("^[a-z0-9][a-z0-9-]*$", m$id)]
  if (length(bad_id)) p <- c(p, paste0("IDs must be lowercase letters, digits and hyphens: ", paste(bad_id, collapse = ", ")))
  dup <- unique(m$id[duplicated(m$id)])
  if (length(dup)) p <- c(p, paste0("Duplicate IDs: ", paste(dup, collapse = ", ")))
  bad_type <- unique(m$type[!m$type %in% manifest_types])
  if (length(bad_type)) p <- c(p, paste0("Unknown row type(s): ", paste(bad_type, collapse = ", "),
                                           " (use ", paste(manifest_types, collapse = ", "), ")"))
  if (nrow(m) && m$type[1] != "section") p <- c(p, "The first row must be a section (every block needs a section above it).")
  seen_section <- FALSE
  for (i in seq_len(nrow(m))) {
    if (m$type[i] == "section") seen_section <- TRUE
    if (m$type[i] == "subsection" && !seen_section) p <- c(p, paste0("Subsection '", m$id[i], "' appears before any section."))
  }
  lib <- block_library()
  broken <- m$id[m$type == "block" & !m$ref %in% lib$block_id]
  if (length(broken)) p <- c(p, paste0("Unknown block reference(s) in rows: ", paste(broken, collapse = ", "),
                                       " (see catalog/blocks.csv)"))
  not_operational <- m$id[m$type == "metric" & !m$ref %in% recipes()$metric_id]
  if (length(not_operational)) p <- c(p, paste0("Metric rows must name operational metrics (with a recipe): ",
                                                paste(not_operational, collapse = ", ")))
  mods <- m$ref[m$type == "custom"]
  if (length(mods)) {
    missing_mod <- mods[!file.exists(root_path("modules", paste0(mods, ".R")))]
    if (length(missing_mod)) p <- c(p, paste0("Custom module file(s) not found in modules/: ", paste(missing_mod, collapse = ", ")))
  }
  for (i in seq_len(nrow(m))) {
    opt <- tryCatch(parse_options(m$options[i]), error = function(e) conditionMessage(e))
    if (is.character(opt)) p <- c(p, paste0("Row '", m$id[i], "': ", opt))
  }
  p
}

# ---- Text records -------------------------------------------------------------------------

text_path <- function() root_path("content", "text.csv")

# Cited historical context (content/history_events.csv), or NULL when there is none.
history_events <- function() {
  path <- root_path("content", "history_events.csv")
  if (file.exists(path)) read_table(path) else NULL
}

load_text_records <- function() {
  t <- read_table(text_path())
  need <- c("field_id", "scope", "text", "updated", "fixed_facts", "note")
  for (col in setdiff(need, names(t))) t[[col]] <- ""
  dup <- duplicated(paste(t$field_id, t$scope))
  if (any(dup)) {
    stop("content/text.csv has duplicate field_id + scope rows: ",
         paste(unique(paste(t$field_id, t$scope)[dup]), collapse = ", "), call. = FALSE)
  }
  t[, need]
}

# Text of a record: inline, or the contents of a referenced Markdown file.
record_text <- function(text) {
  if (grepl("^@[A-Za-z0-9_./-]+\\.md$", text)) {
    path <- root_path("content", sub("^@", "", text))
    if (!file.exists(path)) stop("Text record references a missing file: ", text, call. = FALSE)
    return(read_text_file(path))
  }
  text
}

text_scopes <- function(report_id, profile) {
  c(if (!is_blank(report_id)) paste0("report:", report_id),
    if (!is_blank(profile)) paste0("profile:", profile), "default")
}

# Resolve one text field. Search order (first hit wins):
#   1. the field itself (e.g. "income-trend.caption") in report, profile, default scope
#   2. the same field of the library block the row uses (`ref`), in the same scope order
#   3. the kind template (e.g. "@metric.caption") in report, profile, default scope
# Returns the template text and where it came from.
resolve_text <- function(records, field_id, kind, report_id, profile, ref = NULL) {
  scopes <- text_scopes(report_id, profile)
  field_name <- sub("^[^.]*\\.", "", field_id)
  by_ref <- if (!is_blank(ref) && !startsWith(field_id, paste0(ref, "."))) paste0(ref, ".", field_name)
  candidates <- c(field_id, by_ref, if (!is.null(kind)) paste0("@", kind, ".", field_name))
  for (cand in candidates) {
    for (sc in scopes) {
      hit <- which(records$field_id == cand & records$scope == sc)
      if (length(hit)) {
        return(list(text = record_text(records$text[hit[1]]), scope = sc, record = cand,
                    fixed_facts = records$fixed_facts[hit[1]]))
      }
    }
  }
  list(text = "", scope = "none", record = NA_character_, fixed_facts = "")
}

# The text in effect for one field of a report and where it came from. Compose writes it into
# report.qmd, and harvest and import check edits against it, so all use this one function.
# `rows` and `blocks` are the report's manifest rows and computed blocks (or its snapshot's).
# Category labels fall back to "label.<metric>" and then to the block's catalog label; event
# statements to content/history_events.csv.
field_text <- function(records, field, report_id, profile, rows, blocks, events) {
  resolve <- function(f, kind = NULL, ref = NULL) resolve_text(records, f, kind, report_id, profile, ref)
  fallback <- function(text, scope) list(text = if (length(text) && !is.na(text)) text else "", scope = scope,
                                         record = NA_character_, fixed_facts = "")
  block <- sub("\\..*$", "", field)
  if (block == "event") {
    t <- resolve(field)
    statement <- events$statement[match(field, paste0("event.", events$event_id))]
    if (identical(t$scope, "none")) t <- fallback(statement, "history_events.csv")
    return(t)
  }
  if (grepl(".label.", field, fixed = TRUE)) {
    m <- sub("^.*\\.label\\.", "", field)
    t <- resolve(field)
    if (identical(t$scope, "none")) t <- resolve(paste0("label.", m))
    if (identical(t$scope, "none")) t <- fallback(blocks[[block]]$labels[[m]], "catalog")
    return(t)
  }
  row <- rows[rows$id == block, , drop = FALSE]
  kind <- if (block == "report") "report" else if (!nrow(row)) NULL else
    if (row$type[1] %in% c("section", "subsection")) "section" else
      if (identical(blocks[[block]]$kind, "error")) "error" else row$kind[1]
  resolve(field, kind, if (nrow(row)) row$ref[1])
}

# ---- Templates ----------------------------------------------------------------------------

placeholder_pattern <- "\\{([A-Za-z0-9_.-]+)\\}"

template_names <- function(text) {
  m <- regmatches(text, gregexpr(placeholder_pattern, text))[[1]]
  unique(gsub("[{}]", "", m))
}

# Fill {name} placeholders from `values` (a named list/character vector). Only names are
# looked up; nothing is evaluated. Unknown names are left in place (validation reports them).
fill_template <- function(text, values) {
  if (is_blank(text)) return("")
  names_in <- template_names(text)
  for (n in names_in) {
    v <- values[[n]]
    if (!is.null(v) && length(v) == 1 && !is.na(v)) text <- gsub(paste0("{", n, "}"), as.character(v), text, fixed = TRUE)
  }
  text
}

# Placeholders a template uses that no value provides.
unknown_placeholders <- function(text, available) setdiff(template_names(text), available)
