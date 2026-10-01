test_that("the command line takes switches, valued options and --key=value", {
  p <- parse_cli(c("build", "gary-in", "--offline", "--refresh", "census_acs5,bls", "--workers=2"))
  expect_equal(p$cmd, "build")
  expect_equal(p$args, "gary-in")
  expect_true(p$flags$offline)
  expect_equal(p$flags$refresh, "census_acs5,bls")
  expect_equal(p$flags$workers, "2")
})

test_that("a mistyped or incomplete option stops instead of running with defaults", {
  expect_error(parse_cli(c("build", "--ofline", "gary-in")), "Unknown option --ofline")
  expect_error(parse_cli(c("build", "gary-in", "--refresh")), "--refresh needs a value")
  expect_error(parse_cli(c("build", "--refresh", "--offline", "gary-in")), "--refresh needs a value")
  expect_error(parse_cli(c("build", "--force=yes")), "--force takes no value")
  expect_error(gr_main(c("batch", "--workers", "0")), "--workers needs a whole number")
  expect_error(gr_main(c("build", "gary-in", "--formats", "pdf")), "--formats takes html, typst")
  expect_error(gr_main(c("find")), "Usage: Rscript gr.R find")
  expect_error(gr_main(c("build", "no-such-report")), "Unknown report 'no-such-report'")
})

test_that("an invalid Census API key is reported as such", {
  page <- httr2::response(status_code = 200, headers = list(`Content-Type` = "text/html"),
                          body = charToRaw("<html><head><title>Invalid Key</title></head></html>"))
  expect_error(census_parse(page, "ACS 2024 B01003 state"), "rejected CENSUS_API_KEY")
  json <- httr2::response(status_code = 200, body = charToRaw('[["NAME","state"],["Delaware","10"]]'))
  expect_equal(census_parse(json, "test")$NAME, "Delaware")
})
