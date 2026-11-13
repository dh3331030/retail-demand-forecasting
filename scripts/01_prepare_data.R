# Run from the RStudio project root. This stage prepares data, not models.
source("scripts/00_config.R", local = TRUE)

library(data.table)

library(readxl)

source("scripts/01_prepare_helpers.R", local = TRUE)

dir.create(config$paths$processed, recursive = TRUE, showWarnings = FALSE)

countries <- config$analysis$countries

first <- config$analysis$sample_start

last <- config$analysis$sample_end

raw_path <- config$paths$raw

processed <- config$paths$processed

# 1. Monthly Eurostat sources ---------------------------------------------
# One function performs the repeated select/rename/convert/melt operations.

retail <- read_eurostat(
  file.path(raw_path, "Retail trade volume of sales - food, beverages and tobacco(sts_trtu_m__custom_22913457_spreadsheet).xlsx"),
  config$sources$eurostat_sheet, countries, first, last, "month", "retail_index"
)

inflation <- read_eurostat(
  file.path(raw_path, "Headline inflation.xlsx"),
  config$sources$headline_inflation_sheet, countries, first, last, "month", "inflation_yoy"
)

unemployment <- read_eurostat(
  file.path(raw_path, "Unemployment.xlsx"),
  config$sources$unemployment_sheet, countries, first, last, "month", "unemployment_rate"
)

retail[month <= config$analysis$training_end, sample := "training"]

retail[month > config$analysis$training_end &
         month <= config$analysis$validation_end, sample := "validation"]

retail[month > config$analysis$validation_end &
         month <= config$analysis$test_end, sample := "testing"]

if (any(is.na(retail$sample))) stop("Some retail months have no sample assignment.")

# 2. Quarterly GDP --------------------------------------------------------

first_quarter <- paste0(substr(first, 1, 4), "-Q",
                        (as.integer(substr(first, 6, 7)) - 1) %/% 3 + 1)

last_quarter <- paste0(substr(last, 1, 4), "-Q",
                       (as.integer(substr(last, 6, 7)) - 1) %/% 3 + 1)

gdp <- read_eurostat(
  file.path(raw_path, "(new)Gross domestic product (GDP) and main components (output, expenditure and income)(namq_10_gdp__custom_7680558_spreadsheet).xlsx"),
  config$sources$gdp_sheet, countries, first_quarter, last_quarter, "quarter", "gdp_qoq"
)

gdp[, quarter_number := as.integer(substr(quarter, 7, 7))]

gdp[, quarter_end := paste0(substr(quarter, 1, 4), "-",
                            sprintf("%02d", quarter_number * 3))]

gdp[, gdp_monthly_equivalent := 100 * ((1 + gdp_qoq / 100)^(1 / 3) - 1)]

# Save the quarterly identity for later publication-date alignment in script 02.

saveRDS(gdp, file.path(processed, "gdp_quarterly.rds"))

gdp_monthly <- gdp[, .(
  month_number = (quarter_number - 1) * 3 + 1:3,
  gdp_monthly_equivalent = gdp_monthly_equivalent
), by = .(country, quarter)]

gdp_monthly[, month := paste0(substr(quarter, 1, 4), "-",
                              sprintf("%02d", month_number))]

gdp_monthly <- gdp_monthly[, .(country, month, gdp_monthly_equivalent)]

# 3. COVID ---------------------------------------------------------------
# Extract on each preparation run so the CSV reflects the supplied ZIP.

unzip(file.path(raw_path, "Oxford Covid-19 Government Response Tracker (OxCGRT).zip"),
      files = config$sources$covid_member, exdir = processed, overwrite = TRUE)

covid <- fread(file.path(processed, config$sources$covid_member))

covid <- covid[CountryCode %in% c("DEU", "FRA", "ITA", "POL", "PRT") &
                 Jurisdiction == "NAT_TOTAL",
               .(country = CountryName, date = Date,
                 stringency = StringencyIndex_Average)]

covid[, month := paste0(substr(as.character(date), 1, 4), "-",
                        substr(as.character(date), 5, 6))]

# Preserve the existing missing-data rule; do not silently remove missing days.

covid_monthly <- covid[, .(covid_stringency = mean(stringency)),
                       by = .(country, month)]

# 4. Annual GED: unzip to generated data, never to the versioned raw folder -

annual_zip <- file.path(raw_path, "ucdp/annual/GEDEvent_v23_1.csv.zip")

if (!file.exists(annual_zip)) stop("Annual GED ZIP missing: ", annual_zip)

zip_members <- unzip(annual_zip, list = TRUE)$Name

csv_member <- zip_members[grepl("\\.csv$", zip_members, ignore.case = TRUE) &
                            !grepl("__MACOSX/", zip_members)]

if (length(csv_member) != 1) stop("Annual GED ZIP must contain exactly one CSV.")

annual_folder <- file.path(processed, "ucdp_annual")

dir.create(annual_folder, recursive = TRUE, showWarnings = FALSE)

unzip(annual_zip, files = csv_member, exdir = annual_folder, overwrite = TRUE)

annual_path <- file.path(annual_folder, csv_member)

annual_header <- names(fread(annual_path, nrows = 0))

required_columns <- c("id", "country", "type_of_violence", "code_status",
                      "latitude", "longitude", "date_start", "date_end",
                      "date_prec", "where_prec", "best", "low", "high")

annual <- fread(annual_path, select = required_columns)

annual[, source_file := "GED_23.1"]

annual <- clean_events(annual, "annual")

# Explicitly retain annual events only through the training reference period.

annual <- annual[event_month >= first & event_month <= config$analysis$training_end]

# 5. Candidate releases ---------------------------------------------------
# One source-month vector supplies both names and reference-period metadata.

candidate_months <- c("2022-11", "2022-12",
  paste0("2023-", sprintf("%02d", 1:12)),
  paste0("2024-", sprintf("%02d", 1:12)),
  paste0("2025-", sprintf("%02d", 1:12)))

candidate_sources <- data.table(source_month = candidate_months)

candidate_sources[, source_file := paste0("GEDEvent_v", substr(source_month, 3, 4),
  "_0_", as.integer(substr(source_month, 6, 7)), ".csv")]

candidate_sources[, source_month_id := as.integer(substr(source_month, 1, 4)) * 12 +
                    as.integer(substr(source_month, 6, 7))]

# Scheduling convention, NOT individually verified historical publication dates.

candidate_sources[, available_forecast_month_id := source_month_id + 2]

candidate_tables <- list()
for (i in 1:nrow(candidate_sources)) {
  filename <- candidate_sources$source_file[i]
  path <- file.path(raw_path, "ucdp/candidate", filename)
  if (!file.exists(path)) stop("Candidate file missing: ", filename)
  if (filename == "GEDEvent_v24_0_1.csv") {
    # Confirmed headerless file: preserve its first event and annual column order.
    monthly <- fread(path, header = FALSE, col.names = annual_header)
    monthly <- monthly[, required_columns, with = FALSE]
  } else {
    monthly <- fread(path, select = required_columns)
  }
  monthly[, source_file := filename]
  candidate_tables[[i]] <- monthly
}

candidate <- rbindlist(candidate_tables)

candidate <- merge(candidate, candidate_sources, by = "source_file", all.x = TRUE)

candidate <- clean_events(candidate, "candidate")

candidate[, event_month_id := as.integer(substr(event_month, 1, 4)) * 12 +
            as.integer(substr(event_month, 6, 7))]

saveRDS(candidate_sources, file.path(processed, "ucdp_candidate_sources.rds"))

# 6. Common distance calculation -----------------------------------------

capitals <- data.table(
  country = c("Germany", "France", "Italy", "Poland", "Portugal"),
  latitude = c(52.5200, 48.8566, 41.9028, 52.2297, 38.7223),
  longitude = c(13.4050, 2.3522, 12.4964, 21.0122, -9.1393))

annual_tables <- list()

candidate_weights <- list()
for (i in 1:nrow(capitals)) {
  # Aggregate annual events immediately, avoiding five full copies in memory.
  weighted <- weight_events(annual, capitals[i])
  annual_tables[[i]] <- weighted[, .(
    conflict_500 = sum(weight_500), conflict_1000 = sum(weight_1000),
    conflict_2000 = sum(weight_2000),
    conflict_deaths_1000 = sum(deaths_weight_1000)
  ), by = .(country = focal_country, month = event_month)]
  candidate_weights[[i]] <- weight_events(candidate, capitals[i])
}

conflict_monthly <- rbindlist(annual_tables)

candidate_conflict_events <- rbindlist(candidate_weights)

saveRDS(conflict_monthly, file.path(processed, "ucdp_annual_exposure_monthly.rds"))

saveRDS(candidate_conflict_events,
        file.path(processed, "ucdp_candidate_exposure_events.rds"))

# 7. Merge and save the preparation panel ---------------------------------

panel <- retail

for (extra in list(inflation, unemployment, gdp_monthly, covid_monthly, conflict_monthly)) {
  if (anyDuplicated(extra[, .(country, month)])) stop("Duplicate merge keys.")
  panel <- merge(panel, extra, by = c("country", "month"), all.x = TRUE)
}

panel <- panel[order(country, month)]

if (nrow(panel) != nrow(retail)) stop("A merge changed the number of retail rows.")

if (anyDuplicated(panel[, .(country, month)])) stop("Duplicate panel rows.")

saveRDS(panel, config$paths$prepared_panel)

print(panel[, .(observations = .N, first_month = min(month),
                last_month = max(month)), by = sample])

message("Preparation complete. Annual exposure is present only through training.")
