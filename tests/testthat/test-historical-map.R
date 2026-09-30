test_that("historical counties are chosen by their interior point and touched by overlap", {
  square <- function(x, y, s = 1) sf::st_polygon(list(rbind(c(x, y), c(x + s, y), c(x + s, y + s), c(x, y + s), c(x, y))))
  crs <- 4269
  state <- sf::st_sf(GEOID = "10", NAME = "Delaware", geometry = sf::st_sfc(square(0, 0, 2), crs = crs))
  hist <- sf::st_sf(NHGISNAM = c("Kent", "Sussex", "Elsewhere"), geometry = sf::st_sfc(square(0, 0), square(1, 0), square(5, 5), crs = crs))
  kept <- historical_counties(hist, state)
  expect_equal(kept$NHGISNAM, c("Kent", "Sussex"))
  study <- sf::st_sf(label = "x", geometry = sf::st_sfc(square(0.1, 0.1, 0.5), crs = crs))
  expect_equal(historical_touched(kept, study), c(TRUE, FALSE))
})

test_that("NHGIS boundary extracts are named by level and census year", {
  seen <- NULL
  real <- nhgis_extract
  on.exit(assign("nhgis_extract", real, envir = globalenv()))
  assign("nhgis_extract", function(name, body, link = "tableData") { seen <<- list(name = name, body = body, link = link); stop("stop here") }, envir = globalenv())
  expect_error(nhgis_boundaries("county", 1850), "stop here")
  expect_equal(seen$name, "shape-us_county_1850_tl2008")
  expect_equal(seen$body$shapefiles[[1]], "us_county_1850_tl2008")
  expect_equal(seen$link, "gisData")
})
