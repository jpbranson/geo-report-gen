# Metric engine: computes a cataloged metric for entities (study area, benchmarks, subareas)
# and periods from published pieces, following the metric's recipe (catalog/recipes.csv).
#
# Aggregation rules (never average across areas):
#   count   sum over non-overlapping pieces; MOE by root-sum-of-squares
#   share   numerator and denominator summed separately, then divided (x scale); MOE for
#           a proportion (numerator is a subset of the denominator)
#   ratio   as share but numerator is not a subset (means, per capita); MOE for a ratio
#   median  published median for a single piece; for several pieces, interpolated from the
#           summed published distribution (bins_table); MOE not computed (no Census method)
#   value   published value for a single piece only (indexes, published rates/prices);
#           marked not_aggregable for combined areas

# Variables named in a recipe expression: "A+B" -> c("A","B"). Period-specific mappings are
# written "2000:P001001; 2010:P001001; 2020:P1_001N".
parse_period_vars <- function(expr) {
  items <- split_list(expr)
  keys <- trimws(sub(":.*$", "", items))
  vals <- trimws(sub("^[^:]*:", "", items))
  stats::setNames(lapply(vals, function(v) trimws(strsplit(v, "+", fixed = TRUE)[[1]])), keys)
}

recipe_vars <- function(expr, period = NULL) {
  if (is_blank(expr)) return(character(0))
  if (grepl(":", expr, fixed = TRUE)) {
    map <- parse_period_vars(expr)
    if (is.null(period)) return(unique(unlist(map)))
    return(map[[as.character(period)]] %||% character(0))
  }
  trimws(strsplit(expr, "+", fixed = TRUE)[[1]])
}

# Bin variables and bounds of an ACS distribution table (labels parsed per release, because
# some tables gained bins over time, e.g. home values above $1 million from 2015).
acs_bins <- function(table, release) {
  v <- acs_variables(release, table)
  v <- v[grepl("_[0-9]{3}$", v$variable) & v$variable != paste0(table, "_001"), , drop = FALSE]
  b <- t(vapply(v$label, parse_bin_label, numeric(2)))
  out <- data.frame(variable = v$variable, label = sub("^.*!!", "", v$label),
                    lower = b[, 1], upper = b[, 2], stringsAsFactors = FALSE, row.names = NULL)
  out <- out[!is.na(out$lower), , drop = FALSE]
  # The API lists variables in no particular order; bins must run from low to high.
  out[order(out$lower), , drop = FALSE]
}

# Worst status among components, in order of severity.
status_rank <- c(ok = 0, controlled = 0, open_interval = 1, moe_unavailable = 1, imputed = 1, unreliable = 2,
                 missing = 5, insufficient_sample = 5, suppressed = 5, not_applicable = 6,
                 unavailable = 6, invalid_denominator = 7, not_aggregable = 7)

worst_status <- function(statuses) {
  statuses <- statuses[!is.na(statuses)]
  if (!length(statuses)) return("missing")
  rank <- unname(status_rank[statuses])
  rank[is.na(rank)] <- 5
  statuses[which.max(rank)]
}

# "imputed": the source filled in a value for a non-reporting unit (shown, but flagged).
usable <- function(status) status %in% c("ok", "controlled", "moe_unavailable", "imputed")

# Sum variables over all pieces of an entity for one period.
sum_components <- function(d, vars, piece_keys) {
  x <- d[d$variable %in% vars, , drop = FALSE]
  expected <- length(vars) * length(piece_keys)
  if (!length(vars)) return(list(est = NA_real_, moe = NA_real_, status = "missing"))
  if (nrow(x) < expected) {
    # Some pieces have no data for this period: usually a boundary change (the geography did
    # not exist then) or a table not yet published. A partial sum would understate the area,
    # so the value is unavailable and the missing pieces are named.
    absent <- setdiff(piece_keys, x$geo)
    return(list(est = NA_real_, moe = NA_real_, status = "unavailable",
                absent = if (length(absent)) absent else "some variables"))
  }
  st <- worst_status(x$status)
  if (!usable(st)) return(list(est = NA_real_, moe = NA_real_, status = st))
  # Components without a MOE ("**") keep the estimate but make the combined MOE missing.
  list(est = sum(x$estimate), moe = moe_sum(x$moe), status = if (st == "imputed") "imputed" else "ok")
}

# Compute one entity for one period from its long data `d`.
aggregate_entity <- function(recipe, d, piece_keys, period) {
  type <- recipe$stat_type
  if (!type %in% c("count", "share", "ratio", "median", "value")) {
    stop("Unknown stat_type '", type, "' for metric ", recipe$metric_id)
  }
  scale <- as.numeric(recipe$scale %||% "1")
  if (is.na(scale)) scale <- 1
  single <- length(piece_keys) == 1
  out <- list(value = NA_real_, moe = NA_real_, status = "unavailable", bound = NA_character_,
              method = "no published value for this area and period", num = NA_real_, den = NA_real_)
  # A single published geography uses the source's own estimate when there is one (a
  # published median, per capita income, an index); combined areas are rebuilt from parts.
  published_var <- if (type == "value") recipe_vars(recipe$numerator, period)[1] else recipe$published_var
  if (single && !is_blank(published_var)) {
    x <- d[d$variable == published_var, , drop = FALSE]
    if (nrow(x)) {
      out[c("value", "moe", "status", "bound")] <- list(x$estimate[1], x$moe[1], x$status[1], x$bound[1])
      out$method <- "published estimate"
      return(out)
    }
    if (type %in% c("median", "value")) return(out)
    # Shares and ratios fall through: e.g. LAUS publishes no U.S. rate, but the counts sum.
  }
  if (type == "count") {
    s <- sum_components(d, recipe_vars(recipe$numerator, period), piece_keys)
    out[c("value", "moe", "status", "num")] <- list(s$est, s$moe, s$status, s$est)
    out$method <- if (!is.null(s$absent)) absent_note(s$absent) else if (single) "published count" else "sum of published pieces"
  } else if (type %in% c("share", "ratio")) {
    n <- sum_components(d, recipe_vars(recipe$numerator, period), piece_keys)
    dn <- sum_components(d, recipe_vars(recipe$denominator, period), piece_keys)
    out$num <- n$est
    out$den <- dn$est
    if (!usable(n$status) || !usable(dn$status)) {
      out$status <- worst_status(c(n$status, dn$status))
    } else if (is.na(dn$est) || dn$est <= 0) {
      out$status <- "invalid_denominator"   # never show a plausible-looking value
    } else {
      out$value <- scale * n$est / dn$est
      moe <- if (type == "share") moe_prop(n$est, dn$est, n$moe, dn$moe) else moe_ratio(n$est, dn$est, n$moe, dn$moe)
      out$moe <- scale * moe
      out$status <- "ok"
    }
    absent <- unique(c(n$absent, dn$absent))
    out$method <- if (length(absent)) absent_note(absent) else if (single) "computed from published counts" else "recomputed from summed counts"
  } else if (type == "median" && !is_blank(recipe$bins_table)) {
    bins <- acs_bins(recipe$bins_table, period)
    counts <- vapply(bins$variable, function(v) {
      s <- sum_components(d, v, piece_keys)
      if (usable(s$status)) s$est else NA_real_
    }, numeric(1))
    m <- median_from_bins(counts, bins$lower, bins$upper)
    out[c("value", "moe", "status", "bound")] <- list(m$value, NA_real_, m$status, m$bound)
    out$method <- "median interpolated from the combined published distribution (MOE not computed)"
  } else {
    out$status <- "not_aggregable"
    out$method <- "published values for single areas (medians, indexes, prices) cannot be combined"
  }
  out
}

# Explain an unavailable value caused by pieces without data (a boundary change, or a table
# not yet published in an older release).
absent_note <- function(absent) {
  paste0("not available for this period: no published data for ", paste(absent, collapse = ", "),
         " (boundary change or table not published in this release)")
}

# Periods a metric uses in a report (provider policy, then optional block override).
metric_periods <- function(recipe, settings, override = NULL) {
  prov <- get_provider(recipe$source_id)
  periods <- prov$periods(settings, recipe)
  if (!is.null(override) && length(override)) periods <- intersect(periods, override)
  periods
}

# Compute a metric for a list of entities. Returns one row per entity x period with value,
# MOE, status, CV/reliability, method and components. Each entity is cached separately so a
# benchmark shared by many reports (e.g. a state) is computed once. Dollar values are
# converted to constant dollars unless `constant_dollars = FALSE`.
compute_metric <- function(metric_id, entities, settings, periods = NULL, constant_dollars = TRUE) {
  recipe <- recipe_for(metric_id)
  prov <- get_provider(recipe$source_id)
  periods <- periods %||% metric_periods(recipe, settings)
  if (!length(periods)) return(empty_metric_result())
  bins_vars <- if (!is_blank(recipe$bins_table)) unique(unlist(lapply(periods, function(p) acs_bins(recipe$bins_table, p)$variable))) else character()
  vars <- unique(c(recipe_vars(recipe$numerator), recipe_vars(recipe$denominator),
                   if (!is_blank(recipe$published_var)) recipe$published_var, bins_vars))
  var_by_period <- if (grepl(":", recipe$numerator, fixed = TRUE)) parse_period_vars(recipe$numerator) else NULL
  rows <- lapply(entities, function(e) {
    pieces <- e$pieces
    unsupported <- setdiff(unique(pieces$type), prov$geo_types)
    if (length(unsupported)) {
      return(unavailable_rows(e, periods, prov, "not_applicable",
                              paste0(prov$name, " does not publish ", paste(unsupported, collapse = "/"), " data")))
    }
    data <- prov$fetch(vars, pieces, periods, list(var_by_period = var_by_period, recipe = recipe, settings = settings))
    key <- hash_value(recipe, sort(pieces$key), periods, digest::digest(data), metric_code_version())
    path <- cache_path("metrics", metric_id, paste0(key, ".rds"))
    res <- cached(path, function() {
      do.call(rbind, lapply(periods, function(p) {
        d <- data[data$period == as.character(p), , drop = FALSE]
        a <- aggregate_entity(recipe, d, pieces$key, p)
        # The series a value belongs to (e.g. an estimates vintage); charts never join
        # points from different series.
        series <- if ("series" %in% names(d) && nrow(d)) d$series[1] else prov$series %||% prov$name
        data.frame(entity_id = e$id, period = as.character(p), value = a$value, moe = a$moe,
                   status = a$status, bound = a$bound, method = a$method, num = a$num, den = a$den,
                   series = series, stringsAsFactors = FALSE)
      }))
    })
    res$entity_id <- e$id
    res
  })
  res <- do.call(rbind, rows)
  res$metric_id <- metric_id
  res$period_label <- vapply(res$period, prov$period_label, "")
  bounds <- period_bounds(recipe$source_id, res$period)
  res$period_start <- bounds$start
  res$period_end <- bounds$end
  res$cv <- cv_percent(res$value, res$moe)
  res$reliability <- reliability(res$cv, as.numeric(settings$cv_caution %||% 15), as.numeric(settings$cv_unreliable %||% 30))
  res$status[res$status == "ok" & !is.na(res$reliability) & res$reliability == "unreliable"] <- "unreliable"
  apply_inflation(res, recipe, settings, adjust = constant_dollars)
}

period_bounds <- function(source_id, period) {
  p <- as.integer(period)
  if (identical(get_provider(source_id)$period_kind, "multiyear")) list(start = p - 4L, end = p) else list(start = p, end = p)
}

unavailable_rows <- function(e, periods, prov, status, why) {
  data.frame(entity_id = e$id, period = as.character(periods), value = NA_real_, moe = NA_real_,
             status = status, bound = NA_character_, method = why, num = NA_real_, den = NA_real_,
             series = prov$series %||% prov$name, stringsAsFactors = FALSE)
}

empty_metric_result <- function() {
  data.frame(entity_id = character(), period = character(), value = numeric(), moe = numeric(),
             status = character(), bound = character(), method = character(), num = numeric(),
             den = numeric(), series = character(), metric_id = character(), period_label = character(),
             period_start = integer(), period_end = integer(), cv = numeric(),
             reliability = character(), stringsAsFactors = FALSE)
}

# Code that shapes computed metrics; editing it invalidates cached metric results.
metric_code_version <- function() {
  memoize("metric_code_version", function() code_version(c("R/metrics.R", "R/stats.R")))
}

# Monetary values: keep nominal values and add constant dollars of `dollar_year` using the
# price index in settings (`price_index`). ACS period dollars are already in dollars of the
# final year of the period; annual series are in dollars of their own year.
apply_inflation <- function(res, recipe, settings, adjust = TRUE) {
  res$value_nominal <- res$value
  res$moe_nominal <- res$moe
  res$dollar_year <- NA_integer_
  if (!adjust || is_blank(recipe$dollars) || !nrow(res)) return(res)
  base <- as.integer(settings$dollar_year %||% settings$acs_release %||% 2024)
  from <- res$period_end
  idx <- tryCatch(price_index_table(settings$price_index %||% "r_cpi_u_rs"), error = function(e) {
    warn("Constant dollars unavailable (", conditionMessage(e), "). Dollar values are shown in nominal ",
         "dollars of each period and are not compared over time.")
    NULL
  })
  if (is.null(idx)) return(res)  # dollar_year stays NA: charts and text say "nominal"
  f <- inflation_factor(from, base, idx)
  res$value <- res$value_nominal * f
  res$moe <- res$moe_nominal * f
  res$dollar_year <- base
  gap <- is.na(f) & !is.na(res$value_nominal)
  res$status[gap] <- "unavailable"
  res$method[gap] <- "the price index does not cover this year, so constant dollars cannot be computed"
  res
}
