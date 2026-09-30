test_that("the Indiana provider listing tables are parsed by column name", {
  table <- function(header, rows) paste0("<table><tbody><tr>", paste0("<td><strong>", header, "</strong></td>", collapse = ""), "</tr>",
    paste0("<tr>", vapply(rows, function(r) paste0("<td>", r, "</td>", collapse = ""), ""), "</tr>", collapse = ""), "</tbody></table>")
  html <- paste(
    table(c("Facility Number", "County", "Provider Type", "PTQ Level", "Capacity"), list(c("1", "LAKE", "Licensed Center", "Level 4", "100"), c("2", "ST JOSEPH", "Licensed Center", "Level 1", "40"))),
    table(c("Facility Number", "County", "Provider Type", "PTQ Level", "Capacity"), list(c("3", "LAKE", "Licensed Home", "Level 3", "10"))),
    table(c("Facility Number", "County", "Provider Type", "PTQ Level"), list(c("4", "LAKE", "Registered&nbsp;Ministry", "Level 0"))))
  d <- fssa_parse(html)
  expect_equal(d$type, c("Licensed Center", "Licensed Center", "Licensed Home", "Registered Ministry"))
  expect_equal(d$capacity, c(100, 40, 10, NA))
  expect_error(fssa_parse(table(c("County"), list("LAKE"))), "1 tables")
  real <- fssa_listings
  on.exit(assign("fssa_listings", real, envir = globalenv()))
  d$key <- c("county:18089", "county:18141", "county:18089", "county:18089")
  d$retrieved <- "2026-09-30"
  assign("fssa_listings", function() d, envir = globalenv())
  a <- fssa_areas()
  lake <- a[a$key == "county:18089", ]
  expect_equal(c(lake$centers, lake$homes, lake$ministries, lake$capacity, lake$capacity_ptq34), c(1, 1, 1, 110, 110))
  expect_equal(a$capacity[a$key == "state:18"], 150)
})
