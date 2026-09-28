# Configuration and editable content.
#
#   config/settings.csv   scoped settings: default < profile:<id> < report:<id> < block options
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

# Resolve settings for a report. Keys must be declared in the default scope, so a typo in a
# profile/report/block override is an error rather than a silently ignored setting.
resolve_settings <- function(report_id = NULL, profile = NULL, block_options = list()) {
  s <- settings_table()
  known <- s$key[s$scope == "default"]
  scopes <- c("default", if (!is_blank(profile)) paste0("profile:", profile),
              if (!is_blank(report_id)) paste0("report:", report_id))
  out <- list()
  origin <- list()
  for (sc in scopes) {
    rows <- s[s$scope == sc, , drop = FALSE]
    for (i in seq_len(nrow(rows))) {
      out[[rows$key[i]]] <- rows$value[i]
      origin[[rows$key[i]]] <- sc
    }
  }
  unknown <- setdiff(c(s$key[s$scope %in% scopes], names(block_options)), known)
  if (length(unknown)) {
    stop("Unknown setting(s): ", paste(unique(unknown), collapse = ", "),
         ". Declare new settings in the default scope of config/settings.csv first.", call. = FALSE)
  }
  for (k in names(block_options)) {
    out[[k]] <- block_options[[k]]
    origin[[k]] <- "block options"
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
    m$options[i] <- paste(c(b$options, m$options[i])[nzchar(c(b$options, m$options[i]))], collapse = "; ")
  }
  m
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
