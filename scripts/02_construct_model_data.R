# Work completed through retail-growth lags; availability rules are pending.
library(data.table)

source("scripts/00_config.R")

panel <- as.data.table(
  readRDS(config$paths$prepared_panel)
)

panel <- panel[order(country, month)]

# Check chronological samples: dates and counts only.
panel[
  , .(
    first_month = min(month),
    last_month = max(month),
    observations = .N
  ),
  by = sample
]

# Identify duplicate country-month observations (if any).
panel[, .N, by = .(country, month)][N > 1]

# Convert each month into a consecutive integer.
panel[
  , month_id :=
    as.integer(substr(month, 1, 4)) * 12 +
    as.integer(substr(month, 6, 7))
]

# Check the spacing between consecutive observations within each country.
panel[
  , month_gap := c(NA, diff(month_id)),
  by = country
]

# Display any gaps. This and the duplicate check should return zero rows.
panel[
  !is.na(month_gap) & month_gap != 1,
  .(country, month, month_gap)
]

# Previous month's retail index within each country.
panel[
  , retail_index_previous := c(NA, retail_index[-.N]),
  by = country
]

# Monthly retail growth in log percentage points (0.12 is about 0.12%).
panel[
  , retail_growth :=
    100 * log(retail_index / retail_index_previous)
]

# Training-sample checks.
panel[
  sample == "training",
  .(
    observations = .N,
    missing_growth = sum(is.na(retail_growth)),
    nonpositive_index = sum(retail_index <= 0, na.rm = TRUE)
  ),
  by = country
]

# Retail growth three months before the target month.
panel[
  , retail_growth_lag3 := c(
    NA, NA, NA,
    retail_growth[-c(.N - 2, .N - 1, .N)]
  ),
  by = country
]

# Inflation two months before the target month.
panel[
  , inflation_lag2 := c(
    NA,
    NA,
    inflation_yoy[-c(.N - 1, .N)]
  ),
  by = country
]

# Unemployment three months before the target month.
panel[
  , unemployment_lag3 := c(
    NA,
    NA,
    NA,
    unemployment_rate[-c(.N - 2, .N - 1, .N)]
  ),
  by = country
]

# Load the quarterly GDP table saved during preparation.
gdp <- as.data.table(
  readRDS(
    file.path(config$paths$processed, "gdp_quarterly.rds")
  )
)

# Identify the quarter-end month.
gdp[
  , quarter_end_month_id :=
    as.integer(substr(quarter_end, 1, 4)) * 12 +
    as.integer(substr(quarter_end, 6, 7))
]

# Conservative availability rule for the regular GDP release.
gdp[
  , available_forecast_month_id := quarter_end_month_id + 4
]

# Create the predictor and a column recording its source quarter.
panel[, gdp_available := NA_real_]
panel[, gdp_source_quarter := NA_character_]

for (i in 1:nrow(panel)) {
  
  eligible <- gdp[
    country == panel$country[i] &
      available_forecast_month_id <= panel$month_id[i]
  ]
  
  eligible <- eligible[order(quarter_end_month_id)]
  
  if (nrow(eligible) > 0) {
    
    latest <- nrow(eligible)
    
    panel$gdp_available[i] <-
      eligible$gdp_monthly_equivalent[latest]
    
    panel$gdp_source_quarter[i] <-
      eligible$quarter[latest]
  }
}

# Load Candidate events and the release inventory.
candidate_conflict <- as.data.table(
  readRDS(
    file.path(
      config$paths$processed,
      "ucdp_candidate_exposure_events.rds"
    )
  )
)

candidate_sources <- as.data.table(
  readRDS(
    file.path(
      config$paths$processed,
      "ucdp_candidate_sources.rds"
    )
  )
)

# Target months requiring Candidate-based predictors.
forecast_months <- sort(unique(
  panel[
    sample %in% c("validation", "testing"),
    month_id
  ]
))

# Store one exposure table per target month.
conflict_results <- list()

for (i in 1:length(forecast_months)) {
  
  target_month <- forecast_months[i]
  reference_month <- target_month - 2
  
  # A missing source file must not be interpreted as zero conflict.
  if (!(reference_month %in% candidate_sources$source_month_id)) {
    stop("Candidate source missing for month ID: ", reference_month)
  }
  
  # Select releases available for this forecast.
  eligible <- candidate_conflict[
    available_forecast_month_id <= target_month
  ]
  
  # Retain the latest eligible version of each event.
  eligible <- eligible[order(source_month_id)]
  
  eligible <- eligible[
    , .SD[.N],
    by = .(focal_country, id)
  ]
  
  # Select the two-month-lagged event reference period.
  eligible <- eligible[
    event_month_id == reference_month
  ]
  
  # Aggregate the four alternative measures.
  monthly_exposure <- eligible[
    , .(
      conflict_500_lag2 = sum(weight_500),
      conflict_1000_lag2 = sum(weight_1000),
      conflict_2000_lag2 = sum(weight_2000),
      conflict_deaths_1000_lag2 = sum(deaths_weight_1000)
    ),
    by = focal_country
  ]
  
  monthly_exposure[, month_id := target_month]
  
  conflict_results[[i]] <- monthly_exposure
}

# Combine all target months.
candidate_predictors <- rbindlist(conflict_results)

setnames(candidate_predictors, "focal_country", "country")

# Merge into the forecasting panel.
panel <- merge(
  panel,
  candidate_predictors,
  by = c("country", "month_id"),
  all.x = TRUE
)

annual_conflict <- as.data.table(
  readRDS(
    file.path(
      config$paths$processed,
      "ucdp_annual_exposure_monthly.rds"
    )
  )
)

conflict_columns <- c(
  "conflict_500",
  "conflict_1000",
  "conflict_2000",
  "conflict_deaths_1000"
)

lagged_columns <- paste0(conflict_columns, "_lag2")
annual_columns <- paste0(conflict_columns, "_annual_lag2")

# An exposure observed in month M belongs to target month M + 2.
annual_conflict[
  , month_id :=
    as.integer(substr(month, 1, 4)) * 12 +
    as.integer(substr(month, 6, 7)) + 2
]

setnames(
  annual_conflict,
  conflict_columns,
  annual_columns
)

annual_conflict <- annual_conflict[
  , c("country", "month_id", annual_columns),
  with = FALSE
]

panel <- merge(
  panel,
  annual_conflict,
  by = c("country", "month_id"),
  all.x = TRUE
)

# Replace the training rows with their annual-based predictors.
# Validation and testing retain the Candidate values already calculated.
panel[
  sample == "training",
  (lagged_columns) := .SD,
  .SDcols = annual_columns
]

panel[, conflict_source := NA_character_]

panel[
  sample == "training" &
    !is.na(conflict_1000_lag2),
  conflict_source := "annual_GED_23.1"
]

panel[
  sample %in% c("validation", "testing") &
    !is.na(conflict_1000_lag2),
  conflict_source := "monthly_Candidate"
]

# Remove the temporary annual columns.
panel[, (annual_columns) := NULL]

panel <- panel[order(country, month)]

# Check coverage and provenance.
panel[
  , .(
    observations = .N,
    missing_conflict = sum(is.na(conflict_1000_lag2))
  ),
  by = .(sample, conflict_source)
]

analysis_columns <- c(
  "country",
  "month",
  "month_id",
  "sample",
  "retail_growth",
  "retail_growth_lag3",
  "inflation_lag2",
  "unemployment_lag3",
  "gdp_available",
  "gdp_source_quarter",
  lagged_columns,
  "conflict_source"
)

analysis_panel <- panel[
  , analysis_columns,
  with = FALSE
]

# Values required for the initial model comparisons.
model_variables <- c(
  "retail_growth",
  "retail_growth_lag3",
  "inflation_lag2",
  "unemployment_lag3",
  "gdp_available",
  lagged_columns
)

usable <- complete.cases(
  analysis_panel[, model_variables, with = FALSE]
)

# Preserve excluded rows so we can inspect the reason.
excluded_rows <- analysis_panel[!usable]

print(
  excluded_rows[
    , .(
      excluded = .N,
      first_month = min(month),
      last_month = max(month)
    ),
    by = .(country, sample)
  ]
)

# Unexpected evaluation-period missingness needs investigation.
if (any(excluded_rows$sample %in% c("validation", "testing"))) {
  stop(
    "Missing model inputs or outcomes in validation/testing. ",
    "Inspect excluded_rows before continuing."
  )
}

model_panel <- analysis_panel[usable]

saveRDS(
  analysis_panel,
  config$paths$analysis_panel
)

saveRDS(
  model_panel,
  config$paths$model_panel
)

saveRDS(
  excluded_rows,
  config$paths$excluded_model_rows
)