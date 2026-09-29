# Renderers: turn a computed block (from the report snapshot) plus its resolved text into a
# chart, table or Markdown. Called from the generated report.qmd at render time, so they
# never fetch or compute data. Text inside images (axis labels, legends, category labels)
# comes from the block's text fields; the document text (titles, prose, captions) is
# written into the .qmd and filled by the Quarto filter.

# Colors for the entities in a block, stable across figures: study area(s) first.
block_entity_colors <- function(d, th) {
  ents <- unique(d[, c("label", "role")])
  entity_colors(th, ents$label, ents$role)
}

render_block_metric <- function(b, txt, th) {
  if (b$compare %in% c("parents", "none")) return(plot_compare(b, txt, th))
  plot_trend(b, txt, th)
}

plot_trend <- function(b, txt, th) {
  d <- b$data$results
  units <- b$data$units
  indexed <- "index_value" %in% names(d)
  d$y <- if (indexed) d$index_value else d$value
  kinds <- b$data$period_kind
  d$kind <- kinds[match(d$metric_id, names(kinds))]
  # Multiyear (ACS) periods are drawn at their midpoint with a bar spanning the period, so
  # 5-year estimates are never shown as single-year observations.
  d$x <- ifelse(d$kind == "multiyear", (d$period_start + d$period_end) / 2, d$period_end)
  # Lines connect only points of the same area and series: separate estimate vintages or
  # sources are separate lines, never spliced (a gap marks the change). When census counts
  # share a chart with annual estimates, the counts are drawn as points and the estimates as
  # lines, so the two kinds of observation stay distinguishable.
  d$group <- paste(d$label, d$series, sep = " | ")
  mixed <- any(d$kind == "point") && any(d$kind != "point")
  d$line <- !(mixed & d$kind == "point")
  d$dot <- !mixed | d$kind == "point"
  d$flagged <- d$status %in% c("unreliable", "imputed")
  cols <- block_entity_colors(d, th)
  fam <- chart_font(th)
  shown <- d[!is.na(d$y), , drop = FALSE]
  p <- ggplot(shown, aes(x = x, y = y, color = label, group = group))
  ev <- b$data$events
  if (!is.null(ev) && nrow(ev)) {
    # National periods such as recessions are light shading; they mark timing only.
    shade <- ev[ev$draw == "shade", , drop = FALSE]
    if (nrow(shade)) {
      p <- p + geom_rect(data = shade, aes(xmin = year, xmax = end_year + 1, ymin = -Inf, ymax = Inf),
                         inherit.aes = FALSE, fill = th$color_shading, alpha = 0.8)
    }
    breaks <- ev[ev$draw == "break", , drop = FALSE]
    if (nrow(breaks)) {
      # One label per year (events of the same year are joined), on alternating rows so that
      # labels of neighbouring breaks do not overprint.
      breaks <- stats::aggregate(label ~ year, data = breaks, FUN = function(x) paste(unique(x), collapse = "; "))
      breaks$vjust <- 1.2 + 1.4 * ((seq_len(nrow(breaks)) - 1) %% 2)
      p <- p + geom_vline(data = breaks, aes(xintercept = year), inherit.aes = FALSE,
                          linetype = "22", color = th$color_muted, linewidth = 0.35) +
        geom_text(data = breaks, aes(x = year, y = Inf, label = label, vjust = vjust),
                  inherit.aes = FALSE, hjust = -0.03, size = 2.6, color = th$color_muted, family = fam)
    }
  }
  # The area being described is emphasized; benchmarks are thinner and carry no spans or
  # error bars (their values and margins are in the text and tables).
  focus <- if (any(shown$role == "study")) shown$role == "study" else shown$label == shown$label[1]
  spans <- shown[shown$kind == "multiyear" & focus, , drop = FALSE]
  if (length(unique(spans$label)) > 1) spans <- spans[0, ]   # period bars of several areas would overlap
  if (nrow(spans)) {
    p <- p + geom_segment(data = spans, aes(x = period_start, xend = period_end + 0.98, y = y, yend = y),
                          linewidth = 1.6, alpha = 0.35, lineend = "butt")
  }
  p <- p + geom_line(data = shown[!focus & shown$line, , drop = FALSE], linewidth = 0.45, alpha = 0.85) +
    geom_line(data = shown[focus & shown$line, , drop = FALSE], linewidth = 1.05)
  has_moe <- !indexed & !is.na(shown$moe) & shown$moe > 0 & focus
  if (any(has_moe)) {
    p <- p + geom_errorbar(data = shown[has_moe, , drop = FALSE], aes(ymin = y - moe, ymax = y + moe),
                           width = 0.6, linewidth = 0.4, alpha = 0.9)
  }
  small <- nrow(shown) > 60 && !mixed
  p <- p + geom_point(data = shown[!focus & shown$dot, , drop = FALSE], aes(shape = flagged), size = if (small) 0.6 else 1.2, fill = th$color_background) +
    geom_point(data = shown[focus & shown$dot, , drop = FALSE], aes(shape = flagged), size = if (small) 1.1 else 2, fill = th$color_background)
  # Direct labels at each area's last point (collision-avoiding); a legend is the fallback
  # when there are too many areas to label cleanly.
  last <- shown |> group_by(label) |> filter(x == max(x)) |> slice(1) |> ungroup() |> as.data.frame()
  direct <- length(unique(shown$label)) <= 6
  if (direct) {
    p <- p + ggrepel::geom_text_repel(data = last, aes(label = label), hjust = 0, direction = "y",
                                      nudge_x = 0.02 * diff(range(shown$x, na.rm = TRUE)) + 0.3, size = 3,
                                      segment.color = th$color_rule, family = fam, min.segment.length = 0.2,
                                      seed = 1, max.overlaps = Inf)
  }
  xr <- range(c(shown$period_start, shown$x), na.rm = TRUE)
  p <- p + scale_color_manual(values = cols, guide = if (direct) "none" else "legend", name = txt$legend_title) +
    scale_shape_manual(values = c(`FALSE` = 19, `TRUE` = 21), guide = "none") +
    scale_x_continuous(breaks = pretty_years(xr), expand = expansion(mult = c(0.02, if (direct) 0.22 else 0.04))) +
    scale_y_continuous(labels = if (indexed) scales::label_number(accuracy = 1) else axis_labeller(units)) +
    labs(x = txt$x_label, y = txt$y_label) +
    gr_ggtheme(th)
  if (indexed) p <- p + geom_hline(yintercept = 100, color = th$color_muted, linewidth = 0.5)
  # Counts and dollars start at zero so growth is not exaggerated; rates may use a closer range.
  if (!indexed && unit_kind(units) %in% c("count", "dollars")) p <- p + expand_limits(y = 0)
  p
}

# Year axis breaks at round intervals, inside the plotted range only.
pretty_years <- function(r) {
  span <- diff(r)
  by <- if (span > 60) 10 else if (span > 25) 5 else if (span > 10) 2 else 1
  breaks <- seq(ceiling(r[1] / by) * by, floor(r[2] / by) * by, by = by)
  if (length(breaks) < 2) round(r) else breaks
}

plot_compare <- function(b, txt, th) {
  d <- b$data$results
  units <- b$data$units
  d <- d[d$period == max(d$period[!is.na(d$value)]), , drop = FALSE]
  d$label <- factor(d$label, levels = rev(unique(d$label)))
  cols <- block_entity_colors(transform(d, label = as.character(label)), th)
  d$shown <- fmt_value(d$value, units, th, d$bound)
  fam <- chart_font(th)
  has_moe <- !is.na(d$moe) & d$moe > 0
  p <- ggplot(d, aes(x = value, y = label, color = as.character(label)))
  if (any(has_moe)) {
    p <- p + geom_errorbarh(data = d[has_moe, , drop = FALSE], aes(xmin = value - moe, xmax = value + moe),
                            height = 0.25, linewidth = 0.45)
  }
  p <- p + geom_point(aes(shape = status == "unreliable"), size = 3, fill = th$color_background) +
    geom_text(aes(label = shown, x = value + ifelse(has_moe, moe, 0)), hjust = -0.25, size = 3.1,
              family = fam, color = th$color_text) +
    scale_color_manual(values = cols, guide = "none") +
    scale_shape_manual(values = c(`FALSE` = 19, `TRUE` = 21), guide = "none") +
    scale_x_continuous(labels = axis_labeller(units), expand = expansion(mult = c(0, 0.18))) +
    labs(x = txt$x_label, y = NULL) +
    gr_ggtheme(th) + theme(panel.grid.major.y = element_blank())
  if (unit_kind(units) %in% c("count", "percent", "dollars")) p <- p + expand_limits(x = 0)
  p
}

render_block_composition <- function(b, txt, th) {
  d <- b$data$results
  d <- d[!is.na(d$value), , drop = FALSE]
  labels <- txt$labels %||% list()
  cats <- levels(d$category)
  shown_cats <- vapply(cats, function(cn) {
    mid <- names(b$labels)[b$labels == cn][1]
    labels[[mid]] %||% cn
  }, "")
  d$category <- factor(shown_cats[match(as.character(d$category), cats)], levels = shown_cats)
  by_entity <- grepl("parents", b$compare)
  d$row <- if (by_entity) d$label else d$period_label
  row_levels <- if (by_entity) rev(unique(d$label)) else rev(unique(d$period_label[order(d$period_end)]))
  d$row <- factor(d$row, levels = row_levels)
  if (identical(b$viz, "bar")) return(composition_bars(d, txt, th, by_entity))
  cols <- category_colors(th, shown_cats)
  fam <- chart_font(th)
  # Categories run left to right in catalog order (first category at the left), the same
  # order as the legend, in every period and area.
  d$shown <- ifelse(d$value >= 6, paste0(round(d$value), "%"), "")
  ggplot(d, aes(x = value, y = row, fill = category)) +
    geom_col(width = 0.65, color = th$color_background, linewidth = 0.3, position = position_stack(reverse = TRUE)) +
    geom_text(aes(label = shown), position = position_stack(vjust = 0.5, reverse = TRUE),
              size = 2.8, color = "white", family = fam) +
    scale_fill_manual(values = cols, name = txt$legend_title, labels = wrap_label) +
    scale_x_continuous(labels = function(x) paste0(x, "%"), expand = expansion(mult = c(0, 0.01))) +
    labs(x = txt$y_label, y = NULL) +
    guides(fill = legend_columns(shown_cats)) +
    gr_ggtheme(th) + theme(panel.grid.major.y = element_blank())
}

# Legend entries wrap after about 28 characters, so two columns always fit the plot width.
wrap_label <- function(x) vapply(x, function(s) paste(strwrap(s, 28), collapse = "\n"), "", USE.NAMES = FALSE)
legend_columns <- function(labels) guide_legend(ncol = if (max(nchar(labels)) > 18) 2 else 3, byrow = TRUE)

# Compositions with more categories than the palette has colors (viz = "bar"): one bar per
# category for each area (or period), colored as the areas are in other charts; categories
# keep catalog order from the top.
composition_bars <- function(d, txt, th, by_entity) {
  groups <- rev(levels(d$row))
  cols <- if (by_entity) {
    ids <- d$entity_id[match(groups, as.character(d$row))]
    entity_colors(th, groups, ifelse(grepl("^bm", ids), "benchmark", "study"))
  } else stats::setNames(grDevices::colorRampPalette(c(th$color_muted, th$color_accent))(length(groups)), groups)
  d$category <- factor(d$category, levels = rev(levels(d$category)))
  ggplot(d, aes(x = value, y = category, fill = row)) +
    geom_col(position = position_dodge2(padding = 0.15), width = 0.8) +
    scale_fill_manual(values = cols, breaks = groups, name = txt$legend_title, labels = wrap_label) +
    scale_x_continuous(labels = function(x) paste0(x, "%"), expand = expansion(mult = c(0, 0.05))) +
    labs(x = txt$y_label, y = NULL) +
    guides(fill = legend_columns(groups)) +
    gr_ggtheme(th) + theme(panel.grid.major.y = element_blank())
}

render_block_distribution <- function(b, txt, th) {
  d <- b$data$results
  ents <- unique(d[, c("label", "entity_id")])
  cols <- entity_colors(th, ents$label, ifelse(ents$entity_id == "study", "study", "benchmark"))
  ggplot(d, aes(x = bin, y = share, fill = label)) +
    geom_col(position = position_dodge(width = 0.8), width = 0.75) +
    geom_errorbar(aes(ymin = pmax(0, share - moe), ymax = share + moe), position = position_dodge(width = 0.8),
                  width = 0.25, linewidth = 0.3, color = th$color_muted) +
    scale_fill_manual(values = cols, name = txt$legend_title) +
    scale_y_continuous(labels = function(x) paste0(x, "%"), expand = expansion(mult = c(0, 0.05))) +
    labs(x = txt$x_label, y = txt$y_label) +
    gr_ggtheme(th) + theme(axis.text.x = element_text(angle = 40, hjust = 1, size = rel(0.8)))
}

# Facts table as a Markdown pipe table (renders in HTML and PDF with the document theme).
render_block_facts <- function(b, txt, th) {
  d <- b$data$results
  et <- b$data$entities
  # A comparison area with no value in any row (e.g. a region, for a source that publishes
  # none) gets no column; the study area's column is always shown.
  empty <- vapply(et$entity_id, function(id) all(is.na(d$value[d$entity_id == id])), TRUE)
  et <- et[!empty | et$role == "study", , drop = FALSE]
  labels <- txt$labels %||% list()
  rows <- lapply(b$data$metrics, function(m) {
    x <- d[d$metric_id == m, , drop = FALSE]
    cells <- vapply(et$entity_id, function(id) {
      r <- x[x$entity_id == id, , drop = FALSE]
      if (!nrow(r)) return("")
      if (is.na(r$value)) return("–")
      is_area <- et$role[et$entity_id == id] == "study"
      moe <- if (is_area && !is.na(r$moe) && r$moe > 0) paste0(" (", r$moe_shown, ")") else ""
      paste0(r$shown, moe, r$flag)
    }, "")
    c(labels[[m]] %||% metric_doc(m)$label, cells, x$period_label[1])
  })
  tab <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  names(tab) <- c(txt$indicator_header %||% "Indicator", et$label, txt$period_header %||% "Period")
  knitr::kable(tab, format = "pipe", align = c("l", rep("r", nrow(et)), "l"))
}

# Event lists are written directly into the .qmd (so statements are editable inline);
# nothing to draw here.
render_block_history <- function(b, txt, th) invisible(NULL)
render_block_text <- function(b, txt, th) invisible(NULL)
