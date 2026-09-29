# Blocks: what each block kind computes. A block kind <k> is implemented by
# compute_block_<k>(row, ctx, settings, opts) returning a list with
#   data      data frames the renderer needs (stored in the report snapshot)
#   values    named character values for {placeholders} in the block's text
#   fields    the block's editable text fields (e.g. "title", "prose", "caption")
#   sources   provenance rows (source_id, detail) for the sources appendix
#   unavailable  rows explaining values that could not be shown (and why)
# and a renderer render_block_<k>(block, text, theme) in charts.R / maps.R. Adding a kind means
# writing those two functions; nothing else dispatches on kind names.

# Settings keys may be overridden per block via the manifest `options` column; any other
# option (e.g. index=first) is a block option.
split_block_options <- function(options_text) {
  opts <- parse_options(options_text)
  known <- settings_table()$key
  list(settings = opts[names(opts) %in% known], block = opts[!names(opts) %in% known])
}

compute_block <- function(row, ctx) {
  fn <- get0(paste0("compute_block_", row$kind), mode = "function")
  if (is.null(fn)) stop("No compute function for block kind '", row$kind, "'.", call. = FALSE)
  o <- split_block_options(row$options)
  settings <- resolve_settings(ctx$report_id, ctx$profile, o$settings)
  b <- fn(row, ctx, settings, o$block)
  b$id <- row$id
  b$kind <- row$kind
  b$compare <- b$compare_override %||% row$compare
  b$viz <- row$viz
  b$section <- row$section
  b$settings_used <- settings
  b$values <- c(b$values %||% list(), list(block_id = row$id))
  b
}

# ---- Shared helpers --------------------------------------------------------------------

entity_table <- function(ctx) {
  data.frame(entity_id = vapply(ctx$entities, `[[`, "", "id"),
             label = vapply(ctx$entities, `[[`, "", "short"),
             full_label = vapply(ctx$entities, `[[`, "", "label"),
             role = vapply(ctx$entities, `[[`, "", "role"),
             relation = vapply(ctx$entities, function(e) e$relation %||% "", ""),
             study_share = vapply(ctx$entities, function(e) as.numeric(e$study_share %||% NA), 0),
             contains_study = vapply(ctx$entities, function(e) isTRUE(e$contains_study), TRUE),
             stringsAsFactors = FALSE)
}

# A phrase template (content/text.csv "@phrase.<name>") filled with values.
phrase <- function(ctx, name, values) {
  t <- resolve_text(ctx$text_records, paste0("@phrase.", name), NULL, ctx$report_id, ctx$profile)
  fill_template(t$text, values)
}

join_list <- function(items, ctx) {
  items <- items[nzchar(items)]
  n <- length(items)
  if (n <= 1) return(if (n) items else "")
  comma <- if (n > 2) "," else ""   # serial comma for three or more items
  paste0(paste(items[-n], collapse = ", "), comma, " ", phrase(ctx, "and", list()), " ", items[n])
}

# How an entity is named in running text: "the state of Indiana", "the Midwest Region",
# "the United States" (phrases are editable), so lists like "Lake County, Indiana, ..." are
# never ambiguous. Charts use the short label.
entity_text_label <- function(e, ctx) {
  p <- e$pieces
  if (nrow(p) == 1 && p$type %in% c("state", "region", "division", "nation")) {
    return(phrase(ctx, paste0("name_", p$type), list(name = e$short)))
  }
  e$short
}

metric_units <- function(metric_id) metric_doc(metric_id)$units

# Metric wording: a report/profile/default record "label.<metric>" or "sentence.<metric>"
# in content/text.csv wins over the catalog's label / sentence_label.
metric_text <- function(ctx, metric_id, what = c("label", "sentence")) {
  what <- match.arg(what)
  t <- resolve_text(ctx$text_records, paste0(what, ".", metric_id), NULL, ctx$report_id, ctx$profile)
  if (!identical(t$scope, "none")) return(t$text)
  doc <- metric_doc(metric_id)
  if (what == "label") return(doc$label)
  if (!is_blank(doc$sentence_label)) doc$sentence_label else lower_first(doc$label)
}

source_row <- function(source_id, detail) data.frame(source_id = source_id, detail = detail, stringsAsFactors = FALSE)

# Provenance rows for the sources appendix: each metric's source and table or series.
metric_sources <- function(metrics) {
  do.call(rbind, lapply(metrics, function(m) source_row(recipe_for(m)$source_id, metric_doc(m)$table_or_series)))
}

# Reasons for missing values, for the report's availability appendix. Rows are collapsed:
# one row per measure and reason, naming the areas ("All areas" when every area in the block
# is affected) and the periods (as a range) it applies to.
block_unavailable_rows <- function(res, block_id, ctx) {
  shown <- c("ok", "controlled", "open_interval", "unreliable", "moe_unavailable", "imputed")
  bad <- res[!res$status %in% shown, , drop = FALSE]
  if (!nrow(bad)) return(NULL)
  et <- entity_table(ctx)
  n_ent <- length(unique(res$entity_id))
  every <- ave(bad$entity_id, bad$metric_id, bad$period, FUN = function(x) length(unique(x))) == n_ent
  table_missing <- grepl("^not available for this period: no published data for", bad$method) & every
  bad$reason <- ifelse(table_missing, "not published for this period (the source table is not available in this release)",
                       bad$method)
  bad$entity <- et$full_label[match(bad$entity_id, et$entity_id)]
  # First one row per measure, period, status and reason, naming the areas affected...
  by_period <- split(bad, paste(bad$metric_id, bad$period, bad$status, bad$reason))
  rows <- do.call(rbind, lapply(by_period, function(g) {
    all_areas <- length(unique(g$entity_id)) == n_ent && n_ent > 1
    data.frame(metric_id = g$metric_id[1], period = g$period_label[1], period_end = g$period_end[1],
               status = g$status[1], reason = g$reason[1],
               entity = if (all_areas) "All areas" else paste(g$entity, collapse = "; "), stringsAsFactors = FALSE)
  }))
  # ...then one row per measure, reason and areas, with the periods (a range when more than two).
  groups <- split(rows, paste(rows$metric_id, rows$status, rows$reason, rows$entity))
  do.call(rbind, lapply(groups, function(g) {
    g <- g[order(g$period_end), ]
    n <- nrow(g)
    periods <- if (n > 2) paste0(g$period[1], " to ", g$period[n], " (", n, " periods)") else paste(g$period, collapse = ", ")
    data.frame(block_id = block_id, metric_id = g$metric_id[1], entity = g$entity[1], period = periods,
               status = g$status[1], reason = g$reason[1], stringsAsFactors = FALSE)
  }))
}

# Should levels of the study area and a benchmark be compared? Not for counts (areas of
# different sizes) and not for indexes (their levels only express growth since the base
# year); those are compared by growth over the same span instead.
comparable_stat <- function(metric_id) {
  recipe_for(metric_id)$stat_type %in% c("share", "ratio", "median", "value") && metric_units(metric_id) != "index"
}

# Part-whole dependence adjustment applies to weighted-mean statistics only (see stats.R).
dependence_share <- function(metric_id, bm, settings) {
  if (!as_flag(settings$dependence_adjustment, TRUE)) return(0)
  if (!recipe_for(metric_id)$stat_type %in% c("share", "ratio")) return(0)
  if (!isTRUE(bm$contains_study)) return(0)
  share <- bm$study_share
  if (is.na(share) || share < 0.01) 0 else share
}

# ---- metric: one concept over time and/or against benchmarks ----------------------------

compute_block_metric <- function(row, ctx, settings, opts) {
  metrics <- split_list(row$metrics)
  sources <- vapply(metrics, function(m) recipe_for(m)$source_id, "")
  use_parents <- grepl("parents", row$compare)
  use_time <- grepl("time", row$compare)
  entities <- if (use_parents) ctx$entities else ctx$studies
  focus <- ctx$study
  # Context: if no metric's source publishes the study area's geography type (BEA and FHFA
  # publish counties, not cities), show the benchmarks the first source does publish, starting
  # with the nearest (e.g. the county containing the city), clearly labeled as context.
  prov1 <- get_provider(sources[1])
  publishes_study <- vapply(sources, function(s) all(ctx$study$pieces$type %in% get_provider(s)$geo_types), TRUE)
  context <- NULL
  if (!any(publishes_study)) {
    context <- Filter(function(e) e$role == "benchmark" && all(e$pieces$type %in% prov1$geo_types), ctx$entities)
    if (length(context)) {
      entities <- if (use_parents) context else context[1]
      focus <- context[[1]]
    }
  }
  # A relative view compares areas within the same year, which needs no price adjustment, so
  # it uses nominal dollars (and keeps years the price index does not cover).
  relative <- identical(opts$index, "relative")
  res <- do.call(rbind, lapply(metrics, function(m) {
    compute_metric(m, entities, settings, block_periods(m, settings, opts, use_time), constant_dollars = !relative)
  }))
  et <- entity_table(ctx)
  res$label <- et$label[match(res$entity_id, et$entity_id)]
  res$role <- et$role[match(res$entity_id, et$entity_id)]
  # The text describes the first metric with data for the described area (a long-history
  # block may start with a series that a city lacks).
  described <- vapply(metrics, function(m) any(res$metric_id == m & res$entity_id == focus$id & !is.na(res$value)), TRUE)
  primary <- if (any(described)) metrics[described][1] else metrics[1]
  units <- metric_units(primary)
  indexed <- add_index(res, opts$index, entities, primary, focus)
  res <- indexed$res
  values <- if (isTRUE(ctx$compare) && is.null(context)) compare_values(res, primary, ctx, settings) else
    metric_values(res, primary, ctx, settings, focus)
  values$index_base <- indexed$base
  values <- utils::modifyList(values, observed_values(res, focus, units, ctx$theme))
  if (length(context)) {
    values$context_note <- phrase(ctx, "context_note", list(
      metric_label = values$metric_label, area_short = ctx$area$short, focus = focus$short,
      relation = focus$relation, source_levels = prov1$availability_note %||% ""))
    values$summary_sentence <- paste(values$context_note, values$summary_sentence)
  }
  has_data <- any(!is.na(res$value[res$entity_id %in% c(focus$id, vapply(ctx$studies, `[[`, "", "id"))]))
  list(data = list(results = res, units = units, metrics = metrics,
                   period_kind = vapply(metrics, function(m) get_provider(recipe_for(m)$source_id)$period_kind, ""),
                   events = chart_events(ctx, primary, res, sources)),
       values = values,
       fields = if (has_data) c("title", "prose", "caption", "alt", "x_label", "y_label", "legend_title", "note", "source_note")
                else c("title", "prose", "source_note"),
       sources = metric_sources(metrics),
       unavailable = block_unavailable_rows(res, row$id, ctx),
       figure = has_data)
}

# Periods a block shows for one metric: the source's periods from `history_start` on (ACS
# periods are always kept: each is a 5-year span), limited by the block's `periods` option,
# and only the latest one when the block does not show change over time.
block_periods <- function(metric_id, settings, opts, use_time) {
  recipe <- recipe_for(metric_id)
  periods <- metric_periods(recipe, settings)
  multiyear <- get_provider(recipe$source_id)$period_kind == "multiyear"
  periods <- periods[as.integer(periods) >= as.integer(settings$history_start %||% 0) | multiyear]
  if (!is.null(opts$periods)) periods <- intersect(periods, split_list(opts$periods, ","))
  if (use_time) periods else utils::tail(periods, 1)
}

# Index views (block option `index`). "relative": each area as a percentage of the widest
# benchmark (usually the nation) in the same year; that benchmark is the 100 line, so its own
# series is not drawn. "first": each area relative to its value in the first period the
# described area has data for, so areas of different sizes share one scale. Returns the
# results and the label of the base period.
add_index <- function(res, index, entities, primary, focus) {
  base <- ""
  if (identical(index, "relative")) {
    ref_id <- entities[[length(entities)]]$id
    ref <- res[res$entity_id == ref_id, , drop = FALSE]
    res$index_value <- 100 * res$value / ref$value[match(paste(res$metric_id, res$period), paste(ref$metric_id, ref$period))]
    res$index_value[res$entity_id == ref_id] <- NA
  }
  if (identical(index, "first")) {
    mine <- res[res$metric_id == primary & res$entity_id == focus$id & !is.na(res$value), , drop = FALSE]
    mine <- mine[order(mine$period_end), , drop = FALSE]
    first <- res[res$period == mine$period[1], , drop = FALSE]
    res$index_value <- 100 * res$value / first$value[match(paste(res$metric_id, res$entity_id),
                                                             paste(first$metric_id, first$entity_id))]
    base <- mine$period_label[1] %||% ""
  }
  list(res = res, base = base)
}

# What the chart shows for the described area across all its series: the whole plotted span
# (captions name it) and the first and last observations.
observed_values <- function(res, focus, units, th) {
  d <- res[res$entity_id == focus$id & !is.na(res$value), , drop = FALSE]
  d <- d[order(d$period_end), , drop = FALSE]
  n <- nrow(d)
  out <- if (n > 1) list(period_span = paste0(d$period_label[1], " to ", d$period_label[n])) else list()
  c(out, list(first_observed = if (n) fmt_value(d$value[1], units, th, d$bound[1]) else "",
              first_observed_period = if (n) d$period_label[1] else "",
              last_observed = if (n) fmt_value(d$value[n], units, th, d$bound[n]) else "",
              last_observed_period = if (n) d$period_label[n] else ""))
}

# Values for a metric block's text, computed from the same results the chart shows. The
# statistical logic decides which phrase applies (up, down, not significant, higher than a
# benchmark...); the wording of every phrase lives in content/text.csv.
metric_values <- function(res, metric_id, ctx, settings, focus = ctx$study) {
  doc <- metric_doc(metric_id)
  units <- doc$units
  th <- ctx$theme
  prov <- get_provider(recipe_for(metric_id)$source_id)
  label <- metric_text(ctx, metric_id, "label")
  sentence <- metric_text(ctx, metric_id, "sentence")
  several <- length(unique(res$entity_id)) > 1
  v <- list(metric_label = label, metric_sentence = sentence, metric_label_lower = sentence,
            units_label = units_label(doc, res, label), universe = doc$universe,
            definition = doc$definition, dollar_phrase = dollar_phrase(res, ctx),
            source_short = paste0(prov$name, ", ", doc$table_or_series),
            x_axis_label = phrase(ctx, if (identical(prov$period_kind, "multiyear")) "x_multiyear" else "x_year", list()),
            area_and_benchmarks = if (several) phrase(ctx, "area_and_benchmarks", list(area = focus$label)) else focus$label,
            area_short = focus$short, context_note = "", summary_sentence = "", change_sentence = "",
            benchmark_sentence = "", relation_sentence = "", turning_sentence = "", growth_sentence = "",
            method_note = method_note(res, metric_id, ctx, settings))
  # Every placeholder a template may use exists even when there are no data.
  v[c("latest", "latest_moe", "latest_period", "first", "first_period", "period_span", "moe_phrase",
      "reliability_phrase", "change", "annual_rate", "series_note")] <- ""
  mine <- res[res$metric_id == metric_id & res$entity_id == focus$id & !is.na(res$value), , drop = FALSE]
  mine <- mine[order(mine$period_end), , drop = FALSE]
  if (!nrow(mine)) {
    reasons <- unique(res$method[res$entity_id == focus$id & !is.na(res$method) & nzchar(res$method)])
    v$summary_sentence <- phrase(ctx, "no_data", list(metric_sentence = sentence, area = focus$short,
                                                        reason = if (length(reasons)) reasons[1] else ""))
    return(v)
  }
  last <- mine[nrow(mine), ]
  # Change is described only within one series (e.g. one estimates vintage or census counts);
  # points from series with different boundaries or methods are compared only in the chart.
  same <- mine[mine$series == last$series, , drop = FALSE]
  first <- same[1, ]
  v$latest <- fmt_value(last$value, units, th, last$bound)
  v$latest_moe <- fmt_moe(last$moe, units, th)
  v$latest_period <- last$period_label
  v$first <- fmt_value(first$value, units, th, first$bound)
  v$first_period <- first$period_label
  v$period_span <- if (nrow(mine) > 1) paste0(mine$period_label[1], " to ", last$period_label) else last$period_label
  v$moe_phrase <- if (!is.na(last$moe) && last$moe > 0) phrase(ctx, "moe", list(latest_moe = v$latest_moe)) else ""
  v$reliability_phrase <- if (identical(last$reliability, "unreliable")) phrase(ctx, "unreliable", list()) else ""
  v$summary_sentence <- phrase(ctx, "summary", v)
  # Survey estimates and model-based estimates with published intervals (SAIPE, SAHIE) are called
  # higher or lower only after a significance test; one without a margin of error (e.g. a median
  # interpolated for a combined area) is described as untested. Census counts and administrative
  # series have no sampling error to test.
  survey <- doc$uncertainty %in% c("acs_moe", "survey_se", "model_interval")
  is_count <- recipe_for(metric_id)$stat_type == "count"
  if (nrow(same) > 1) {
    series_note <- if (nrow(same) < nrow(mine)) phrase(ctx, "within_series", list(series = last$series)) else ""
    nominal <- unit_kind(units) == "dollars" && all(is.na(res$dollar_year))
    v <- change_values(v, ctx, mine, first, last, units, survey, is_count, nominal, series_note)
  }
  bms <- Filter(function(e) e$role == "benchmark" && e$id != focus$id && any(res$entity_id == e$id), ctx$entities)
  if (length(bms) && nrow(mine) > 1 && (is_count || unit_kind(units) == "index")) {
    v$growth_sentence <- growth_sentence(ctx, res, metric_id, bms, first, last, v, units)
  }
  if (length(bms) && comparable_stat(metric_id)) {
    v$benchmark_sentence <- benchmark_sentence(ctx, res, metric_id, bms, focus, last, units, survey, settings)
    v$relation_sentence <- relation_sentence(ctx, res, metric_id, bms, focus, mine, first, last, units)
  }
  v
}

# Change over time within one series: tested for survey estimates (overlapping ACS periods
# adjusted), "untested" for a survey estimate without a margin of error, and taken at face
# value for census counts and administrative or model-based series. Also the annual growth
# rate of counts and the peak of series without sampling error.
change_values <- function(v, ctx, mine, first, last, units, survey, is_count, nominal, series_note) {
  if (nominal) {
    v$change_sentence <- phrase(ctx, "nominal_only", list())
    return(v)
  }
  th <- ctx$theme
  v$change <- fmt_change(last$value, first$value, units, th)$text
  moes <- c(first$moe, last$moe)
  overlap <- period_overlap(first$period_start, first$period_end, last$period_start, last$period_end)
  test <- diff_test(last$value, last$moe, first$value, first$moe, overlap = overlap)
  testable <- survey && !anyNA(moes) && !all(moes %in% 0)
  dir <- if (survey && anyNA(moes)) "untested" else
    change_direction(last$value - first$value, if (testable) test$significant else NA)
  wording <- c(up = "change_up", down = "change_down", not_significant = "change_ns", flat = "change_flat",
               untested = "change_untested")
  v$change_sentence <- trimws(paste(if (dir %in% names(wording)) phrase(ctx, wording[[dir]], v) else "", series_note))
  years <- last$period_end - first$period_end
  if (is_count && years > 0) {
    v$annual_rate <- paste0(formatC(100 * annual_rate(first$value, last$value, years), format = "f", digits = 1), "%")
  }
  tp <- turning_points(mine$period_label, mine$value)
  if (!is.na(tp$peak) && all(mine$moe %in% 0)) {
    v$turning_sentence <- phrase(ctx, "peak", list(peak_period = tp$peak, peak_value = fmt_value(tp$peak_value, units, th)))
  }
  v
}

# Counts and indexes: growth in each benchmark over the same span (their levels would compare
# areas of different sizes, or index levels that only express growth since the base year).
growth_sentence <- function(ctx, res, metric_id, bms, first, last, v, units) {
  items <- character()
  for (bm in bms) {
    b <- res[res$metric_id == metric_id & res$entity_id == bm$id & res$period %in% c(first$period, last$period) &
               !is.na(res$value), , drop = FALSE]
    if (nrow(b) != 2) next
    b <- b[order(b$period_end), ]
    items <- c(items, paste0(fmt_change(b$value[2], b$value[1], units, ctx$theme)$text, " in ", entity_text_label(bm, ctx)))
  }
  if (!length(items)) return("")
  phrase(ctx, "growth_compare", list(first_period = v$first_period, latest_period = v$latest_period,
                                     change = v$change %||% "", list = join_list(items, ctx), area_short = v$area_short))
}

# Levels against each benchmark in the latest period. Survey estimates are tested (with the
# part-whole adjustment when a benchmark contains the study area); without margins of error a
# survey difference is "untested", and other data are compared at face value ("about the
# same" when both round to the same figure).
benchmark_sentence <- function(ctx, res, metric_id, bms, focus, last, units, survey, settings) {
  th <- ctx$theme
  parts <- list(higher = character(), lower = character(), ns = character(), same = character(), untested = character())
  for (bm in bms) {
    b <- res[res$metric_id == metric_id & res$entity_id == bm$id & res$period == last$period, , drop = FALSE]
    if (!nrow(b) || is.na(b$value)) next
    share <- if (identical(focus$id, "study")) dependence_share(metric_id, bm, settings) else 0
    t <- diff_test(last$value, last$moe, b$value, b$moe, part_share = share)
    testable <- !is.na(last$moe) && !is.na(b$moe)
    key <- if (testable && !t$significant) "ns" else
      if (!testable && survey) "untested" else
        if (!testable && fmt_value(last$value, units, th) == fmt_value(b$value, units, th)) "same" else
          if (last$value > b$value) "higher" else "lower"
    parts[[key]] <- c(parts[[key]], paste0(entity_text_label(bm, ctx), " (", fmt_value(b$value, units, th, b$bound), ")"))
  }
  clauses <- unlist(lapply(c("higher", "lower", "ns", "same"), function(k) {
    if (length(parts[[k]])) phrase(ctx, paste0("bench_", k), list(list = join_list(parts[[k]], ctx)))
  }))
  out <- ""
  if (length(clauses)) {
    out <- phrase(ctx, "bench_sentence", list(parts = join_list(clauses, ctx), latest_period = last$period_label))
  }
  if (length(parts$untested)) {
    out <- trimws(paste(out, phrase(ctx, "bench_untested", list(list = join_list(parts$untested, ctx)))))
  }
  out
}

# The area's position against the widest benchmark that contains it (usually the nation) in the
# first and latest periods: the gap in percentage points for percentages, a ratio otherwise.
# Same-year comparisons need no price adjustment. The change in the gap is not tested, so the
# wording stays neutral (no "widened" or "narrowed").
relation_sentence <- function(ctx, res, metric_id, bms, focus, mine, first, last, units) {
  containing <- Filter(function(e) isTRUE(e$contains_study), bms)
  if (!length(containing) || nrow(mine) < 2) return("")
  ref <- containing[[length(containing)]]
  rb <- res[res$metric_id == metric_id & res$entity_id == ref$id & !is.na(res$value) &
              res$period %in% c(first$period, last$period), , drop = FALSE]
  if (nrow(rb) != 2) return("")
  rb <- rb[order(rb$period_end), ]
  common <- list(benchmark = entity_text_label(ref, ctx), area_short = focus$short,
                 first_period = first$period_label, latest_period = last$period_label)
  if (unit_kind(units) == "percent") {
    gap <- c(first$value - rb$value[1], last$value - rb$value[2])
    side <- function(g) phrase(ctx, if (g >= 0) "side_above" else "side_below", list())
    points <- formatC(abs(gap), format = "f", digits = 1)
    return(phrase(ctx, "gap", c(common, list(gap_first = points[1], side_first = side(gap[1]),
                                             gap_latest = points[2], side_latest = side(gap[2])))))
  }
  if (rb$value[1] <= 0 || rb$value[2] <= 0) return("")
  phrase(ctx, "ratio_change", c(common, list(ratio_first = paste0(round(100 * first$value / rb$value[1]), "%"),
                                             ratio_latest = paste0(round(100 * last$value / rb$value[2]), "%"))))
}

# Compare mode: list every area's latest value and whether it differs significantly from the
# first shared benchmark. Areas are not ranked against each other (pairwise differences are
# not tested), so the text never says one area is "higher" than another.
compare_values <- function(res, metric_id, ctx, settings) {
  th <- ctx$theme
  units <- metric_units(metric_id)
  v <- metric_values(res, metric_id, ctx, settings, ctx$studies[[1]])
  if (!any(res$metric_id == metric_id & !is.na(res$value))) return(v)
  latest_p <- max(res$period_end[res$metric_id == metric_id & !is.na(res$value)], na.rm = TRUE)
  at <- res[res$metric_id == metric_id & res$period_end == latest_p, , drop = FALSE]
  bm <- Filter(function(e) e$role == "benchmark", ctx$entities)
  ref <- if (length(bm)) at[at$entity_id == bm[[1]]$id & !is.na(at$value), , drop = FALSE] else at[0, ]
  # Levels are compared with the benchmark only where that is meaningful (not counts or indexes).
  use_ref <- nrow(ref) > 0 && comparable_stat(metric_id)
  items <- vapply(ctx$studies, function(s) {
    r <- at[at$entity_id == s$id, , drop = FALSE]
    if (!nrow(r) || is.na(r$value)) return(paste0(s$short, " (not available)"))
    flag <- ""
    if (use_ref && !is.na(r$moe) && !is.na(ref$moe)) {
      t <- diff_test(r$value, r$moe, ref$value, ref$moe)
      flag <- phrase(ctx, if (!t$significant) "cmp_ns" else if (r$value > ref$value) "cmp_above" else "cmp_below", list())
    }
    paste0(s$short, " ", fmt_value(r$value, units, th, r$bound), flag)
  }, "")
  v$summary_sentence <- phrase(ctx, "compare_summary", list(metric_sentence = metric_text(ctx, metric_id, "sentence"),
                                                            latest_period = at$period_label[1], list = join_list(items, ctx)))
  if (use_ref) {
    v$summary_sentence <- paste(v$summary_sentence, phrase(ctx, "compare_benchmark", list(
      benchmark = entity_text_label(bm[[1]], ctx), benchmark_value = fmt_value(ref$value, units, th, ref$bound))))
  }
  v$change_sentence <- ""
  v$benchmark_sentence <- ""
  v$relation_sentence <- ""
  v$turning_sentence <- ""
  v$growth_sentence <- ""
  v$area_and_benchmarks <- ctx$area$label
  v
}

lower_first <- function(x) paste0(tolower(substr(x, 1, 1)), substr(x, 2, nchar(x)))

units_label <- function(doc, res, label = doc$label) {
  kind <- unit_kind(doc$units)
  if (kind == "dollars") {
    yr <- stats::na.omit(res$dollar_year)[1]
    return(if (!is.na(yr)) paste0(label, " (", yr, " dollars)") else paste0(label, " (nominal dollars)"))
  }
  if (kind == "percent") return(paste0(label, " (%)"))
  label
}

dollar_phrase <- function(res, ctx) {
  yr <- stats::na.omit(res$dollar_year)[1]
  if (is.na(yr)) return("")
  phrase(ctx, "dollars", list(dollar_year = yr, price_index = price_index_label(ctx$settings$price_index)))
}

# Method notes shown under a figure: period type, uncertainty and known breaks.
method_note <- function(res, metric_id, ctx, settings) {
  doc <- metric_doc(metric_id)
  prov <- get_provider(recipe_for(metric_id)$source_id)
  notes <- character()
  if (identical(prov$period_kind, "multiyear")) notes <- c(notes, phrase(ctx, "note_multiyear", list()))
  # A city's values over time follow its boundaries at each date, so annexations are part of change.
  legal_area <- any(ctx$study$pieces$type %in% c("place", "place_part", "cousub")) &&
    length(unique(res$period[res$entity_id == "study"])) > 1
  if (legal_area) notes <- c(notes, phrase(ctx, "note_legal_area", list()))
  if (any(grepl("interpolated", res$method))) notes <- c(notes, phrase(ctx, "note_interpolated", list()))
  if (any(res$status == "unreliable")) {
    notes <- c(notes, phrase(ctx, "note_unreliable", list(cv = settings$cv_unreliable)))
  }
  if (any(res$status == "imputed")) notes <- c(notes, phrase(ctx, "note_imputed", list()))
  if (nzchar(doc$breaks)) notes <- c(notes, doc$breaks)
  paste(notes, collapse = " ")
}

# History events drawn on a chart: events for the study area, its parents or the nation that
# concern the metric's catalog subtopic (history_events.csv `subtopics`), apply to one of the
# plotted sources (`sources`; blank means any) and fall inside the plotted years. Definitional
# and boundary changes are drawn as breaks; national events that span a period (recessions)
# are shaded. Other events appear only in the history list.
chart_events <- function(ctx, metric_id, res, sources) {
  ev <- ctx$events
  if (is.null(ev) || !nrow(ev) || !nrow(res)) return(NULL)
  topic <- metric_doc(metric_id)$subtopic_id
  ev <- ev[vapply(ev$subtopics, function(s) topic %in% split_list(s), TRUE) &
             vapply(ev$sources, function(s) is_blank(s) || any(sources %in% split_list(s)), TRUE), , drop = FALSE]
  ev$draw <- ifelse(ev$evidence_type %in% c("definitional_change", "boundary_change"), "break",
                    ifelse(ev$geo_scope == "nation" & nzchar(ev$end_date), "shade", ""))
  ev$year <- as.integer(substr(ev$start_date, 1, 4))
  ev$end_year <- suppressWarnings(as.integer(substr(ev$end_date, 1, 4)))
  ev$end_year[is.na(ev$end_year)] <- ev$year[is.na(ev$end_year)]
  yrs <- range(c(res$period_start, res$period_end), na.rm = TRUE)
  ev <- ev[nzchar(ev$draw) & !is.na(ev$year) & ev$year >= yrs[1] & ev$year <= yrs[2], , drop = FALSE]
  if (!nrow(ev)) return(NULL)
  ev[, c("event_id", "year", "end_year", "label", "draw")]
}

# ---- composition: shares of categories over time or across areas -------------------------

compute_block_composition <- function(row, ctx, settings, opts) {
  group <- sub("^group:", "", row$metrics)
  rec <- recipes()
  members <- rec[rec$group == group, , drop = FALSE]
  if (!nrow(members)) stop("Block '", row$id, "': no metrics in group '", group, "'.", call. = FALSE)
  use_parents <- grepl("parents", row$compare) || isTRUE(ctx$compare)
  entities <- if (isTRUE(ctx$compare)) ctx$studies else if (use_parents) ctx$entities else ctx$studies
  res <- do.call(rbind, lapply(members$metric_id, function(m) {
    recipe <- recipe_for(m)
    periods <- metric_periods(recipe, settings)
    if (!is.null(opts$periods)) periods <- intersect(periods, split_list(opts$periods, ","))
    if (use_parents || identical(opts$latest_only, "true")) periods <- utils::tail(periods, 1)
    r <- compute_metric(m, entities, settings, periods)
    r$category <- recipe$category
    r
  }))
  res$category <- factor(res$category, levels = members$category)
  et <- entity_table(ctx)
  res$label <- et$label[match(res$entity_id, et$entity_id)]
  study <- res[res$entity_id == ctx$study$id & !is.na(res$value), , drop = FALSE]
  if (!nrow(study)) {
    reasons <- unique(res$method[nzchar(res$method)])
    no_data <- phrase(ctx, "no_data", list(metric_sentence = lower_first(members$group[1]), area = ctx$area$short,
                                           reason = reasons[1] %||% ""))
    return(list(data = list(results = res, categories = members$category), figure = FALSE,
                values = list(summary_sentence = no_data, change_sentence = "", method_note = "",
                              area_short = ctx$area$short, latest_period = "", largest_category = "", largest_share = ""),
                fields = c("title", "prose", "source_note"),
                sources = source_row(members$source_id[1], metric_doc(members$metric_id[1])$table_or_series),
                unavailable = block_unavailable_rows(res, row$id, ctx)))
  }
  latest_p <- max(study$period_end, na.rm = TRUE)
  now <- study[study$period_end == latest_p, , drop = FALSE]
  top <- now[which.max(now$value), ]
  th <- ctx$theme
  # Categories share one source table, so their documented breaks repeat; keep the first.
  breaks <- unique(stats::na.omit(unlist(lapply(members$metric_id, function(m) metric_doc(m)$breaks))))
  v <- list(largest_category = as.character(top$category), largest_share = fmt_value(top$value, "percent", th),
            latest_period = if (nrow(now)) now$period_label[1] else "",
            group_label = members$group[1], summary_sentence = "", change_sentence = "",
            method_note = breaks[1] %||% "", area_short = ctx$area$short)
  v$summary_sentence <- phrase(ctx, "composition_summary", c(v, list(area = ctx$area$short)))
  if (isTRUE(ctx$compare)) {
    # Each compared area's largest group; the areas are not ranked against each other.
    tops <- vapply(ctx$studies, function(s) {
      x <- res[res$entity_id == s$id & res$period_end == latest_p & !is.na(res$value), , drop = FALSE]
      if (!nrow(x)) return(paste0(s$short, " (not available)"))
      x <- x[which.max(x$value), ]
      paste0(x$category, " in ", s$short, " (", fmt_value(x$value, "percent", th), ")")
    }, "")
    v$summary_sentence <- phrase(ctx, "composition_compare",
                                 list(latest_period = v$latest_period, list = join_list(tops, ctx)))
  }
  firsts <- study[study$period_end == min(study$period_end), , drop = FALSE]
  if (nrow(firsts) && min(study$period_end) < latest_p) {
    moves <- merge(firsts[, c("category", "value", "moe", "period_label", "period_start", "period_end")],
                   now[, c("category", "value", "moe", "period_label", "period_start", "period_end")],
                   by = "category", suffixes = c("_1", "_2"))
    moves$diff <- moves$value_2 - moves$value_1
    t <- diff_test(moves$value_2, moves$moe_2, moves$value_1, moves$moe_1)
    moves$sig <- t$significant
    big <- moves[moves$sig, , drop = FALSE]
    big <- big[order(-abs(big$diff)), , drop = FALSE]
    if (nrow(big)) {
      b <- big[1, ]
      v$change_sentence <- phrase(ctx, "composition_change", list(
        category = as.character(b$category), first = fmt_value(b$value_1, "percent", th),
        latest = fmt_value(b$value_2, "percent", th), first_period = b$period_label_1,
        latest_period = b$period_label_2, change = fmt_change(b$value_2, b$value_1, "percent", th)$text))
    } else {
      v$change_sentence <- phrase(ctx, "composition_stable",
                                  list(first_period = firsts$period_label[1], latest_period = v$latest_period))
    }
  }
  list(data = list(results = res, categories = members$category),
       compare_override = if (isTRUE(ctx$compare)) "subgroups+parents" else NULL,
       values = v,
       fields = c("title", "prose", "caption", "alt", "y_label", "legend_title", "note", "source_note", "labels"),
       labels = stats::setNames(members$category, members$metric_id),
       sources = source_row(members$source_id[1], metric_doc(members$metric_id[1])$table_or_series),
       unavailable = block_unavailable_rows(res, row$id, ctx),
       figure = TRUE)
}

# ---- distribution: a binned distribution for the study area and one benchmark --------------

compute_block_distribution <- function(row, ctx, settings, opts) {
  metric_id <- split_list(row$metrics)[1]
  recipe <- recipe_for(metric_id)
  if (is_blank(recipe$bins_table)) {
    stop("Block '", row$id, "': metric ", metric_id, " has no bins_table.", call. = FALSE)
  }
  release <- utils::tail(metric_periods(recipe, settings), 1)
  bins <- acs_bins(recipe$bins_table, release)
  bm <- Filter(function(e) e$role == "benchmark" && isTRUE(e$contains_study), ctx$entities)
  entities <- c(list(ctx$study), if (length(bm)) list(bm[[length(bm)]]))
  rows <- list()
  for (e in entities) {
    data <- acs_fetch(c(bins$variable), e$pieces, release)
    counts <- vapply(bins$variable, function(vv) {
      s <- sum_components(data, vv, e$pieces$key)
      if (usable(s$status)) s$est else NA_real_
    }, numeric(1))
    moes <- vapply(bins$variable, function(vv) moe_sum(data$moe[data$variable == vv]), numeric(1))
    total <- sum(counts)
    rows[[length(rows) + 1]] <- data.frame(entity_id = e$id, label = e$short, bin = bins$label,
                                           share = 100 * counts / total,
                                           moe = 100 * moe_prop(counts, total, moes, moe_sum(moes)),
                                           stringsAsFactors = FALSE)
  }
  res <- do.call(rbind, rows)
  res$bin <- factor(res$bin, levels = bins$label)
  period_label <- get_provider(recipe$source_id)$period_label(release)
  list(data = list(results = res),
       values = list(metric_label = metric_doc(metric_id)$label, latest_period = period_label,
                     benchmark = if (length(entities) > 1) entities[[2]]$short else "",
                     dollar_note = paste0("in ", release, " dollars (nominal for this period)")),
       fields = c("title", "prose", "caption", "alt", "x_label", "y_label", "legend_title", "note", "source_note"),
       sources = source_row(recipe$source_id, recipe$bins_table),
       figure = TRUE)
}

# ---- facts: headline table of latest values against benchmarks ----------------------------

compute_block_facts <- function(row, ctx, settings, opts) {
  metrics <- split_list(row$metrics)
  th <- ctx$theme
  et <- entity_table(ctx)
  # Significance flags compare each column with a reference: the study area, or in compare
  # mode the first shared benchmark (the listed areas are not tested against each other).
  bms <- Filter(function(e) e$role == "benchmark", ctx$entities)
  ref_entity <- if (isTRUE(ctx$compare) && length(bms)) bms[[1]] else ctx$study
  all <- list()
  for (m in metrics) {
    recipe <- recipe_for(m)
    periods <- utils::tail(metric_periods(recipe, settings), 1)
    r <- compute_metric(m, ctx$entities, settings, periods)
    units <- metric_units(m)
    ref <- r[r$entity_id == ref_entity$id, ]
    r$shown <- fmt_value(r$value, units, th, r$bound)
    r$moe_shown <- fmt_moe(r$moe, units, th)
    r$flag <- ""
    for (i in which(r$entity_id != ref_entity$id)) {
      other <- ctx$entities[[match(r$entity_id[i], et$entity_id)]]
      if (comparable_stat(m) && nrow(ref) && !anyNA(c(ref$value, r$value[i], ref$moe, r$moe[i]))) {
        share <- if (identical(ref_entity$id, "study")) dependence_share(m, other, settings) else 0
        t <- diff_test(ref$value, ref$moe, r$value[i], r$moe[i], part_share = share)
        if (t$significant) r$flag[i] <- "*"
      }
    }
    r$flag[r$status == "unreliable"] <- paste0(r$flag[r$status == "unreliable"], "‡")
    all[[length(all) + 1]] <- r
  }
  res <- do.call(rbind, all)
  res$label <- et$label[match(res$entity_id, et$entity_id)]
  labels <- stats::setNames(vapply(metrics, function(m) metric_doc(m)$label, ""), metrics)
  latest <- paste(unique(res$period_label), collapse = ", ")
  # Like a chart, the table is left out when the study area has no value at all; the text says why.
  has_data <- any(!is.na(res$value[res$entity_id %in% vapply(ctx$studies, `[[`, "", "id")]))
  summary <- if (has_data) {
    # Name the comparison areas the table shows (those with at least one value).
    bm <- et$label[et$role == "benchmark" & et$entity_id %in% res$entity_id[!is.na(res$value)]]
    phrase(ctx, "facts_compare", list(area_short = ctx$area$short, latest_period = latest,
                                      benchmark_list = if (length(bm)) join_list(bm, ctx) else phrase(ctx, "no_benchmarks", list())))
  } else {
    reasons <- res$method[res$entity_id == ctx$study$id & nzchar(res$method)]
    phrase(ctx, "facts_no_data", list(area_short = ctx$area$short, reason = reasons[1] %||% ""))
  }
  list(data = list(results = res, metrics = metrics, entities = et),
       values = list(n_indicators = length(metrics), latest_period = latest, flag_reference = ref_entity$short,
                     summary_sentence = summary, dollar_phrase = dollar_phrase(res, ctx)),
       fields = if (has_data) c("title", "prose", "caption", "note", "source_note", "labels") else c("title", "prose", "source_note"),
       labels = labels,
       sources = metric_sources(metrics),
       unavailable = block_unavailable_rows(res, row$id, ctx),
       table = has_data)
}

# ---- history: cited context events ---------------------------------------------------------

compute_block_history <- function(row, ctx, settings, opts) {
  ev <- ctx$events
  subjects <- split_list(opts$subjects, ",")
  if (!is.null(ev) && length(subjects)) {
    ev <- ev[vapply(ev$subjects, function(s) any(split_list(s) %in% subjects), TRUE), , drop = FALSE]
  }
  local <- if (!is.null(ev)) ev[ev$geo_scope != "nation", , drop = FALSE] else NULL
  national <- if (!is.null(ev)) ev[ev$geo_scope == "nation", , drop = FALSE] else NULL
  # National events (recessions, definitional changes) annotate charts; the list shows them
  # only when the block option national=true asks for it.
  include_national <- as_flag(opts$national, FALSE)
  shown <- rbind(local, if (include_national) national)
  any_shown <- !is.null(shown) && nrow(shown) > 0
  if (any_shown) shown <- shown[order(shown$start_date), , drop = FALSE]
  list(data = list(events = shown),
       values = list(n_events = if (is.null(shown)) 0 else nrow(shown), area = ctx$area$short),
       fields = c("title", "prose", "note"),
       event_fields = if (any_shown) paste0("event.", shown$event_id) else character(),
       sources = if (any_shown) source_row("history_events", paste(unique(shown$publisher), collapse = "; ")),
       table = FALSE)
}

# ---- text: prose only ----------------------------------------------------------------------

compute_block_text <- function(row, ctx, settings, opts) {
  list(data = list(), values = list(), fields = c("body"))
}

# ---- appendices ------------------------------------------------------------------------------

compute_block_sources <- function(row, ctx, settings, opts) {
  list(data = list(), values = list(), fields = c("title", "prose"), deferred = TRUE)
}

compute_block_availability <- function(row, ctx, settings, opts) {
  list(data = list(), values = list(), fields = c("title", "prose"), deferred = TRUE)
}

# ---- custom: trusted analysis modules in modules/<ref>.R ----------------------------------

# Helpers a module receives: resolved geography and benchmarks, validated metric data (same
# rules as built-in blocks), formatting, statistics and the theme. Modules never fetch raw
# data themselves unless they read a local file named in their options.
module_context <- function(ctx, settings, opts) {
  et <- entity_table(ctx)
  metric <- function(metric_id, entities = ctx$entities, periods = NULL) {
    r <- compute_metric(metric_id, entities, settings, periods)
    r$label <- et$label[match(r$entity_id, et$entity_id)]
    r
  }
  list(area = ctx$area, study = ctx$study, studies = ctx$studies, benchmarks = ctx$benchmarks,
       entities = ctx$entities, settings = settings, options = opts, theme = ctx$theme,
       metric = metric,
       latest = function(metric_id, entities = ctx$entities) {
         metric(metric_id, entities, utils::tail(metric_periods(recipe_for(metric_id), settings), 1))
       },
       fmt = function(x, units) fmt_value(x, units, ctx$theme),
       stats = list(moe_sum = moe_sum, moe_prop = moe_prop, moe_ratio = moe_ratio, diff_test = diff_test),
       local_file = function(name) root_path("data", "local", name))
}

load_module <- function(name) {
  env <- new.env(parent = globalenv())
  sys.source(root_path("modules", paste0(name, ".R")), envir = env)
  for (f in c("compute", "render")) {
    if (!is.function(env[[f]])) stop("Module ", name, " must define a function `", f, "`.", call. = FALSE)
  }
  env
}

compute_block_custom <- function(row, ctx, settings, opts) {
  mod <- load_module(row$ref)
  out <- mod$compute(module_context(ctx, settings, opts), opts)
  list(data = out$data, module = row$ref,
       values = c(out$values %||% list(), list(module_title = mod$title %||% row$ref)),
       fields = c("title", "prose", "caption", "alt", "x_label", "y_label", "legend_title", "note", "source_note"),
       sources = out$sources, depends_on = out$depends_on, figure = TRUE)
}

render_block_custom <- function(b, txt, th) {
  load_module(b$module)$render(b$data, txt, th)
}
