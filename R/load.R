# Loads the engine. Used by gr.R, by rendered reports (via GR_ROOT) and by tests.
local({
  root <- Sys.getenv("GR_ROOT")
  if (!nzchar(root)) root <- getwd()
  # Machine-specific settings (Census API key, BLS contact) live in the git-ignored .env file.
  if (file.exists(file.path(root, ".env"))) readRenviron(file.path(root, ".env"))
  # core.R and fetch.R come first because the providers register themselves with them.
  r_dir <- file.path(root, "R")
  first <- file.path(r_dir, c("core.R", "fetch.R"))
  files <- c(first,
             list.files(file.path(r_dir, "providers"), pattern = "\\.R$", full.names = TRUE),
             setdiff(list.files(r_dir, pattern = "\\.R$", full.names = TRUE), c(first, file.path(r_dir, "load.R"))))
  for (f in files) sys.source(f, envir = globalenv())
})
invisible(loaded_inputs_hash())  # the code and catalog as loaded (see compose_key())
