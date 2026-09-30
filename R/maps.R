# Boundaries and maps. Boundaries are Census cartographic boundary files (1:500,000,
# generalized for display) of the report's boundary vintage, cached as sf objects.
# Maps use a Lambert azimuthal equal-area projection centred on the area shown, so any
# location (including Alaska, Hawaii and Puerto Rico) gets a suitable projection.

cb_layers <- c(state = "us", county = "us", cbsa = "us", place = "state", tract = "state",
               cousub = "state", bg = "state", unsd = "state")

boundaries <- function(layer, vintage, state = NULL) {
  scope <- if (cb_layers[[layer]] == "us") "us" else state
  url <- sprintf("https://www2.census.gov/geo/tiger/GENZ%d/shp/cb_%d_%s_%s_500k.zip", vintage, vintage, scope, layer)
  path <- cache_path("geo", "boundaries", vintage, paste0(scope, "_", layer, ".rds"))
  cached(path, source = "census_geo", compute = function() {
    zip <- cached_download(url, cache_path("geo", "boundaries", vintage, basename(url)), "census_geo")
    shp <- sf::st_read(paste0("/vsizip/", zip), quiet = TRUE)
    shp <- sf::st_make_valid(shp)
    shp[, intersect(c("GEOID", "NAME", "NAMELSAD", "STATEFP", "ALAND"), names(shp))]
  })
}

# Geometry of one published piece (place parts are the place clipped to the county).
piece_geometry <- function(type, geoid, vintage) {
  switch(type,
    state = boundaries("state", vintage)[boundaries("state", vintage)$GEOID == geoid, ],
    county = { b <- boundaries("county", vintage); b[b$GEOID == geoid, ] },
    cbsa = { b <- boundaries("cbsa", vintage); b[b$GEOID == geoid, ] },
    place = { b <- boundaries("place", vintage, substr(geoid, 1, 2)); b[b$GEOID == geoid, ] },
    tract = { b <- boundaries("tract", vintage, substr(geoid, 1, 2)); b[b$GEOID == geoid, ] },
    cousub = { b <- boundaries("cousub", vintage, substr(geoid, 1, 2)); b[b$GEOID == geoid, ] },
    place_part = {
      pl <- piece_geometry("place", sub("-.*$", "", geoid), vintage)
      co <- piece_geometry("county", sub("^.*-", "", geoid), vintage)
      suppressWarnings(sf::st_intersection(sf::st_geometry(pl), sf::st_geometry(co))) |> sf::st_sf(geometry = _)
    },
    stop("No boundaries available for geography type '", type, "'"))
}

entity_geometry <- function(e, vintage) {
  parts <- lapply(seq_len(nrow(e$pieces)), function(i) sf::st_geometry(piece_geometry(e$pieces$type[i], e$pieces$geoid[i], vintage)))
  geom <- do.call(c, parts)
  sf::st_sf(label = e$short, geometry = sf::st_union(sf::st_make_valid(geom)))
}

local_crs <- function(geom) {
  c <- sf::st_coordinates(sf::st_centroid(sf::st_union(sf::st_transform(geom, 4326))))
  sprintf("+proj=laea +lat_0=%.4f +lon_0=%.4f +datum=WGS84 +units=m +no_defs", c[2], c[1])
}

map_theme <- function(th) {
  gr_ggtheme(th) + theme(axis.text = element_blank(), axis.title = element_blank(),
                         panel.grid.major = element_blank(), legend.position = "right",
                         legend.justification = "top")
}

# ---- Locator ------------------------------------------------------------------------------

compute_block_locator <- function(row, ctx, settings, opts) {
  v <- ctx$area$vintage
  study <- do.call(rbind, lapply(ctx$studies, entity_geometry, vintage = v))
  all_pieces <- do.call(rbind, lapply(ctx$studies, `[[`, "pieces"))
  states <- unique(substr(all_pieces$geoid[all_pieces$type != "nation"], 1, 2))
  area_types <- unique(all_pieces$type)
  if (any(area_types %in% c("region", "division", "nation", "state")) || !length(states)) {
    context <- boundaries("state", v)
    context <- context[!context$GEOID %in% c("02", "15", "72", "60", "66", "69", "78") | context$GEOID %in% states, ]
    counties <- NULL
  } else {
    context <- boundaries("state", v)
    context <- context[context$GEOID %in% states, ]
    counties <- boundaries("county", v)
    counties <- counties[substr(counties$GEOID, 1, 2) %in% states, ]
  }
  bm_counties <- Filter(function(e) all(e$pieces$type == "county") && nrow(e$pieces) <= 12, ctx$benchmarks)
  bm_geo <- if (length(bm_counties)) do.call(rbind, lapply(bm_counties, entity_geometry, vintage = v)) else NULL
  list(data = list(study = study, context = context, counties = counties, benchmarks = bm_geo),
       values = list(context_label = paste(context$NAME, collapse = ", "), area_short = ctx$area$short),
       fields = c("title", "caption", "alt", "source_note"),
       sources = source_row("census_geo", paste0("Cartographic boundary files ", v, " (1:500,000)")),
       figure = TRUE)
}

render_block_locator <- function(b, txt, th) {
  d <- b$data
  crs <- local_crs(d$context)
  fam <- chart_font(th)
  p <- ggplot() + geom_sf(data = sf::st_transform(d$context, crs), fill = "#f7f7f5", color = th$color_muted, linewidth = 0.4)
  if (!is.null(d$counties)) p <- p + geom_sf(data = sf::st_transform(d$counties, crs), fill = NA, color = th$color_rule, linewidth = 0.2)
  if (!is.null(d$benchmarks)) p <- p + geom_sf(data = sf::st_transform(d$benchmarks, crs), fill = NA, color = theme_colors(th, "color_benchmarks")[1], linewidth = 0.6)
  st <- sf::st_transform(d$study, crs)
  p + geom_sf(data = st, fill = th$color_accent, color = th$color_accent, alpha = 0.85, linewidth = 0.3) +
    ggrepel::geom_label_repel(data = st, aes(geometry = geometry, label = label), stat = "sf_coordinates",
                              size = 3.2, family = fam, label.size = 0.15, min.segment.length = 0,
                              box.padding = 0.8, seed = 1, fill = scales::alpha(th$color_background, 0.9)) +
    coord_sf(crs = crs, datum = NA) + map_theme(th)
}

# ---- Within-area map -------------------------------------------------------------------------

# Subareas used to show variation inside the study area. Tracts nest in counties, so county-
# based areas use exactly their tracts. Tracts do not nest in places: for places we use
# every tract that overlaps the place by at least 1% of the tract's area, draw each tract
# whole, and outline the place, so a tract is never presented as only its part inside.
study_subareas <- function(ctx, vintage) {
  pieces <- ctx$study$pieces
  counties <- unique(c(pieces$geoid[pieces$type == "county"], sub("^.*-", "", pieces$geoid[pieces$type == "place_part"])))
  tracts <- list()
  exact <- TRUE
  for (st in unique(substr(c(counties, pieces$geoid[pieces$type %in% c("place", "tract")]), 1, 2))) {
    tr <- boundaries("tract", vintage, st)
    if (any(pieces$type == "county")) tracts[[length(tracts) + 1]] <- tr[substr(tr$GEOID, 1, 5) %in% pieces$geoid[pieces$type == "county"], ]
    pl <- pieces[pieces$type %in% c("place", "place_part") & substr(pieces$geoid, 1, 2) == st, , drop = FALSE]
    if (nrow(pl)) {
      exact <- FALSE
      shape <- entity_geometry(entity("x", "x", "x", pl), vintage)
      crs <- local_crs(shape)
      trp <- sf::st_transform(tr, crs)
      shp <- sf::st_transform(shape, crs)
      inter <- suppressWarnings(sf::st_intersection(trp, sf::st_geometry(shp)))
      share <- as.numeric(sf::st_area(inter)) / as.numeric(sf::st_area(trp[match(inter$GEOID, trp$GEOID), ]))
      keep <- unique(inter$GEOID[share >= 0.01])
      tracts[[length(tracts) + 1]] <- tr[tr$GEOID %in% keep, ]
    }
  }
  out <- do.call(rbind, tracts)
  out <- out[!duplicated(out$GEOID), ]
  attr(out, "exact") <- exact
  out
}

compute_block_map <- function(row, ctx, settings, opts) {
  metric_id <- split_list(row$metrics)[1]
  recipe <- recipe_for(metric_id)
  v <- ctx$area$vintage
  release <- utils::tail(metric_periods(recipe, settings), 1)
  sub <- study_subareas(ctx, v)
  keys <- paste0("tract:", sub$GEOID)
  pieces <- data.frame(key = keys, type = "tract", geoid = sub$GEOID, stringsAsFactors = FALSE)
  vars <- unique(c(recipe_vars(recipe$numerator), recipe_vars(recipe$denominator), if (!is_blank(recipe$published_var)) recipe$published_var))
  data <- get_provider(recipe$source_id)$fetch(vars, pieces, release, list(recipe = recipe))
  vals <- lapply(keys, function(k) aggregate_entity(recipe, data[data$geo == k, , drop = FALSE], k, release))
  sub$value <- vapply(vals, `[[`, 0, "value")
  sub$moe <- vapply(vals, `[[`, 0, "moe")
  sub$status <- vapply(vals, `[[`, "", "status")
  cv <- cv_percent(sub$value, sub$moe)
  sub$class <- ifelse(is.na(sub$value), "No data",
                      ifelse(!is.na(cv) & cv > as.numeric(settings$cv_unreliable), "Unreliable estimate", "ok"))
  outline <- entity_geometry(ctx$study, v)
  units <- metric_units(metric_id)
  th <- ctx$theme
  n_unrel <- sum(sub$class == "Unreliable estimate")
  list(data = list(tracts = sub, outline = outline, units = units, exact = attr(sub, "exact")),
       values = list(metric_label = metric_text(ctx, metric_id, "label"), metric_sentence = metric_text(ctx, metric_id, "sentence"),
                     metric_label_lower = metric_text(ctx, metric_id, "sentence"),
                     latest_period = get_provider(recipe$source_id)$period_label(release),
                     n_tracts = as.character(nrow(sub)), n_unreliable = as.character(n_unrel),
                     tract_note = if (isTRUE(attr(sub, "exact"))) phrase(ctx, "tracts_exact", list()) else phrase(ctx, "tracts_overlap", list())),
       fields = c("title", "prose", "caption", "alt", "legend_title", "legend", "note", "source_note"),
       sources = source_row(recipe$source_id, paste(metric_doc(metric_id)$table_or_series, "(census tracts)")),
       figure = TRUE)
}

# Quantile classes over the tracts with values. Unreliable estimates keep their class color
# and get a dashed outline (hiding them would blank out most low-rate tracts, whose CVs are
# large); tracts without a value get the "no data" color. Classes are shared by every map
# of the same metric in a report because they come from the same tract values.
render_block_map <- function(b, txt, th) {
  d <- b$data
  tr <- d$tracts
  crs <- local_crs(d$outline)
  pal <- theme_colors(th, "palette_sequential")
  has_value <- !is.na(tr$value)
  breaks <- unique(stats::quantile(tr$value[has_value], probs = seq(0, 1, length.out = min(6, length(pal) + 1)), na.rm = TRUE))
  fmt <- function(x) fmt_value(x, d$units, th)
  bins <- factor()
  if (length(breaks) >= 2) {
    bins <- cut(tr$value, breaks = breaks, include.lowest = TRUE, dig.lab = 10)
    levels(bins) <- paste(fmt(utils::head(breaks, -1)), "to", fmt(breaks[-1]))
    tr$fill_class <- ifelse(has_value, as.character(bins), "No data")
  } else tr$fill_class <- ifelse(has_value, "All tracts", "No data")
  lv <- c(levels(bins), "All tracts", "No data")
  tr$fill_class <- factor(tr$fill_class, levels = lv[lv %in% tr$fill_class])
  # Fewer classes than colors: use the darkest ones, so the lowest class stays visible on the page.
  n <- max(0, length(breaks) - 1)
  cols <- c(stats::setNames(pal[seq_len(n) + length(pal) - n], utils::head(levels(bins), n)),
            `All tracts` = pal[3], `No data` = th$color_missing)
  shapes <- sf::st_transform(tr, crs)
  unreliable <- shapes[tr$class == "Unreliable estimate", ]
  p <- ggplot() +
    geom_sf(data = shapes, aes(fill = fill_class), color = th$color_background, linewidth = 0.15)
  if (nrow(unreliable)) {
    p <- p + geom_sf(data = unreliable, aes(linetype = "Unreliable estimate (CV above threshold)"), fill = NA,
                     color = th$color_text, linewidth = 0.25)
  }
  p + geom_sf(data = sf::st_transform(d$outline, crs), fill = NA, color = th$color_text, linewidth = 0.7) +
    scale_fill_manual(values = cols, name = txt$legend_title, drop = TRUE, guide = guide_legend(order = 1)) +
    scale_linetype_manual(values = c(`Unreliable estimate (CV above threshold)` = "22"), name = NULL,
                          guide = guide_legend(order = 2)) +
    coord_sf(crs = crs, datum = NA) + map_theme(th)
}

# ---- Historical county map -------------------------------------------------------------------

# The counties of a census year (NHGIS boundary files) whose interior point lies in the given
# states of today, so counties of territories that were not yet states are included too.
historical_counties <- function(hist, context) {
  points <- suppressWarnings(sf::st_point_on_surface(sf::st_geometry(hist)))
  inside <- lengths(sf::st_intersects(points, sf::st_union(sf::st_transform(context, sf::st_crs(hist))))) > 0
  hist[inside, ]
}

# Counties that contribute at least 2% of the study area's extent (or of which at least 20% lies in it).
historical_touched <- function(hist, study) {
  crs <- local_crs(study)
  h <- sf::st_transform(hist, crs)
  s <- sf::st_transform(study, crs)
  overlap <- vapply(seq_len(nrow(h)), function(i) {
    x <- suppressWarnings(sf::st_intersection(sf::st_geometry(h)[i], sf::st_union(sf::st_geometry(s))))
    if (length(x)) as.numeric(sum(sf::st_area(x))) else 0
  }, 0)
  overlap / as.numeric(sum(sf::st_area(s))) >= 0.02 | overlap / as.numeric(sf::st_area(h)) >= 0.2
}

compute_block_historical_map <- function(row, ctx, settings, opts) {
  year <- as.integer(opts$boundary_year %||% 1900)
  v <- ctx$area$vintage
  study <- do.call(rbind, lapply(ctx$studies, entity_geometry, vintage = v))
  pieces <- do.call(rbind, lapply(ctx$studies, `[[`, "pieces"))
  states <- unique(substr(pieces$geoid[!pieces$type %in% c("nation", "region", "division")], 1, 2))
  if (!length(states)) stop("A historical county map needs a study area within states.", call. = FALSE)
  context <- boundaries("state", v)
  context <- context[context$GEOID %in% states, ]
  hist <- historical_counties(nhgis_boundaries("county", year), context)
  touched <- historical_touched(hist, study)
  list(data = list(study = study, context = context, counties = hist, touched = touched),
       values = list(boundary_year = as.character(year), area_short = ctx$area$short, context_label = paste(context$NAME, collapse = ", "),
                     n_counties = as.character(nrow(hist)), touched_counties = paste(sort(hist$NHGISNAM[touched]), collapse = ", ")),
       fields = c("title", "caption", "alt", "source_note"),
       sources = source_row("ipums_nhgis", paste0("Historical county boundary file of ", year)),
       figure = TRUE)
}

render_block_historical_map <- function(b, txt, th) {
  d <- b$data
  crs <- local_crs(d$context)
  h <- sf::st_transform(d$counties, crs)
  p <- ggplot() + geom_sf(data = sf::st_transform(d$context, crs), fill = "#f7f7f5", color = th$color_muted, linewidth = 0.4) +
    geom_sf(data = h, fill = NA, color = th$color_rule, linewidth = 0.25) +
    geom_sf(data = h[d$touched, ], fill = NA, color = th$color_text, linewidth = 0.5) +
    geom_sf(data = sf::st_transform(d$study, crs), fill = th$color_accent, color = th$color_accent, alpha = 0.6, linewidth = 0.3)
  if (any(d$touched)) {
    p <- p + ggrepel::geom_text_repel(data = h[d$touched, ], aes(geometry = geometry, label = NHGISNAM), stat = "sf_coordinates",
                                      size = 3, family = chart_font(th), min.segment.length = Inf, seed = 1)
  }
  p + coord_sf(crs = crs, datum = NA) + map_theme(th)
}
