config <- list(
  
  paths = list(
    raw = "data/raw",
    processed = "data/processed",
    prepared_panel = "data/processed/prepared_panel.rds",
    analysis_panel = "data/processed/analysis_panel.rds",
    model_panel = "data/processed/model_panel.rds",
    excluded_model_rows = "data/processed/model_panel_excluded_rows.rds",
    development = "results/development",
    final = "results/final",
    frozen_config = "results/development/frozen_config.rds"
  ),
  
  sources = list(
    
    expected_count = 6L,
    
    expected_prefixes = c(
      "Retail trade volume of sales",
      "Headline inflation.xlsx",
      "Unemployment.xlsx",
      "(new)Gross domestic product (GDP)",
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
    forecast_horizon = 1L,
    target_definition =
      "100 * log(retail_index / previous_month_retail_index)",
    training_end = "2022-12",
    validation_end = "2023-12",
    test_end = "2025-12",
    predictor_specification = list(
      common_predictors = c(
        "retail_growth_lag3",
        "inflation_lag2",
        "unemployment_lag3",
        "gdp_available"
      ),
      conflict_alternatives = c(
        "conflict_500_lag2",
        "conflict_1000_lag2",
        "conflict_2000_lag2",
        "conflict_deaths_1000_lag2"
      ),
      provenance_columns = c(
        "gdp_source_quarter",
        "conflict_source"
      )
    ),
    predictor_availability_rules = list(
      forecast_origin = "End of the month preceding the target month",
      retail_lag_months = 3L,
      inflation_lag_months = 2L,
      unemployment_lag_months = 3L,
      gdp_rule =
        "Latest quarter eligible from quarter-end month plus four months",
      conflict_reference_lag_months = 2L,
      candidate_rule =
        "Eligible from source month plus two target months; retain latest eligible version per event",
      conflict_training_source = "Annual GED 23.1",
      conflict_evaluation_source = "Historical monthly Candidate releases",
      timing_status =
        "Conservative scheduling conventions; individual release dates not fully reconstructed"
    ),
    frequency_conversion_rules = NULL,
    missing_value_rules = NULL,
    conflict_definition = c(
      "conflict_500",
      "conflict_1000",
      "conflict_2000",
      "conflict_deaths_1000"
    ),
    model_specifications = list(
      
      selected_models = c(
        "zero_growth",
        "country_mean",
        "shared_slopes_reduced_macro_only",
        "forest_reduced_without_gdp",
        "forest_without_conflict",
        "forest_conflict_deaths_1000_lag2"
      ),
      
      macro_regression_predictors = c(
        "country",
        "inflation_lag2",
        "unemployment_lag3",
        "gdp_available"
      ),
      
      forest_settings = list(
        num_trees = 500L,
        mtry = 2L,
        max_depth = 5L,
        min_node_size = 40L,
        min_bucket = 20L,
        sample_fraction = 1,
        replace = TRUE
      )
    ),
    evaluation_protocol = list(
      
      primary_metric = "RMSE",
      secondary_metric = "MAE",
      
      validation_period = "2023",
      testing_period = "2024-2025",
      
      estimation = "Expanding window, refitted monthly",
      
      outcome_availability_lag_months = 3L,
      
      reporting = "Overall and separately by country",
      
      model_selection =
        "Finalists selected using 2023 validation; no selection using test scores",
      
      evaluation_type =
        "Retrospective chronological holdout with revised historical data and publication-delay conventions",
      
      early_test_limitation =
        "Complete 2023 validation outcomes were not all published before the earliest 2024 forecast dates",
      
      forest_seed_base = 20564L
    )
  )
)