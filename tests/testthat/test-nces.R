test_that("NCES requires 95% reporting within every state part, including empty areas", {
  expect_equal(nces_sum(numeric(), character(), "students", 2024)$estimate, 0)
  expect_equal(nces_sum(c(rep(10, 19), NA), rep("10", 20), "students", 2024)$estimate, 190)
  missing <- nces_sum(c(rep(10, 100), NA), c(rep("10", 100), "18"), "students", 2024)
  expect_equal(missing$status, "unavailable")
  expect_match(missing$note, "Indiana")
  expect_length(get_provider("nces_ccd")$periods(list(history_start = 2030), list()), 0)
})

test_that("NCES excludes virtual offices locally and recomputes combined student-teacher ratios", {
  real <- nces_schools
  on.exit(assign("nces_schools", real, envir = globalenv()))
  assign("nces_schools", function(year) data.frame(
    id = c("a", "b", "c"), state = "10", county = c("10001", "10005", "10001"),
    lat = 39, lon = -75, virtual = c(FALSE, FALSE, TRUE), students = c(100, 300, 600),
    prek = c(0, 20, 0), teachers = c(10, 20, 40)), envir = globalenv())
  area <- function(id, keys) entity(id, "study", id, data.frame(key = keys, type = sub(":.*$", "", keys),
    geoid = sub("^[^:]*:", "", keys), name = id, pop = NA_real_))
  st <- resolve_settings()
  county <- area("kent", "county:10001")
  both <- area("both", c("county:10001", "county:10005"))
  state <- area("de", "state:10")
  r <- compute_metric("public_school_membership_ccd", list(county,both,state), st, periods=2024L)
  expect_equal(r$value, c(100,400,1000))
  expect_equal(r$period_label, rep("2024–25",3))
  ratio <- compute_metric("public_school_students_per_teacher_ccd", list(both), st, periods=2024L)
  expect_equal(ratio$value, 400/30)
  expect_equal(compute_metric("public_prek_membership_ccd", list(county), st, periods=2024L)$value, 0)
})
