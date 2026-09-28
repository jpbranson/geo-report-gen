# Custom analysis module (example): licensed child care slots per 100 children under 5.
#
# A module is a trusted R file with a `title`, a `compute(ctx, options)` function and a
# `render(output, text, theme)` function. It is inserted into a report with a manifest row
# of type "custom" whose ref is the file name ("childcare_gap"). The engine calls compute()
# while composing (data come from validated metrics through ctx$metric()) and render() while
# the report renders. Nothing in the engine is specific to this module.

title <- "Licensed child care slots per 100 children under 5"

compute <- function(ctx, options) {
  # Areas published by both sources: counties and the state (the licensing data are
  # county totals, so a city is represented by the counties it intersects).
  areas <- Filter(function(e) all(e$pieces$type %in% c("county", "state")), ctx$entities)
  if (!length(areas)) stop("No county or state areas to compare for this study area.")
  capacity <- ctx$latest("childcare_capacity_tx", areas)
  children <- ctx$latest("children_under5_acs", areas)
  d <- merge(capacity[, c("entity_id", "label", "value", "period_label")],
             children[, c("entity_id", "value", "moe", "period_label")], by = "entity_id", suffixes = c("_capacity", "_children"))
  d <- d[!is.na(d$value_capacity) & !is.na(d$value_children) & d$value_children > 0, , drop = FALSE]
  if (!nrow(d)) stop("Licensed capacity is published for Texas counties only.")
  # A ratio of a count without sampling error to an ACS estimate: MOE from the ratio formula
  # with the capacity treated as exact.
  d$per_100 <- 100 * d$value_capacity / d$value_children
  d$per_100_moe <- 100 * ctx$stats$moe_ratio(d$value_capacity, d$value_children, 0, d$moe)
  d <- d[order(match(d$entity_id, vapply(areas, `[[`, "", "id"))), ]
  top <- d[1, ]
  list(data = d,
       values = list(
         summary_sentence = paste0("In ", top$label, ", licensed operations had ", ctx$fmt(top$value_capacity, "children"),
                                   " slots for ", ctx$fmt(top$value_children, "children"), " children under 5, or ",
                                   formatC(top$per_100, format = "f", digits = 0), " slots per 100 young children."),
         method_note = paste0("Capacity is the licensed maximum from current Texas licensing records (", top$period_label_capacity,
                              ") and often includes school-age slots, so it overstates care available to children under 5; ",
                              "children under 5 are ACS ", top$period_label_children,
                              " estimates. The two measures refer to different dates. Ratios use the ACS margin of error only."),
         source_short = "Texas HHSC Child Care Regulation operations data; U.S. Census Bureau, ACS 5-year estimates (B01001)"),
       sources = data.frame(source_id = c("tx_hhsc", "census_acs5"), detail = c("licensed capacity by county", "B01001 children under 5")),
       depends_on = c("childcare_capacity_tx", "children_under5_acs"))
}

render <- function(output, text, theme) {
  d <- output
  d$label <- factor(d$label, levels = rev(d$label))
  ggplot(d, aes(x = per_100, y = label)) +
    geom_col(fill = theme$color_accent, width = 0.6) +
    geom_errorbar(aes(xmin = pmax(0, per_100 - per_100_moe), xmax = per_100 + per_100_moe), orientation = "y",
                  width = 0.2, color = theme$color_muted) +
    geom_text(aes(label = formatC(per_100, format = "f", digits = 0)), hjust = -0.4, size = 3.2, color = theme$color_text) +
    scale_x_continuous(expand = expansion(mult = c(0, 0.12))) +
    labs(x = text$x_label, y = NULL) +
    gr_ggtheme(theme) + theme(panel.grid.major.y = element_blank())
}
