# Entry point for data preparation, training, and validation.
# Open Retail_forecasting.Rproj before running this script.

local({
  
  source("00_setup.R", local = TRUE)
  source("scripts/00_config.R", local = TRUE)
  source("scripts/00_preflight.R", local = TRUE)
  
  # Prepare and save the merged panel.
  
  source("scripts/01_prepare_data.R", local = TRUE)
  
  message(
    "Data preparation complete. Saved data/processed/prepared_panel.rds."
  )
})