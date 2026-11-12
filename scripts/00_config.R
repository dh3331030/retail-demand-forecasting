# Shared project settings
#
# Stores the folder paths, source-file requirements, and approved analytical
# settings used throughout the project.
# Load these settings before running scripts that use the config object,
# by running the following command through the console:
#
# source("scripts/00_config.R")
#
# Access individual settings using $, for example: config$paths$raw.
# Both master scripts will load this file to use the same settings.
#
# This script only defines settings. It does not read or validate datasets,
# create folders, fit models, or produce results.
# Change shared settings here rather than repeating them in other scripts.

config <- list(
  
  paths = list(
    raw = "data/raw",
    processed = "data/processed",
    prepared_panel = "data/processed/prepared_panel.rds",
    development = "results/development",
    final = "results/final",
    frozen_config = "results/development/frozen_config.rds"
  ),
  
  sources = list(
    
    expected_count = 7L,
    
    expected_prefixes = c(
      "Retail trade volume of sales",
      "Headline inflation.xlsx",
      "Unemployment.xlsx",
      "(new)Gross domestic product (GDP)",
      "UCDP Georeferenced Event Dataset",
      "Oxford Covid-19 Government Response Tracker",
      "Household final consumption expenditure.xlsx"
    ),
    
    ucdp_sheet = "GEDEvent_v26_1",
    eurostat_sheet = "Sheet 1",
    gdp_sheet = "Sheet 2",
    
    covid_member =
      "covid-policy-dataset-main/data/OxCGRT_compact_national_v1.csv",
    
    headline_inflation_sheet = "Sheet 16",
    unemployment_sheet = "Sheet 1"
  ),
    
  # Analytical settings: NULL means not yet agreed
  
  analysis = list(
    countries = c(
      "Germany",
      "France",
      "Italy",
      "Poland",
      "Portugal"
    ),
    sample_start = "2015-01",
    sample_end = "2025-12",
    forecast_horizon = NULL,
    target_definition = NULL,
    training_end = "2022-12",
    validation_end = "2023-12",
    test_end = "2025-12",
    predictor_specification = NULL,
    predictor_availability_rules = NULL,
    frequency_conversion_rules = NULL,
    missing_value_rules = NULL,
    conflict_definition = c(
      "conflict_500",
      "conflict_1000",
      "conflict_2000",
      "conflict_deaths_1000"
    ),
    model_specifications = NULL,
    evaluation_protocol = NULL
  )
)