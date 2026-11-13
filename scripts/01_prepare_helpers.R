# Small reusable calculations used by 01_prepare_data.R.
# Functions use the same base R/data.table operations as the tutoring scripts.

read_eurostat <- function(path, sheet, countries, first, last, period, value) {
  raw <- as.data.table(read_excel(
    path, sheet = sheet, col_names = FALSE,
    col_types = "text", na = c("", ":")
  ))
  labels <- as.character(unlist(raw[raw[[1]] == "TIME"], use.names = FALSE))
  columns <- which(!is.na(labels) & labels >= first & labels <= last)
  if (length(columns) == 0) stop("No requested periods in: ", path)
  result <- raw[raw[[1]] %in% countries, c(1, columns), with = FALSE]
  if (nrow(result) != length(countries) || !all(countries %in% result[[1]])) {
    stop("Expected one row per country in: ", path)
  }
  setnames(result, c("country", labels[columns]))
  result[, (names(result)[-1]) := lapply(.SD, as.numeric),
         .SDcols = names(result)[-1]]
  result <- melt(result, id.vars = "country", variable.name = period,
                 value.name = value, variable.factor = FALSE)
  if (anyDuplicated(result[, c("country", period), with = FALSE])) {
    stop("Duplicate country-period rows in: ", path)
  }
  result
}

# Validate required fields, and preserve every excluded record for inspection.

clean_events <- function(events, label) {
  events[, date_start := as.Date(date_start)]
  events[, date_end := as.Date(date_end)]
  if (any(is.na(events$id)) || any(is.na(events$date_start)) ||
      any(is.na(events$date_end)) || any(is.na(events$best))) {
    stop("Missing event ID, date or best death estimate in ", label)
  }
  if (any(events$date_end < events$date_start)) stop("Reversed event dates in ", label)
  if (any(events$best < 0)) stop("Negative best death estimate in ", label)
  if (anyDuplicated(events[, .(source_file, id)])) {
    stop("Repeated event ID within a release in ", label)
  }
  excluded <- events[is.na(latitude) | is.na(longitude)]
  saveRDS(excluded, file.path(config$paths$processed,
                            paste0("ucdp_", label, "_missing_coordinates.rds")))
  events <- events[!is.na(latitude) & !is.na(longitude)]
  if (any(abs(events$latitude) > 90) || any(abs(events$longitude) > 180)) {
    stop("Coordinates outside valid ranges in ", label)
  }
  message(label, ": excluded ", nrow(excluded), " records without coordinates.")
  events[, event_month := format(date_start, "%Y-%m")]
  events
}

# Calculate the same four weights for either annual or Candidate events.
weight_events <- function(input, capital_row) {
  events <- copy(input)
  capital_lat <- capital_row$latitude
  capital_lon <- capital_row$longitude
  events[, a := sin((latitude - capital_lat) * pi / 360)^2 +
           cos(latitude * pi / 180) * cos(capital_lat * pi / 180) *
           sin((longitude - capital_lon) * pi / 360)^2]
  events[, a := pmin(1, pmax(0, a))]
  events[, distance_km := 2 * 6371 * asin(sqrt(a))]
  events[, a := NULL]
  events[, focal_country := capital_row$country]
  events[, weight_500 := exp(-distance_km / 500)]
  events[, weight_1000 := exp(-distance_km / 1000)]
  events[, weight_2000 := exp(-distance_km / 2000)]
  events[, deaths_weight_1000 := best * weight_1000]
  events
}
