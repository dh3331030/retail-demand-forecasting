source("scripts/00_config.R")
library(data.table)

selected_models <-
  config$analysis$model_specifications$selected_models

if (length(selected_models) != 6) {
  stop("Expected the six agreed finalists.")
}

validation_scores <- fread(
  file.path(
    config$paths$development,
    "validation_scores.csv"
  )
)

if (!all(selected_models %in% validation_scores$model)) {
  stop("Some finalists are missing from the saved validation results.")
}

# Prevent accidentally replacing an existing freeze.
if (file.exists(config$paths$frozen_config)) {
  stop("A frozen configuration already exists. No files were changed.")
}

frozen_scores <- validation_scores[
  model %in% selected_models
][order(RMSE)]

print(frozen_scores)

# Save the supporting results first, then the configuration.
fwrite(
  frozen_scores,
  file.path(
    config$paths$development,
    "frozen_finalists_validation_scores.csv"
  )
)

saveRDS(
  config,
  config$paths$frozen_config
)

message("Development settings frozen. No test evaluation was performed.")