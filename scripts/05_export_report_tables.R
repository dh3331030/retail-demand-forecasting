# Tables for the working paper. This file DEFINES reporting functions.
# Source it, then call the functions shown in docs/RUN_REPORT_TABLES.txt.
# Uses base R only. Does not fit models or change model-selection settings.

report_model_labels <- c(
  zero_growth = "Zero growth",
  latest_available_growth = "Latest available growth",
  country_mean = "Country mean",
  shared_slopes_without_conflict = "Shared slopes without conflict",
  country_specific_without_conflict = "Country-specific slopes without conflict",
  tree_without_conflict = "Decision tree without conflict",
  bagging_without_conflict = "Bagging without conflict",
  forest_without_conflict = "Random forest without conflict",
  shared_slopes_conflict_500_lag2 = "Shared slopes with events, 500 km",
  shared_slopes_conflict_1000_lag2 = "Shared slopes with events, 1000 km",
  shared_slopes_conflict_2000_lag2 = "Shared slopes with events, 2000 km",
  shared_slopes_conflict_deaths_1000_lag2 = "Shared slopes with weighted deaths, 1000 km",
  forest_conflict_500_lag2 = "Random forest with events, 500 km",
  forest_conflict_1000_lag2 = "Random forest with events, 1000 km",
  forest_conflict_2000_lag2 = "Random forest with events, 2000 km",
  forest_conflict_deaths_1000_lag2 = "Random forest with weighted deaths, 1000 km",
  shared_slopes_reduced_retail_only = "Shared slopes, retail only",
  shared_slopes_reduced_without_inflation = "Shared slopes without inflation",
  shared_slopes_reduced_without_unemployment = "Shared slopes without unemployment",
  shared_slopes_reduced_without_gdp = "Shared slopes without GDP",
  shared_slopes_reduced_macro_only = "Shared slopes, macro only",
  forest_reduced_retail_only = "Random forest, retail only",
  forest_reduced_without_inflation = "Random forest without inflation",
  forest_reduced_without_unemployment = "Random forest without unemployment",
  forest_reduced_without_gdp = "Random forest without GDP",
  forest_reduced_macro_only = "Random forest, macro only"
)

# Escape values before inserting them into HTML.
report_escape <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- ""
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x
}

# Return HTML table lines. Formatting is applied to a copy; CSVs stay numeric.
report_table_html <- function(x, title, note = "") {
  x <- as.data.frame(x)
  if ("model" %in% names(x)) {
    x$model <- as.character(x$model)
    labels <- unname(report_model_labels[x$model])
    labels[is.na(labels)] <- x$model[is.na(labels)]
    x$model <- labels
  }
  for (column in names(x)) {
    if (is.factor(x[[column]])) x[[column]] <- as.character(x[[column]])
    if (is.numeric(x[[column]])) {
      if (column == "observations") {
        x[[column]] <- sprintf("%.0f", x[[column]])
      } else if (grepl("pct", column, fixed = TRUE)) {
        x[[column]] <- sprintf("%.2f", x[[column]])
      } else if (grepl("MAE|RMSE|MSE", column)) {
        x[[column]] <- sprintf("%.4f", x[[column]])
      }
    } else if (is.logical(x[[column]])) {
      x[[column]] <- ifelse(is.na(x[[column]]), "", ifelse(x[[column]], "Yes", "No"))
    }
  }
  headings <- gsub("_", " ", names(x), fixed = TRUE)
  headings[names(x) == "RMSE_improvement_vs_zero_pct"] <- "RMSE improvement vs zero (%)"
  headings[names(x) == "RMSE_improvement_pct"] <- "RMSE improvement vs parent (%)"
  headings[names(x) == "primary"] <- "Selected primary model"
  html <- c(paste0("<h2>", report_escape(title), "</h2>"),
            "<table><thead><tr>",
            paste0("<th>", report_escape(headings), "</th>", collapse = ""),
            "</tr></thead><tbody>")
  for (i in seq_len(nrow(x))) {
    selected <- "primary" %in% names(x) && identical(x$primary[i], "Yes")
    row_tag <- if (selected) '<tr class="primary">' else "<tr>"
    html <- c(html, row_tag,
              paste0("<td>", report_escape(unlist(x[i, ], use.names = FALSE)),
                     "</td>", collapse = ""), "</tr>")
  }
  c(html, "</tbody></table>", paste0('<p class="note">', report_escape(note), "</p>"))
}

report_write_html <- function(body, file, title) {
  writeLines(c(
    '<!doctype html><html lang="en"><head><meta charset="utf-8">',
    paste0("<title>", report_escape(title), "</title>"),
    "<style>",
    "body{font-family:Arial,sans-serif;margin:32px;color:#111;line-height:1.4}",
    "h1{font-size:22px}h2{font-size:17px;margin-top:28px}",
    "table{border-collapse:collapse;width:100%;font-size:12px;margin:12px 0}",
    "th,td{border:1px solid #ccc;padding:8px;text-align:right;overflow-wrap:anywhere}",
    "th:first-child,td:first-child{text-align:left}thead{display:table-header-group}",
    "th{background:#e8edf1}.primary{font-weight:bold;background:#eef4ed}",
    ".note{font-size:11px}tr{break-inside:avoid}",
    "@media print{body{margin:0}h2{break-after:avoid}table{font-size:9px}}",
    "</style></head><body>", paste0("<h1>", report_escape(title), "</h1>"),
    body, "</body></html>"
  ), file, useBytes = TRUE)
}

# 1. Main-text table plus all 26 validation models for the appendix.
write_validation_table <- function(validation_scores,
                                   out_dir = "results/report_tables",
                                   primary_model = "zero_growth") {
  scores <- as.data.frame(validation_scores)
  needed <- c("model", "observations", "MAE", "RMSE")
  if (!all(needed %in% names(scores))) {
    stop("validation_scores must contain model, observations, MAE and RMSE.")
  }
  scores <- scores[, needed]
  scores$model <- as.character(scores$model)
  if (anyDuplicated(scores$model) || any(!is.finite(scores$RMSE)) ||
      any(!is.finite(scores$MAE))) stop("Expected one finite score row per model.")
  if (!primary_model %in% scores$model) stop("Selected primary model is missing.")
  baseline <- scores$RMSE[scores$model == "zero_growth"]
  if (length(baseline) != 1L || baseline <= 0) stop("A positive zero-growth RMSE is required.")
  scores$RMSE_improvement_vs_zero_pct <- 100 * (baseline - scores$RMSE) / baseline
  scores$primary <- scores$model == primary_model
  scores <- scores[order(scores$RMSE, scores$model), ]
  rownames(scores) <- NULL

  # Covers every model discussed in the validation-performance paragraph:
  # initial seven, country mean, two selected reductions, selected conflict forest.
  main_models <- c(
    "zero_growth", "latest_available_growth", "country_mean",
    "shared_slopes_without_conflict", "country_specific_without_conflict",
    "tree_without_conflict", "bagging_without_conflict", "forest_without_conflict",
    "shared_slopes_reduced_macro_only", "forest_reduced_without_gdp",
    "forest_conflict_deaths_1000_lag2"
  )
  if (!all(main_models %in% scores$model)) {
    stop("Run 03_train_validate.R and 03a_compare_reduced_predictors.R first. Missing: ",
         paste(setdiff(main_models, scores$model), collapse = ", "))
  }
  main <- scores[scores$model %in% main_models, ]
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  write.csv(main, file.path(out_dir, "table_validation_main.csv"), row.names = FALSE)
  write.csv(scores, file.path(out_dir, "validation_all_models.csv"), row.names = FALSE)
  note <- paste(
    "Validation targets: January-December 2023; five countries; 60 observations per model.",
    "MAE and RMSE are in log percentage points. Lower errors are better.",
    "Positive RMSE improvement means lower error than zero growth.",
    "The primary model was selected during validation; display rounding does not determine ranks."
  )
  report_write_html(report_table_html(main, "Validation performance and selected primary model", note),
                    file.path(out_dir, "table_validation_main.html"), "Validation results")
  report_write_html(report_table_html(scores, "All validation specifications", note),
                    file.path(out_dir, "validation_all_models.html"), "Complete validation results")

  # Print a readable copy in the R console.
  display <- main
  display$model <- unname(report_model_labels[display$model])
  display$MAE <- round(display$MAE, 4)
  display$RMSE <- round(display$RMSE, 4)
  display$RMSE_improvement_vs_zero_pct <- round(display$RMSE_improvement_vs_zero_pct, 2)
  print(display, row.names = FALSE)
  message("Validation tables saved in: ", out_dir)
  invisible(main)
}

# 2. Combine ALL saved accuracy/comparison CSVs into an appendix.
# This avoids guessing the final script's in-memory object names.
# extra_tables accepts named data frames for results that were printed but not saved.
write_results_appendix <- function(
    result_dirs = c("results/development", "results/final"),
    extra_tables = list(), out_dir = "results/report_tables") {
  tables <- list()
  sources <- character()
  files <- unique(unlist(lapply(result_dirs, function(folder) {
    list.files(folder, pattern = "\\.csv$", recursive = TRUE, full.names = TRUE)
  })))
  for (file in files) {
    x <- read.csv(file, check.names = FALSE, stringsAsFactors = FALSE)
    # Predictions are kept separately; this appendix contains summary results.
    if ("model" %in% names(x) && any(c("MAE", "RMSE") %in% names(x))) {
      name <- paste0(basename(dirname(file)), "__", tools::file_path_sans_ext(basename(file)))
      name <- make.unique(c(names(tables), name))[length(tables) + 1L]
      tables[[name]] <- x
      sources[name] <- file
    }
  }
  if (length(extra_tables)) {
    if (is.null(names(extra_tables)) || any(!nzchar(names(extra_tables)))) {
      stop("Give every extra table a name, for example validation_by_country.")
    }
    for (name in names(extra_tables)) {
      x <- as.data.frame(extra_tables[[name]])
      if (!nrow(x)) stop("Empty extra table: ", name)
      new_name <- make.unique(c(names(tables), name))[length(tables) + 1L]
      tables[[new_name]] <- x
      sources[new_name] <- "Explicitly supplied R result object"
    }
  }
  if (!length(tables)) stop("No accuracy CSVs found. Run the model scripts or supply extra_tables.")
  appendix_dir <- file.path(out_dir, "appendix")
  dir.create(appendix_dir, recursive = TRUE, showWarnings = FALSE)
  body <- c("<p>All supplied model accuracy and comparison tables. Values are rounded only for display.</p>",
            "<p>Zero growth remains the primary model selected using validation. Test rankings do not change that choice.</p>")
  for (i in seq_along(tables)) {
    x <- tables[[i]]
    # Sort within country or year when those grouping fields are present.
    if ("RMSE" %in% names(x)) {
      if ("country" %in% names(x)) {
        x <- x[order(x$country, x$RMSE), ]
      } else if ("year" %in% names(x)) {
        x <- x[order(x$year, x$RMSE), ]
      } else x <- x[order(x$RMSE), ]
    }
    safe_name <- gsub("[^A-Za-z0-9_-]", "_", names(tables)[i])
    write.csv(x, file.path(appendix_dir, paste0(safe_name, ".csv")), row.names = FALSE)
    # Preserve model identifiers in the appendix as well as readable labels.
    if ("model" %in% names(x)) x$model_id <- as.character(x$model)
    title <- paste0("Appendix table ", i, "  ", gsub("_", " ", names(tables)[i], fixed = TRUE))
    note <- paste("Source:", sources[i],
                  "MAE/RMSE are in target units. Percentage improvements retain the baseline defined by the source table.")
    body <- c(body, report_table_html(x, title, note))
  }
  report_write_html(body, file.path(out_dir, "appendix_all_results.html"), "Appendix model results")
  index <- data.frame(table = names(tables), source = unname(sources))
  write.csv(index, file.path(out_dir, "appendix_source_index.csv"), row.names = FALSE)
  print(index, row.names = FALSE)
  message("Appendix saved in: ", file.path(out_dir, "appendix_all_results.html"))
  invisible(index)
}

# 3. Generate the EXACT software references for the R installation used.
# This does not download packages or guess their versions.
write_software_references <- function(out_dir = "results/report_tables") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  references <- capture.output(utils::citation())
  bib <- capture.output(print(utils::toBibtex(utils::citation())))
  packages <- c("data.table", "readxl", "rpart", "ranger")
  for (package in packages) {
    if (requireNamespace(package, quietly = TRUE)) {
      references <- c(references, "", paste("PACKAGE", package),
                      capture.output(print(utils::citation(package))))
      bib <- c(bib, "", capture.output(print(utils::toBibtex(utils::citation(package)))))
    }
  }
  writeLines(references, file.path(out_dir, "software_references.txt"))
  writeLines(bib, file.path(out_dir, "software_references.bib"))
  writeLines(capture.output(sessionInfo()), file.path(out_dir, "sessionInfo.txt"))
  message("Software citations and session information saved in: ", out_dir)
}
