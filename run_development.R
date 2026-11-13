# Entry point for data preparation, training, and validation.
# Open Retail_forecasting.Rproj before running this script.

local({
  
  source("00_setup.R", local = TRUE)
  source("scripts/00_config.R", local = TRUE)
  source("scripts/00_preflight.R", local = TRUE)
  
  # Prepare and save the merged panel.
  
  source("scripts/01_prepare_helpers.R", local = TRUE)
  source("scripts/01_prepare_data.R", local = TRUE)
  source("scripts/02_construct_model_data.R", local = TRUE)
  source("scripts/03_train_validate.R", local = TRUE)
  source("scripts/03a_compare_reduced_predictors.R", local = TRUE)
  
  message(
    "Data preparation and model-data construction complete."
  )
})