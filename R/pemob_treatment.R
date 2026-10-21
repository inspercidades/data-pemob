source(here::here("R", "pemob_series.R"))

# Treat the target series: apply review decisions, then fill one-edition gaps
# in fares and cycling infrastructure. See Phase 3 in ROADMAP.md.

pemob_fare_variable <- "3.1.1.A"
pemob_fare_record_variables <- c("3.1.1.B", "3.1.1.C")


# Adjustment dates ---------------------------------------------------------

# Parse the last fare adjustment date (`3.1.1.C`) to the first day of its
# month. Editions write it as "2023-01-01", "03/2020", or "Jan-25".
parse_pemob_month <- function(x) {
  x <- trimws(as.character(x))
  result <- rep(as.Date(NA), length(x))

  iso <- !is.na(x) & grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x)
  result[iso] <- as.Date(sub("-[0-9]{2}$", "-01", x[iso]))

  month_year <- !is.na(x) & grepl("^[0-9]{2}/[0-9]{4}$", x)
  result[month_year] <- as.Date(sub(
    "^([0-9]{2})/([0-9]{4})$",
    "\\2-\\1-01",
    x[month_year]
  ))

  abbreviated <- !is.na(x) &
    grepl("^[A-Za-z]{3}-[0-9]{2}$", x) &
    tolower(substr(x, 1, 3)) %in% tolower(month.abb)
  month <- match(tolower(substr(x[abbreviated], 1, 3)), tolower(month.abb))
  result[abbreviated] <- as.Date(sprintf(
    "20%s-%02d-01",
    substr(x[abbreviated], 5, 6),
    month
  ))

  return(result)
}


# Gap estimates ------------------------------------------------------------

# Estimate a one-edition gap from its usable neighbours. `left_value` and
# `right_value` are missing when the neighbour is not usable. Fares use the
# next edition's previous fare and adjustment date when it reports them.
estimate_pemob_gaps <- function(gaps) {
  required_cols <- c(
    "code_variable",
    "year",
    "left_value",
    "right_value",
    "right_previous_fare",
    "right_adjustment"
  )
  if (!all(required_cols %in% names(gaps))) {
    cli::cli_abort("Gap inputs must include {.field {required_cols}}.")
  }

  same_value <- function(x, y) !is.na(x) & !is.na(y) & abs(x - y) < 0.005

  year_start <- as.Date(paste0(gaps$year, "-01-01"))
  year_end <- as.Date(paste0(gaps$year, "-12-31"))
  has_endpoints <- !is.na(gaps$left_value) & !is.na(gaps$right_value)
  is_fare <- gaps$code_variable == pemob_fare_variable
  has_date <- !is.na(gaps$right_adjustment)

  adjusted_before <- is_fare & has_date & gaps$right_adjustment < year_start
  adjusted_after <- is_fare &
    has_date &
    gaps$right_adjustment > year_end &
    same_value(gaps$right_previous_fare, gaps$left_value)
  carried <- (!is_fare | !has_date) &
    same_value(gaps$left_value, gaps$right_value)
  linear <- !is_fare & !carried

  method <- dplyr::case_when(
    !has_endpoints ~ NA_character_,
    adjusted_before ~ "fare_current_since_earlier_adjustment",
    adjusted_after ~ "fare_previous_until_later_adjustment",
    carried ~ "equal_endpoints",
    linear ~ "linear",
    .default = NA_character_
  )
  estimate <- dplyr::case_when(
    method == "fare_current_since_earlier_adjustment" ~ gaps$right_value,
    method == "fare_previous_until_later_adjustment" ~ gaps$right_previous_fare,
    method == "equal_endpoints" ~ gaps$left_value,
    method == "linear" ~ (gaps$left_value + gaps$right_value) / 2,
    .default = NA_real_
  )

  result <- tibble::tibble(
    estimate_value = estimate,
    treatment_method = method
  )
  return(result)
}


# Neighbours ---------------------------------------------------------------

read_pemob_fare_records <- function(series) {
  required_cols <- c("code_muni", "year", "code_variable", "raw_response")
  if (!all(required_cols %in% names(series))) {
    cli::cli_abort("Fare records need {.field {required_cols}}.")
  }

  result <- series |>
    dplyr::filter(code_variable %in% pemob_fare_record_variables) |>
    dplyr::select(dplyr::all_of(required_cols)) |>
    tidyr::pivot_wider(
      names_from = code_variable,
      values_from = raw_response
    ) |>
    dplyr::rename(
      previous_fare_raw = "3.1.1.B",
      adjustment_raw = "3.1.1.C"
    )

  return(result)
}

# Attach the usable values of the previous and next editions, and the next
# edition's fare record, to every cell.
add_pemob_neighbours <- function(treated, fare_records) {
  usable <- treated |>
    dplyr::filter(usable_endpoint) |>
    dplyr::select(code_muni, code_variable, year, treated_value)

  fares <- fare_records |>
    dplyr::transmute(
      code_muni,
      right_year = year,
      code_variable = pemob_fare_variable,
      right_previous_fare = parse_pemob_response(
        previous_fare_raw
      )$parsed_value,
      right_adjustment = parse_pemob_month(adjustment_raw)
    )

  result <- treated |>
    dplyr::mutate(left_year = year - 1, right_year = year + 1) |>
    dplyr::left_join(
      dplyr::rename(usable, left_year = year, left_value = treated_value),
      by = c("code_muni", "code_variable", "left_year")
    ) |>
    dplyr::left_join(
      dplyr::rename(usable, right_year = year, right_value = treated_value),
      by = c("code_muni", "code_variable", "right_year")
    ) |>
    dplyr::left_join(fares, by = c("code_muni", "code_variable", "right_year"))

  return(result)
}


# Treated series -----------------------------------------------------------

treat_pemob_target_series <- function(series, ledger, fare_records) {
  series_cols <- c(
    "code_muni",
    "name_muni",
    "abbrev_state",
    "year",
    "participated",
    "code_variable",
    "raw_response"
  )
  if (!all(series_cols %in% names(series))) {
    cli::cli_abort("The target series must include {.field {series_cols}}.")
  }

  reviewed <- series |>
    dplyr::select(dplyr::all_of(series_cols)) |>
    dplyr::filter(code_variable %in% pemob_target_variables) |>
    as.data.frame() |>
    apply_pemob_review_decisions(ledger) |>
    tibble::as_tibble()
  reviewed$expected_unit <- unname(pemob_expected_units[reviewed$code_variable])

  # Endpoints must be reviewed or unflagged, nonnegative, and in the expected
  # unit; a reviewer's correction is taken to use the expected unit.
  treated <- reviewed |>
    dplyr::mutate(
      treatment_status = dplyr::if_else(
        treatment_status == "reported" & is.na(treated_value),
        "missing",
        treatment_status
      ),
      usable_endpoint = treatment_status %in%
        c("reported", "accepted", "corrected") &
        !is.na(treated_value) &
        treated_value >= 0 &
        (treatment_status == "corrected" |
          is.na(parsed_unit) |
          parsed_unit == expected_unit),
      is_gap = treatment_status == "missing" &
        (participated %in% FALSE | missing_reason %in% "NR")
    )

  estimates <- add_pemob_neighbours(treated, fare_records)
  estimates <- dplyr::bind_cols(
    dplyr::select(estimates, code_muni, code_variable, year),
    estimate_pemob_gaps(estimates)
  )

  result <- treated |>
    dplyr::left_join(estimates, by = c("code_muni", "code_variable", "year")) |>
    dplyr::mutate(
      filled = is_gap & !is.na(estimate_value),
      treated_value = dplyr::if_else(filled, estimate_value, treated_value),
      treatment_method = dplyr::if_else(
        filled,
        treatment_method,
        NA_character_
      ),
      treatment_status = dplyr::case_when(
        filled &
          code_variable == pemob_fare_variable &
          treatment_method != "equal_endpoints" ~ "reconstructed",
        filled ~ "interpolated",
        .default = treatment_status
      )
    ) |>
    dplyr::select(
      dplyr::all_of(series_cols),
      parsed_value,
      parsed_unit,
      parse_status,
      missing_reason,
      treated_value,
      treatment_status,
      treatment_method,
      review_evidence,
      reviewer
    ) |>
    dplyr::arrange(code_variable, code_muni, year)

  return(result)
}


# Masking validation -------------------------------------------------------

# Hide each usable value in turn, estimate it from its neighbours with the
# gap rules, and keep the cells the rules would fill.
mask_pemob_observed_values <- function(treated, fare_records) {
  observed <- treated |>
    dplyr::select(-treatment_method) |>
    dplyr::mutate(
      usable_endpoint = treatment_status %in%
        c("reported", "accepted", "corrected") &
        !is.na(treated_value) &
        treated_value >= 0 &
        (treatment_status == "corrected" |
          is.na(parsed_unit) |
          parsed_unit == unname(pemob_expected_units[code_variable]))
    )
  neighbours <- add_pemob_neighbours(observed, fare_records)

  result <- dplyr::bind_cols(neighbours, estimate_pemob_gaps(neighbours)) |>
    dplyr::filter(usable_endpoint, !is.na(estimate_value)) |>
    dplyr::transmute(
      code_muni,
      name_muni,
      year,
      code_variable,
      treatment_method,
      observed_value = treated_value,
      estimate_value,
      error = estimate_value - observed_value
    )

  return(result)
}

summarise_pemob_masking <- function(masked) {
  result <- masked |>
    dplyr::summarise(
      cells = dplyr::n(),
      exact_share = mean(abs(error) < 0.005),
      mean_absolute_error = mean(abs(error)),
      median_absolute_percent_error = stats::median(
        abs(error) / observed_value * 100
      ),
      .by = c(code_variable, treatment_method)
    ) |>
    dplyr::arrange(code_variable, treatment_method)

  return(result)
}


# Build --------------------------------------------------------------------

build_pemob_treatment <- function() {
  ledger <- readr::read_csv(
    here::here("docs", "internal", "pemob-review-ledger.csv"),
    col_types = readr::cols(
      candidate_id = readr::col_character(),
      raw_response = readr::col_character(),
      review_decision = readr::col_character(),
      treated_value = readr::col_double(),
      review_evidence = readr::col_character(),
      reviewer = readr::col_character(),
      .default = readr::col_skip()
    ),
    show_col_types = FALSE
  )

  series <- read_pemob_target_series(
    c(pemob_target_variables, pemob_fare_record_variables)
  )
  fare_records <- read_pemob_fare_records(series)
  treated <- treat_pemob_target_series(series, ledger, fare_records)
  masking <- summarise_pemob_masking(
    mask_pemob_observed_values(treated, fare_records)
  )
  status_counts <- dplyr::count(
    treated,
    code_variable,
    year,
    treatment_status,
    name = "cells"
  )

  readr::write_csv(
    treated,
    here::here("data", "pemob_target_treated.csv"),
    na = ""
  )
  readr::write_csv(
    status_counts,
    here::here("data", "pemob_treatment_counts.csv"),
    na = ""
  )
  readr::write_csv(
    masking,
    here::here("data", "pemob_masking_validation.csv"),
    na = ""
  )

  filled <- sum(
    treated$treatment_status %in% c("reconstructed", "interpolated")
  )
  cli::cli_alert_success(
    "Wrote the treated target series; {filled} gap cell{?s} filled."
  )

  return(invisible(list(
    treated = treated,
    counts = status_counts,
    masking = masking
  )))
}

if (sys.nframe() == 0L) {
  build_pemob_treatment()
}
