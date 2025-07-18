#' Fetch Game Market Summary Data
#'
#' Retrieves aggregated download and revenue estimates by game categories, 
#' countries, and date ranges. This provides a market overview of game 
#' performance across different segments.
#'
#' @param categories Character string or numeric vector. Game category IDs to 
#'   analyze. Defaults to 7001 (a popular game category). Use `st_categories()` 
#'   to find valid category IDs.
#' @param countries Character vector or comma-separated string. Country codes 
#'   (e.g., `"US"`, `c("US", "GB")`, `"WW"`) to analyze. Defaults to "WW" 
#'   (worldwide).
#' @param os Character string. Operating System. Must be one of "ios", "android", 
#'   or "unified". Defaults to "unified".
#' @param date_granularity Character string. Time granularity for aggregation. 
#'   Must be one of "daily", "weekly", "monthly", or "quarterly". 
#'   Defaults to "daily".
#' @param start_date Character string or Date object. Start date for the query 
#'   in "YYYY-MM-DD" format. Defaults to 30 days ago.
#' @param end_date Character string or Date object. End date for the query 
#'   in "YYYY-MM-DD" format, inclusive. Defaults to yesterday.
#' @param auth_token Optional. Character string. Your Sensor Tower API token.
#' @param base_url Optional. Character string. The base URL for the API.
#' @param enrich_response Optional. Logical. If `TRUE` (default), enriches
#'   the response with readable column names and processes the data.
#'
#' @return A [tibble][tibble::tibble] with game market summary data including:
#'   - **Category information**: Game category details
#'   - **Geographic data**: Country-level breakdowns
#'   - **Downloads**: Unified iOS (iPhone + iPad combined) and Android download estimates
#'   - **Revenue**: Unified iOS (iPhone + iPad combined) and Android revenue estimates
#'   - **Time series**: Data broken down by specified granularity
#'   
#'   **Automatic Data Combination**: For iOS and unified platforms, iPhone and iPad
#'   data are automatically combined into single "iOS Downloads" and "iOS Revenue" 
#'   columns for simplified analysis.
#'
#' @section API Endpoint Used:
#'   - **Game Summary**: `GET /v1/\{os\}/games_breakdown`
#'
#' @section Field Mappings and Processing:
#'   The API returns abbreviated field names which are automatically mapped to 
#'   descriptive names and processed:
#'   - **iOS**: `iu` + `au` → iOS Downloads (combined), `ir` + `ar` → iOS Revenue (combined)
#'   - **Android**: `u` → Android Downloads, `r` → Android Revenue
#'   - **Common**: `cc` → Country Code, `d` → Date, `aid` → App ID
#'   
#'   iPhone and iPad data are automatically combined for simplified analysis.
#'
#' @examples
#' \dontrun{
#' # Basic game market summary (last 30 days, worldwide)
#' game_summary <- st_game_summary()
#'
#' # Specific categories and countries
#' rpg_summary <- st_game_summary(
#'   categories = c(7001, 7002),
#'   countries = c("US", "GB", "DE"),
#'   date_granularity = "weekly"
#' )
#'
#' # Monthly summary for iOS games in the US
#' ios_monthly <- st_game_summary(
#'   os = "ios",
#'   countries = "US", 
#'   date_granularity = "monthly",
#'   start_date = "2024-01-01",
#'   end_date = "2024-06-30"
#' )
#' }
#'
#' @seealso [st_categories()], [st_top_charts()], [st_metrics()]
#' @export
st_game_summary <- function(categories = 7001,
                            countries = "WW",
                            os = "unified",
                            date_granularity = "daily",
                            start_date = Sys.Date() - 30,
                            end_date = Sys.Date() - 1,
                            auth_token = NULL,
                            base_url = "https://api.sensortower.com",
                            enrich_response = TRUE) {
  
  # Validate inputs
  if (!date_granularity %in% c("daily", "weekly", "monthly", "quarterly")) {
    stop("date_granularity must be one of: daily, weekly, monthly, quarterly")
  }
  
  if (!os %in% c("ios", "android", "unified")) {
    stop("os must be one of: ios, android, unified")
  }
  
  # --- Authentication ---
  auth_token_val <- auth_token %||% Sys.getenv("SENSORTOWER_AUTH_TOKEN")
  if (auth_token_val == "") {
    rlang::abort(
      "Authentication token not found. Please set it as an environment variable."
    )
  }
  
  # Convert dates to proper format
  start_date <- as.character(as.Date(start_date))
  end_date <- as.character(as.Date(end_date))
  
  # Convert categories to comma-separated string if vector
  if (is.numeric(categories) || length(categories) > 1) {
    categories <- paste(categories, collapse = ",")
  }
  
  # Convert countries to comma-separated string if vector
  if (length(countries) > 1) {
    countries <- paste(countries, collapse = ",")
  }
  
  # Build API request
  path_segments <- c("v1", os, "games_breakdown")
  
  query_params <- list(
    auth_token = auth_token_val,
    categories = categories,
    date_granularity = date_granularity,
    start_date = start_date,
    end_date = end_date
  )
  
  # Add countries parameter (API uses "WW" for worldwide by default)
  if (!is.null(countries) && countries != "WW") {
    query_params$countries <- countries
  }
  
  # Build and perform request
  req <- build_request(base_url, path_segments, query_params)
  resp <- perform_request(req)
  
  # Process response
  if (enrich_response) {
    result <- process_game_summary_response(resp, os)
  } else {
    result <- process_response(resp, FALSE)
  }
  
  return(result)
}

#' Process Game Summary API Response
#'
#' Internal function to process and enrich game summary API responses.
#'
#' @param resp List. Raw API response from game summary endpoint.
#' @param os Character string. Operating system to determine field mappings.
#'
#' @return A processed tibble with descriptive column names.
#' @keywords internal
process_game_summary_response <- function(resp, os) {
  
  # First get the raw response like process_response does
  body_raw <- httr2::resp_body_raw(resp)
  if (length(body_raw) == 0) {
    return(tibble::tibble())
  }

  body_text <- rawToChar(body_raw)
  result <- jsonlite::fromJSON(body_text, flatten = TRUE)

  if (length(result) == 0) {
    return(tibble::tibble())
  }

  # Convert to tibble
  result_tbl <- tibble::as_tibble(result)
  
  if (nrow(result_tbl) == 0) {
    return(result_tbl)
  }
  
  # Apply field name mappings using the games_breakdown_key data
  result_tbl <- map_game_summary_fields(result_tbl, os)
  
  # Convert date fields to proper Date format
  if ("Date" %in% names(result_tbl)) {
    result_tbl$Date <- as.Date(substr(result_tbl$Date, 1, 10))
  }
  
  # Convert numeric fields from character if needed
  numeric_patterns <- c("Downloads", "Revenue", "_downloads", "_revenue")
  numeric_cols <- names(result_tbl)[
    sapply(names(result_tbl), function(x) any(grepl(paste(numeric_patterns, collapse = "|"), x, ignore.case = TRUE)))
  ]
  
  for (col in numeric_cols) {
    if (is.character(result_tbl[[col]])) {
      result_tbl[[col]] <- as.numeric(result_tbl[[col]])
    }
  }
  
  # Automatically combine iPad and iPhone data into unified iOS totals
  if (os %in% c("ios", "unified")) {
    # Check if we have both iPhone and iPad columns
    has_iphone_downloads <- "iPhone Downloads" %in% names(result_tbl)
    has_ipad_downloads <- "iPad Downloads" %in% names(result_tbl)
    has_iphone_revenue <- "iPhone Revenue" %in% names(result_tbl)
    has_ipad_revenue <- "iPad Revenue" %in% names(result_tbl)
    
    if (has_iphone_downloads && has_ipad_downloads) {
      result_tbl$`iOS Downloads` <- result_tbl$`iPhone Downloads` + result_tbl$`iPad Downloads`
      # Remove individual device columns
      result_tbl$`iPhone Downloads` <- NULL
      result_tbl$`iPad Downloads` <- NULL
      message("Combined iPhone and iPad downloads into 'iOS Downloads'")
    }
    
    if (has_iphone_revenue && has_ipad_revenue) {
      result_tbl$`iOS Revenue` <- result_tbl$`iPhone Revenue` + result_tbl$`iPad Revenue`
      # Remove individual device columns
      result_tbl$`iPhone Revenue` <- NULL
      result_tbl$`iPad Revenue` <- NULL
      message("Combined iPhone and iPad revenue into 'iOS Revenue'")
    }
  }
  
  return(result_tbl)
}

#' Map Game Summary Field Names
#'
#' Internal function to map abbreviated API field names to descriptive names.
#'
#' @param data Tibble. Data with abbreviated field names.
#' @param os Character string. Operating system to determine mappings.
#'
#' @return Tibble with descriptive field names.
#' @keywords internal
map_game_summary_fields <- function(data, os) {
  
  # Get the appropriate field mappings from internal data
  if (os == "unified") {
    # For unified, we need to handle both iOS and Android fields
    ios_mappings <- games_breakdown_key$ios
    android_mappings <- games_breakdown_key$android
    
    # Combine mappings, with iOS taking precedence for common fields
    field_mappings <- c(ios_mappings, android_mappings[!names(android_mappings) %in% names(ios_mappings)])
  } else {
    field_mappings <- games_breakdown_key[[os]]
  }
  
  if (is.null(field_mappings)) {
    warning("Unknown OS: ", os, ". Field names will not be mapped.")
    return(data)
  }
  
  # Apply mappings
  current_names <- names(data)
  new_names <- current_names
  
  for (i in seq_along(current_names)) {
    old_name <- current_names[i]
    if (old_name %in% names(field_mappings)) {
      new_names[i] <- field_mappings[[old_name]]
    }
  }
  
  names(data) <- new_names
  return(data)
} 