test_that("NDCP serves prices for counties and the labor force rate for states", {
  real <- ndcp_long
  on.exit(assign("ndcp_long", real, envir = globalenv()))
  assign("ndcp_long", function() data.frame(key = c("county:48453", "state:48"), year = 2022L, MCINFANT = c(300, NA),
                                            MFCCSA = c(180, NA), FLFPR_20to64_UNDER6 = c(73.1, 67), stringsAsFactors = FALSE), envir = globalenv())
  pieces <- data.frame(key = c("county:48453", "state:48"), type = c("county", "state"), geoid = c("48453", "48"))
  v <- get_provider("dol_ndcp")$fetch(c("MCINFANT", "MFCCSA", "FLFPR_20to64_UNDER6"), pieces, 2022L)
  expect_equal(nrow(v), 4)
  expect_equal(v$estimate[v$geo == "state:48"], 67)
  expect_false("MCINFANT" %in% v$variable[v$geo == "state:48"])
  expect_equal(v$estimate[v$geo == "county:48453" & v$variable == "MFCCSA"], 180)
  expect_equal(nrow(get_provider("dol_ndcp")$fetch("MCINFANT", pieces[2, ], 2022L)), 0)   # a state has no prices
})

test_that("NDCP metrics merged into their operational twins are gone", {
  ids <- read_table(root_path("catalog", "metrics.csv"))$metric_id
  expect_false(any(c("childcare_price_home_infant_ndcp", "childcare_price_burden_center_infant_ndcp") %in% ids))
})
