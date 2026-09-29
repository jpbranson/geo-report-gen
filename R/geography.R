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
  rows <- lapply(seq_along(keys), function(i) {
    d <- geo_catalog(g$type[i], vintage, census_scope(g$type[i], g$geoid[i]))
    hit <- d[d$key == keys[i], , drop = FALSE]
    if (!nrow(hit)) return(data.frame(key = keys[i], name = NA_character_, pop = NA_real_, pop_moe = NA_real_))
    hit[1, c("key", "name", "pop", "pop_moe")]
  })
  cbind(g[, c("type", "geoid")], do.call(rbind, rows))
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
  st <- state_table()
  state_hint <- if (length(parts) > 1) {
    hint <- tolower(parts[length(parts)])
    st$name[tolower(st$name) == hint | tolower(st$usps) == hint][1]
  } else NA_character_
  types <- c("state", "county", "place", "cbsa", "region", "division")
  cand <- do.call(rbind, lapply(types, geo_catalog, vintage = vintage))
  cand_state <- sub("^.*,\\s*", "", cand$name)
  exact <- normalize_name(cand$name) == normalize_name(query)
  base_hit <- base_name(sub(",.*$", "", cand$name)) == base_name(parts[1]) &
    (is.na(state_hint) | cand_state == state_hint)
  matched <- exact | base_hit
  hits <- cand[matched, , drop = FALSE]
  hits$exact <- exact[matched]
  hits <- hits[order(!hits$exact, -hits$pop), , drop = FALSE]
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
  parts <- geo_catalog("place_part", vintage, paste0("place_part-", place_geoid))
  parts$county <- sub("^.*-", "", parts$geoid)
  parts
}

# A 2020 ZCTA relationship file: land area of each ZCTA-county or ZCTA-place intersection.
read_zcta_relationship <- function(file) {
  url <- paste0("https://www2.census.gov/geo/docs/maps-data/data/rel2020/zcta520/", file)
  raw <- cached_download(url, cache_path("geo", "rel2020", file), "census_geo")
  utils::read.delim(raw, sep = "|", colClasses = "character")
}

# Counties a ZCTA intersects, with each intersection's share of the ZCTA's land area.
zcta_county_parts <- function(zcta) {
  rel <- cached(cache_path("geo", "rel2020", "zcta520_county20.parquet"), source = "census_geo", compute = function() {
    d <- read_zcta_relationship("tab20_zcta520_county20_natl.txt")
    d <- d[nzchar(d$GEOID_ZCTA5_20), ]
    data.frame(zcta = d$GEOID_ZCTA5_20, county = d$GEOID_COUNTY_20,
               area_part = as.numeric(d$AREALAND_PART), area_zcta = as.numeric(d$AREALAND_ZCTA5_20))
  })
  d <- rel[rel$zcta == zcta, , drop = FALSE]
  d$share <- d$area_part / sum(d$area_part)
  d
}

zcta_place_overlap <- function(zcta, place) {
  rel <- cached(cache_path("geo", "rel2020", "zcta520_place20.parquet"), source = "census_geo", compute = function() {
    d <- read_zcta_relationship("tab20_zcta520_place20_natl.txt")
    d <- d[nzchar(d$GEOID_ZCTA5_20) & nzchar(d$GEOID_PLACE_20), ]
    data.frame(zcta = d$GEOID_ZCTA5_20, place = d$GEOID_PLACE_20, area_part = as.numeric(d$AREALAND_PART))
  })
  any(rel$zcta == zcta & rel$place == place & rel$area_part > 0)
}

# Counties composing a metropolitan/micropolitan area, from the OMB delineation file
# that the ACS release uses (July 2023 delineations for 2023+ releases).
cbsa_counties <- function(cbsa, vintage) {
  d <- cached(cache_path("geo", "cbsa", "delineation_2023.parquet"), source = "census_geo", compute = function() {
    url <- paste0("https://www2.census.gov/programs-surveys/metro-micro/geographies/reference-files/2023/",
                  "delineation-files/list1_2023.xlsx")
    raw <- cached_download(url, cache_path("geo", "cbsa", "list1_2023.xlsx"), "census_geo")
    x <- readxl::read_excel(raw, skip = 2, col_types = "text")
    x <- x[!is.na(x$`FIPS County Code`), ]
    data.frame(cbsa = x$`CBSA Code`, county = paste0(x$`FIPS State Code`, x$`FIPS County Code`))
  })
  if (vintage < 2023) warn("CBSA membership uses the July 2023 delineation; release ", vintage, " used an earlier one.")
  d$county[d$cbsa == cbsa]
}

# Counties a geography lies in or consists of (NA for a state; NULL for larger areas).
geo_counties <- function(key, vintage) {
  g <- split_key(key)
  switch(g$type,
    county = g$geoid,
    place = place_parts(g$geoid, vintage)$county,
    place_part = sub("^.*-", "", g$geoid),
    cousub = , tract = , bg = substr(g$geoid, 1, 5),
    zcta = zcta_county_parts(g$geoid)$county,
    cbsa = cbsa_counties(g$geoid, vintage),
    state = NA_character_,
    NULL)
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
  counties <- county_shares(key, vintage)
  states <- state_shares(key, counties, vintage)
  st <- state_table()
  rows <- list(
    if (!is.null(counties)) parent_rows("county", counties$county, counties$share, counties$basis),
    if (!is.null(states) && g$type != "state") parent_rows("state", states$state, states$share),
    if (!is.null(states)) regional_parents(states),
    if (g$type == "division") parent_rows("region", st$region[match(g$geoid, st$division)], 1),
    if (g$type %in% c("region", "division")) parent_rows("nation", "US", 1))
  do.call(rbind, rows) %||%
    data.frame(parent = character(), level = character(), relation = character(), share = numeric(),
               basis = character())
}

# Parents at one level; the relation is "contains" when there is only one.
parent_rows <- function(level, codes, share, basis = "exact nesting",
                        relation = if (length(codes) == 1) "contains" else "intersects") {
  data.frame(parent = paste0(level, ":", codes), level = level, relation = relation, share = share,
             basis = basis, stringsAsFactors = FALSE)
}

# The geography's share in each county it touches, and where the share comes from (NULL
# when it does not lie within counties).
county_shares <- function(key, vintage) {
  g <- split_key(key)
  if (g$type == "place") {
    parts <- place_parts(g$geoid, vintage)
    if (!nrow(parts)) return(NULL)
    total <- sum(parts$pop, na.rm = TRUE)
    return(data.frame(county = parts$county, share = if (total > 0) parts$pop / total else NA_real_,
                      basis = paste0("published population of place-by-county parts (ACS ", vintage - 4, "-",
                                     vintage, ")")))
  }
  if (g$type == "zcta") {
    parts <- zcta_county_parts(g$geoid)
    if (!nrow(parts)) return(NULL)
    return(data.frame(county = parts$county, share = parts$share,
                      basis = paste("land area of ZCTA-county intersections (2020 relationship file;",
                                    "population shares not published)")))
  }
  if (g$type %in% c("place_part", "cousub", "tract", "bg")) {
    return(data.frame(county = geo_counties(key, vintage), share = 1, basis = "exact nesting"))
  }
  NULL
}

# The geography's share in each state: its own state when it nests in one; otherwise from
# its counties (ZCTAs by land area, metro areas by county population).
state_shares <- function(key, counties, vintage) {
  g <- split_key(key)
  if (g$type %in% c("county", "place", "place_part", "cousub", "tract", "bg", "sdu", "state")) {
    return(data.frame(state = substr(g$geoid, 1, 2), share = 1))
  }
  if (g$type == "zcta" && !is.null(counties)) {
    by_county <- data.frame(state = substr(counties$county, 1, 2), share = counties$share)
    return(stats::aggregate(share ~ state, data = by_county, FUN = sum))
  }
  if (g$type == "cbsa") {
    members <- cbsa_counties(g$geoid, vintage)
    if (!length(members)) return(NULL)
    cp <- geo_catalog("county", vintage)
    cp <- cp[cp$geoid %in% members, , drop = FALSE]
    states <- stats::aggregate(pop ~ state, data = data.frame(state = substr(cp$geoid, 1, 2), pop = cp$pop), FUN = sum)
    states$share <- states$pop / sum(states$pop)
    return(states)
  }
  NULL
}

# Division, region and nation parents from the geography's shares by state.
regional_parents <- function(states) {
  st <- state_table()
  info <- st[match(states$state, st$state), ]
  rows <- lapply(c("division", "region"), function(level) {
    codes <- info[[level]]
    if (any(is.na(codes) | !nzchar(codes))) return(NULL)  # Puerto Rico and Island Areas have no region
    u <- unique(codes)
    parent_rows(level, u, vapply(u, function(code) min(1, sum(states$share[codes == code])), 0, USE.NAMES = FALSE))
  })
  nation <- if (all(as.logical(info$in_nation))) parent_rows("nation", "US", 1) else
    parent_rows("nation", "US", 0, "outside U.S. totals (50 states and DC)", relation = "reference")
  do.call(rbind, c(rows, list(nation)))
}

# Is `inner` known to lie entirely inside `outer`? FALSE also when the relationship is not
# published (e.g. tracts versus places); geo_relation() then decides what that means.
geo_contains <- function(outer, inner, vintage) {
  if (outer == inner) return(TRUE)
  o <- split_key(outer)
  i <- split_key(inner)
  if (o$type %in% c("nation", "region", "division", "state") ||
      (o$type == "county" && i$type %in% c("place", "zcta"))) {
    p <- geo_parents(inner, vintage)
    return(any(p$parent == outer) && all(p$relation[p$parent == outer] == "contains"))
  }
  if (o$type == "county" && i$type %in% c("place_part", "cousub", "tract", "bg")) {
    return(geo_counties(inner, vintage) == o$geoid)
  }
  if (o$type == "cbsa" && i$type %in% c("county", "place", "cousub", "tract", "bg")) {
    return(all(geo_counties(inner, vintage) %in% cbsa_counties(o$geoid, vintage)))
  }
  if (o$type == "tract" && i$type == "bg") return(substr(i$geoid, 1, 11) == o$geoid)
  if (o$type == "place" && i$type == "place_part") return(sub("-.*$", "", i$geoid) == o$geoid)
  FALSE
}

# Relationship between two members of a selection:
# "equal", "inside" (a inside b), "contains" (a contains b), "disjoint", "overlap", "unknown".
geo_relation <- function(a, b, vintage) {
  if (a == b) return("equal")
  if (geo_contains(b, a, vintage)) return("inside")
  if (geo_contains(a, b, vintage)) return("contains")
  ga <- split_key(a)
  gb <- split_key(b)
  types <- c(ga$type, gb$type)
  # Distinct geographies of the same type never overlap (tract vs tract, place vs place...).
  if (ga$type == gb$type && ga$type != "sdu") return("disjoint")
  # State-bounded types in different states cannot overlap.
  sa <- state_of(ga$type, ga$geoid)
  sb <- state_of(gb$type, gb$geoid)
  if (!is.na(sa) && !is.na(sb) && sa != sb) return("disjoint")
  if (setequal(types, c("zcta", "place"))) {
    z <- if (ga$type == "zcta") ga else gb
    p <- if (ga$type == "place") ga else gb
    return(if (zcta_place_overlap(z$geoid, p$geoid)) "overlap" else "disjoint")
  }
  ca <- geo_counties(a, vintage)
  cb <- geo_counties(b, vintage)
  shared <- length(intersect(ca, cb)) > 0
  # A place or ZCTA and a county or metro area overlap exactly when they share a county.
  if (any(types %in% c("place", "zcta")) && any(types %in% c("county", "cbsa"))) {
    return(if (shared) "overlap" else "disjoint")
  }
  # County-nested types in different counties cannot overlap.
  if (length(ca) && length(cb) && !anyNA(c(ca, cb)) && !shared) return("disjoint")
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
    notes <- paste0("Duplicate selection removed: ", paste(unique(members$key[dup]), collapse = ", "), ".")
    members <- members[!dup, , drop = FALSE]
  }
  members <- describe_members(members, mode, vintage)
  if (mode == "union") {
    resolved <- union_pieces(members, vintage)
    pieces <- resolved$pieces
    notes <- c(notes, resolved$notes)
  } else {
    pieces <- members[, c("key", "type", "geoid", "name", "pop")]
    pieces$from_member <- members$key
    if (mode == "compare") notes <- c(notes, compare_overlap_notes(members, vintage))
  }
  if (!nzchar(label)) label <- default_area_label(members, mode)
  list(mode = mode, vintage = vintage, members = members, notes = notes, pieces = pieces,
       label = label, short = short_label(label), pop = sum(pieces$pop, na.rm = TRUE))
}

# Add each member's name and population, or stop when a member is not defined in the
# vintage or its type cannot serve as a study area (or union member).
describe_members <- function(members, mode, vintage) {
  info <- geo_info(members$key, vintage)
  missing <- is.na(info$name)
  if (any(missing)) {
    ct <- substr(members$geoid, 1, 2) == "09" & members$type == "county" & vintage >= 2022
    hint <- ifelse(ct[missing], paste(" Connecticut's counties were replaced by planning regions",
                                      "(county codes 09110-09190) from 2022."), "")
    stop("Not defined in ", vintage, " boundaries: ", paste0(members$key[missing], hint, collapse = "; "),
         call. = FALSE)
  }
  members$name <- info$name
  members$pop <- info$pop
  support <- geo_support()
  role <- if (mode == "union") "union_member" else "study_area"
  ok <- support[[role]][match(members$type, support$type)] == "yes"
  if (any(!ok)) {
    stop("Geography type not supported as ", if (mode == "union") "a union member" else "a study area", ": ",
         paste(unique(members$type[!ok]), collapse = ", "), ". See catalog/geo_support.csv.", call. = FALSE)
  }
  members
}

# Pairwise relationships of members: rel[i, j] is member i's relation to member j.
relation_matrix <- function(keys, vintage) {
  n <- length(keys)
  rel <- matrix("", n, n, dimnames = list(keys, keys))
  for (i in seq_len(n)) for (j in seq_len(n)) if (i < j) {
    r <- geo_relation(keys[i], keys[j], vintage)
    rel[i, j] <- r
    rel[j, i] <- switch(r, inside = "contains", contains = "inside", r)
  }
  rel
}

# Turn union members into non-overlapping published pieces, or stop with an explanation.
union_pieces <- function(members, vintage) {
  keys <- members$key
  rel <- relation_matrix(keys, vintage)
  unknown <- which(rel == "unknown", arr.ind = TRUE)
  if (nrow(unknown)) {
    pairs <- unique(apply(unknown, 1, function(ix) paste(sort(keys[ix]), collapse = " and ")))
    stop("Cannot combine ", paste(pairs, collapse = "; "), ": the Census Bureau does not publish their ",
         "relationship or the parts where they overlap, so a union could double-count residents. ",
         "Use non-overlapping members (e.g. whole counties), or produce separate reports.", call. = FALSE)
  }
  notes <- character()
  # Members inside another member (including coterminous duplicates) add nothing.
  drop <- rep(FALSE, length(keys))
  for (i in seq_along(keys)) {
    inside <- which(rel[i, ] == "inside" & !drop)
    if (!length(inside)) next
    drop[i] <- TRUE
    notes <- c(notes, paste0(members$name[i], " lies inside ", members$name[inside[1]],
                             "; it adds nothing to the union and was not counted twice."))
  }
  pieces <- members[!drop, c("key", "type", "geoid", "name", "pop"), drop = FALSE]
  pieces$from_member <- pieces$key
  # A place partly overlapping county-based members adds only its published parts in other
  # counties. No other partial overlap can be resolved from published data.
  for (i in which(!drop)) {
    overlaps <- which(!drop & rel[i, ] == "overlap")
    if (!length(overlaps)) next
    if (members$type[i] == "place" && all(members$type[overlaps] %in% county_like)) {
      covered <- unique(unlist(lapply(keys[overlaps], geo_counties, vintage = vintage)))
      parts <- place_parts(members$geoid[i], vintage)
      outside <- parts[!parts$county %in% covered, , drop = FALSE]
      pieces <- pieces[pieces$key != keys[i], , drop = FALSE]
      if (nrow(outside)) {
        pieces <- rbind(pieces, data.frame(key = outside$key, type = "place_part", geoid = outside$geoid,
                                           name = outside$name, pop = outside$pop, from_member = keys[i]))
      }
      notes <- c(notes, paste0(members$name[i], " overlaps ", paste(members$name[overlaps], collapse = " and "),
                               "; only its parts outside ", if (length(overlaps) > 1) "those areas" else "that area",
                               " were added (", nrow(outside), " published place-by-county part",
                               if (nrow(outside) == 1) "" else "s", ")."))
    } else if (!(members$type[i] %in% county_like && any(members$type[overlaps] == "place"))) {
      stop("Cannot combine ", members$name[i], " with ", paste(members$name[overlaps], collapse = ", "),
           ": they overlap and the Census Bureau does not publish estimates for the overlapping parts. ",
           "Choose non-overlapping members or produce separate reports. (Allocation by land area is not ",
           "applied automatically because it can misstate populations.)", call. = FALSE)
    }  # else: a county-based member overlapping a place is handled from the place's side
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

# Plain names of geography types, for text.
geo_type_names <- c(nation = "the nation", region = "regions", division = "divisions", state = "states",
                    county = "counties", place = "places", place_part = "the parts of a place in each county",
                    cousub = "county subdivisions", tract = "tracts", bg = "block groups", zcta = "ZCTAs",
                    cbsa = "metro areas", sdu = "school districts")

default_area_label <- function(members, mode) {
  if (mode != "union" || nrow(members) == 1) return(members$name[1])
  st <- unique(sub("^.*,\\s*", "", members$name))
  if (all(members$type == "county") && length(st) == 1 && nrow(members) <= 4) {
    names <- sub(" County,.*$| Parish,.*$|,.*$", "", members$name)
    return(paste0(paste(names[-length(names)], collapse = ", "), " and ", names[length(names)],
                  " counties, ", st))
  }
  kind <- if (length(unique(members$type)) == 1) unname(geo_type_names[members$type[1]]) else NA
  if (is.na(kind)) kind <- "areas"
  paste0("Combined area (", nrow(members), " ", kind,
         if (length(st) > 1) paste0(" in ", length(st), " states") else paste0(", ", st), ")")
}

# The short name used in sentences: "Gary city, Indiana" -> "Gary", "Kansas City, MO-KS Metro
# Area" -> "Kansas City". Only a trailing state or metro area suffix is dropped, so a label such
# as "Travis, Williamson and Hays counties" stays whole.
short_label <- function(label) {
  tail <- sub("^.*,\\s*", "", label)
  if (grepl(",", label, fixed = TRUE) && (tail %in% state_table()$name || grepl("^[A-Z]{2}(-[A-Z]{2})* (Metro|Micro) Area$", tail))) {
    label <- sub(",[^,]*$", "", label)
  }
  sub(" (city|town|village|borough|CDP|municipality)$", "", label)
}

# ---- Entities and benchmarks ----------------------------------------------------------

entity <- function(id, role, label, pieces, relation = "", reason = "", study_share = NA_real_) {
  list(id = id, role = role, label = label, short = short_label(label),
       pieces = pieces[, c("key", "type", "geoid", "name", "pop")],
       relation = relation, reason = reason, study_share = study_share)
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
  explicit <- split_list(settings$benchmarks)
  if (length(explicit)) {
    return(lapply(seq_along(explicit), function(i) {
      info <- geo_info(explicit[i], area$vintage)
      entity(paste0("bm", i), "benchmark", info$name, info, "chosen explicitly", "Listed in the report settings")
    }))
  }
  cand <- benchmark_candidates(area, settings)
  if (is.null(cand)) return(list())
  notes <- cand$notes
  ents <- list()
  for (i in seq_along(cand$picks)) {
    e <- benchmark_entity(cand$picks[[i]], paste0("bm", i), area)
    # Rule 4: drop benchmarks covering the same territory as the study area or an earlier one.
    if (same_territory(area$pieces, e$pieces, area$vintage)) {
      notes <- c(notes, paste(e$label, "is coterminous with the study area and is not shown as a separate benchmark."))
      next
    }
    same <- vapply(ents, function(x) same_territory(x$pieces, e$pieces, area$vintage), TRUE)
    if (any(same)) {
      notes <- c(notes, paste0(e$label, " is identical to ", ents[[which(same)[1]]]$label, " and is shown once."))
      next
    }
    ents[[length(ents) + 1]] <- e
  }
  attr(ents, "notes") <- notes
  ents
}

# Rules 1-3: the parents to offer at each level (a list of picks), and notes on the
# intersecting parents left out. NULL when the area has no parents.
benchmark_candidates <- function(area, settings) {
  levels <- split_list(settings$benchmark_levels %||% "county;state;region;nation")
  min_share <- as.numeric(settings$benchmark_min_share %||% 0.05)
  cand <- area_parents(area)
  if (!nrow(cand)) return(NULL)
  cand <- cand[cand$level %in% levels & level_rank[cand$level] > max(level_rank[area$pieces$type]), , drop = FALSE]
  if (area$mode == "compare") cand <- cand[cand$contains, , drop = FALSE]
  cand <- cand[order(-level_rank[cand$level], -cand$share), , drop = FALSE]
  picks <- list()
  notes <- character()
  for (lvl in levels) {
    at <- cand[cand$level == lvl, , drop = FALSE]
    if (!nrow(at)) next
    containing <- at[at$contains | at$reference, , drop = FALSE]
    if (nrow(containing)) {
      for (k in seq_len(nrow(containing))) {
        rel <- if (containing$reference[k]) "reference (does not contain the study area)" else "contains the study area"
        picks[[length(picks) + 1]] <- list(key = containing$parent[k], level = lvl, relation = rel,
                                           share = containing$share[k], contains = containing$contains[k])
      }
      next
    }
    keep <- at[!is.na(at$share) & at$share >= min_share, , drop = FALSE]
    for (k in seq_len(nrow(keep))) {
      picks[[length(picks) + 1]] <- list(key = keep$parent[k], level = lvl, share = keep$share[k], contains = FALSE,
                                         relation = sprintf("contains %s of the study area's residents",
                                                            fmt_share(keep$share[k])))
    }
    skip <- at[!(at$parent %in% keep$parent), , drop = FALSE]
    if (nrow(skip)) {
      listed <- paste0(geo_info(skip$parent, area$vintage)$name, " (", vapply(skip$share, fmt_share, ""), ")",
                       collapse = ", ")
      notes <- c(notes, paste0("Also intersecting at the ", lvl, " level but holding under ", fmt_share(min_share),
                               " of residents: ", listed, "."))
    }
    if (lvl == "county" && as_flag(settings$benchmark_parent_union) && nrow(at) > 1) {
      picks[[length(picks) + 1]] <- list(key = at$parent, level = "county_union", share = 1, contains = TRUE,
                                         relation = "counties intersecting the study area, combined")
    }
  }
  list(picks = picks, notes = notes)
}

# The entity for one pick. `study_share` is the share of the benchmark's population living in
# the study area (the dependence adjustment in significance tests).
benchmark_entity <- function(pick, id, area) {
  info <- geo_info(pick$key, area$vintage)
  label <- if (length(pick$key) > 1) paste0("Counties containing ", area$short, " (combined)") else info$name
  e <- entity(id, "benchmark", label, info, pick$relation,
              paste0(if (pick$contains) "Contains" else "Intersects", " the study area"))
  e$level <- pick$level
  e$contains_study <- isTRUE(pick$contains)
  bm_pop <- sum(info$pop, na.rm = TRUE)
  e$study_share <- if (bm_pop > 0) min(1, (pick$share %||% 0) * area$pop / bm_pop) else NA_real_
  e
}

# Do two sets of pieces cover the same territory? Identical pieces, a place that is all of
# its county (San Francisco city and county), or a state that is one county (DC).
same_territory <- function(a, b, vintage) {
  if (identical(sort(a$key), sort(b$key))) return(TRUE)
  if (nrow(a) != 1 || nrow(b) != 1) return(FALSE)
  types <- c(a$type, b$type)
  if (setequal(types, c("place", "county"))) {
    place <- if (a$type == "place") a else b
    county <- if (a$type == "county") a else b
    parts <- place_parts(place$geoid, vintage)
    return(nrow(parts) == 1 && parts$county == county$geoid && isTRUE(all.equal(parts$pop, county$pop)))
  }
  if (setequal(types, c("state", "county"))) {
    return(substr(a$geoid, 1, 2) == substr(b$geoid, 1, 2) && isTRUE(all.equal(a$pop, b$pop)))
  }
  FALSE
}

fmt_share <- function(x) {
  if (is.na(x)) return("an unknown share")
  if (x == 0) return("0%")
  if (x < 0.001) return("<0.1%")
  paste0(formatC(100 * x, format = "f", digits = if (x < 0.1) 1 else 0), "%")
}
