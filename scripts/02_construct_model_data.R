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

# Identify duplicate country-month observations.
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

# Retail growth one month earlier.
panel[
  , retail_growth_lag1 := c(NA, retail_growth[-.N]),
  by = country
]

# Retail growth two months earlier.
panel[
  , retail_growth_lag2 := c(NA, retail_growth_lag1[-.N]),
  by = country
]

# Inspect the alignment using training observations.
panel[
  country == "France" &
    month >= "2015-01" & month <= "2015-06",
  .(month, retail_growth, retail_growth_lag1, retail_growth_lag2)
]


