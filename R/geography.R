# Geography: specs, names, relationships, study-area resolution and benchmark policy.
#
# Relationships form a graph, not a tree: a place lies in one state but may intersect
# several counties; tracts nest in counties but not in places; ZCTAs and metro areas can
# cross state lines. Every study area and benchmark is represented as an "entity": a set
# of non-overlapping published geographies ("pieces") whose union is the area. Metrics are
# then computed from published pieces only, so residents are never counted twice.

# ---- Specs ----------------------------------------------------------------------

geo_type_aliases <- c(
  us = "nation", nation = "nation", region = "region", division = "division",
  state = "state", county = "county", place = "place", city = "place",
  cousub = "cousub", county_subdivision = "cousub", mcd = "cousub",
  tract = "tract", bg = "bg", blockgroup = "bg", block_group = "bg",
  zcta = "zcta", cbsa = "cbsa", metro = "cbsa", msa = "cbsa",
  sdu = "sdu", school_district = "sdu", place_part = "place_part")

geo_id_patterns <- c(
  nation = "^US$", region = "^[1-4]$", division = "^[1-9]$", state = "^[0-9]{2}$",
  county = "^[0-9]{5}$", cousub = "^[0-9]{10}$", place = "^[0-9]{7}$",
  place_part = "^[0-9]{7}-[0-9]{5}$", tract = "^[0-9]{11}$", bg = "^[0-9]{12}$",
  zcta = "^[0-9]{5}$", cbsa = "^[0-9]{5}$", sdu = "^[0-9]{7}$")

geo_support <- function() memoize("geo_support", function() read_table(root_path("catalog", "geo_support.csv")))

state_table <- function() memoize("state_table", function() read_table(root_path("catalog", "geo_states.csv")))

geo_row <- function(type, geoid, vintage) {
  data.frame(type = type, geoid = geoid, key = paste0(type, ":", geoid),
             vintage = as.integer(vintage), stringsAsFactors = FALSE)
}

split_key <- function(key) {
  data.frame(type = sub(":.*$", "", key), geoid = sub("^[^:]*:", "", key), key = key,
             stringsAsFactors = FALSE)
}

# Parse one geography spec: "place:1827000", "county:48453@2024", "us", or
# "name:Gary, Indiana" (resolved through the name index; ambiguity is an error).
parse_geo <- function(spec, vintage) {
  s <- trimws(spec)
  if (grepl("@", s, fixed = TRUE)) {
    vintage <- as.integer(sub("^.*@", "", s))
    s <- trimws(sub("@.*$", "", s))
  }
  if (tolower(s) %in% c("us", "usa", "nation", "united states")) return(geo_row("nation", "US", vintage))
  if (!grepl(":", s, fixed = TRUE)) {
    stop("Geography '", spec, "' must be type:GEOID (e.g. place:1827000) or name:<name>. ",
         "Find IDs with: Rscript gr.R find \"", s, "\"", call. = FALSE)
  }
  raw_type <- tolower(trimws(sub(":.*$", "", s)))
  geoid <- trimws(sub("^[^:]*:", "", s))
  if (raw_type %in% c("zip", "zipcode", "zip_code", "postal")) {
    stop("'", spec, "': USPS ZIP Codes are mail delivery routes, not statistical areas. Use zcta:",
         geoid, " for the ZIP Code Tabulation Area, the Census Bureau's block-based approximation.",
         call. = FALSE)
  }
  if (raw_type == "name") return(resolve_name(geoid, vintage))
  type <- unname(geo_type_aliases[raw_type])
  if (is.na(type)) {
    stop("Unknown geography type '", raw_type, "' in '", spec, "'. Known types: ",
         paste(unique(geo_type_aliases), collapse = ", "), call. = FALSE)
  }
  if (!grepl(geo_id_patterns[[type]], geoid)) {
    ex <- geo_support()$example[geo_support()$type == type]
    stop("'", spec, "' is not a valid ", type, " identifier (example: ", ex, ").", call. = FALSE)
  }
  geo_row(type, geoid, vintage)
}

# A list of members separated by "+" or ";" (e.g. "county:48453 + county:48491").
parse_geo_list <- function(text, vintage) {
  parts <- trimws(unlist(strsplit(text, "[+;\n]")))
  do.call(rbind, lapply(parts[nzchar(parts)], parse_geo, vintage = vintage))
}

# ---- Names and populations ---------------------------------------------------------

# All geographies of a type within a scope, with names and ACS total population (B01003)
# from the vintage's 5-year release. The scope defaults to nationwide for the type.
geo_catalog <- function(type, vintage, scope = type) {
  d <- acs_table(vintage, "B01003", scope)
  d <- d[d$variable == "B01003_001", , drop = FALSE]
  data.frame(key = d$geo, type = sub(":.*$", "", d$geo), geoid = sub("^[^:]*:", "", d$geo),
             name = d$name, pop = d$estimate, pop_moe = d$moe, stringsAsFactors = FALSE)
}

# Name and population for specific keys (NA name = not defined in that vintage).
geo_info <- function(keys, vintage) {
  g <- split_key(keys)
  scopes <- mapply(census_scope, g$type, g$geoid)
  out <- lapply(seq_along(keys), function(i) {
    cat <- geo_catalog(g$type[i], vintage, scopes[[i]])
    hit <- cat[cat$key == keys[i], , drop = FALSE]
    if (!nrow(hit)) return(data.frame(key = keys[i], name = NA_character_, pop = NA_real_, pop_moe = NA_real_))
    hit[1, c("key", "name", "pop", "pop_moe")]
  })
  out <- do.call(rbind, out)
  cbind(g[, c("type", "geoid")], out)
}

normalize_name <- function(x) {
  x <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT", sub = "")
  x <- tolower(gsub("[^A-Za-z0-9, ]", " ", x))
  trimws(gsub("\\s+", " ", x))
}

# Legal/statistical area descriptions that follow a name ("Gary city", "Lake County").
lsad_words <- c("city and borough", "consolidated government \\(balance\\)", "metro government \\(balance\\)",
                "unified government \\(balance\\)", "\\(balance\\)", "census area", "planning region",
                "municipality", "borough", "village", "town", "township", "city", "cdp", "county",
                "parish", "metro area", "micro area", "region", "division")

base_name <- function(name_part) {
  x <- normalize_name(name_part)
  for (w in lsad_words) x <- sub(paste0("\\s+", w, "$"), "", x)
  trimws(x)
}

# Search places, counties, states, metro areas, regions and divisions by name.
find_geographies <- function(query, vintage) {
  parts <- trimws(strsplit(query, ",", fixed = TRUE)[[1]])
  want_base <- base_name(parts[1])
  want_full <- normalize_name(query)
  st <- state_table()
  state_hint <- if (length(parts) > 1) {
    hint <- tolower(parts[length(parts)])
    st$name[tolower(st$name) == hint | tolower(st$usps) == hint][1]
  } else NA_character_
  pools <- list(geo_catalog("state", vintage), geo_catalog("county", vintage),
                geo_catalog("place", vintage), geo_catalog("cbsa", vintage),
                geo_catalog("region", vintage), geo_catalog("division", vintage))
  cand <- do.call(rbind, pools)
  cand_state <- sub("^.*,\\s*", "", cand$name)
  cand_base <- vapply(sub(",.*$", "", cand$name), base_name, "")
  exact <- normalize_name(cand$name) == want_full
  base_hit <- cand_base == want_base & (is.na(state_hint) | cand_state == state_hint)
  matched <- exact | base_hit
  hits <- cand[matched, , drop = FALSE]
  hits$exact <- exact[matched]
  hits <- hits[order(!hits$exact, -hits$pop), , drop = FALSE]
  hits$spec <- hits$key
  rownames(hits) <- NULL
  hits
}

resolve_name <- function(query, vintage) {
  hits <- find_geographies(query, vintage)
  if (any(hits$exact)) hits <- hits[hits$exact, , drop = FALSE]
  if (nrow(hits) == 1) {
    note("Resolved name '", query, "' to ", hits$key, " (", hits$name, ")")
    return(geo_row(hits$type, hits$geoid, vintage))
  }
  if (!nrow(hits)) {
    stop("No geography named '", query, "' in ", vintage, " boundaries. Try: Rscript gr.R find \"",
         query, "\"", call. = FALSE)
  }
  listing <- paste0("  ", hits$key, "  ", hits$name, collapse = "\n")
  stop("The name '", query, "' is ambiguous; use one of these IDs instead:\n", listing, call. = FALSE)
}

# ---- Relationships -------------------------------------------------------------------

# County parts of a place, with published population (ACS summary level 155).
place_parts <- function(place_geoid, vintage) {
  cat <- geo_catalog("place_part", vintage, paste0("place_part-", place_geoid))
  cat$county <- sub("^.*-", "", cat$geoid)
  cat
}

# The ZCTA-to-county relationship file (2020) gives land area of each intersection.
zcta_county_parts <- function(zcta) {
  path <- cache_path("geo", "rel2020", "zcta520_county20.parquet")
  rel <- cached(path, source = "census_geo", compute = function() {
    raw <- cached_download("https://www2.census.gov/geo/docs/maps-data/data/rel2020/zcta520/tab20_zcta520_county20_natl.txt",
                           cache_path("geo", "rel2020", "tab20_zcta520_county20_natl.txt"), "census_geo")
    d <- utils::read.delim(raw, sep = "|", colClasses = "character")
    d <- d[nzchar(d$GEOID_ZCTA5_20), ]
    data.frame(zcta = d$GEOID_ZCTA5_20, county = d$GEOID_COUNTY_20,
               area_part = as.numeric(d$AREALAND_PART), area_zcta = as.numeric(d$AREALAND_ZCTA5_20))
  })
  d <- rel[rel$zcta == zcta, , drop = FALSE]
  d$share <- d$area_part / sum(d$area_part)
  d
}

zcta_place_overlap <- function(zcta, place) {
  path <- cache_path("geo", "rel2020", "zcta520_place20.parquet")
  rel <- cached(path, source = "census_geo", compute = function() {
    raw <- cached_download("https://www2.census.gov/geo/docs/maps-data/data/rel2020/zcta520/tab20_zcta520_place20_natl.txt",
                           cache_path("geo", "rel2020", "tab20_zcta520_place20_natl.txt"), "census_geo")
    d <- utils::read.delim(raw, sep = "|", colClasses = "character")
    d <- d[nzchar(d$GEOID_ZCTA5_20) & nzchar(d$GEOID_PLACE_20), ]
    data.frame(zcta = d$GEOID_ZCTA5_20, place = d$GEOID_PLACE_20, area_part = as.numeric(d$AREALAND_PART))
  })
  any(rel$zcta == zcta & rel$place == place & rel$area_part > 0)
}

state_of <- function(type, geoid) {
  if (type %in% c("nation", "region", "division", "zcta", "cbsa")) return(NA_character_)
  substr(geoid, 1, 2)
}

# Ancestors of one published geography at benchmark levels (county, state, division,
# region, nation). `share` is the fraction of the geography's population inside the
# ancestor (1 for exact nesting); `basis` documents where the share comes from.
geo_parents <- function(key, vintage) {
  g <- split_key(key)
  type <- g$type
  geoid <- g$geoid
  st <- state_table()
  rows <- list()
  add <- function(parent, level, relation, share, basis) {
    rows[[length(rows) + 1]] <<- data.frame(parent = parent, level = level, relation = relation,
                                            share = share, basis = basis, stringsAsFactors = FALSE)
  }
  # County level.
  counties <- NULL
  if (type == "place") {
    parts <- place_parts(geoid, vintage)
    if (nrow(parts)) {
      total <- sum(parts$pop, na.rm = TRUE)
      rel <- if (nrow(parts) == 1) "contains" else "intersects"
      for (i in seq_len(nrow(parts))) {
        add(paste0("county:", parts$county[i]), "county", rel,
            if (total > 0) parts$pop[i] / total else NA_real_,
            paste0("published population of place-by-county parts (ACS ", vintage - 4, "-", vintage, ")"))
      }
      counties <- parts$county
    }
  } else if (type == "place_part") {
    counties <- sub("^.*-", "", geoid)
    add(paste0("county:", counties), "county", "contains", 1, "exact nesting")
  } else if (type %in% c("cousub", "tract", "bg")) {
    counties <- substr(geoid, 1, 5)
    add(paste0("county:", counties), "county", "contains", 1, "exact nesting")
  } else if (type == "zcta") {
    parts <- zcta_county_parts(geoid)
    rel <- if (nrow(parts) == 1) "contains" else "intersects"
    for (i in seq_len(nrow(parts))) {
      add(paste0("county:", parts$county[i]), "county", rel, parts$share[i],
          "land area of ZCTA-county intersections (2020 relationship file; population shares not published)")
    }
    counties <- parts$county
  } else if (type == "cbsa") {
    counties <- cbsa_counties(geoid, vintage)
  }
  # State level: from the geography's own code, or from its counties when it can cross
  # state lines (ZCTAs by land area, metro areas by county population).
  states <- NULL
  if (type %in% c("county", "place", "place_part", "cousub", "tract", "bg", "sdu", "state")) {
    states <- data.frame(state = substr(geoid, 1, 2), share = 1)
  } else if (type == "zcta" && length(counties)) {
    parts <- zcta_county_parts(geoid)
    states <- stats::aggregate(share ~ state, FUN = sum,
                               data = data.frame(state = substr(parts$county, 1, 2), share = parts$share))
  } else if (type == "cbsa" && length(counties)) {
    cp <- geo_catalog("county", vintage)
    cp <- cp[cp$geoid %in% counties, , drop = FALSE]
    states <- stats::aggregate(pop ~ state, FUN = sum, data = data.frame(state = substr(cp$geoid, 1, 2), pop = cp$pop))
    states$share <- states$pop / sum(states$pop)
  }
  if (!is.null(states)) {
    if (type != "state") {
      rel <- if (nrow(states) == 1) "contains" else "intersects"
      for (i in seq_len(nrow(states))) add(paste0("state:", states$state[i]), "state", rel, states$share[i], "exact nesting")
    }
    info <- st[match(states$state, st$state), ]
    for (lvl in c("division", "region")) {
      codes <- info[[lvl]]
      if (any(is.na(codes) | !nzchar(codes))) next  # Puerto Rico and Island Areas have no region
      rel <- if (length(unique(codes)) == 1) "contains" else "intersects"
      for (code in unique(codes)) {
        add(paste0(lvl, ":", code), lvl, rel, min(1, sum(states$share[codes == code])), "exact nesting")
      }
    }
    in_nation <- all(as.logical(info$in_nation))
    add("nation:US", "nation", if (in_nation) "contains" else "reference", if (in_nation) 1 else 0,
        if (in_nation) "exact nesting" else "outside U.S. totals (50 states and DC)")
  } else if (type %in% c("region", "division")) {
    if (type == "division") {
      reg <- unique(st$region[st$division == geoid & nzchar(st$division)])
      add(paste0("region:", reg), "region", "contains", 1, "exact nesting")
    }
    add("nation:US", "nation", "contains", 1, "exact nesting")
  }
  if (!length(rows)) return(data.frame(parent = character(), level = character(), relation = character(),
                                       share = numeric(), basis = character()))
  do.call(rbind, rows)
}

# Counties composing a metropolitan/micropolitan area, from the OMB delineation file
# that the ACS release uses (July 2023 delineations for 2023+ releases).
cbsa_counties <- function(cbsa, vintage) {
  path <- cache_path("geo", "cbsa", "delineation_2023.parquet")
  d <- cached(path, source = "census_geo", compute = function() {
    raw <- cached_download("https://www2.census.gov/programs-surveys/metro-micro/geographies/reference-files/2023/delineation-files/list1_2023.xlsx",
                           cache_path("geo", "cbsa", "list1_2023.xlsx"), "census_geo")
    x <- readxl::read_excel(raw, skip = 2, col_types = "text")
    x <- x[!is.na(x$`FIPS County Code`), ]
    data.frame(cbsa = x$`CBSA Code`, county = paste0(x$`FIPS State Code`, x$`FIPS County Code`))
  })
  if (vintage < 2023) warn("CBSA membership uses the July 2023 delineation; release ", vintage, " used an earlier one.")
  d$county[d$cbsa == cbsa]
}

# Is `inner` entirely inside `outer`? Returns TRUE, FALSE, or NA when the relationship is
# not published (e.g. tracts versus places), which callers must treat as unresolvable.
geo_contains <- function(outer, inner, vintage) {
  o <- split_key(outer)
  i <- split_key(inner)
  if (outer == inner) return(TRUE)
  if (o$type == "nation") {
    p <- geo_parents(inner, vintage)
    return(any(p$level == "nation" & p$relation == "contains"))
  }
  if (o$type %in% c("region", "division", "state")) {
    p <- geo_parents(inner, vintage)
    hit <- p[p$parent == outer, , drop = FALSE]
    return(nrow(hit) > 0 && all(hit$relation == "contains"))
  }
  if (o$type == "county") {
    if (i$type %in% c("cousub", "tract", "bg")) return(substr(i$geoid, 1, 5) == o$geoid)
    if (i$type == "place_part") return(sub("^.*-", "", i$geoid) == o$geoid)
    if (i$type %in% c("place", "zcta")) {
      p <- geo_parents(inner, vintage)
      hit <- p[p$parent == outer, , drop = FALSE]
      return(nrow(hit) > 0 && all(hit$relation == "contains"))
    }
    if (i$type %in% c("state", "region", "division", "nation", "county", "cbsa")) return(FALSE)
    return(NA)
  }
  if (o$type == "tract") {
    if (i$type == "bg") return(substr(i$geoid, 1, 11) == o$geoid)
    if (i$type %in% c("tract", "county", "state", "place")) return(FALSE)
    return(NA)
  }
  if (o$type == "place") {
    if (i$type == "place_part") return(sub("-.*$", "", i$geoid) == o$geoid)
    if (i$type %in% c("place", "county", "state", "region", "division", "nation")) return(FALSE)
    return(NA)
  }
  if (o$type == "cbsa") {
    counties <- cbsa_counties(o$geoid, vintage)
    if (i$type == "county") return(i$geoid %in% counties)
    if (i$type %in% c("cousub", "tract", "bg")) return(substr(i$geoid, 1, 5) %in% counties)
    if (i$type == "place") return(all(place_parts(i$geoid, vintage)$county %in% counties))
    return(NA)
  }
  if (i$type == o$type) return(FALSE)
  NA
}

# Relationship between two members of a selection:
# "equal", "inside" (a inside b), "contains" (a contains b), "disjoint", "overlap", "unknown".
geo_relation <- function(a, b, vintage) {
  if (a == b) return("equal")
  if (isTRUE(geo_contains(b, a, vintage))) return("inside")
  if (isTRUE(geo_contains(a, b, vintage))) return("contains")
  ta <- split_key(a)
  tb <- split_key(b)
  # Distinct geographies of the same type never overlap (tract vs tract, place vs place...).
  if (ta$type == tb$type && ta$type != "sdu") return("disjoint")
  # State-bounded types in different states cannot overlap.
  sa <- state_of(ta$type, ta$geoid)
  sb <- state_of(tb$type, tb$geoid)
  if (!is.na(sa) && !is.na(sb) && sa != sb) return("disjoint")
  counties_of <- function(k) {
    g <- split_key(k)
    switch(g$type,
      county = g$geoid, place = place_parts(g$geoid, vintage)$county,
      place_part = sub("^.*-", "", g$geoid), cousub = , tract = , bg = substr(g$geoid, 1, 5),
      zcta = zcta_county_parts(g$geoid)$county, cbsa = cbsa_counties(g$geoid, vintage),
      state = NA_character_, NULL)
  }
  # Place vs county-based areas: decide from the place's published county parts.
  if ((ta$type == "place" && tb$type %in% c("county", "cbsa")) || (tb$type == "place" && ta$type %in% c("county", "cbsa"))) {
    place <- if (ta$type == "place") a else b
    other <- if (ta$type == "place") b else a
    shared <- intersect(counties_of(place), counties_of(other))
    return(if (length(shared)) "overlap" else "disjoint")
  }
  if (ta$type == "zcta" || tb$type == "zcta") {
    z <- if (ta$type == "zcta") ta else tb
    other <- if (ta$type == "zcta") tb else ta
    if (other$type == "place") return(if (zcta_place_overlap(z$geoid, other$geoid)) "overlap" else "disjoint")
    if (other$type %in% c("county", "cbsa")) {
      shared <- intersect(zcta_county_parts(z$geoid)$county, counties_of(other$key))
      return(if (length(shared)) "overlap" else "disjoint")
    }
  }
  # County-nested types in different counties cannot overlap.
  ca <- counties_of(a)
  cb <- counties_of(b)
  if (length(ca) && length(cb) && !anyNA(ca) && !anyNA(cb) && !length(intersect(ca, cb))) return("disjoint")
  "unknown"
}

# ---- Study areas --------------------------------------------------------------------

county_like <- c("county", "cbsa", "state", "division", "region", "nation")

# Resolve a selection into a study area. `mode` must be explicit for lists:
#   single  - exactly one geography
#   union   - one combined area; members are made non-overlapping using published parts
#   compare - several areas side by side in one report (no aggregation)
resolve_area <- function(members, mode, vintage, label = "") {
  if (!mode %in% c("single", "union", "compare")) {
    stop("Mode must be single, union, or compare (got '", mode, "').", call. = FALSE)
  }
  if (nrow(members) > 1 && mode == "single") {
    stop("A list of ", nrow(members), " geographies needs an explicit mode: 'union' (one combined area), ",
         "'compare' (side by side in one report) or 'separate' (one report each).", call. = FALSE)
  }
  notes <- character()
  dup <- duplicated(members$key)
  if (any(dup)) {
    notes <- c(notes, paste0("Duplicate selection removed: ", paste(unique(members$key[dup]), collapse = ", "), "."))
    members <- members[!dup, , drop = FALSE]
  }
  info <- geo_info(members$key, vintage)
  missing <- is.na(info$name)
  if (any(missing)) {
    hint <- ifelse(substr(members$geoid[missing], 1, 2) == "09" & members$type[missing] == "county" &
                     vintage >= 2022,
                   " Connecticut's counties were replaced by planning regions (county codes 09110-09190) from 2022.", "")
    stop("Not defined in ", vintage, " boundaries: ", paste0(members$key[missing], hint, collapse = "; "),
         call. = FALSE)
  }
  members$name <- info$name
  members$pop <- info$pop
  support <- geo_support()
  role_col <- if (mode == "union") "union_member" else "study_area"
  ok <- support[[role_col]][match(members$type, support$type)] == "yes"
  if (any(!ok)) {
    stop("Geography type not supported as ", if (mode == "union") "a union member" else "a study area", ": ",
         paste(unique(members$type[!ok]), collapse = ", "), ". See catalog/geo_support.csv.", call. = FALSE)
  }
  area <- list(mode = mode, vintage = vintage, members = members, notes = notes)
  if (mode == "union") {
    resolved <- union_pieces(members, vintage)
    area$pieces <- resolved$pieces
    area$notes <- c(area$notes, resolved$notes)
  } else {
    area$pieces <- members[, c("key", "type", "geoid", "name", "pop")]
    area$pieces$from_member <- members$key
    if (mode == "compare") area$notes <- c(area$notes, compare_overlap_notes(members, vintage))
  }
  area$label <- if (nzchar(label)) label else default_area_label(area)
  area$short <- short_label(area$label)
  area$pop <- sum(area$pieces$pop, na.rm = TRUE)
  area
}

# Turn union members into non-overlapping published pieces, or stop with an explanation.
union_pieces <- function(members, vintage) {
  notes <- character()
  keys <- members$key
  n <- length(keys)
  rel <- matrix("", n, n, dimnames = list(keys, keys))
  for (i in seq_len(n)) for (j in seq_len(n)) if (i < j) {
    r <- geo_relation(keys[i], keys[j], vintage)
    rel[i, j] <- r
    rel[j, i] <- switch(r, inside = "contains", contains = "inside", r)
  }
  if (any(rel == "unknown")) {
    bad <- which(rel == "unknown", arr.ind = TRUE)
    pairs <- unique(apply(bad, 1, function(ix) paste(sort(keys[ix]), collapse = " and ")))
    stop("Cannot combine ", paste(pairs, collapse = "; "), ": the Census Bureau does not publish their ",
         "relationship or the parts where they overlap, so a union could double-count residents. ",
         "Use non-overlapping members (e.g. whole counties), or produce separate reports.", call. = FALSE)
  }
  # Drop members inside another member (including coterminous duplicates).
  drop <- rep(FALSE, n)
  for (i in seq_len(n)) {
    inside <- which(rel[i, ] == "inside" & !drop)
    if (length(inside)) {
      drop[i] <- TRUE
      notes <- c(notes, paste0(members$name[i], " lies inside ", members$name[inside[1]],
                               "; it adds nothing to the union and was not counted twice."))
    }
  }
  pieces <- members[!drop, c("key", "type", "geoid", "name", "pop"), drop = FALSE]
  pieces$from_member <- pieces$key
  # Resolve partial overlaps between a place and county-based members using the place's
  # published parts: keep only the parts in counties not already covered.
  kept <- keys[!drop]
  for (i in which(!drop)) {
    others <- setdiff(which(!drop), i)
    overl <- others[rel[i, others] == "overlap"]
    if (!length(overl)) next
    if (members$type[i] == "place" && all(members$type[overl] %in% county_like)) {
      covered <- unique(unlist(lapply(members$key[overl], function(k) {
        g <- split_key(k)
        if (g$type == "county") g$geoid else if (g$type == "cbsa") cbsa_counties(g$geoid, vintage) else NULL
      })))
      parts <- place_parts(members$geoid[i], vintage)
      outside <- parts[!parts$county %in% covered, , drop = FALSE]
      pieces <- pieces[pieces$key != members$key[i], , drop = FALSE]
      if (nrow(outside)) {
        pieces <- rbind(pieces, data.frame(key = outside$key, type = "place_part", geoid = outside$geoid,
                                           name = outside$name, pop = outside$pop,
                                           from_member = members$key[i], stringsAsFactors = FALSE))
      }
      notes <- c(notes, paste0(members$name[i], " overlaps ", paste(members$name[overl], collapse = " and "),
                               "; only its parts outside ", if (length(overl) > 1) "those areas" else "that area",
                               " were added (", nrow(outside), " published place-by-county part",
                               if (nrow(outside) == 1) "" else "s", ")."))
    } else if (members$type[i] %in% county_like && any(members$type[overl] == "place")) {
      next  # handled from the place's side
    } else {
      stop("Cannot combine ", members$name[i], " with ", paste(members$name[overl], collapse = ", "),
           ": they overlap and the Census Bureau does not publish estimates for the overlapping parts. ",
           "Choose non-overlapping members or produce separate reports. (Allocation by land area is not ",
           "applied automatically because it can misstate populations.)", call. = FALSE)
    }
  }
  rownames(pieces) <- NULL
  list(pieces = pieces, notes = notes)
}

compare_overlap_notes <- function(members, vintage) {
  out <- character()
  n <- nrow(members)
  for (i in seq_len(n)) for (j in seq_len(n)) if (i < j) {
    r <- geo_relation(members$key[i], members$key[j], vintage)
    if (r %in% c("inside", "contains", "overlap")) {
      out <- c(out, paste0(members$name[i], " and ", members$name[j], " overlap (", r,
                           "); their values are not independent."))
    }
  }
  out
}

default_area_label <- function(area) {
  m <- area$members
  if (area$mode != "union" || nrow(m) == 1) return(m$name[1])
  st <- unique(sub("^.*,\\s*", "", m$name))
  if (all(m$type == "county") && length(st) == 1 && nrow(m) <= 4) {
    names <- sub(" County,.*$| Parish,.*$|,.*$", "", m$name)
    return(paste0(paste(names[-length(names)], collapse = ", "), " and ", names[length(names)],
                  " counties, ", st))
  }
  plural <- c(county = "counties", place = "places", tract = "tracts", bg = "block groups",
              cousub = "county subdivisions", zcta = "ZCTAs", cbsa = "metro areas", state = "states")
  kind <- if (length(unique(m$type)) == 1) unname(plural[m$type[1]]) else NA
  if (is.na(kind)) kind <- "areas"
  paste0("Combined area (", nrow(m), " ", kind,
         if (length(st) > 1) paste0(" in ", length(st), " states") else paste0(", ", st), ")")
}

short_label <- function(label) {
  s <- sub(",.*$", "", label)
  s <- sub(" (city|town|village|borough|CDP|municipality)$", "", s)
  s
}

# ---- Entities and benchmarks ----------------------------------------------------------

entity <- function(id, role, label, pieces, relation = "", reason = "", study_share = NA_real_) {
  list(id = id, role = role, label = label, short = short_label(label),
       pieces = pieces[, c("key", "type", "geoid", "name", "pop")],
       relation = relation, reason = reason, study_share = study_share)
}

entity_from_key <- function(key, vintage, id, role, relation = "", reason = "") {
  info <- geo_info(key, vintage)
  entity(id, role, info$name, info, relation, reason)
}

study_entity <- function(area) {
  entity("study", "study", area$label, area$pieces)
}

# Candidate ancestors of the whole study area, with the share of its residents in each.
area_parents <- function(area) {
  pieces <- area$pieces
  total <- sum(pieces$pop, na.rm = TRUE)
  rows <- lapply(seq_len(nrow(pieces)), function(i) {
    p <- geo_parents(pieces$key[i], area$vintage)
    if (!nrow(p)) return(NULL)
    p$piece_pop <- pieces$pop[i]
    p
  })
  p <- do.call(rbind, rows)
  if (is.null(p) || !nrow(p)) return(data.frame())
  p$res <- p$share * p$piece_pop
  agg <- p |>
    group_by(parent, level) |>
    summarise(residents = sum(res, na.rm = TRUE),
              all_contained = all(relation == "contains"),
              n_pieces = n(), reference = any(relation == "reference"),
              basis = paste(unique(basis), collapse = "; "), .groups = "drop")
  agg$share <- if (total > 0) agg$residents / total else NA_real_
  # Contains the whole area only if every piece is contained in it.
  agg$contains <- agg$all_contained & agg$n_pieces == nrow(pieces)
  as.data.frame(agg)
}

level_rank <- c(tract = 1, bg = 0, cousub = 2, zcta = 2, place = 2, place_part = 2, sdu = 2,
                county = 3, cbsa = 4, state = 5, division = 6, region = 7, nation = 8)

# Benchmark policy (documented in README "Benchmarks"):
# 1. Containing parents at each level in `benchmark_levels` are offered (county, state,
#    region, nation by default).
# 2. If no single parent at a level contains the area, each intersecting parent holding at
#    least `benchmark_min_share` of the area's residents is offered individually and labeled
#    with that share; the rest are listed in notes. Parent values are never averaged.
# 3. `benchmark_parent_union = TRUE` adds the union of all intersecting parents at the
#    county level (e.g. "counties containing Austin, combined"), computed from counts.
# 4. Parents identical to the study area (coterminous) or to another benchmark are dropped.
# 5. `benchmarks` may list explicit keys (e.g. "state:18; nation:US") to override all of this.
# For compare mode, only shared ancestors (containing every compared area) are offered.
choose_benchmarks <- function(area, settings) {
  vintage <- area$vintage
  explicit <- split_list(settings$benchmarks)
  if (length(explicit)) {
    return(lapply(seq_along(explicit), function(i) {
      entity_from_key(explicit[i], vintage, paste0("bm", i), "benchmark", "chosen explicitly",
                      "Listed in the report settings")
    }))
  }
  levels <- split_list(settings$benchmark_levels %||% "county;state;region;nation")
  min_share <- as.numeric(settings$benchmark_min_share %||% 0.05)
  study_rank <- max(level_rank[area$pieces$type])
  cand <- area_parents(area)
  if (!nrow(cand)) return(list())
  cand <- cand[cand$level %in% levels & level_rank[cand$level] > study_rank, , drop = FALSE]
  if (area$mode == "compare") cand <- cand[cand$contains, , drop = FALSE]
  cand <- cand[order(-level_rank[cand$level], -cand$share), , drop = FALSE]
  out <- list()
  notes <- character()
  for (lvl in levels) {
    at <- cand[cand$level == lvl, , drop = FALSE]
    if (!nrow(at)) next
    containing <- at[at$contains | at$reference, , drop = FALSE]
    if (nrow(containing)) {
      for (k in seq_len(nrow(containing))) {
        rel <- if (containing$reference[k]) "reference (does not contain the study area)" else "contains the study area"
        out[[length(out) + 1]] <- list(key = containing$parent[k], relation = rel, share = containing$share[k],
                                        level = lvl, contains = containing$contains[k])
      }
    } else {
      keep <- at[!is.na(at$share) & at$share >= min_share, , drop = FALSE]
      skip <- at[!(at$parent %in% keep$parent), , drop = FALSE]
      for (k in seq_len(nrow(keep))) {
        out[[length(out) + 1]] <- list(key = keep$parent[k], level = lvl, contains = FALSE,
                                        share = keep$share[k],
                                        relation = sprintf("contains %s of the study area's residents", fmt_share(keep$share[k])))
      }
      if (nrow(skip)) {
        notes <- c(notes, paste0("Also intersecting at the ", lvl, " level but holding under ",
                                 fmt_share(min_share), " of residents: ",
                                 paste(skip$parent, " (", vapply(skip$share, fmt_share, ""), ")", sep = "", collapse = ", "), "."))
      }
      if (lvl == "county" && as_flag(settings$benchmark_parent_union) && nrow(at) > 1) {
        out[[length(out) + 1]] <- list(key = at$parent, level = "county_union", contains = TRUE, share = 1,
                                        relation = "counties intersecting the study area, combined")
      }
    }
  }
  ents <- list()
  study_keys <- sort(area$pieces$key)
  for (i in seq_along(out)) {
    b <- out[[i]]
    info <- geo_info(b$key, vintage)
    label <- if (length(b$key) > 1) paste0("Counties containing ", area$short, " (combined)") else info$name
    e <- entity(paste0("bm", i), "benchmark", label, info, b$relation,
                paste0(if (b$contains) "Contains" else "Intersects", " the study area"))
    e$level <- b$level
    e$contains_study <- isTRUE(b$contains)
    # Share of the benchmark's population living in the study area (dependence in tests).
    bm_pop <- sum(info$pop, na.rm = TRUE)
    e$study_share <- if (bm_pop > 0) min(1, (b$share %||% 0) * area$pop / bm_pop) else NA_real_
    # Rule 4: drop benchmarks identical to the study area or to an earlier benchmark.
    if (identical(sort(e$pieces$key), study_keys) || is_coterminous(e, area)) {
      notes <- c(notes, paste0(e$label, " is coterminous with the study area and is not shown as a separate benchmark."))
      next
    }
    dup <- vapply(ents, function(x) identical(sort(x$pieces$key), sort(e$pieces$key)) || same_population_area(x, e), TRUE)
    if (length(dup) && any(dup)) {
      notes <- c(notes, paste0(e$label, " is identical to ", ents[[which(dup)[1]]]$label, " and is shown once."))
      next
    }
    ents[[length(ents) + 1]] <- e
  }
  attr(ents, "notes") <- notes
  ents
}

# A county that holds a place's entire population and nothing else (e.g. San Francisco city
# and San Francisco County) is the same statistical area as the place.
is_coterminous <- function(e, area) {
  if (nrow(area$pieces) != 1 || nrow(e$pieces) != 1) return(FALSE)
  s <- area$pieces
  b <- e$pieces
  if (s$type == "place" && b$type == "county") {
    parts <- place_parts(s$geoid, area$vintage)
    return(nrow(parts) == 1 && parts$county == b$geoid && isTRUE(all.equal(parts$pop, b$pop)))
  }
  FALSE
}

# Two benchmarks describing the same territory under different names (e.g. DC as a state
# and as a county): same single-piece population and nesting.
same_population_area <- function(a, b) {
  if (nrow(a$pieces) != 1 || nrow(b$pieces) != 1) return(FALSE)
  pa <- a$pieces
  pb <- b$pieces
  if (pa$type == pb$type) return(FALSE)
  if (pa$type %in% c("state", "county") && pb$type %in% c("state", "county") &&
      substr(pa$geoid, 1, 2) == substr(pb$geoid, 1, 2)) {
    return(isTRUE(all.equal(pa$pop, pb$pop)))
  }
  FALSE
}

fmt_share <- function(x) {
  if (is.na(x)) return("an unknown share")
  if (x > 0 && x < 0.001) return("<0.1%")
  paste0(formatC(100 * x, format = "f", digits = if (x < 0.1) 1 else 0), "%")
}
