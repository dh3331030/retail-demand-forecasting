# Run from the RStudio project root. This stage prepares data, not models.
source("scripts/00_config.R", local = TRUE)

library(data.table)

library(readxl)

#load the helper function definitions used for data reading and processing
source("scripts/01_prepare_helpers.R", local = TRUE)

#create the "processed" folder
dir.create(config$paths$processed, recursive = TRUE, showWarnings = FALSE)


countries <- config$analysis$countries

first <- config$analysis$sample_start

last <- config$analysis$sample_end

raw_path <- config$paths$raw

processed <- config$paths$processed

# 1. Monthly Eurostat sources ---------------------------------------------
# One function performs the repeated select/rename/convert/melt operations.

# call the helper function to load monthly retail-volume indices for the five countries.
retail <- read_eurostat(
  file.path(raw_path, "Retail trade volume of sales - food, beverages and tobacco(sts_trtu_m__custom_22913457_spreadsheet).xlsx"),
  config$sources$eurostat_sheet, countries, first, last, "month", "retail_index"
)

#call the same helper to load monthly YoY headline inflation
inflation <- read_eurostat(
  file.path(raw_path, "Headline inflation.xlsx"),
  config$sources$headline_inflation_sheet, countries, first, last, "month", "inflation_yoy"
)

#call the same helper to load monthly unemployment rates
unemployment <- read_eurostat(
  file.path(raw_path, "Unemployment.xlsx"),
  config$sources$unemployment_sheet, countries, first, last, "month", "unemployment_rate"
)

# `:=` changes a column in place
#mark the observations through the cutoff as training rows
retail[month <= config$analysis$training_end, sample := "training"]

#label months after training and through the validation cutoff as validation rows
retail[month > config$analysis$training_end &
         month <= config$analysis$validation_end, sample := "validation"]

#label months after validation through the test cutoff as testing rows
retail[month > config$analysis$validation_end &
         month <= config$analysis$test_end, sample := "testing"]

#STOP1 if any retail observation was not assigned to a sample
if (any(is.na(retail$sample))) stop("Some retail months have no sample assignment.")

# 2. Quarterly GDP --------------------------------------------------------

#derive the first quarterly period from the starting year and month 
first_quarter <- paste0(substr(first, 1, 4), "-Q",
                        (as.integer(substr(first, 6, 7)) - 1) %/% 3 + 1)

#derive the last quarterly period from the final year and month
last_quarter <- paste0(substr(last, 1, 4), "-Q",
                       (as.integer(substr(last, 6, 7)) - 1) %/% 3 + 1)

#load quarterly GDP changes from workbook
gdp <- read_eurostat(
  file.path(raw_path, "(new)Gross domestic product (GDP) and main components (output, expenditure and income)(namq_10_gdp__custom_7680558_spreadsheet).xlsx"),
  config$sources$gdp_sheet, countries, first_quarter, last_quarter, "quarter", "gdp_qoq"
)

#parse Q1-Q4 into a numeric quarter identifier
gdp[, quarter_number := as.integer(substr(quarter, 7, 7))]

#create a "YYYY-MM" identifier for the quarter's ending month
gdp[, quarter_end := paste0(substr(quarter, 1, 4), "-",
                            sprintf("%02d", quarter_number * 3))]

#convert quarterly percentage growth into the monthly rate that compounds to the same quarterly growth.
gdp[, gdp_monthly_equivalent := 100 * ((1 + gdp_qoq / 100)^(1 / 3) - 1)]

#save for later in script 02.
saveRDS(gdp, file.path(processed, "gdp_quarterly.rds"))

#repeat each quarterly transformed rate across its three constituent month numbers
gdp_monthly <- gdp[, .(
  month_number = (quarter_number - 1) * 3 + 1:3,
  gdp_monthly_equivalent = gdp_monthly_equivalent
), by = .(country, quarter)]

#format those month numbers into `YYYY-MM` strings.
gdp_monthly[, month := paste0(substr(quarter, 1, 4), "-",
                              sprintf("%02d", month_number))]

#keeping only the country, month and monthly-equivalent GDP columns needed for merging.
gdp_monthly <- gdp_monthly[, .(country, month, gdp_monthly_equivalent)]

# 3. COVID ---------------------------------------------------------------
# Extract on each preparation run so the CSV reflects the supplied ZIP.

unzip(file.path(raw_path, "Oxford Covid-19 Government Response Tracker (OxCGRT).zip"),
      files = config$sources$covid_member, exdir = processed, overwrite = TRUE)

#read with `fread()`
covid <- fread(file.path(processed, config$sources$covid_member))

#keep national-level observations for the five study countries
covid <- covid[CountryCode %in% c("DEU", "FRA", "ITA", "POL", "PRT") &
                 Jurisdiction == "NAT_TOTAL",
               .(country = CountryName, date = Date,
                 stringency = StringencyIndex_Average)]

#convert the daily date representation into a calendar-month key.
covid[, month := paste0(substr(as.character(date), 1, 4), "-",
                        substr(as.character(date), 5, 6))]

#aggregate daily stringency indices into a monthly mean for each country.
covid_monthly <- covid[, .(covid_stringency = mean(stringency)),
                       by = .(country, month)]

# 4. Annual GED: unzip to generated data, never to the versioned raw folder -

#path to the annual conflict event ZIP.
annual_zip <- file.path(raw_path, "ucdp/annual/GEDEvent_v23_1.csv.zip")

#stop the annual GED archive is missing.
if (!file.exists(annual_zip)) stop("Annual GED ZIP missing: ", annual_zip)

#list filenames
zip_members <- unzip(annual_zip, list = TRUE)$Name

#filter to CSV files (excluding macOS metadata)
csv_member <- zip_members[grepl("\\.csv$", zip_members, ignore.case = TRUE) &
                            !grepl("__MACOSX/", zip_members)]

#require one CSV.
if (length(csv_member) != 1) stop("Annual GED ZIP must contain exactly one CSV.")

#extraction folder
annual_folder <- file.path(processed, "ucdp_annual")

#create that folder if necessary
dir.create(annual_folder, recursive = TRUE, showWarnings = FALSE)

#extract the CSV into the folder
unzip(annual_zip, files = csv_member, exdir = annual_folder, overwrite = TRUE)

#build the extracted CSV's full path
annual_path <- file.path(annual_folder, csv_member)

#read file header and retain its column names for a later headerless candidate
annual_header <- names(fread(annual_path, nrows = 0))

required_columns <- c("id", "country", "type_of_violence", "code_status",
                      "latitude", "longitude", "date_start", "date_end",
                      "date_prec", "where_prec", "best", "low", "high")

#read the selected columns
annual <- fread(annual_path, select = required_columns)

#tag annual observations with their source-release identifier
annual[, source_file := "GED_23.1"]

#`clean_events()` helper to validate the annual records and exclude missing coordinates.
annual <- clean_events(annual, "annual")

# Explicitly retain annual events only through the training reference period.

#keep annual events in the initial training reference window only
annual <- annual[event_month >= first & event_month <= config$analysis$training_end]

# 5. Candidate releases ---------------------------------------------------
# One source-month vector supplies both names and reference-period metadata.

#construct all monthly Candidate source periods: late 2022 and every month in 2023-2025.
#late 2022 is included
candidate_months <- c("2022-11", "2022-12",
  paste0("2023-", sprintf("%02d", 1:12)),
  paste0("2024-", sprintf("%02d", 1:12)),
  paste0("2025-", sprintf("%02d", 1:12)))

#create the table recording one Candidate release per source month.
candidate_sources <- data.table(source_month = candidate_months)

#generate the expected CSV filename from each source year and month.
candidate_sources[, source_file := paste0("GEDEvent_v", substr(source_month, 3, 4),
  "_0_", as.integer(substr(source_month, 6, 7)), ".csv")]

#convert each release month to an integer month index (`year * 12 + month`).
candidate_sources[, source_month_id := as.integer(substr(source_month, 1, 4)) * 12 +
                    as.integer(substr(source_month, 6, 7))]

#define assumed first eligible forecast month as two months after each source month.
candidate_sources[, available_forecast_month_id := source_month_id + 2]
#initialize a list for the individual Candidate source tables.
candidate_tables <- list()
#loop over every expected Candidate release file.
for (i in 1:nrow(candidate_sources)) {
  filename <- candidate_sources$source_file[i]
  path <- file.path(raw_path, "ucdp/candidate", filename)
  if (!file.exists(path)) stop("Candidate file missing: ", filename)
  if (filename == "GEDEvent_v24_0_1.csv") {
    #confirmed headerless file: preserve its first event and annual column order.
    monthly <- fread(path, header = FALSE, col.names = annual_header)
    monthly <- monthly[, required_columns, with = FALSE]
  } else {
    monthly <- fread(path, select = required_columns)
  }
  monthly[, source_file := filename]
  candidate_tables[[i]] <- monthly
}
#row-bind all Candidate releases into one event table.
candidate <- rbindlist(candidate_tables)

#join release metadata to each event by its source filename; retain all event rows.
candidate <- merge(candidate, candidate_sources, by = "source_file", all.x = TRUE)

#validate Candidate events and exclude geolocation-missing records via the helper.
candidate <- clean_events(candidate, "candidate")

#convert each Candidate event month to the common integer month index.
candidate[, event_month_id := as.integer(substr(event_month, 1, 4)) * 12 +
            as.integer(substr(event_month, 6, 7))]

#save the Candidate release inventory and its assumed forecast availability dates.
saveRDS(candidate_sources, file.path(processed, "ucdp_candidate_sources.rds"))

# 6. Common distance calculation -----------------------------------------

#define capital coordinates for Germany, France, Italy, Poland and Portugal in matching order.
capitals <- data.table(
  country = c("Germany", "France", "Italy", "Poland", "Portugal"),
  latitude = c(52.5200, 48.8566, 41.9028, 52.2297, 38.7223),
  longitude = c(13.4050, 2.3522, 12.4964, 21.0122, -9.1393))

#initialize monthly summaries of annual conflict exposure by capital.
annual_tables <- list()

#initialize per-capital Candidate event weights for later vintage-aware construction.
candidate_weights <- list()
#repeat the distance/weight calculations for each capital.
for (i in 1:nrow(capitals)) {
  #aggregate annual events immediately, avoiding five full copies in memory.
  #`weight_events()` on annual events relative to the current capital.
  weighted <- weight_events(annual, capitals[i])
  #sum annual exposure weights by focal country and event month for all four alternatives.
  annual_tables[[i]] <- weighted[, .(
    conflict_500 = sum(weight_500), conflict_1000 = sum(weight_1000),
    conflict_2000 = sum(weight_2000),
    conflict_deaths_1000 = sum(deaths_weight_1000)
  ), by = .(country = focal_country, month = event_month)]
  #compute weighted Candidate event records relative to the same capital; preserve release versions.
  candidate_weights[[i]] <- weight_events(candidate, capitals[i])
}

#combine the five capital-specific annual exposure tables.
conflict_monthly <- rbindlist(annual_tables)

#combine the five capital-specific Candidate weighted-event tables.
candidate_conflict_events <- rbindlist(candidate_weights)

#save monthly annual conflict indicators for use in the training sample.
saveRDS(conflict_monthly, file.path(processed, "ucdp_annual_exposure_monthly.rds"))

#save event-level weighted Candidate releases for use in future validation/test forecasts.
saveRDS(candidate_conflict_events,
        file.path(processed, "ucdp_candidate_exposure_events.rds"))

# 7. Merge and save the preparation panel ---------------------------------

#initialize the merged preparation panel with the retail observations as the key universe.
panel <- retail

#iterate over each complementary macroeconomic, COVID and annual-conflict table.
for (extra in list(inflation, unemployment, gdp_monthly, covid_monthly, conflict_monthly)) {
  #refuse a source table with duplicate country-month keys before joining it.
  if (anyDuplicated(extra[, .(country, month)])) stop("Duplicate merge keys.")
  #left-join the supplementary data to retail by country and month, keeping all retail rows.
  panel <- merge(panel, extra, by = c("country", "month"), all.x = TRUE)
}

#sort the resulting panel by country, then calendar month.
panel <- panel[order(country, month)]

#check that the series of left joins did not change the total number of retail observations.
if (nrow(panel) != nrow(retail)) stop("A merge changed the number of retail rows.")

#check again for duplicate `(country, month)` panel keys.
if (anyDuplicated(panel[, .(country, month)])) stop("Duplicate panel rows.")

#serialize the prepared panel to the configured RDS path.
saveRDS(panel, config$paths$prepared_panel)

#print observation counts and date ranges by training/validation/testing sample.
print(panel[, .(observations = .N, first_month = min(month),
                last_month = max(month)), by = sample])

#report that preparation ended and that annual exposure was restricted to the training period.
message("Preparation complete. Annual exposure is present only through training.")
