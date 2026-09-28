# Tests run offline. A temporary copy of tests/fixtures/cache (real Census API responses,
# public domain) stands in for the shared cache, so geography tests are deterministic and
# nothing is written to the project's own cache.
root <- normalizePath(file.path("..", ".."), winslash = "/")
cache <- file.path(tempdir(), "gr-test-cache")
unlink(cache, recursive = TRUE)
dir.create(cache)
file.copy(list.files(file.path(root, "tests", "fixtures", "cache"), full.names = TRUE), cache, recursive = TRUE)
Sys.setenv(GR_ROOT = root, GR_CACHE = cache)
source(file.path(root, "R", "load.R"))
run_reset(offline = TRUE)

# Long-form data as providers return it (only the columns the metric engine reads).
long <- function(geo, variable, estimate, moe = 0, status = "ok") {
  data.frame(geo = geo, variable = variable, estimate = estimate, moe = moe, status = status,
             bound = NA_character_, stringsAsFactors = FALSE)
}

recipe <- function(...) {
  utils::modifyList(list(metric_id = "test", stat_type = "count", numerator = "", denominator = "",
                         published_var = "", bins_table = "", scale = "1"), list(...))
}
