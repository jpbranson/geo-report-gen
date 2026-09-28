test_that("settings resolve default < profile < report < block options; typos are errors", {
  expect_equal(resolve_settings()$history_start, "1990")
  expect_equal(resolve_settings(NULL, "early-childhood")$history_start, "2000")
  s <- resolve_settings("gary-in", "early-childhood", list(history_start = "1995"))
  expect_equal(s$history_start, "1995")
  expect_equal(attr(s, "origin")$history_start, "block options")
  expect_error(resolve_settings(NULL, NULL, list(histroy_start = "1")), "Unknown setting")
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
})

test_that("every profile, manifest and catalog table in the project is valid", {
  for (f in c(list.files(root_path("profiles"), full.names = TRUE),
              list.files(root_path("config", "manifests"), full.names = TRUE))) {
    expect_no_error(load_manifest(f))
  }
  expect_equal(validate_catalog(), character())
})
