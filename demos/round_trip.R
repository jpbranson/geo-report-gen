# Editing round trip on a real report: inline edits to prose, a caption and an axis label in
# report.qmd; a bulk edit through CSV; sections reordered by moving manifest rows; then a data
# refresh and rebuild, after which every edit must still be there. Finally a conflicting edit
# is attempted. Runs in a temporary copy of the project and prints each check. The data come
# from the project's own cache/, and the refresh step downloads census_govfin into it again, so
# it needs the network and the keys in .env.
#   Rscript demos/round_trip.R
root <- normalizePath(".", winslash = "/")
work <- file.path(tempdir(), "gr-round-trip")
unlink(work, recursive = TRUE)
dir.create(work)
for (f in c("R", "config", "content", "catalog", "profiles", "modules", "quarto", "gr.R", ".env")) {
  file.copy(file.path(root, f), work, recursive = TRUE)
}
env <- c("current", GR_ROOT = work, GR_CACHE = file.path(root, "cache"),
         R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
gr <- function(...) {
  res <- processx::run(file.path(R.home("bin"), "Rscript"), c("--vanilla", "gr.R", ...), wd = work, env = env,
                       error_on_status = FALSE)
  invisible(paste(res$stdout, res$stderr))
}
path <- function(...) file.path(work, ...)
read <- function(p) readLines(p, warn = FALSE, encoding = "UTF-8")
write <- function(text, p) writeBin(charToRaw(paste0(paste(text, collapse = "\n"), "\n")), p)
check <- function(what, ok) cat(sprintf("[%s] %s\n", if (isTRUE(ok)) "ok" else "FAILED", what))

cat("1. Build gary-in\n")
gr("build", "gary-in")
qmd <- path("reports", "gary-in", "report.qmd")

cat("2. Inline edits in report.qmd: prose, a caption and an axis label\n")
q <- read(qmd)
prose <- grep('gr-field="unemployment-trend.prose"', q) + 1
q[prose] <- "Unemployment in {area_short} was {latest} in {latest_period} (prose edited inline)."
chunk <- grep("^#\\| label: fig-unemployment-trend", q)
q[chunk + 1] <- '#| fig-cap: "Unemployment rate, {area_short} and comparison areas (caption edited inline)"'
y <- chunk - 1 + grep("^#\\| gr-y-label:", q[chunk:(chunk + 8)])[1]
q[y] <- '#| gr-y-label: "Percent of the labor force (edited inline)"'
write(q, qmd)

cat("3. Bulk edit through CSV: export, change a caption, import\n")
csv <- path("gary-in-text.csv")
gr("text-export", "gary-in", csv)
x <- utils::read.csv(csv, colClasses = "character", check.names = FALSE, fileEncoding = "UTF-8-BOM")
x$text[x$field_id == "income-trend.caption"] <- "Median household income, in constant dollars (caption edited in bulk)"
utils::write.csv(x, csv, row.names = FALSE, fileEncoding = "UTF-8")
gr("text-import", csv)

cat("4. Reorder: a report manifest with the Housing section moved above Economy\n")
m <- utils::read.csv(path("profiles", "general.csv"), colClasses = "character")
sec <- cumsum(m$type == "section")
order_ <- c(which(sec <= 2), which(sec == 4), which(sec == 3), which(sec >= 5))
utils::write.csv(m[order_, ], path("config", "manifests", "gary-in.csv"), row.names = FALSE)
r <- read(path("config", "reports.csv"))
r <- sub("^gary-in,place:1827000,single,,general,,", "gary-in,place:1827000,single,,general,config/manifests/gary-in.csv,", r)
write(r, path("config", "reports.csv"))

cat("5. Rebuild with a data refresh (Census of Governments finance file re-downloaded)\n")
downloads <- function() sum(grepl("\tcensus_govfin\t", read(file.path(root, "cache", "requests.log"))))
before <- downloads()
out <- gr("build", "gary-in", "--refresh", "census_govfin")
q <- read(qmd)
html <- paste(read(path("reports", "gary-in", "report.html")), collapse = "\n")
check("inline prose survived the rebuild", any(grepl("(prose edited inline)", q, fixed = TRUE)))
check("inline caption survived the rebuild", any(grepl("(caption edited inline)", q, fixed = TRUE)))
check("inline axis label survived the rebuild", any(grepl("Percent of the labor force (edited inline)", q, fixed = TRUE)))
check("bulk caption is in the regenerated report", grepl("(caption edited in bulk)", html, fixed = TRUE))
check("placeholders in edited prose were filled", grepl("Unemployment in Gary was [0-9.]+% in 2025", html))
check("Housing now comes before Economy", grep("^# Housing", q) < grep("^# Economy", q))
recs <- utils::read.csv(path("content", "text.csv"), colClasses = "character", fileEncoding = "UTF-8-BOM")
check("the four edits are canonical records in content/text.csv", sum(recs$scope == "report:gary-in") == 4)
check("the data were re-downloaded", downloads() > before)

cat("6. A conflicting edit: the same title changed inline and in content/text.csv\n")
q <- read(qmd)
q <- sub("^## Unemployment rate", "## Joblessness (inline)", q)
write(q, qmd)
recs <- rbind(recs, data.frame(field_id = "unemployment-trend.title", scope = "report:gary-in", text = "Unemployment (CSV)",
                               updated = "", fixed_facts = "", note = ""))
utils::write.csv(recs, path("content", "text.csv"), row.names = FALSE, fileEncoding = "UTF-8")
out <- gr("build", "gary-in")
check("the build stops and names the conflict", grepl("also changed in content/text.csv", out))
check("conflicts.csv lists both versions", file.exists(path("reports", "gary-in", "conflicts.csv")))
