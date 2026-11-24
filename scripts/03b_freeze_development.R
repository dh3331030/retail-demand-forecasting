# READING GUIDE: This stage records a model choice from validation before final testing.
# It checks for an existing freeze to avoid silently overwriting it.

# Load the current configuration whose finalist definitions will be locked for evaluation.
source("scripts/00_config.R")
# Attach `data.table` for reading and filtering the validation results.
library(data.table)

# Extract the six selected finalist model names from the configuration.
selected_models <-
  config$analysis$model_specifications$selected_models

# Check that the selected finalist list contains exactly six entries.
if (length(selected_models) != 6) {
  # Stop if the required number of finalists is not met.
  stop("Expected the six agreed finalists.")
}

# Read the saved validation accuracy scores from the development folder.
validation_scores <- fread(
  file.path(
    config$paths$development,
    "validation_scores.csv"
  )
)

# Verify that all selected finalist models are present in the saved validation results.
if (!all(selected_models %in% validation_scores$model)) {
  # Stop when a proposed finalist lacks a corresponding validation score.
  stop("Some finalists are missing from the saved validation results.")
}

# Prevent accidentally replacing an existing freeze.
# Guard against overwriting a previously frozen development configuration.
if (file.exists(config$paths$frozen_config)) {
  # Stop immediately if the frozen file already exists.
  stop("A frozen configuration already exists. No files were changed.")
}

# Keep only the selected finalists' validation rows and sort by increasing RMSE.
frozen_scores <- validation_scores[
  model %in% selected_models
][order(RMSE)]

# Print the finalists' validation performance before freezing the selection.
print(frozen_scores)

# Save the supporting results first, then the configuration.
# Export the shortlisted validation scores as supporting evidence.
fwrite(
  frozen_scores,
  file.path(
    config$paths$development,
    "frozen_finalists_validation_scores.csv"
  )
)

# Serialize the complete current configuration as the frozen RDS used by final testing.
saveRDS(
  config,
  config$paths$frozen_config
)

# Confirm that the freeze finished without using the test holdout.
message("Development settings frozen. No test evaluation was performed.")