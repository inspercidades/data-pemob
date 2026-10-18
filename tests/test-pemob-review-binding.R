source(here::here("R", "pemob_interpolation.R"))

series <- data.frame(
  candidate_id = c("1::1.6.1.G::2020", "1::1.6.1.G::2022"),
  raw_response = c("10", "30"),
  review_decision = "unreviewed",
  review_evidence = NA_character_
)
ledger <- series
ledger$review_decision <- "accepted"
ledger$review_evidence <- "Checked the source response."

reviewed <- apply_pemob_endpoint_reviews(series, ledger)
stopifnot(
  all(reviewed$review_decision == "accepted"),
  identical(reviewed$review_evidence, ledger$review_evidence)
)

changed <- series
changed$raw_response[2] <- "30000"
reviewed <- apply_pemob_endpoint_reviews(changed, ledger)
stopifnot(
  reviewed$review_decision[1] == "accepted",
  reviewed$review_decision[2] == "unreviewed",
  is.na(reviewed$review_evidence[2]),
  identical(reviewed$raw_response, changed$raw_response)
)

gap_series <- data.frame(
  code_muni = 1,
  name_muni = "Example",
  abbrev_state = "SP",
  year = 2020:2022,
  code_variable = "1.6.1.G",
  candidate_id = paste("1::1.6.1.G", 2020:2022, sep = "::"),
  raw_response = c("10", "NR", "30"),
  participated = TRUE,
  review_decision = "unreviewed",
  review_evidence = NA_character_
)
accepted <- apply_pemob_endpoint_reviews(gap_series, ledger)
candidate <- build_pemob_interpolation_candidates(accepted)
stopifnot(candidate$eligible, candidate$estimate_value == 20)

gap_series$raw_response[3] <- "30000"
stale <- apply_pemob_endpoint_reviews(gap_series, ledger)
candidate <- build_pemob_interpolation_candidates(stale)
stopifnot(!candidate$eligible, is.na(candidate$estimate_value))

ledger$raw_response[2] <- "30000"
renewed <- apply_pemob_endpoint_reviews(gap_series, ledger)
candidate <- build_pemob_interpolation_candidates(renewed)
stopifnot(candidate$eligible, candidate$estimate_value == 15005)

missing_response <- ledger
missing_response$raw_response[2] <- NA_character_
reviewed <- apply_pemob_endpoint_reviews(series, missing_response)
stopifnot(reviewed$review_decision[2] == "unreviewed")

unmatched <- apply_pemob_endpoint_reviews(series, ledger[FALSE, ])
stopifnot(identical(unmatched, series))

duplicate_error <- tryCatch(
  apply_pemob_endpoint_reviews(series, rbind(ledger, ledger[1, ])),
  error = identity
)
stopifnot(
  inherits(duplicate_error, "error"),
  grepl("unique candidate IDs", conditionMessage(duplicate_error))
)
