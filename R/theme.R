# One theme (config/themes.csv) drives the document CSS, charts, maps and tables, plus the
# number formats. Theme settings are cosmetic: nothing here changes a statistic.

load_theme <- function(name = "default") {
  t <- read_table(root_path("config", "themes.csv"))
  base <- t[t$theme == "default", , drop = FALSE]
  th <- stats::setNames(as.list(base$value), base$key)
  if (!identical(name, "default")) {
    over <- t[t$theme == name, , drop = FALSE]
    if (!nrow(over)) stop("Unknown theme '", name, "' (see config/themes.csv).", call. = FALSE)
    for (i in seq_len(nrow(over))) th[[over$key[i]]] <- over$value[i]
  }
  th$name <- name
  th
}

theme_num <- function(th, key) as.numeric(th[[key]])
theme_colors <- function(th, key) trimws(strsplit(th[[key]], ",", fixed = TRUE)[[1]])

# Font used for charts. If the configured font is not installed, fall back to the default
# sans font and warn (the build manifest records the warning).
chart_font <- function(th, key = "font_family") {
  family <- th[[key]]
  known <- tryCatch(any(tolower(systemfonts::system_fonts()$family) == tolower(family)), error = function(e) FALSE)
  if (!known) {
    warn("Font '", family, "' is not installed; charts use the default sans-serif font.")
    return("sans")
  }
  family
}

# ggplot2 theme. Titles are document headings (editable text), so plots carry none.
gr_ggtheme <- function(th) {
  family <- chart_font(th)
  theme_minimal(base_size = theme_num(th, "base_size"), base_family = family) +
    theme(text = element_text(color = th$color_text),
          plot.title = element_blank(),
          axis.text = element_text(color = th$color_muted),
          axis.title = element_text(color = th$color_muted, size = rel(0.95)),
          panel.grid.major = element_line(color = th$color_rule, linewidth = 0.3),
          panel.grid.minor = element_blank(),
          legend.position = "top", legend.justification = "left",
          legend.title = element_text(size = rel(0.9), color = th$color_muted),
          legend.text = element_text(size = rel(0.9)),
          plot.background = element_rect(fill = th$color_background, color = NA),
          panel.background = element_rect(fill = th$color_background, color = NA),
          plot.margin = margin(6, 14, 6, 6))
}

# Colors for entities: the study area always uses the accent color; benchmarks follow the
# benchmark palette in listing order, so meanings stay stable across figures.
entity_colors <- function(th, entity_labels, roles) {
  bm <- theme_colors(th, "color_benchmarks")
  areas <- theme_colors(th, "palette_categories")
  several <- sum(roles == "study") > 1  # compare mode: each area gets its own color
  cols <- character(length(entity_labels))
  k <- 0
  s <- 0
  for (i in seq_along(entity_labels)) {
    if (roles[i] == "study") {
      s <- s + 1
      cols[i] <- if (several) areas[(s - 1) %% length(areas) + 1] else th$color_accent
    } else {
      k <- k + 1
      cols[i] <- bm[(k - 1) %% length(bm) + 1]
    }
  }
  stats::setNames(cols, entity_labels)
}

category_colors <- function(th, categories) {
  pal <- theme_colors(th, "palette_categories")
  stats::setNames(pal[(seq_along(categories) - 1) %% length(pal) + 1], categories)
}

# Document styles generated from the theme (Quarto SCSS layers).
theme_scss <- function(th) {
  fonts <- function(key) paste0("\"", th[[key]], "\", ", th$font_fallback)
  break_before <- if (as_flag(th$print_break_before_sections)) "  h1.title, section.level1 > h1 { break-before: page; }\n" else ""
  paste0(
    "/*-- scss:defaults --*/\n",
    "$font-family-sans-serif: ", fonts("font_family"), ";\n",
    "$headings-font-family: ", fonts("font_family_headings"), ";\n",
    "$body-color: ", th$color_text, ";\n",
    "$body-bg: ", th$color_background, ";\n",
    "$link-color: ", th$color_accent, ";\n",
    "$font-size-root: ", th$body_size, ";\n",
    "$table-border-color: ", th$color_rule, ";\n",
    "$headings-color: ", th$color_text, ";\n",
    "\n/*-- scss:rules --*/\n",
    "main.content { max-width: ", th$content_width, "; }\n",
    "h1, h2 { border-bottom: 1px solid ", th$color_rule, "; padding-bottom: .25rem; }\n",
    "h3 { margin-top: 2rem; }\n",
    ".gr-note, .gr-source, .gr-caveat { font-size: .85rem; color: ", th$color_muted, "; margin-top: .25rem; }\n",
    ".gr-source p, .gr-note p { margin-bottom: .25rem; }\n",
    ".gr-unavailable { color: ", th$color_muted, "; font-style: italic; }\n",
    "table { font-variant-numeric: tabular-nums; font-size: .92rem; }\n",
    "table td, table th { padding: .3rem .55rem !important; }\n",
    "table thead th { border-bottom: 1.5px solid ", th$color_text, " !important; }\n",
    "figure .figure-caption, .quarto-figure figcaption { color: ", th$color_muted, "; font-size: .9rem; }\n",
    ".gr-events li { margin-bottom: .4rem; }\n",
    ".gr-evidence { font-size: .8rem; color: ", th$color_muted, "; text-transform: uppercase; letter-spacing: .03em; }\n",
    "@media print {\n", break_before,
    "  figure, table { break-inside: avoid; }\n",
    "  h2, h3 { break-after: avoid; }\n",
    "}\n",
    "@page { size: ", th$print_page_size, "; margin: 0.8in; }\n")
}

# ---- Number formats ----------------------------------------------------------------------

# How a metric's units (catalog/metrics.csv `units`, which may be descriptive, e.g. "percent
# of households" or "persons per household") are formatted: percent, dollars, years (ages,
# durations), year (calendar year), minutes, index, coefficient (0-1, e.g. the Gini index),
# ratio (any "x per y"), otherwise a count (persons, households, housing units...).
unit_kind <- function(units) {
  if (startsWith(units, "percent")) return("percent")
  if (startsWith(units, "dollars")) return("dollars")
  if (units %in% c("years", "year", "minutes", "ratio", "index", "coefficient")) return(units)
  if (grepl(" per ", units, fixed = TRUE)) return("ratio")
  "count"
}

fmt_value <- function(x, units, th, bound = NA) {
  kind <- unit_kind(units)
  out <- vapply(seq_along(x), function(i) {
    v <- x[i]
    if (is.na(v)) return("–")
    s <- switch(kind,
      percent = paste0(formatC(v, format = "f", digits = theme_num(th, "digits_percent"), big.mark = ","), "%"),
      dollars = paste0(if (v < 0) "-" else "", "$", fmt_dollar_amount(abs(v), theme_num(th, "digits_dollars"))),
      years = formatC(v, format = "f", digits = 1),
      year = formatC(round(v), format = "d"),
      minutes = formatC(v, format = "f", digits = 1),
      index = formatC(v, format = "f", digits = 1, big.mark = ","),
      coefficient = formatC(v, format = "f", digits = 3),
      ratio = formatC(v, format = "f", digits = theme_num(th, "digits_ratio"), big.mark = ","),
      formatC(round(v), format = "d", big.mark = ","))
    b <- if (length(bound) >= i) bound[i] else NA
    if (!is.na(b) && b == "lower") s <- paste0(s, "+")
    if (!is.na(b) && b == "upper") s <- paste0(s, "-")
    s
  }, "")
  out
}

# Large totals (such as expected losses of a state) in millions or billions, so tables stay narrow.
fmt_dollar_amount <- function(v, digits) {
  if (v >= 1e9) return(paste(formatC(v / 1e9, format = "f", digits = 1), "billion"))
  if (v >= 1e7) return(paste(formatC(v / 1e6, format = "f", digits = 1), "million"))
  formatC(v, format = "f", digits = digits, big.mark = ",")
}

# MOE of a percentage is in percentage points; shown without the % sign.
fmt_moe <- function(moe, units, th) {
  kind <- unit_kind(units)
  vapply(moe, function(m) {
    if (is.na(m)) return("–")
    if (m == 0) return("±0")
    paste0("±", switch(kind,
      percent = formatC(m, format = "f", digits = theme_num(th, "digits_percent")),
      dollars = paste0("$", formatC(m, format = "f", digits = theme_num(th, "digits_dollars"), big.mark = ",")),
      count = , year = formatC(round(m), format = "d", big.mark = ","),
      coefficient = formatC(m, format = "f", digits = 3),
      formatC(m, format = "f", digits = 1, big.mark = ",")))
  }, "")
}

# Difference between two values of a metric: percentage points for percentages, the plain
# difference for calendar years and coefficients, percent change otherwise. Returns the
# formatted string and which kind it is.
fmt_change <- function(new, old, units, th) {
  if (is.na(new) || is.na(old)) return(list(text = "–", kind = NA))
  kind <- unit_kind(units)
  d <- new - old
  sign <- if (d > 0) "+" else if (d < 0) "−" else ""
  if (kind == "percent") {
    return(list(text = paste0(sign, formatC(abs(d), format = "f", digits = theme_num(th, "digits_percent")),
                              " percentage points"), kind = "points"))
  }
  if (kind == "year") return(list(text = paste0(sign, round(abs(d)), " years"), kind = "difference"))
  if (kind == "coefficient") return(list(text = paste0(sign, formatC(abs(d), format = "f", digits = 3)), kind = "difference"))
  if (old == 0) return(list(text = "–", kind = NA))
  pct <- 100 * (new / old - 1)
  list(text = paste0(if (pct > 0) "+" else if (pct < 0) "−" else "", formatC(abs(pct), format = "f", digits = 1), "%"),
       kind = "percent_change")
}

# Axis label formatter for ggplot scales.
axis_labeller <- function(units) {
  switch(unit_kind(units),
    percent = function(x) paste0(scales::number(x, accuracy = 1, big.mark = ","), "%"),
    dollars = scales::label_dollar(accuracy = 1),
    years = , minutes = , ratio = , index = scales::label_number(accuracy = 0.1, big.mark = ","),
    year = scales::label_number(accuracy = 1, big.mark = ""),
    coefficient = scales::label_number(accuracy = 0.01),
    scales::label_comma(accuracy = 1))
}
