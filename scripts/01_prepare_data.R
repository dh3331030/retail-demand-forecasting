source("scripts/00_config.R")

library(data.table)
library(readxl)

retail_raw <- as.data.table(
  read_excel(
    "data/raw/Retail trade volume of sales - food, beverages and tobacco(sts_trtu_m__custom_22913457_spreadsheet).xlsx",
    sheet = config$sources$eurostat_sheet,
    col_names = FALSE,
    col_types = "text",
    na = c("", ":")
  )
)

retail_dates <- retail_raw[retail_raw[[1]] == "TIME"]
countries <- config$analysis$countries

retail <- retail_raw[retail_raw[[1]] %in% countries]

date_labels <- as.character(
  unlist(retail_dates, use.names = FALSE)
)

date_columns <- which(
  date_labels >= "2015-01" &
    date_labels <= "2025-12"
)

retail <- retail[, c(1, date_columns), with = FALSE]

setnames(
  retail,
  c("country", date_labels[date_columns])
)

retail[
  , (names(retail)[-1]) := lapply(.SD, as.numeric),
  .SDcols = names(retail)[-1]
]

retail <- melt(
  retail,
  id.vars = "country",
  variable.name = "month",
  value.name = "retail_index",
  variable.factor = FALSE
)

retail <- retail[order(country, month)]

retail[
  month <= config$analysis$training_end,
  sample := "training"
]

retail[
  month > config$analysis$training_end &
    month <= config$analysis$validation_end,
  sample := "validation"
]

retail[
  month > config$analysis$validation_end &
    month <= config$analysis$test_end,
  sample := "testing"
]

retail[, .(
  observations = .N,
  missing_values = sum(is.na(retail_index))
), by = sample]

inflation_raw <- as.data.table(
  read_excel(
    "data/raw/Headline inflation.xlsx",
    sheet = config$sources$headline_inflation_sheet,
    col_names = FALSE,
    col_types = "text",
    na = c("", ":")
  )
)

inflation_dates <- inflation_raw[inflation_raw[[1]] == "TIME"]

inflation <- inflation_raw[inflation_raw[[1]] %in% countries]

date_labels <- as.character(
  unlist(inflation_dates, use.names = FALSE)
)

date_columns <- which(
  date_labels >= "2015-01" &
    date_labels <= "2025-12"
)

inflation <- inflation[, c(1, date_columns), with = FALSE]

setnames(
  inflation,
  c("country", date_labels[date_columns])
)

inflation[
  , (names(inflation)[-1]) := lapply(.SD, as.numeric),
  .SDcols = names(inflation)[-1]
]

inflation <- melt(
  inflation,
  id.vars = "country",
  variable.name = "month",
  value.name = "inflation_yoy",
  variable.factor = FALSE
)

inflation <- inflation[order(country, month)]

inflation[, .(
  observations = .N,
  missing_values = sum(is.na(inflation_yoy))
)]

unemployment_raw <- as.data.table(
  read_excel(
    "data/raw/Unemployment.xlsx",
    sheet = config$sources$unemployment_sheet,
    col_names = FALSE,
    col_types = "text",
    na = c("", ":")
  )
)

unemployment_dates <- unemployment_raw[
  unemployment_raw[[1]] == "TIME"
]

unemployment <- unemployment_raw[
  unemployment_raw[[1]] %in% countries
]

date_labels <- as.character(
  unlist(unemployment_dates, use.names = FALSE)
)

date_columns <- which(
  !is.na(date_labels) &
    date_labels >= "2015-01" &
    date_labels <= "2025-12"
)

unemployment <- unemployment[
  , c(1, date_columns), with = FALSE
]

setnames(
  unemployment,
  c("country", date_labels[date_columns])
)

unemployment[
  , (names(unemployment)[-1]) := lapply(.SD, as.numeric),
  .SDcols = names(unemployment)[-1]
]

unemployment <- melt(
  unemployment,
  id.vars = "country",
  variable.name = "month",
  value.name = "unemployment_rate",
  variable.factor = FALSE
)

unemployment <- unemployment[order(country, month)]

unemployment[, .(
  observations = .N,
  missing_values = sum(is.na(unemployment_rate))
)]

gdp_raw <- as.data.table(
  read_excel(
    "data/raw/(new)Gross domestic product (GDP) and main components (output, expenditure and income)(namq_10_gdp__custom_7680558_spreadsheet).xlsx",
    sheet = config$sources$gdp_sheet,
    col_names = FALSE,
    col_types = "text",
    na = c("", ":")
  )
)

gdp_dates <- gdp_raw[gdp_raw[[1]] == "TIME"]

gdp <- gdp_raw[gdp_raw[[1]] %in% countries]

date_labels <- as.character(
  unlist(gdp_dates, use.names = FALSE)
)

date_columns <- which(
  !is.na(date_labels) &
    date_labels >= "2015-Q1" &
    date_labels <= "2025-Q4"
)

gdp <- gdp[, c(1, date_columns), with = FALSE]

setnames(
  gdp,
  c("country", date_labels[date_columns])
)

gdp[
  , (names(gdp)[-1]) := lapply(.SD, as.numeric),
  .SDcols = names(gdp)[-1]
]

gdp <- melt(
  gdp,
  id.vars = "country",
  variable.name = "quarter",
  value.name = "gdp_qoq",
  variable.factor = FALSE
)

gdp[
  , gdp_monthly_equivalent :=
    100 * ((1 + gdp_qoq / 100)^(1 / 3) - 1)
]

gdp <- gdp[order(country, quarter)]

names(gdp)

gdp[, .(
  observations = .N,
  missing_growth = sum(is.na(gdp_monthly_equivalent))
)]

gdp[substr(quarter, 6, 7) == "Q1",
    quarter_end := paste0(substr(quarter, 1, 4), "-03")]

gdp[substr(quarter, 6, 7) == "Q2",
    quarter_end := paste0(substr(quarter, 1, 4), "-06")]

gdp[substr(quarter, 6, 7) == "Q3",
    quarter_end := paste0(substr(quarter, 1, 4), "-09")]

gdp[substr(quarter, 6, 7) == "Q4",
    quarter_end := paste0(substr(quarter, 1, 4), "-12")]

unique(gdp[, .(quarter, quarter_end)])[1:4]

gdp_monthly <- gdp[
  , .(
    month_number = 1:3,
    gdp_monthly_equivalent = gdp_monthly_equivalent
  ),
  by = .(country, quarter)
]

gdp_monthly[substr(quarter, 6, 7) == "Q1",
            month_number := 1:3, by = .(country, quarter)]

gdp_monthly[substr(quarter, 6, 7) == "Q2",
            month_number := 4:6, by = .(country, quarter)]

gdp_monthly[substr(quarter, 6, 7) == "Q3",
            month_number := 7:9, by = .(country, quarter)]

gdp_monthly[substr(quarter, 6, 7) == "Q4",
            month_number := 10:12, by = .(country, quarter)]

gdp_monthly[
  , month := paste0(
    substr(quarter, 1, 4),
    "-",
    sprintf("%02d", month_number)
  )
]

gdp_monthly <- gdp_monthly[
  , .(country, month, gdp_monthly_equivalent)
]

gdp_monthly <- gdp_monthly[order(country, month)]

gdp_monthly[, .(
  observations = .N,
  missing_growth = sum(is.na(gdp_monthly_equivalent))
)]

unzip(
  "data/raw/Oxford Covid-19 Government Response Tracker (OxCGRT).zip",
  files = "covid-policy-dataset-main/data/OxCGRT_compact_national_v1.csv",
  exdir = "data/processed"
)

covid_raw <- fread(
  "data/processed/covid-policy-dataset-main/data/OxCGRT_compact_national_v1.csv"
)

covid <- covid_raw[
  CountryCode %in% c("DEU", "FRA", "ITA", "POL", "PRT") &
    Jurisdiction == "NAT_TOTAL",
  .(
    country = CountryName,
    date = Date,
    stringency = StringencyIndex_Average
  )
]

covid[, .N, by = country]

covid[, month := paste0(
  substr(as.character(date), 1, 4),
  "-",
  substr(as.character(date), 5, 6)
)]

covid_monthly <- covid[
  , .(
    covid_stringency = mean(stringency)
  ),
  by = .(country, month)
]

covid_monthly <- covid_monthly[order(country, month)]

covid_monthly[, .(
  observations = .N,
  missing_values = sum(is.na(covid_stringency))
)]

ucdp_raw <- fread(
  "data/raw/ucdp/annual/GEDEvent_v23_1.csv"
)

ucdp_raw[
  , .(
    events = .N,
    first_year = min(year),
    last_year = max(year)
  )
]

# List the monthly Candidate files.
candidate_names <- c(
  paste0("GEDEvent_v22_0_", 11:12, ".csv"),
  paste0("GEDEvent_v23_0_", 1:12, ".csv"),
  paste0("GEDEvent_v24_0_", 1:12, ".csv"),
  paste0("GEDEvent_v25_0_", 1:12, ".csv")
)

# Columns required for our conflict calculations.
required_columns <- c(
  "id",
  "country",
  "type_of_violence",
  "code_status",
  "latitude",
  "longitude",
  "date_start",
  "date_end",
  "date_prec",
  "where_prec",
  "best",
  "low",
  "high"
)

# Store one table per monthly release.
candidate_tables <- list()

for (i in 1:length(candidate_names)) {
  
  message("Reading: ", candidate_names[i])
  
  if (candidate_names[i] == "GEDEvent_v24_0_1.csv") {
    
    # January 2024 has no header row.
    monthly_data <- fread(
      file.path(
        "data/raw/ucdp/candidate",
        candidate_names[i]
      ),
      header = FALSE,
      col.names = names(ucdp_raw)
    )
    
  } else {
    
    # All other files use their existing header row.
    monthly_data <- fread(
      file.path(
        "data/raw/ucdp/candidate",
        candidate_names[i]
      )
    )
    
  }
  
  missing_columns <- required_columns[
    !required_columns %in% names(monthly_data)
  ]
  
  if (length(missing_columns) > 0) {
    
    print(names(monthly_data))
    
    stop(
      "File: ", candidate_names[i],
      "\nMissing columns: ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }
  
  # Keep the required columns.
  monthly_data <- monthly_data[
    , required_columns,
    with = FALSE
  ]
  
  # Preserve the identity of the release.
  monthly_data[, source_file := candidate_names[i]]
  
  candidate_tables[[i]] <- monthly_data
}

candidate_events <- rbindlist(candidate_tables)

candidate_events[, date_start := as.Date(date_start)]
candidate_events[, date_end := as.Date(date_end)]

# Preserve records that cannot be used in distance calculations.
candidate_missing_coordinates <- copy(
  candidate_events[
    is.na(latitude) | is.na(longitude)
  ]
)

saveRDS(
  candidate_missing_coordinates,
  "data/processed/ucdp_candidate_missing_coordinates.rds"
)

# Retain events with both coordinates.
candidate_events <- candidate_events[
  !is.na(latitude) & !is.na(longitude)
]

# Confirm that the exclusions were recorded.
print(nrow(candidate_missing_coordinates))

# Confirm that the remaining events have complete coordinates.
print(
  candidate_events[
    , .(
      missing_latitude = sum(is.na(latitude)),
      missing_longitude = sum(is.na(longitude))
    )
  ]
)

ucdp <- ucdp_raw[
  , .(
    id,
    country,
    type_of_violence,
    latitude,
    longitude,
    date_start,
    date_end,
    date_prec,
    where_prec,
    best,
    low,
    high
  )
]

ucdp[, date_start := as.Date(date_start)]
ucdp[, date_end := as.Date(date_end)]

ucdp[, .(
  missing_start = sum(is.na(date_start)),
  missing_end = sum(is.na(date_end))
)]

ucdp <- ucdp[
  date_end >= as.Date("2015-01-01") &
    date_start <= as.Date("2025-12-31")
]

ucdp[, .(
  events = .N,
  missing_latitude = sum(is.na(latitude)),
  missing_longitude = sum(is.na(longitude))
)]

ucdp[, month := format(date_start, "%Y-%m")]

ucdp <- ucdp[
  month >= "2015-01" &
    month <= "2025-12"
]

capitals <- data.table(
  country = c("Germany", "France", "Italy", "Poland", "Portugal"),
  capital = c("Berlin", "Paris", "Rome", "Warsaw", "Lisbon"),
  latitude = c(52.5200, 48.8566, 41.9028, 52.2297, 38.7223),
  longitude = c(13.4050, 2.3522, 12.4964, 21.0122, -9.1393)
)

country_events <- list()

for (i in 1:nrow(capitals)) {
  
  events <- copy(ucdp)
  
  capital_lat <- capitals$latitude[i]
  capital_lon <- capitals$longitude[i]
  
  events[, a :=
           sin((latitude - capital_lat) * pi / 180 / 2)^2 +
           cos(latitude * pi / 180) *
           cos(capital_lat * pi / 180) *
           sin((longitude - capital_lon) * pi / 180 / 2)^2
  ]
  
  events[, a := pmin(1, pmax(0, a))]
  
  events[, distance_km := 2 * 6371 * asin(sqrt(a))]
  
  events[, a := NULL]

  events[, focal_country := capitals$country[i]]
  
  country_events[[i]] <- events
}

conflict_events <- rbindlist(country_events)

conflict_events[, .(
  events = .N,
  missing_distances = sum(is.na(distance_km))
), by = focal_country]

conflict_events[
  , weight_500 := exp(-distance_km / 500)
]

conflict_events[
  , weight_1000 := exp(-distance_km / 1000)
]

conflict_events[
  , weight_2000 := exp(-distance_km / 2000)
]

conflict_monthly <- conflict_events[
  , .(
    conflict_500 = sum(weight_500),
    conflict_1000 = sum(weight_1000),
    conflict_2000 = sum(weight_2000),
    conflict_deaths_1000 = sum(best * weight_1000)
  ),
  by = .(focal_country, month)
]

setnames(conflict_monthly, "focal_country", "country")

conflict_monthly <- conflict_monthly[order(country, month)]

conflict_monthly[, .(
  observations = .N,
  missing_deaths_exposure = sum(is.na(conflict_deaths_1000))
), by = country]

panel <- merge(
  retail,
  inflation,
  by = c("country", "month"),
  all.x = TRUE
)

panel <- merge(
  panel,
  unemployment,
  by = c("country", "month"),
  all.x = TRUE
)

panel <- merge(
  panel,
  gdp_monthly,
  by = c("country", "month"),
  all.x = TRUE
)

panel <- merge(
  panel,
  covid_monthly,
  by = c("country", "month"),
  all.x = TRUE
)

panel <- merge(
  panel,
  conflict_monthly,
  by = c("country", "month"),
  all.x = TRUE
)

panel <- panel[order(country, month)]

nrow(panel)

panel[, .N, by = .(country, month)][N > 1]

saveRDS(
  panel,
  config$paths$prepared_panel
)
