#each function defines a reusable routine for other scripts to call
#`.N` means group size
#`.SD` refers to selected columns.

#`read_eurostat()`: load one spreadsheet and return one numeric observation per country and period.
read_eurostat <- function(path, sheet, countries, first, last, period, value) {
  #read the specified Excel sheet as text, then convert the result to a `data.table`
  raw <- as.data.table(read_excel(
    path, sheet = sheet, col_names = FALSE,
    col_types = "text", na = c("", ":")
  ))
  #find the row marked `TIME` and extract its period labels as a character vector.
  labels <- as.character(unlist(raw[raw[[1]] == "TIME"], use.names = FALSE))
  #use `which()` to identify periods in the requested inclusive date range.
  columns <- which(!is.na(labels) & labels >= first & labels <= last)
  #stop if the sheet contains no periods inside that range.
  if (length(columns) == 0) stop("No requested periods in: ", path)
  #select the target countries and the first column plus matching period columns.
  result <- raw[raw[[1]] %in% countries, c(1, columns), with = FALSE]
  #check that there is exactly one selected row for every requested country.
  if (nrow(result) != length(countries) || !all(countries %in% result[[1]])) {
    #stop if country rows are missing or do not match expectations.
    stop("Expected one row per country in: ", path)
  }
  #rename the first column `country` and the remaining columns with their period labels.
  setnames(result, c("country", labels[columns]))
  #convert every period column to numeric by reference
  result[, (names(result)[-1]) := lapply(.SD, as.numeric),
         .SDcols = names(result)[-1]]
  #reshape wide year/month columns into long country-period-value rows with `melt()`.
  result <- melt(result, id.vars = "country", variable.name = period,
                 value.name = value, variable.factor = FALSE)
  #check that the reshaped data has no repeated country-period key.
  if (anyDuplicated(result[, c("country", period), with = FALSE])) {
    #stop if duplicate
    stop("Duplicate country-period rows in: ", path)
  }
  #return the cleaned table
  result
}


#`clean_events()` validates event and document records dropped for missing coordinates.
clean_events <- function(events, label) {
  #convert event start dates to R `Date` objects by reference.
  events[, date_start := as.Date(date_start)]
  #convert event end dates to R `Date` objects by reference.
  events[, date_end := as.Date(date_end)]
  #verify that event ID, start/end dates and the best death estimate are present.
  if (any(is.na(events$id)) || any(is.na(events$date_start)) ||
      any(is.na(events$date_end)) || any(is.na(events$best))) {
    #reject events with missing indispensable fields.
    stop("Missing event ID, date or best death estimate in ", label)
  }
  #reject any event whose end date precedes its start date.
  if (any(events$date_end < events$date_start)) stop("Reversed event dates in ", label)
  #reject any negative best death estimate.
  if (any(events$best < 0)) stop("Negative best death estimate in ", label)
  if (anyDuplicated(events[, .(source_file, id)])) {
    #reject repeated event IDs inside the same source file.
    stop("Repeated event ID within a release in ", label)
  }
  #gather rows lacking either latitude or longitude for separate inspection
  excluded <- events[is.na(latitude) | is.na(longitude)]
  #persist excluded geolocation records in an RDS file named for the source label
  saveRDS(excluded, file.path(config$paths$processed,
                            paste0("ucdp_", label, "_missing_coordinates.rds")))
  #retain only events with both coordinates populated.
  events <- events[!is.na(latitude) & !is.na(longitude)]
  #check latitude and longitude against their physical bounds in degrees
  if (any(abs(events$latitude) > 90) || any(abs(events$longitude) > 180)) {
    #stop if the remaining coordinates are invalid.
    stop("Coordinates outside valid ranges in ", label)
  }
  #report how many event records were excluded for missing coordinates
  message(label, ": excluded ", nrow(excluded), " records without coordinates.")
  #convert each event's start date to `YYYY-MM` for monthly aggregation
  events[, event_month := format(date_start, "%Y-%m")]
  #return the validated, complete events table
  events
}

#calculate the same four weights for either annual or Candidate events.
#`weight_events()` computes event distance and conflict-exposure weights relative to a capital
weight_events <- function(input, capital_row) {
  #copy the input so the subsequent by-reference columns do not modify the caller's table
  events <- copy(input)
  capital_lat <- capital_row$latitude
  capital_lon <- capital_row$longitude
  #calculate the haversine intermediate term `a` from event and capital coordinates (angles in radians).
  events[, a := sin((latitude - capital_lat) * pi / 360)^2 +
           cos(latitude * pi / 180) * cos(capital_lat * pi / 180) *
           sin((longitude - capital_lon) * pi / 360)^2]
  #clamp `a` between zero and one to avoid numerical domain errors in `asin()`.
  events[, a := pmin(1, pmax(0, a))]
  #convert haversine `a` to great-circle distance in km, using Earth radius 6371 km.
  events[, distance_km := 2 * 6371 * asin(sqrt(a))]
  #drop the temporary haversine calculation column.
  events[, a := NULL]
  events[, focal_country := capital_row$country]
  #assign an exponentially declining distance weight with a 500-km scale.
  events[, weight_500 := exp(-distance_km / 500)]
  events[, weight_1000 := exp(-distance_km / 1000)]
  events[, weight_2000 := exp(-distance_km / 2000)]
  #multiply estimated event deaths by the 1,000-km weight to form death-weighted exposure
  events[, deaths_weight_1000 := best * weight_1000]
  #return the table with distance and the four computed exposure measures.
  events
}
