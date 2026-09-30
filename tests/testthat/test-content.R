test_that("settings resolve default < profile < library block < report < manifest options; typos are errors", {
  expect_equal(resolve_settings()$history_start, "1990")
  expect_equal(resolve_settings(NULL, "early-childhood")$history_start, "2000")
  s <- resolve_settings("gary-in", "early-childhood", library = list(history_start = "1970"))
  expect_equal(s$history_start, "1970")
  expect_equal(attr(s, "origin")$history_start, "block library")
  expect_equal(resolve_settings("ct-capitol", "general", library = list(theme = "default"))$theme, "civic")  # report wins
  s <- resolve_settings("ct-capitol", "general", list(theme = "default"), list(theme = "minimal", history_start = "2010"))
  expect_equal(c(s$theme, s$history_start), c("minimal", "2010"))
  expect_equal(attr(s, "origin")$history_start, "manifest options")
  expect_error(resolve_settings(NULL, NULL, block_options = list(histroy_start = "1")), "Unknown setting")
})

test_that("a manifest row's options override its library block's options", {
  m <- load_manifest(root_path("profiles", "general.csv"))
  row <- as.list(m[m$id == "unemployment-trend", ])
  row$options <- "history_start=2010"
  lib <- split_block_options(row$library_options)
  own <- split_block_options(row$options)
  expect_equal(lib$settings$history_start, "1990")
  expect_equal(resolve_settings("gary-in", "general", lib$settings, own$settings)$history_start, "2010")
  expect_error(parse_options("history_start=1970; history_start=2000"), "given twice")
})

test_that("text resolves report > profile > default, then the library block, then the kind template", {
  recs <- data.frame(field_id = c("b1.title", "b1.title", "lib.title", "@metric.title", "b2.caption"),
                     scope = c("default", "report:r", "default", "default", "profile:p"),
                     text = c("default", "report", "library", "template", "profile"),
                     updated = "", fixed_facts = "", note = "")
  expect_equal(resolve_text(recs, "b1.title", "metric", "r", "p")$text, "report")
  expect_equal(resolve_text(recs, "b1.title", "metric", "other", "p")$text, "default")
  expect_equal(resolve_text(recs, "b3.title", "metric", "r", "p", ref = "lib")$text, "library")
  expect_equal(resolve_text(recs, "b3.title", "metric", "r", "p")$text, "template")
  expect_equal(resolve_text(recs, "b2.caption", "metric", "r", "p")$text, "profile")
})

test_that("templates fill named values only and never evaluate anything", {
  expect_equal(fill_template("Hello {name}!", list(name = "Gary")), "Hello Gary!")
  expect_equal(fill_template("{x} and {missing}", list(x = "1")), "1 and {missing}")
  expect_equal(fill_template("{system('echo hi')}", list()), "{system('echo hi')}")
  expect_equal(unknown_placeholders("{a} {b}", "a"), "b")
})

test_that("an unknown placeholder stops compose; a known one without a value is a warning", {
  run_reset(offline = TRUE)
  texts <- list(b.prose = list(text = "Relative to its {index_base} count in {area}."))
  check_placeholders(texts, list(report = list(area = "Gary"), b = list(index_base = NA)))
  expect_match(run$warnings, "b.prose: \\{index_base\\} has no value")
  expect_error(check_placeholders(texts, list(report = list(area = "Gary"), b = list())), "Unknown placeholders")
})

test_that("CSV tables keep Unicode, commas, quotes, line breaks and leading zeros", {
  df <- data.frame(id = c("01", "02"), text = c("Año, \"quoted\"\nsecond line", "Überlingen – ok"))
  path <- tempfile(fileext = ".csv")
  write_table(df, path)
  expect_equal(read_table(path), df)
})

test_that("line breaks saved as CRLF by another program read back as LF", {
  path <- tempfile(fileext = ".csv")
  writeBin(charToRaw("id,text\r\n1,\"first\r\nsecond\"\r\n"), path)
  expect_equal(read_table(path)$text, "first\nsecond")
})

test_that("manifests reject duplicate ids, unknown blocks and rows before the first section", {
  m <- data.frame(id = c("intro", "intro", "x"), type = c("text", "section", "block"), ref = c("intro", "", "nope"),
                  enabled = "TRUE", compare = "", viz = "", options = "")
  p <- paste(validate_manifest(m), collapse = "\n")
  expect_match(p, "Duplicate IDs: intro")
  expect_match(p, "first row must be a section")
  expect_match(p, "Unknown block reference")
  # A chart form the block does not draw is an error, not silently ignored.
  path <- tempfile(fileext = ".csv")
  write_table(data.frame(id = c("s", "unemployment-trend"), type = c("section", "block"), ref = c("", "unemployment-trend"),
                         enabled = "TRUE", compare = "", viz = c("", "dot"), options = ""), path)
  expect_error(load_manifest(path), "viz")
})

test_that("every profile, manifest and catalog table in the project is valid", {
  for (f in c(list.files(root_path("profiles"), full.names = TRUE),
              list.files(root_path("config", "manifests"), full.names = TRUE))) {
    expect_no_error(load_manifest(f))
  }
  expect_equal(validate_catalog(), character())
})
