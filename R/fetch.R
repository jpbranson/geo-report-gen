# The only code that touches the network, plus the shared on-disk cache.
#
# Cache layout (all under cache_root()):
#   raw/<source>/...        downloaded files and API responses, normalized to parquet
#   geo/...                 geography indexes, relationships and boundaries
#   metrics/<metric>/...    computed metric results (keyed by inputs + code version)
# A cache path encodes everything its content depends on; see the providers for keys.

# Polite request rates per source (requests per second). The Census API publishes no
# hard limit for keyed use; BLS asks automated clients to throttle and identify themselves.
source_rates <- c(census_api = 5, census_files = 3, bls = 1, bea = 2, default = 2)

# BLS rejects automated requests that do not name a contact, so BLS requests (and only
# those) carry GR_HTTP_CONTACT, set in the git-ignored .env file, in the User-Agent header.
user_agent_string <- function(source) {
  contact <- if (identical(source, "bls")) Sys.getenv("GR_HTTP_CONTACT") else ""
  if (nzchar(contact)) paste0("geo-report-gen/0.1 (", contact, ")") else "geo-report-gen/0.1"
}

# ---- Cache --------------------------------------------------------------------

wants_refresh <- function(path, source) {
  !is.na(source) && source %in% run$refresh && !(path %in% run$refreshed)
}

read_cache_file <- function(path) {
  switch(tools::file_ext(path),
    parquet = as.data.frame(nanoparquet::read_parquet(path)),
    rds = readRDS(path),
    path)  # downloaded files are returned by path
}

write_cache_file <- function(value, path) {
  tmp <- paste0(path, ".tmp-", Sys.getpid())
  switch(tools::file_ext(path),
    parquet = nanoparquet::write_parquet(as.data.frame(value), tmp),
    rds = saveRDS(value, tmp),
    stop("write_cache_file() only writes .parquet or .rds; downloads use cached_download()"))
  replace_file(tmp, path)
}

# Return the cached value at `path`, or compute it, store it atomically under a file
# lock (so parallel reports never compute or write the same entry twice), and return it.
# `source` marks raw data that `--refresh <source>` should re-download.
cached <- function(path, compute, source = NA_character_) {
  if (file.exists(path) && !wants_refresh(path, source)) {
    run$cache["hit"] <- run$cache["hit"] + 1L
    return(read_cache_file(path))
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  lock <- filelock::lock(paste0(path, ".lock"), timeout = 30 * 60 * 1000)
  if (is.null(lock)) stop("Timed out waiting for the cache lock on ", path)
  on.exit(filelock::unlock(lock), add = TRUE)
  # Another process may have produced it while we waited for the lock.
  if (file.exists(path) && !wants_refresh(path, source)) {
    run$cache["hit"] <- run$cache["hit"] + 1L
    return(read_cache_file(path))
  }
  run$cache["miss"] <- run$cache["miss"] + 1L
  value <- compute()
  write_cache_file(value, path)
  if (!is.na(source)) run$refreshed <- c(run$refreshed, path)
  value
}

# Derived tables built from raw downloads carry the version of the provider code that built
# them, so changing a parser rebuilds the table from the cached download (no refetch).
derived_path <- function(source, name, code_file) {
  v <- memoize(paste0("code_", code_file), function() substr(code_version(file.path("R", "providers", code_file)), 1, 8))
  cache_path("raw", source, paste0(name, "-", v, ".parquet"))
}

# ---- HTTP ---------------------------------------------------------------------

http_request <- function(url, source, query = list(), secret = list()) {
  if (isTRUE(run$offline)) {
    stop("Offline mode: no cached copy available, and fetching from ", source,
         " is disabled (", url, ")", call. = FALSE)
  }
  rate <- source_rates[[if (source %in% names(source_rates)) source else "default"]]
  req <- httr2::request(url)
  if (length(query) || length(secret)) req <- httr2::req_url_query(req, !!!query, !!!secret)
  req <- httr2::req_user_agent(req, user_agent_string(source))
  req <- httr2::req_throttle(req, rate = rate, realm = source)
  req <- httr2::req_retry(req, max_tries = 5, retry_on_failure = TRUE,
                          is_transient = function(resp) httr2::resp_status(resp) %in% c(429, 500, 502, 503, 504),
                          backoff = function(attempt) min(60, 2^attempt))
  req <- httr2::req_timeout(req, 900)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  # Remember the loggable URL (without secrets) for the request log.
  attr(req, "log_url") <- if (length(query)) {
    paste0(url, "?", paste(names(query), vapply(query, as.character, ""), sep = "=", collapse = "&"))
  } else url
  attr(req, "source") <- source
  req
}

log_response <- function(req, resp, seconds) {
  status <- if (inherits(resp, "httr2_response")) httr2::resp_status(resp) else NA_integer_
  bytes <- if (inherits(resp, "httr2_response") && !is.null(resp$body)) {
    if (is.raw(resp$body)) length(resp$body) else file.size(resp$body)
  } else NA_real_
  entry <- list(time = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"), source = attr(req, "source"),
                url = attr(req, "log_url"), status = status, bytes = bytes,
                seconds = round(seconds, 2))
  run$requests[[length(run$requests) + 1]] <- entry
  line <- paste(entry$time, entry$source, entry$status, entry$bytes, entry$seconds,
                gsub("\\s", "%20", entry$url), sep = "\t")
  dir.create(cache_root(), showWarnings = FALSE, recursive = TRUE)
  cat(line, "\n", file = cache_path("requests.log"), append = TRUE, sep = "")
}

# Perform one request (optionally streaming the body to `path`).
http_perform <- function(req, path = NULL) {
  t0 <- Sys.time()
  resp <- httr2::req_perform(req, path = path)
  log_response(req, resp, as.numeric(difftime(Sys.time(), t0, units = "secs")))
  resp
}

# Perform several requests with bounded concurrency (throttling still applies per source).
http_perform_many <- function(reqs, max_active = 4) {
  if (!length(reqs)) return(list())
  t0 <- Sys.time()
  resps <- httr2::req_perform_parallel(reqs, on_error = "continue", progress = FALSE,
                                       max_active = max_active)
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs")) / length(reqs)
  for (i in seq_along(reqs)) log_response(reqs[[i]], resps[[i]], secs)
  resps
}

check_status <- function(resp, what) {
  if (!inherits(resp, "httr2_response")) {
    stop("Request failed for ", what, ": ", conditionMessage(resp), call. = FALSE)
  }
  status <- httr2::resp_status(resp)
  if (status >= 400) {
    body <- tryCatch(substr(httr2::resp_body_string(resp), 1, 300), error = function(e) "")
    stop("HTTP ", status, " for ", what, if (nzchar(body)) paste0(": ", body), call. = FALSE)
  }
  invisible(status)
}

# Download a file into the cache once (atomic rename; locked against parallel downloads).
cached_download <- function(url, path, source) {
  if (file.exists(path) && !wants_refresh(path, source)) {
    run$cache["hit"] <- run$cache["hit"] + 1L
    return(path)
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  lock <- filelock::lock(paste0(path, ".lock"), timeout = 30 * 60 * 1000)
  on.exit(filelock::unlock(lock), add = TRUE)
  if (file.exists(path) && !wants_refresh(path, source)) return(path)
  run$cache["miss"] <- run$cache["miss"] + 1L
  tmp <- paste0(path, ".download-", Sys.getpid())
  resp <- http_perform(http_request(url, source), path = tmp)
  if (httr2::resp_status(resp) >= 400) {
    unlink(tmp)
    stop("HTTP ", httr2::resp_status(resp), " downloading ", url, call. = FALSE)
  }
  replace_file(tmp, path)
  run$refreshed <- c(run$refreshed, path)
  # Record when each raw file was retrieved (the build manifest reports it).
  write_json_file(list(url = url, retrieved = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                       bytes = file.size(path), md5 = unname(tools::md5sum(path))),
                  paste0(path, ".meta.json"))
  path
}

# ---- Census Data API ------------------------------------------------------------

# The key comes from CENSUS_API_KEY (normally set in .env). It is passed as a secret
# query parameter and never logged or written to outputs.
census_key <- function() {
  key <- Sys.getenv("CENSUS_API_KEY")
  if (!nzchar(key)) {
    stop("The Census Data API requires a key. Add CENSUS_API_KEY=<key> to .env ",
         "(free key: https://api.census.gov/data/key_signup.html).", call. = FALSE)
  }
  key
}

census_request <- function(dataset_path, query) {
  http_request(paste0("https://api.census.gov/data/", dataset_path), "census_api",
               query = query, secret = list(key = census_key()))
}

# Parse a Census API response (JSON array of arrays) into a character data frame.
# HTTP 204 means "no data for that geography" and yields zero rows.
census_parse <- function(resp, what) {
  check_status(resp, what)
  if (httr2::resp_status(resp) == 204 || !length(resp$body)) return(data.frame())
  m <- jsonlite::fromJSON(httr2::resp_body_string(resp), simplifyVector = TRUE)
  df <- as.data.frame(m[-1, , drop = FALSE], stringsAsFactors = FALSE)
  names(df) <- m[1, ]
  df
}
