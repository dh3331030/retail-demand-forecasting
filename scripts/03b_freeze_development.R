#this script records a model choice from validation before final testing.
#also, it checks for an existing freeze to avoid silently overwriting it.

#load the current config whose finalist definitions will be locked for evaluation.
source("scripts/00_config.R")
library(data.table)

#extract the six selected finalist model names from the configuration.
selected_models <-
  config$analysis$model_specifications$selected_models

#STOP1 finalist list needs exactly six entries.
if (length(selected_models) != 6) {
  stop("Length of the 'selected_models' is not 6")
}

#read the saved validation accuracy scores from the result development folder.
validation_scores <- fread(
  file.path(
    config$paths$development,
    "validation_scores.csv"
  )
)

#STOP2 verify that all selected finalist models are present in the saved validation results.
#     and abort if a proposed finalist lacks a corresponding validation score.
if (!all(selected_models %in% validation_scores$model)) {
  stop("Some finalists are missing from the saved validation results.")
}

#STOP3 to prevent accidentally replacing an existing freeze.
# this stops overwriting a previously frozen development configuration.
if (file.exists(config$paths$frozen_config)) {
  stop("A frozen configuration already exists. No files were changed.")
}

#keep only the selected finalists' validation rows and sort by increasing RMSE.
frozen_scores <- validation_scores[
  model %in% selected_models
][order(RMSE)]

#print the finalists' validation performance before freezing the selection.
print(frozen_scores)

#saves the supporting results first, then the configuration.
#and exports the shortlisted validation scores as supporting evidence.
fwrite(
  frozen_scores,
  file.path(
    config$paths$development,
    "frozen_finalists_validation_scores.csv"
  )
)

#serializing the complete current configuration as the frozen RDS used by final testing.
# .rds file format is used to save and load a single R object
saveRDS(
  config,
  config$paths$frozen_config
)

message("Development settings frozen. No test evaluation was performed.")