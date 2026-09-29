# Functions called from a generated report.qmd while Quarto renders it. They read the
# report snapshot only; no data is fetched or computed at render time.

# Captions and alt text are chunk options. Quarto turns labeled figures into internal
# cross-reference nodes before document filters run, so their {placeholders} are filled
# here, by knitr option hooks, using the block named in the chunk label (fig-<id>/tbl-<id>).
gr_open_snapshot <- function(path) {
  snap <- readRDS(path)
  fill_option <- function(name) {
    force(name)
    function(options) {
      id <- sub("^(fig|tbl)-", "", options$label %||% "")
      options[[name]] <- fill_template(options[[name]], c(snap$values[[id]], snap$values$report))
      options
    }
  }
  for (nm in c("fig.cap", "fig.alt", "tbl.cap", "fig-cap", "fig-alt", "tbl-cap")) {
    hook <- list(fill_option(nm))
    names(hook) <- nm
    do.call(knitr::opts_hooks$set, hook)
  }
  snap
}

# Draw one block. Text drawn inside images comes from the chunk options first (so in-place
# edits show up immediately in `quarto preview`), then from the snapshot.
gr_block <- function(snap, id) {
  b <- snap$blocks[[id]]
  if (is.null(b)) stop("Block '", id, "' is not in the report snapshot; rebuild the report.")
  # A block's own values come first (as in quarto/gr-placeholders.lua), e.g. the county a
  # chart shows as context for a city.
  vals <- c(snap$values[[id]], snap$values$report)
  opt <- function(option, field) {
    v <- knitr::opts_current$get(option)
    if (is.null(v)) v <- snap$texts[[paste0(id, ".", field)]]
    fill_template(v %||% "", vals)
  }
  txt <- list(x_label = opt("gr-x-label", "x_label"),
              y_label = opt("gr-y-label", "y_label"),
              legend_title = opt("gr-legend-title", "legend_title"))
  labels <- knitr::opts_current$get("gr-labels")
  if (is.null(labels)) {
    keys <- grep(paste0("^", id, "\\.label\\."), names(snap$texts), value = TRUE)
    labels <- stats::setNames(lapply(keys, function(k) snap$texts[[k]]), sub(paste0("^", id, "\\.label\\."), "", keys))
  }
  txt$labels <- lapply(labels, fill_template, values = vals)
  fn <- get0(paste0("render_block_", b$kind), mode = "function")
  if (is.null(fn)) stop("No renderer for block kind '", b$kind, "'.")
  out <- fn(b, txt, snap$theme)
  if (inherits(out, "ggplot")) print(out) else out
}
