# ─────────────────────────────────────────────────────────────────────────────
# 1. Load Libraries & Define Global Parameters.----
# ─────────────────────────────────────────────────────────────────────────────

library(tidyverse)
library(httr2)

# Global parameters ----
WORKING_DIR <- "[YOUR WD]"
DURATION <- 1000
START_DATE <- Sys.Date() - DURATION + 1
END_DATE   <- Sys.Date()

GEMINI_API_KEY <- "[YOUR API KEY]"
GEMINI_URL <- "https://generativelanguage.googleapis.com/v1beta/models/"
GEMINI_MODEL <- "gemini-2.0-flash"

FRED_API_KEY <- "[YOUR API KEY]"
FRED_URL <- "https://api.stlouisfed.org/fred/series/observations"
FREDLIST_PATH <- '[YOUR PATH]'

MIN_NUM_OBS <- 10
MAX_LAG_DAYS <- 3

# ─────────────────────────────────────────────────────────────────────────────
# 2. Prompt Templates & Generator Functions----
# ─────────────────────────────────────────────────────────────────────────────

PROMPT_CHOOSE_SURPRISED_DATA <- paste0(
  "Choose the single data series from the list below that has the most ",
  "unexpected latest value. Provide only the exact series_id as your ",
  "response—no extra text or explanations.\n"
)

generate_prompt_choose_surprise <- function(data_list) {
  data_text <- paste(capture.output(print(data_list, n = nrow(data_list))), collapse = "\n")
  paste0(PROMPT_CHOOSE_SURPRISED_DATA, data_text)
}

PROMPT_EXPLAIN_SURPRISE_TEMPLATE <- paste0(
  "Here is the historical data for %s. Please provide a concise single-paragraph analysis covering:\n",
  "1) the recent trend before the latest value,\n",
  "2) the extent of surprise in the latest value,\n",
  "3) potential reasons for this surprise, and\n",
  "4) possible implications of the latest value.\n"
)

generate_prompt_explain_surprise <- function(surprise_name, surprise_data, num_rows = 500) {
  data_text <- paste(capture.output(print(tail(surprise_data, num_rows))), collapse = "\n")
  prompt_body <- sprintf(PROMPT_EXPLAIN_SURPRISE_TEMPLATE, surprise_name)
  paste0(prompt_body, data_text)
}

PROMPT_ASK_CORR_VAR_TEMPLATE <- paste0(
  "Please tell me which one of the below variables is most likely to explain the change of %s.\n",
  "Only return to me the exact series_id. Don't include other messages.\n\n"
)

generate_prompt_ask_corr_var <- function(surprise_name, surprise_id, data_list) {
  # Filter out the chosen surprise ID
  filtered_data <- data_list %>%
    filter(series_id != surprise_id) %>%
    select(`Series Name`, series_id)
  
  variable_list <- paste(
    filtered_data$`Series Name`, 
    "(", 
    filtered_data$series_id, 
    ")", 
    collapse = ", "
  )
  
  prompt_header <- sprintf(PROMPT_ASK_CORR_VAR_TEMPLATE, surprise_name)
  paste0(prompt_header, variable_list)
}

PROMPT_EXPLAIN_CORR_TEMPLATE <- paste0(
  "Please provide a concise single-paragraph analysis covering the following points:\n",
  "1) State that we are investigating the reasons behind the change in %s.\n",
  "2) Explain how a change in %s could potentially influence the change in %s.\n",
  "3) Discuss the benefits of exploring this potential causal relationship.\n",
  "4) Conclude by stating that the plot below will illustrate the relationship between the two variables.\n"
)

generate_prompt_explain_corr <- function(surprise_name, corr_name) {
  sprintf(PROMPT_EXPLAIN_CORR_TEMPLATE, surprise_name, corr_name, surprise_name)
}

PROMPT_DESCRIBE_PLOT_TEMPLATE <- paste0(
  "Assume that a line plot has already been created to visualize the time trends ",
  "of %s (the affected variable) and %s (the influencing variable). The raw data ",
  "used for the plot are shown below.\n\n",
  "Please provide a concise, single-paragraph analysis that:\n",
  "1) States that the plot above illustrates the historical trends of the two variables over time.\n",
  "2) Describes the individual trends of %s and %s.\n",
  "3) Infers a potential causal relationship between the two variables based on observed historical patterns.\n",
  "4) Explains the latest unexpected trend in %s based on this inferred relationship.\n",
  "5) Concludes with a brief summary statement from an investment perspective.\n\n"
)

generate_prompt_describe_plot <- function(surprise_name, corr_name, surprise_data, corr_data, num_rows = 500) {
  surprise_text <- paste(capture.output(print(tail(surprise_data, num_rows))), collapse = "\n")
  corr_text     <- paste(capture.output(print(tail(corr_data, num_rows))), collapse = "\n")
  
  prompt_body <- sprintf(
    PROMPT_DESCRIBE_PLOT_TEMPLATE, 
    surprise_name, corr_name, 
    surprise_name, corr_name, 
    surprise_name
  )
  
  paste0(
    prompt_body,
    "\n## ", surprise_name, "\n", surprise_text,
    "\n\n## ", corr_name, "\n", corr_text
  )
}

PROMPT_ASK_TITLE_TEMPLATE <- paste0(
  "Based on the following full text of the report, generate an attention-grabbing title for this report.\n",
  "Only provide the title—no additional information.\n\n%s\n\n%s\n\n%s\n\n"
)

generate_prompt_ask_title <- function(surprise_explanation, corr_explanation, plot_description) {
  sprintf(
    PROMPT_ASK_TITLE_TEMPLATE, 
    surprise_explanation, corr_explanation, plot_description
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. Functions for Gemini API Calls----
# ─────────────────────────────────────────────────────────────────────────────

get_response_gemini <- function(
  prompt,
  gemini_api_key = GEMINI_API_KEY, 
  gemini_url = GEMINI_URL,
  gemini_model = GEMINI_MODEL,
  gemini_action = "generateContent"
) {
  payload <- list(
    contents = list(
      list(parts = list(
        list(text = prompt)
      ))
    )
  )
  
  response <- request(
    paste0(gemini_url, gemini_model, ":", gemini_action)
  ) %>%
    req_url_query(key = gemini_api_key) %>%
    req_body_json(payload) %>%
    req_perform() %>%
    resp_body_json()
  
  response$candidates[[1]]$content$parts[[1]]$text
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. Functions to Fetch & Process FRED Data----
# ─────────────────────────────────────────────────────────────────────────────

fetch_fred_data <- function(
  series_id, 
  start_date = START_DATE, 
  end_date = END_DATE, 
  fred_api_key = FRED_API_KEY,
  url = FRED_URL
) {
  response <- request(url) %>%
    req_url_query(
      series_id = series_id,
      api_key = fred_api_key,
      observation_start = start_date,
      observation_end = end_date,
      file_type = "json"
    ) %>%
    req_perform()
  
  data_json <- resp_body_json(response)
  
  df <- do.call(rbind, lapply(data_json$observations, as.data.frame))
  
  if (!is.null(df) && nrow(df) > 0) {
    df <- df %>%
      select(date, value) %>%
      filter(!str_detect(value, '^\\.$')) %>%
      filter(!str_detect(value, 'NA')) %>%
      mutate(
        date  = as.Date(date, format = "%Y-%m-%d"),
        value = as.numeric(value)
      )
  } else {
    df <- data.frame(date = as.Date(character()), value = numeric())
  }
  
  df
}

check_num_obs <- function(df) {
  nrow(df)
}

check_lag_days <- function(df) {
  latest_date <- max(df$date, na.rm = TRUE)
  as.numeric(Sys.Date() - latest_date)
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. Functions to Compute Surprise----
# ─────────────────────────────────────────────────────────────────────────────

compute_ar1_mean_reverting_surprise <- function(training_set, verifying_set, actual_set) {
  mean_value <- mean(training_set$value)
  detrended_series <- training_set$value - mean_value
  
  fit <- tryCatch(
    arima(detrended_series, order = c(1, 0, 0), include.mean = FALSE),
    error = function(e) NULL
  )
  
  if (!is.null(fit)) {
    phi   <- as.numeric(fit$coef["ar1"])
    sigma <- sqrt(fit$sigma2)
    
    forecast_value <- mean_value + phi * (verifying_set$value - mean_value)
    abs(actual_set$value - forecast_value) / sigma
  } else {
    NA
  }
}

compute_surprise_measures <- function(data) {
  data <- data %>% arrange(date)
  
  # Split data into training, verifying, and actual sets
  training_set  <- data %>% slice(1:(nrow(data) - 2))
  verifying_set <- data %>% slice(nrow(data) - 1)
  actual_set    <- data %>% slice(nrow(data))
  
  tibble(
    Model    = "ar1_mean_reverting",
    Surprise = compute_ar1_mean_reverting_surprise(training_set, verifying_set, actual_set)
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. Load FRED Data & Determine Surprised Variable----
# ─────────────────────────────────────────────────────────────────────────────

# fredData <- readxl::read_excel(FREDLIST_PATH) %>%
#   rename(series_id = `FRED ID`) %>%
#   mutate(ts_data = list(fetch_fred_data(series_id)), .by=series_id)
# fredData %>% saveRDS(paste0(WORKING_DIR, 'fredData.rds'))

# Load pre-fetched data from RDS
fredData <- readRDS(file.path(WORKING_DIR, 'fredData.rds'))

surprise_data_list <- fredData %>%
  mutate(num_obs = check_num_obs(ts_data[[1]]), .by = series_id) %>%
  filter(num_obs > MIN_NUM_OBS) %>%
  mutate(lag_days = check_lag_days(ts_data[[1]]), .by = series_id) %>%
  filter(lag_days <= MAX_LAG_DAYS) %>%
  mutate(surprise = compute_surprise_measures(ts_data[[1]]), .by = series_id) %>%
  unnest(cols = c(surprise)) %>%
  group_by(Genre1, Genre2) %>%
  arrange(desc(Surprise)) %>%
  filter(row_number() == 1) %>%
  ungroup() %>%
  select(series_id, `Series Name`, Surprise)

# Generate prompt for the model
prompt_choose_surprise <- generate_prompt_choose_surprise(surprise_data_list)
AI_chosen_surprise_id <- get_response_gemini(prompt_choose_surprise) %>%
  gsub("\n", "", .)

AI_chosen_surprise_name <- fredData %>%
  filter(series_id == AI_chosen_surprise_id) %>%
  pull(`Series Name`) %>%
  unique()

# ─────────────────────────────────────────────────────────────────────────────
# 7. Explain the Surprised Variable----
# ─────────────────────────────────────────────────────────────────────────────

surprise_data <- fredData %>%
  filter(series_id == AI_chosen_surprise_id) %>%
  pull(ts_data) %>%
  .[[1]]

prompt_explain_surprise <- generate_prompt_explain_surprise(AI_chosen_surprise_name, surprise_data)
AI_surprise_explanation <- get_response_gemini(prompt_explain_surprise)

# ─────────────────────────────────────────────────────────────────────────────
# 8. Find & Explain Correlation Variable----
# ─────────────────────────────────────────────────────────────────────────────

prompt_ask_corr_var <- generate_prompt_ask_corr_var(
  AI_chosen_surprise_name, 
  AI_chosen_surprise_id, 
  surprise_data_list
)

AI_chosen_corr_id <- get_response_gemini(prompt_ask_corr_var) %>%
  gsub("\n", "", .)

AI_chosen_corr_name <- fredData %>%
  filter(series_id == AI_chosen_corr_id) %>%
  pull(`Series Name`) %>%
  unique()

prompt_explain_corr <- generate_prompt_explain_corr(AI_chosen_surprise_name, AI_chosen_corr_name)
AI_corr_explanation <- get_response_gemini(prompt_explain_corr)

# ─────────────────────────────────────────────────────────────────────────────
# 9. Describe & Infer from the Plot----
# ─────────────────────────────────────────────────────────────────────────────

corr_data <- fredData %>%
  filter(series_id == AI_chosen_corr_id) %>%
  pull(ts_data) %>%
  .[[1]]

prompt_describe_plot <- generate_prompt_describe_plot(
  AI_chosen_surprise_name, 
  AI_chosen_corr_name, 
  surprise_data, 
  corr_data
)

AI_plot_description <- get_response_gemini(prompt_describe_plot)

# ─────────────────────────────────────────────────────────────────────────────
# 10. Generate Report Title----
# ─────────────────────────────────────────────────────────────────────────────

prompt_ask_title <- generate_prompt_ask_title(
  AI_surprise_explanation, 
  AI_corr_explanation, 
  AI_plot_description
)

AI_suggested_title <- get_response_gemini(prompt_ask_title) %>%
  gsub("\n", "", .)

# ─────────────────────────────────────────────────────────────────────────────
# 11. Save Data & Render Report----
# ─────────────────────────────────────────────────────────────────────────────

plot_data <- list(
  surprise = surprise_data,
  corr     = corr_data
)
saveRDS(plot_data, file.path(WORKING_DIR, 'plot_data.rds'))

narrative_data <- list(
  surprise_name = AI_chosen_surprise_name,
  corr_name     = AI_chosen_corr_name,
  title         = AI_suggested_title,
  paragraph1    = AI_surprise_explanation,
  paragraph2    = AI_corr_explanation,
  paragraph3    = AI_plot_description
)
saveRDS(narrative_data, file.path(WORKING_DIR, 'narrative_data.rds'))

quarto::quarto_render(
  input = file.path(WORKING_DIR, "report.qmd")
)


  


