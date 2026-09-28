# Statistical rules. Formulas follow Census Bureau guidance:
#   [H8]  Understanding and Using ACS Data (2020), ch. 8 "Calculating Measures of Error for
#         Derived Estimates" (sums, proportions, ratios, percent change, products).
#   [ST]  Instructions for Applying Statistical Testing to ACS Data (2020): z test at 90%,
#         controlled estimates have SE 0, census counts have SE 0, "**"/"***" -> no test.
#   [ST12] Instructions for Applying Statistical Testing to the 2008-2012 ACS 5-Year Data:
#         overlapping periods, SE(A-B) = sqrt(1 - C) * sqrt(SE(A)^2 + SE(B)^2).
# These are approximations that ignore covariance; results say so where it matters.

Z90 <- 1.645  # ACS MOEs are 90% (1.65 for 2005 and earlier releases; all our releases are 2009+)

moe_to_se <- function(moe) moe / Z90

# [H8 eq.1] MOE of a sum of estimates. Missing component MOEs make the result missing.
moe_sum <- function(moe) sqrt(sum(moe^2))

# [H8 eq.6] Proportion P = X/Y where X is a subset of Y. If the radicand is negative use the
# ratio formula; if P = 1 use MOE(X)/Y ([ST]).
moe_prop <- function(x, y, moe_x, moe_y) {
  p <- x / y
  radicand <- moe_x^2 - p^2 * moe_y^2
  out <- ifelse(radicand < 0, sqrt(moe_x^2 + p^2 * moe_y^2), sqrt(pmax(radicand, 0))) / y
  ifelse(!is.na(p) & p == 1, moe_x / y, out)
}

# [H8 eq.7] Ratio R = X/Y where X is not a subset of Y (means, per capita values, change ratios).
moe_ratio <- function(x, y, moe_x, moe_y) sqrt(moe_x^2 + (x / y)^2 * moe_y^2) / y


# Coefficient of variation in percent (SE / estimate * 100).
cv_percent <- function(est, moe) ifelse(is.na(est) | est == 0, NA_real_, 100 * moe_to_se(moe) / abs(est))

# Reliability label from the CV. The Census Bureau sets no fixed threshold ("no hard-and-fast
# rules"); the cut-offs are project settings (cv_caution, cv_unreliable).
reliability <- function(cv, caution = 15, unreliable = 30) {
  ifelse(is.na(cv), NA_character_,
         ifelse(cv > unreliable, "unreliable", ifelse(cv > caution, "caution", "reliable")))
}

# Test whether A and B differ at the 90% level.
#   overlap    fraction of overlapping years between two multiyear periods (C in [ST12]);
#   part_share for a study area that is part of benchmark B, the study area's share of B's
#              denominator (w). With B = w*A + (1-w)*Rest and A, Rest independent samples,
#              Var(A - B) = Var(A)(1 - 2w) + Var(B). Census formulas omit this covariance and
#              are then conservative; we apply the adjustment for weighted-mean statistics
#              (shares, rates, ratios) and fall back to the conservative form if it is negative.
# MOEs of 0 (controlled estimates, census counts) are valid; NA MOEs make the test unavailable.
diff_test <- function(a, moe_a, b, moe_b, overlap = 0, part_share = 0, z_crit = Z90) {
  var_a <- moe_to_se(moe_a)^2
  var_b <- moe_to_se(moe_b)^2
  var_indep <- var_a + var_b
  var_dep <- var_a * (1 - 2 * part_share) + var_b
  var_diff <- ifelse(!is.na(var_dep) & var_dep > 0, var_dep, var_indep)
  var_diff <- (1 - overlap) * var_diff
  se <- sqrt(var_diff)
  z <- ifelse(se > 0, (a - b) / se, ifelse(a == b, 0, Inf * sign(a - b)))
  data.frame(diff = a - b, moe_diff = Z90 * se, z = z,
             significant = !is.na(z) & abs(z) > z_crit, testable = !is.na(z),
             stringsAsFactors = FALSE)
}

# Fraction of overlapping years between two periods given as start/end years.
period_overlap <- function(start1, end1, start2, end2) {
  shared <- pmax(0, pmin(end1, end2) - pmax(start1, start2) + 1)
  len <- end1 - start1 + 1
  ifelse(len > 0, shared / len, 0)
}

# Median of a binned distribution by linear interpolation within the bin containing the
# 50th percentile (the standard grouped-data method). Returns the value and a status:
# "open_interval" when the median falls in an open-ended top or bottom bin (value is then
# the bin bound), "invalid_denominator" when the distribution is empty.
median_from_bins <- function(counts, lower, upper) {
  if (is.unsorted(lower)) stop("median_from_bins(): bins must be ordered from low to high.")
  ok <- !is.na(counts)
  if (!all(ok)) return(list(value = NA_real_, status = "missing", bound = NA_character_))
  total <- sum(counts)
  if (total <= 0) return(list(value = NA_real_, status = "invalid_denominator", bound = NA_character_))
  half <- total / 2
  cum <- cumsum(counts)
  k <- which(cum >= half)[1]
  below <- if (k == 1) 0 else cum[k - 1]
  if (is.infinite(upper[k])) return(list(value = lower[k], status = "open_interval", bound = "lower"))
  if (is.infinite(lower[k])) return(list(value = upper[k], status = "open_interval", bound = "upper"))
  value <- lower[k] + (half - below) / counts[k] * (upper[k] - lower[k])
  list(value = value, status = "ok", bound = NA_character_)
}

# Parse ACS distribution labels such as "Less than $10,000", "$10,000 to $14,999",
# "$200,000 or more", "Built 1939 or earlier" into numeric [lower, upper) bounds.
parse_bin_label <- function(label) {
  last <- sub("^.*!!", "", label)
  nums <- as.numeric(gsub(",", "", regmatches(last, gregexpr("[0-9][0-9,]*(\\.[0-9]+)?", last))[[1]]))
  if (grepl("less than|under", last, ignore.case = TRUE) && length(nums) >= 1) return(c(0, nums[1]))
  if (grepl("or more|and over|or later|\\+", last, ignore.case = TRUE) && length(nums) >= 1) return(c(nums[1], Inf))
  if (grepl("or earlier|and under", last, ignore.case = TRUE) && length(nums) >= 1) return(c(-Inf, nums[1] + 1))
  if (grepl(" to | - ", last) && length(nums) >= 2) return(c(nums[1], nums[2] + 1))
  c(NA_real_, NA_real_)
}

# Annualized growth rate between two values `years` apart.
annual_rate <- function(start, end, years) {
  ifelse(is.na(start) | is.na(end) | start <= 0 | end <= 0 | years <= 0, NA_real_,
         (end / start)^(1 / years) - 1)
}

# ---- Inflation ---------------------------------------------------------------------

# Factor that converts dollars of `from_year` into dollars of `to_year` using an annual
# price index table (columns year, index). Missing years give NA (never silently imputed).
inflation_factor <- function(from_year, to_year, index_table) {
  idx_from <- index_table$index[match(from_year, index_table$year)]
  idx_to <- index_table$index[match(to_year, index_table$year)]
  idx_to / idx_from
}

# ---- Describing change ---------------------------------------------------------------

# Direction word for a change, honoring statistical significance when uncertainty exists.
# `significant` is NA for series without sampling error (census counts, administrative data).
change_direction <- function(change, significant = NA, tolerance = 0) {
  if (is.na(change)) return("unavailable")
  if (!is.na(significant) && !significant) return("not_significant")
  if (abs(change) <= tolerance) return("flat")
  if (change > 0) "up" else "down"
}

# Turning points of a series without sampling error: the peak and trough years, reported
# only when they are interior (not at the first or last observation).
turning_points <- function(period, value) {
  ok <- !is.na(value)
  period <- period[ok]
  value <- value[ok]
  if (length(value) < 3) return(list(peak = NA, trough = NA))
  peak <- which.max(value)
  trough <- which.min(value)
  list(peak = if (peak %in% c(1, length(value))) NA else period[peak],
       peak_value = value[peak],
       trough = if (trough %in% c(1, length(value))) NA else period[trough],
       trough_value = value[trough])
}
