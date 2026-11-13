# Entry point for final testing and reporting.
# Uses the configuration frozen after model development.
# Refits frozen specifications monthly; does not select models or tune parameters.

local({
  
  source("00_setup.R", local = TRUE)
  source("scripts/00_config.R", local = TRUE)
  
  # Check that development has produced a frozen configuration.
  
  if (!file.exists(config$paths$frozen_config)) {
    stop(
      "Final evaluation cannot run: no frozen development configuration exists.",
      call. = FALSE
    )
  }
  
  frozen_config <- readRDS(config$paths$frozen_config)
  
  # Prevent evaluation under settings different from the frozen settings.
  
  if (!identical(config, frozen_config)) {
    stop(
      "Current settings differ from the frozen development configuration.",
      call. = FALSE
    )
  }
  
  source("scripts/04_final_evaluation.R", local = TRUE)
})
