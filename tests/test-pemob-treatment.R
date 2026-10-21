source(here::here("R", "pemob_treatment.R"))

# Adjustment dates ---------------------------------------------------------

stopifnot(
  identical(
    parse_pemob_month(c(
      "2023-01-01",
      "2019-11-15",
      "03/2020",
      "Jan-25",
      "sep-23",
      "NR",
      "",
      NA
    )),
    as.Date(c(
      "2023-01-01",
      "2019-11-01",
      "2020-03-01",
      "2025-01-01",
      "2023-09-01",
      NA,
      NA,
      NA
    ))
  )
)


# Gap estimates ------------------------------------------------------------

gap_fixture <- tibble::tibble(
  code_variable = c(
    "3.1.1.A",
    "3.1.1.A",
    "3.1.1.A",
    "3.1.1.A",
    "3.1.1.A",
    "3.1.1.A",
    "1.6.1.G",
    "1.6.1.H",
    "1.6.1.G"
  ),
  year = 2020,
  left_value = c(4, 4, 4, 4, 4, 4, 10, 10, 10),
  right_value = c(5, 5, 5, 5, 4, 5, 10, 20, NA),
  right_previous_fare = c(4.5, 4, 4.5, 3.9, NA, NA, NA, NA, NA),
  right_adjustment = as.Date(c(
    "2019-06-01",
    "2021-02-01",
    "2020-05-01",
    "2021-02-01",
    NA,
    NA,
    NA,
    NA,
    NA
  ))
)
gap_estimates <- estimate_pemob_gaps(gap_fixture)

stopifnot(
  identical(names(gap_estimates), c("estimate_value", "treatment_method")),
  # Adjusted before the gap year: the next edition's fare was in force.
  gap_estimates$estimate_value[1] == 5,
  gap_estimates$treatment_method[1] == "fare_current_since_earlier_adjustment",
  # Adjusted after the gap year, and the previous fare matches the left value.
  gap_estimates$estimate_value[2] == 4,
  gap_estimates$treatment_method[2] == "fare_previous_until_later_adjustment",
  # Adjusted during the gap year: the fare in force is ambiguous.
  is.na(gap_estimates$estimate_value[3]),
  is.na(gap_estimates$treatment_method[3]),
  # Adjusted after the gap year, but the previous fare contradicts the left.
  is.na(gap_estimates$estimate_value[4]),
  # Without an adjustment date, only equal fare endpoints are carried.
  gap_estimates$estimate_value[5] == 4,
  gap_estimates$treatment_method[5] == "equal_endpoints",
  is.na(gap_estimates$estimate_value[6]),
  gap_estimates$estimate_value[7] == 10,
  gap_estimates$treatment_method[7] == "equal_endpoints",
  gap_estimates$estimate_value[8] == 15,
  gap_estimates$treatment_method[8] == "linear",
  # A missing endpoint is never filled.
  is.na(gap_estimates$estimate_value[9])
)


# Treated series -----------------------------------------------------------

series_fixture <- tibble::tibble(
  code_muni = rep(c(1, 2, 3, 4, 5), each = 3),
  name_muni = rep(paste("City", 1:5), each = 3),
  abbrev_state = "SP",
  year = rep(2019:2021, 5),
  participated = c(
    TRUE,
    FALSE,
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    FALSE,
    TRUE
  ),
  code_variable = c(
    rep("3.1.1.A", 3),
    rep("1.6.1.G", 3),
    rep("1.6.1.G", 3),
    rep("1.6.1.G", 3),
    rep("1.6.1.G", 3)
  ),
  raw_response = c(
    # Skipped edition, fare reconstructed from the 2021 record.
    "4,00",
    NA,
    "R$ 4,50",
    # Item nonresponse between unequal endpoints.
    "10",
    "NR",
    "20 km",
    # Not applicable is not a gap.
    "10",
    "NA",
    "20",
    # A pending review candidate is not a usable endpoint.
    "10",
    "NR",
    "17600",
    # An endpoint in metres is not a usable endpoint.
    "10",
    NA,
    "500 m"
  )
)
fare_fixture <- tibble::tibble(
  code_muni = 1,
  year = 2021,
  previous_fare_raw = "4,00",
  adjustment_raw = "2021-01-01"
)
ledger_fixture <- tibble::tibble(
  candidate_id = c("4::1.6.1.G::2021", "5::1.6.1.G::2021"),
  raw_response = c("17600", "500 m"),
  review_decision = "pending",
  treated_value = c(17600, 500),
  review_evidence = NA_character_,
  reviewer = NA_character_
)
current_candidates <- build_pemob_review_candidates(series_fixture)
stopifnot(identical(
  build_pemob_candidate_id(
    current_candidates$code_muni,
    current_candidates$code_variable,
    current_candidates$year
  ),
  "5::1.6.1.G::2021"
))
missing_candidate_ledger <- ledger_fixture[
  ledger_fixture$candidate_id != "5::1.6.1.G::2021",
]
stopifnot(inherits(
  try(
    treat_pemob_target_series(
      series_fixture,
      missing_candidate_ledger,
      fare_fixture
    ),
    silent = TRUE
  ),
  "try-error"
))
stale_candidate_ledger <- ledger_fixture
stale_candidate_ledger$raw_response[2] <- "500 km"
stopifnot(inherits(
  suppressWarnings(try(
    treat_pemob_target_series(
      series_fixture,
      stale_candidate_ledger,
      fare_fixture
    ),
    silent = TRUE
  )),
  "try-error"
))
series_before <- series_fixture
treated <- treat_pemob_target_series(
  series_fixture,
  ledger_fixture,
  fare_fixture
)
cell <- function(code, year) {
  treated[treated$code_muni == code & treated$year == year, ]
}

stopifnot(
  identical(series_fixture, series_before),
  nrow(treated) == nrow(series_fixture),
  identical(
    treated$raw_response[order(treated$code_muni, treated$year)],
    series_fixture$raw_response
  ),
  !anyNA(treated$treatment_status),
  all(
    treated$treatment_status %in%
      c(
        "reported",
        "missing",
        "pending",
        "accepted",
        "corrected",
        "excluded",
        "reconstructed",
        "interpolated"
      )
  ),
  cell(1, 2019)$treatment_status == "reported",
  cell(1, 2019)$treated_value == 4,
  cell(1, 2020)$treatment_status == "reconstructed",
  cell(1, 2020)$treated_value == 4,
  cell(1, 2020)$treatment_method == "fare_previous_until_later_adjustment",
  cell(2, 2020)$treatment_status == "interpolated",
  cell(2, 2020)$treated_value == 15,
  cell(3, 2020)$treatment_status == "missing",
  is.na(cell(3, 2020)$treated_value),
  cell(4, 2021)$treatment_status == "pending",
  cell(4, 2020)$treatment_status == "missing",
  cell(5, 2020)$treatment_status == "missing",
  all(is.na(treated$treatment_method[
    !treated$treatment_status %in% c("reconstructed", "interpolated")
  ]))
)

endpoint_fixture <- tibble::tibble(
  code_muni = 9,
  name_muni = "Endpoint City",
  abbrev_state = "SP",
  year = 2019:2022,
  participated = TRUE,
  code_variable = "1.6.1.G",
  raw_response = c("10", "1000", "NR", "1000")
)
endpoint_candidate <- build_pemob_review_candidates(endpoint_fixture)
stopifnot(
  nrow(endpoint_candidate) == 1L,
  endpoint_candidate$year == 2020,
  grepl("abrupt_change_10x", endpoint_candidate$flag_reasons)
)
endpoint_error <- tryCatch(
  treat_pemob_target_series(
    endpoint_fixture,
    ledger_fixture[FALSE, ],
    fare_fixture
  ),
  error = identity
)
stopifnot(
  inherits(endpoint_error, "error"),
  grepl("9::1.6.1.G::2020", conditionMessage(endpoint_error), fixed = TRUE)
)
endpoint_ledger <- tibble::tibble(
  candidate_id = "9::1.6.1.G::2020",
  raw_response = "1000",
  review_decision = "pending",
  treated_value = 1000,
  review_evidence = NA_character_,
  reviewer = NA_character_
)
endpoint_treated <- treat_pemob_target_series(
  endpoint_fixture,
  endpoint_ledger,
  fare_fixture
)
stopifnot(
  endpoint_treated$treatment_status[endpoint_treated$year == 2020] == "pending",
  endpoint_treated$treatment_status[endpoint_treated$year == 2021] == "missing",
  is.na(endpoint_treated$treated_value[endpoint_treated$year == 2021])
)


# Masking validation -------------------------------------------------------

validation_fixture <- tibble::tibble(
  code_muni = rep(c(1, 2), each = 3),
  name_muni = rep(c("City 1", "City 2"), each = 3),
  abbrev_state = "SP",
  year = rep(2019:2021, 2),
  participated = TRUE,
  code_variable = rep(c("3.1.1.A", "1.6.1.G"), each = 3),
  raw_response = c("4", "4", "5", "10", "16", "20")
)
validation_fares <- tibble::tibble(
  code_muni = 1,
  year = 2021,
  previous_fare_raw = "4",
  adjustment_raw = "2021-03-01"
)
validation_treated <- treat_pemob_target_series(
  validation_fixture,
  ledger_fixture[FALSE, ],
  validation_fares
)
masked <- mask_pemob_observed_values(validation_treated, validation_fares)

stopifnot(
  nrow(masked) == 2L,
  all(masked$year == 2020),
  masked$estimate_value[masked$code_muni == 1] == 4,
  masked$estimate_value[masked$code_muni == 2] == 15,
  masked$observed_value[masked$code_muni == 2] == 16,
  all(validation_treated$treatment_status == "reported")
)

masking_summary <- summarise_pemob_masking(masked)
stopifnot(
  identical(
    names(masking_summary),
    c(
      "code_variable",
      "treatment_method",
      "cells",
      "exact_share",
      "mean_absolute_error",
      "median_absolute_percent_error"
    )
  ),
  masking_summary$exact_share[masking_summary$code_variable == "3.1.1.A"] == 1,
  masking_summary$mean_absolute_error[
    masking_summary$code_variable == "1.6.1.G"
  ] ==
    1
)

zero_masked <- tibble::tibble(
  code_variable = "1.6.1.G",
  treatment_method = "equal_endpoints",
  observed_value = c(0, 10),
  error = c(0, 2)
)
zero_summary <- summarise_pemob_masking(zero_masked)
stopifnot(
  zero_summary$cells == 2L,
  zero_summary$exact_share == 0.5,
  zero_summary$mean_absolute_error == 1,
  zero_summary$median_absolute_percent_error == 20
)
zero_only_summary <- summarise_pemob_masking(zero_masked[1, ])
stopifnot(
  zero_only_summary$cells == 1L,
  zero_only_summary$exact_share == 1,
  zero_only_summary$mean_absolute_error == 0,
  is.na(zero_only_summary$median_absolute_percent_error)
)
