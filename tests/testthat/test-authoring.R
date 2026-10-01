# Inline and bulk editing, run against a throwaway copy of the project's configuration and
# content with a small hand-made report (no data needed). Both workflows must update the same
# canonical records (content/text.csv) and refuse to overwrite conflicting edits.

temp_project <- function() {
  tmp <- tempfile("gr-authoring-")
  dir.create(tmp)
  for (d in c("config", "content", "catalog", "profiles")) file.copy(root_path(d), tmp, recursive = TRUE)
  tmp
}

# A generated report as compose would leave it: report.qmd, its base texts and a snapshot.
fake_report <- function(id) {
  dir.create(snapshot_dir(id), recursive = TRUE, showWarnings = FALSE)
  rows <- data.frame(id = c("overview", "key-facts"), type = c("section", "block"), ref = c("", "key-facts"),
                     kind = c("section", "facts"), stringsAsFactors = FALSE)
  snap <- list(rows = rows, blocks = list(`key-facts` = list(kind = "facts")),
               values = list(report = list(area = "Gary city, Indiana", area_population = "68,113"),
                             `key-facts` = list(latest_period = "2020–2024")))
  records <- load_text_records()
  fields <- c("report.title", "overview.title", "key-facts.title", "key-facts.prose", "key-facts.caption")
  snap$texts <- stats::setNames(lapply(fields, function(f) current_field_text(records, f, id, "general", snap, NULL)), fields)
  saveRDS(snap, file.path(snapshot_dir(id), "report.rds"))
  write_json_file(snap$texts, file.path(snapshot_dir(id), "qmd_base.json"))
  tx <- snap$texts
  write_text_file(c("---", paste0("title: ", yaml_str(tx[["report.title"]])), "---", "",
                    paste0("# ", tx[["overview.title"]], " {#sec-overview}"), "",
                    paste0("## ", tx[["key-facts.title"]], " {#blk-key-facts}"), "",
                    text_div("key-facts.prose", tx[["key-facts.prose"]], "key-facts"),
                    "```{r}", "#| label: tbl-key-facts", chunk_option("tbl-cap", tx[["key-facts.caption"]]),
                    "gr_block(gr, \"key-facts\")", "```"),
                  file.path(report_dir(id), "report.qmd"))
  save_qmd_skeleton(id)
}

edit_qmd <- function(id, pattern, replacement) {
  path <- file.path(report_dir(id), "report.qmd")
  write_text_file(sub(pattern, replacement, readLines(path, encoding = "UTF-8")), path)
}

report_record <- function(field) {
  r <- load_text_records()
  r$text[r$field_id == field & r$scope == "report:gary-in"]
}

test_that("inline edits to a heading, prose and a caption become report-scope records", {
  withr::local_envvar(GR_ROOT = temp_project())
  fake_report("gary-in")
  edit_qmd("gary-in", "^## Key facts", "## Headline numbers")
  edit_qmd("gary-in", "^\\{summary_sentence\\}$", "Gary has 68,113 residents; see {benchmark_list}.")
  edit_qmd("gary-in", "tbl-cap: .*", "tbl-cap: \"Selected indicators, edited inline\"")
  h <- harvest_report("gary-in")
  expect_setequal(names(h$applied), c("key-facts.title", "key-facts.prose", "key-facts.caption"))
  expect_equal(report_record("key-facts.title"), "Headline numbers")
  expect_equal(report_record("key-facts.caption"), "Selected indicators, edited inline")
  # The next build resolves the edited text (so it survives regeneration)...
  snap <- readRDS(file.path(snapshot_dir("gary-in"), "report.rds"))
  expect_equal(current_field_text(load_text_records(), "key-facts.title", "gary-in", "general", snap, NULL),
               "Headline numbers")
  # ...and the typed-in number is remembered, so a later build warns when the data move.
  r <- load_text_records()
  facts <- r$fixed_facts[r$field_id == "key-facts.prose" & r$scope == "report:gary-in"]
  w <- stale_fact_warnings(list(`key-facts.prose` = list(fixed_facts = facts)),
                           list(report = list(area_population = "67,450")))
  expect_match(w, "68,113")
})

test_that("an inline edit that conflicts with a newer canonical edit is not saved", {
  withr::local_envvar(GR_ROOT = temp_project())
  fake_report("gary-in")
  save_text_records(upsert_record(load_text_records(), "key-facts.title", "report:gary-in", "Changed in the CSV"))
  edit_qmd("gary-in", "^## Key facts", "## Changed inline")
  expect_error(harvest_report("gary-in"), "also changed")
  expect_true(file.exists(file.path(report_dir("gary-in"), "conflicts.csv")))
  expect_equal(report_record("key-facts.title"), "Changed in the CSV")
})

test_that("text typed outside the editable fields stops the harvest before it can be lost", {
  withr::local_envvar(GR_ROOT = temp_project())
  fake_report("gary-in")
  edit_qmd("gary-in", "^## Key facts \\{#blk-key-facts\\}$", "## Key facts {#blk-key-facts}\n\nA paragraph typed under the heading.")
  edit_qmd("gary-in", "^\\{summary_sentence\\}$", "Edited inside the fences.")
  expect_error(harvest_report("gary-in"), "outside the editable fields")
  expect_equal(report_record("key-facts.prose"), character())   # nothing saved
})

test_that("gr.R new adds a report whose manifest comes from chosen subjects and metrics", {
  withr::local_envvar(GR_ROOT = temp_project())
  new_report("travis-housing", list(geo = "county:48453", subjects = "housing", metrics = "median_age_acs"))
  expect_true("travis-housing" %in% report_table()$report_id)
  m <- load_manifest(root_path("config", "manifests", "travis-housing.csv"))
  expect_true(all(c("housing", "tenure-trend", "selected-measures", "median-age-acs", "sources") %in% m$id))
  expect_true(any(load_text_records()$field_id == "selected-measures.title"))
  expect_error(new_report("travis-housing", list(geo = "county:48453")), "already exists")
  expect_error(new_report("bad-union", list(geo = "zcta:78704 + place:4805000", mode = "union")), "overlap")
})

test_that("bulk export and import update the same records and reject stale exports", {
  withr::local_envvar(GR_ROOT = temp_project())
  fake_report("gary-in")
  path <- tempfile(fileext = ".csv")
  x <- text_export("gary-in", path)
  edited <- "Selected indicators, with \"quotes\", a comma\nand a second line"
  x$text[x$field_id == "key-facts.caption"] <- edited
  write_table(x, path)
  text_import(path)
  expect_equal(report_record("key-facts.caption"), edited)
  # The same export edited again is stale: the canonical text changed since it was written.
  x$text[x$field_id == "key-facts.caption"] <- "Another edit"
  write_table(x, path)
  expect_error(text_import(path), "changed in content since export")
  expect_equal(report_record("key-facts.caption"), edited)
  # The list of conflicts goes beside the imported file and never replaces it, whatever its name.
  odd <- sub("[.]csv$", ".CSV", path)
  write_table(x, odd)
  expect_error(text_import(odd), "changed in content since export")
  expect_true("Another edit" %in% read_table(odd)$text)
  expect_true(file.exists(paste0(tools::file_path_sans_ext(odd), "-conflicts.csv")))
  # After a rebuild, text imported to the default scope stays hidden in gary-in by its report record.
  fake_report("gary-in")
  x <- text_export("gary-in", path)
  x$text[x$field_id == "key-facts.caption"] <- "For every report"
  x$edit_scope <- "default"
  write_table(x, path)
  run_reset(offline = TRUE)
  text_import(path)
  expect_match(run$warnings, "keeps its own report:gary-in record", all = FALSE)
})

test_that("a build reuses the last compose only while nothing it read has changed", {
  withr::local_envvar(GR_ROOT = temp_project())
  fake_report("gary-in")
  for (f in c("values.json", "theme.scss")) write_text_file("{}", file.path(snapshot_dir("gary-in"), f))
  raw <- file.path(cache_root(), "raw", "test", "table.parquet")
  dir.create(dirname(raw), recursive = TRUE, showWarnings = FALSE)
  write_cache_file(data.frame(a = 1), raw)
  prev <- list(status = "ok", complete = TRUE, compose_key = compose_key("gary-in"),
               sources = list(list(file = "raw/test/table.parquet", stamp = file_stamp(raw))))
  expect_true(reusable_compose("gary-in", prev))
  expect_false(reusable_compose("gary-in", utils::modifyList(prev, list(complete = FALSE))))  # a source had failed
  Sys.setFileTime(raw, Sys.time() + 60)                                                        # raw data replaced
  expect_false(reusable_compose("gary-in", prev))
  prev$sources[[1]]$stamp <- file_stamp(raw)
  save_text_records(upsert_record(load_text_records(), "key-facts.title", "default", "Changed"))  # text edited
  expect_false(reusable_compose("gary-in", prev))
})

test_that("the compose key holds the code and catalog as loaded, so a later edit means a new compose", {
  withr::local_envvar(GR_ROOT = temp_project())
  fake_report("gary-in")
  loaded <- get("loaded_inputs_hash", envir = memo)
  on.exit(assign("loaded_inputs_hash", loaded, envir = memo), add = TRUE)
  rm("loaded_inputs_hash", envir = memo)   # load the temporary project
  key <- compose_key("gary-in")
  cat("\n", file = root_path("catalog", "subjects.csv"), append = TRUE)
  expect_identical(compose_key("gary-in"), key)   # this process still holds what it loaded
  rm("loaded_inputs_hash", envir = memo)            # the next process loads the edited table
  expect_false(identical(compose_key("gary-in"), key))
})
