portal_code <- parse(here::here("R", "pemob_portal_final.R"))
metro_code <- parse(here::here("R", "pemob_metropolitana.R"))
source(here::here("R", "pemob_helpers.R"))

assignment <- function(code, name) {
  matches <- vapply(
    code,
    function(expr) {
      is.call(expr) &&
        identical(expr[[1]], as.name("<-")) &&
        identical(expr[[2]], as.name(name))
    },
    logical(1)
  )
  return(code[[which(matches)[1]]])
}

portal_env <- new.env()
portal_env$here <- here::here
eval(assignment(portal_code, "dict"), portal_env)
stopifnot("code_variable" %in% names(portal_env$dict))

metro_env <- new.env()
metro_env$tibble <- tibble::tibble
metro_env$all_years <- c(2019, 2021:2024)
complete <- data.frame(
  metro_key = "SP::Example",
  abbrev_state = "SP",
  name_metro = "Example",
  year = metro_env$all_years,
  answer = 1:5
)
metro_env$iter_pemob <- list(complete, complete[complete$year != 2021, ])
eval(assignment(metro_code, "error_inds"), metro_env)
eval(assignment(metro_code, "find_missing_years"), metro_env)
missing <- metro_env$find_missing_years(metro_env$iter_pemob[[2]])
stopifnot(
  identical(metro_env$error_inds, c(FALSE, TRUE)),
  missing$name_variable == "answer",
  missing$missing == "2021"
)

fare_series <- data.frame(
  code_muni = 1,
  name_muni = "Example",
  abbrev_state = "SP",
  year = 2019:2023,
  code_variable = "3.1.1.A",
  raw_response = c("5", "5", "50", "5", "NR")
)
cycle_outliers <- data.frame(
  code_muni = 100:107,
  name_muni = paste("City", 100:107),
  abbrev_state = "SP",
  year = 2024,
  code_variable = "1.6.1.G",
  raw_response = c("10", "12", "13", "14", "15", "16", "20", "17600")
)
other_candidates <- data.frame(
  code_muni = c(2, 2, 4, 5),
  name_muni = c("Zero City", "Zero City", "Unit City", "Text City"),
  abbrev_state = "SP",
  year = c(2023, 2024, 2024, 2024),
  code_variable = "1.6.1.H",
  raw_response = c("0", "10", "15 m", "texto sem número")
)
negative_fare <- data.frame(
  code_muni = 6,
  name_muni = "Negative City",
  abbrev_state = "SP",
  year = 2024,
  code_variable = "3.1.1.A",
  raw_response = "-1"
)
review_fixture <- rbind(
  fare_series,
  cycle_outliers,
  other_candidates,
  negative_fare
)
review_candidates <- build_pemob_review_candidates(review_fixture)
empty_candidates <- build_pemob_review_candidates(review_fixture[FALSE, ])

stopifnot(
  any(
    review_candidates$code_muni == 1 &
      review_candidates$year == 2021 &
      grepl("abrupt_change_10x", review_candidates$flag_reasons)
  ),
  any(
    review_candidates$code_muni == 107 &
      review_candidates$year == 2024 &
      grepl("cross_city_outlier", review_candidates$flag_reasons)
  ),
  any(
    review_candidates$code_muni == 2 &
      grepl("zero_transition", review_candidates$flag_reasons)
  ),
  any(
    review_candidates$code_muni == 4 &
      grepl("unit_mismatch", review_candidates$flag_reasons)
  ),
  any(
    review_candidates$code_muni == 5 &
      grepl("unparsed_response", review_candidates$flag_reasons)
  ),
  any(
    review_candidates$code_muni == 6 &
      grepl("negative_value", review_candidates$flag_reasons)
  ),
  !any(review_candidates$raw_response == "NR"),
  all(review_candidates$review_decision == "pending"),
  all(
    is.na(review_candidates$treated_value) ==
      is.na(review_candidates$parsed_value) &
      review_candidates$treated_value == review_candidates$parsed_value,
    na.rm = TRUE
  ),
  any(review_candidates$raw_response == "15 m"),
  nrow(empty_candidates) == 0L,
  all(c("flag_reasons", "review_decision") %in% names(empty_candidates))
)

treatment_data <- data.frame(
  code_muni = 20:24,
  name_muni = paste("Treatment City", 20:24),
  abbrev_state = "SP",
  year = 2024,
  code_variable = "1.6.1.G",
  raw_response = c("12", "25", "30", "0", "21,6 total ciclovias/ciclofaixas"),
  stringsAsFactors = FALSE
)
treatment_ledger <- data.frame(
  candidate_id = paste(20:23, "1.6.1.G", "2024", sep = "::"),
  raw_response = c("12", "25", "30", "0"),
  review_decision = c("corrected", "excluded", "pending", "accepted"),
  treated_value = c(12.5, NA_real_, 30, 0),
  review_evidence = c(
    "Municipal report confirms value in km.",
    "Source agency confirmed response is invalid.",
    NA_character_,
    "Source cell and unit reviewed."
  ),
  reviewer = c("reviewer", "reviewer", NA_character_, "reviewer"),
  stringsAsFactors = FALSE
)
treatment_result <- apply_pemob_review_decisions(
  treatment_data,
  treatment_ledger
)

stopifnot(
  identical(treatment_result$raw_response, treatment_data$raw_response),
  identical(treatment_result$treated_value[1], 12.5),
  is.na(treatment_result$treated_value[2]),
  identical(treatment_result$treated_value[3], 30),
  identical(treatment_result$treated_value[4], 0),
  is.na(treatment_result$treated_value[5]),
  identical(
    treatment_result$treatment_status,
    c("corrected", "excluded", "pending", "accepted", "reported")
  ),
  identical(
    treatment_result$review_evidence[1],
    treatment_ledger$review_evidence[1]
  )
)

missing_evidence_ledger <- treatment_ledger[1, ]
missing_evidence_ledger$review_evidence <- NA_character_
missing_evidence_ledger$reviewer <- NA_character_
stopifnot(inherits(
  try(
    apply_pemob_review_decisions(treatment_data, missing_evidence_ledger),
    silent = TRUE
  ),
  "try-error"
))

invalid_status_ledger <- treatment_ledger[1, ]
invalid_status_ledger$review_decision <- "auto_corrected"
stopifnot(inherits(
  try(
    apply_pemob_review_decisions(treatment_data, invalid_status_ledger),
    silent = TRUE
  ),
  "try-error"
))

stale_ledger <- treatment_ledger[1:2, ]
stale_ledger$raw_response <- c("100", "250")
stale_result <- suppressWarnings(
  apply_pemob_review_decisions(treatment_data, stale_ledger)
)
stopifnot(
  identical(stale_result$treated_value[1:2], c(12, 25)),
  identical(stale_result$treatment_status[1:2], c("pending", "pending")),
  identical(stale_result$review_decision[1:2], c("pending", "pending")),
  all(is.na(stale_result$review_evidence[1:2])),
  all(is.na(stale_result$reviewer[1:2]))
)

# A pending row whose source response changed is stale, not a value mismatch.
stale_pending_ledger <- treatment_ledger[3, ]
stale_pending_ledger$raw_response <- "300"
stale_pending_ledger$treated_value <- 300
stale_pending_result <- suppressWarnings(
  apply_pemob_review_decisions(treatment_data, stale_pending_ledger)
)
stopifnot(
  identical(stale_pending_result$treated_value[3], 30),
  identical(stale_pending_result$treatment_status[3], "pending")
)

missing_response_ledger <- treatment_ledger
missing_response_ledger$raw_response <- NULL
stopifnot(inherits(
  try(
    apply_pemob_review_decisions(treatment_data, missing_response_ledger),
    silent = TRUE
  ),
  "try-error"
))

unknown_key_ledger <- treatment_ledger[1, ]
unknown_key_ledger$candidate_id <- "999::1.6.1.G::2024"
stopifnot(inherits(
  try(
    apply_pemob_review_decisions(treatment_data, unknown_key_ledger),
    silent = TRUE
  ),
  "try-error"
))

shuffled_candidates <- build_pemob_review_candidates(
  review_fixture[rev(seq_len(nrow(review_fixture))), ]
)
gap_fixture <- data.frame(
  code_muni = 30,
  name_muni = "Gap City",
  abbrev_state = "SP",
  year = c(2019, 2021),
  code_variable = "3.1.1.A",
  raw_response = c("0", "50")
)
stopifnot(
  setequal(
    paste(
      shuffled_candidates$code_muni,
      shuffled_candidates$year,
      shuffled_candidates$flag_reasons
    ),
    paste(
      review_candidates$code_muni,
      review_candidates$year,
      review_candidates$flag_reasons
    )
  ),
  nrow(build_pemob_review_candidates(gap_fixture)) == 0L
)
