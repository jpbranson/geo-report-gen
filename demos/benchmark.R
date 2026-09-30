# Batch benchmark: a cold cache, a warm cache, a resumed run, and what edits to text, theme,
# geography and data invalidate. It runs `gr.R batch` in a temporary copy of the project with
# an empty cache, so the real project and its shared cache are not touched, and writes the
# numbers to docs/benchmark.csv. With --warm it uses the project's cache instead and skips the
# cold run (a cold run requests every source again, including new IPUMS extracts).
#   Rscript demos/benchmark.R [--warm] [report ids]      (default: every enabled report)
root <- normalizePath(".", winslash = "/")
ids <- commandArgs(trailingOnly = TRUE)
warm <- "--warm" %in% ids
ids <- setdiff(ids, "--warm")
work <- file.path(tempdir(), "gr-benchmark")
unlink(work, recursive = TRUE)
dir.create(work)
for (f in c("R", "config", "content", "catalog", "profiles", "modules", "quarto", "gr.R", ".env")) {
  file.copy(file.path(root, f), work, recursive = TRUE)
}
env <- c("current", GR_ROOT = work, GR_CACHE = if (warm) file.path(root, "cache") else file.path(work, "cache"),
         R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))

batch <- function(step, args = character(), stop_after = NULL) {
  p <- processx::process$new(file.path(R.home("bin"), "Rscript"), c("--vanilla", "gr.R", "batch", ids, args),
                             wd = work, env = env, stdout = file.path(work, "batch.log"), stderr = "2>&1")
  if (!is.null(stop_after)) {
    Sys.sleep(stop_after)   # simulate an interruption (a crash or Ctrl+C)
    p$kill_tree()
    return(NULL)
  }
  p$wait()
  logs <- sort(list.files(file.path(work, "reports", "_batch"), full.names = TRUE))
  log <- jsonlite::fromJSON(logs[length(logs)])
  r <- log$results
  message(step, ": ", log$seconds$total, " s")
  data.frame(step = step, seconds = log$seconds$total, compose_s = log$seconds$compose_phase,
             render_s = log$seconds$render_phase, requests = log$requests, cache_hits = log$cache_hits,
             cache_misses = log$cache_misses, rendered = sum(r$action == "rendered"),
             up_to_date = sum(r$action == "up to date"), failed = sum(r$status != "ok"))
}

edit <- function(file, from, to) {
  path <- file.path(work, file)
  text <- sub(from, to, readLines(path, warn = FALSE, encoding = "UTF-8"))
  writeBin(charToRaw(paste0(paste(text, collapse = "\n"), "\n")), path)
}

results <- rbind(
  batch(if (warm) "first build of a fresh copy (warm cache)" else "cold: empty cache"),
  batch("warm: nothing changed"),
  batch("warm: forced re-render of everything", "--force"))
edit("content/prose/intro.md", "^This profile", "This community profile")
batch("interrupted after 70 s", stop_after = 70)
results <- rbind(results,
  batch("resumed after the interruption (default intro text edited)"),
  { edit("config/themes.csv", "^default,color_accent,#1f5aa6", "default,color_accent,#2b6f8c")
    batch("theme edit (default accent color)") },
  { edit("config/reports.csv", "county:18089,single", "county:18089 + county:18127,union")
    batch("geography edit (lake-in becomes Lake + Porter counties)") },
  # A refresh re-downloads into the cache, so it is left out when the cache is the project's.
  if (!warm) batch("data refresh (building permits)", c("--refresh", "census_bps")))
print(results, row.names = FALSE)
utils::write.csv(results, file.path(root, "docs", "benchmark.csv"), row.names = FALSE)
