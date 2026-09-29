test_that("geography specs are parsed strictly; ZIP codes are not ZCTAs", {
  expect_equal(parse_geo("county:18089@2024", 2020)$key, "county:18089")
  expect_equal(parse_geo("county:18089@2024", 2020)$vintage, 2024L)
  expect_error(parse_geo("zip:78704", 2024), "ZIP Code Tabulation Area")
  expect_error(parse_geo("county:1808", 2024), "not a valid county")
  expect_error(parse_geo("planet:1", 2024), "Unknown geography type")
})

test_that("a list of areas needs an explicit mode, and 'separate' makes one report per area", {
  expect_error(resolve_area(parse_geo_list("county:48453 + county:48491", 2024), "single", 2024), "explicit mode")
  r <- data.frame(report_id = "x", geography = "place:1827000 + place:4805000", mode = "separate", label = "",
                  profile = "general", manifest = "", vintage = "", enabled = "TRUE", note = "")
  e <- expand_reports(r)
  expect_equal(e$report_id, c("x-1827000", "x-4805000"))
  expect_equal(e$mode, c("single", "single"))
})

test_that("unions drop duplicates and members that lie inside another member", {
  a <- resolve_area(parse_geo_list("county:48453 + county:48453 + state:48", 2024), "union", 2024)
  expect_equal(a$pieces$key, "state:48")
  expect_match(paste(a$notes, collapse = " "), "Duplicate")
  expect_match(paste(a$notes, collapse = " "), "inside Texas")
})

test_that("a county plus an overlapping city counts every resident once", {
  a <- resolve_area(parse_geo_list("county:48453 + place:4805000", 2024), "union", 2024)
  parts <- place_parts("4805000", 2024)
  travis <- geo_info("county:48453", 2024)$pop
  expect_equal(a$pop, travis + sum(parts$pop[parts$county != "48453"]))
  expect_false("place:4805000" %in% a$pieces$key)
  expect_setequal(unique(a$pieces$type), c("county", "place_part"))
})

test_that("overlapping members without published parts are rejected with an explanation", {
  expect_error(resolve_area(parse_geo_list("zcta:78704 + place:4805000", 2024), "union", 2024),
               "overlap.*Census Bureau does not publish")
})

test_that("benchmarks: containing parents, plus large intersecting counties; small ones in notes", {
  area <- resolve_area(parse_geo_list("place:4805000", 2024), "single", 2024)
  b <- choose_benchmarks(area, resolve_settings())
  expect_equal(vapply(b, function(e) e$pieces$key, ""),
               c("county:48453", "county:48491", "state:48", "region:3", "nation:US"))
  expect_false(b[[1]]$contains_study)                 # Travis holds most of Austin, not all
  expect_true(b[[3]]$contains_study)
  expect_match(paste(attr(b, "notes"), collapse = " "), "Hays County")
})

test_that("the same territory under two names is shown once (DC as state and county)", {
  dc <- function(type, geoid) data.frame(key = paste0(type, ":", geoid), type = type, geoid = geoid,
                                         name = "District of Columbia", pop = 700000)
  expect_true(same_territory(dc("state", "11"), dc("county", "11001"), 2024))
  expect_false(same_territory(dc("state", "11"), dc("county", "12001"), 2024))
})

test_that("short names drop only a trailing state or metro area suffix", {
  expect_equal(short_label("Gary city, Indiana"), "Gary")
  expect_equal(short_label("Lake County, Indiana"), "Lake County")
  expect_equal(short_label("Kansas City, MO-KS Metro Area"), "Kansas City")
  expect_equal(short_label("Travis, Williamson and Hays counties"), "Travis, Williamson and Hays counties")
  expect_equal(short_label("Travis, Williamson and Hays counties, Texas"), "Travis, Williamson and Hays counties")
  expect_equal(short_label("Combined area (5 counties, Texas)"), "Combined area (5 counties, Texas)")
})
