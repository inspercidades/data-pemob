source(here::here("R", "pemob_series.R"))

# Copy a ledger decision only when the reviewed response still matches the
# current source response; stale approvals leave the row unreviewed.
apply_pemob_endpoint_reviews <- function(series, review_ledger) {
  if (anyDuplicated(review_ledger$candidate_id)) {
    cli::cli_abort("The review ledger must have unique candidate IDs.")
  }

  review_row <- match(series$candidate_id, review_ledger$candidate_id)
  reviewed_response <- review_ledger$raw_response[review_row]
  reviewed <- !is.na(review_row) &
    !is.na(series$raw_response) &
    !is.na(reviewed_response) &
    series$raw_response == reviewed_response
  series$review_decision[reviewed] <-
    review_ledger$review_decision[review_row[reviewed]]
  series$review_evidence[reviewed] <-
    review_ledger$review_evidence[review_row[reviewed]]

  return(series)
}

build_pemob_interpolation_candidates_file <- function() {
  review_path <- here::here("docs", "internal", "pemob-review-ledger.csv")
  output_path <- here::here("data", "pemob_interpolation_candidates.csv")

  review_ledger <- readr::read_csv(
    review_path,
    col_types = readr::cols(
      candidate_id = readr::col_character(),
      raw_response = readr::col_character(),
      review_decision = readr::col_character(),
      review_evidence = readr::col_character(),
      .default = readr::col_skip()
    ),
    show_col_types = FALSE
  )

  series <- read_pemob_target_series() |>
    dplyr::mutate(
      reference_time = year,
      candidate_id = build_pemob_candidate_id(code_muni, code_variable, year),
      review_decision = "unreviewed",
      review_evidence = NA_character_
    )
  reviewed_series <- apply_pemob_endpoint_reviews(series, review_ledger)

  candidates <- build_pemob_interpolation_candidates(reviewed_series) |>
    dplyr::mutate(
      source_file = unname(pemob_municipal_source_files[as.character(year)])
    )

  readr::write_csv(candidates, output_path, na = "")
  cli::cli_alert_success(
    "Wrote {nrow(candidates)} gap candidates; {sum(candidates$eligible)} eligible for interpolation."
  )

  return(invisible(candidates))
}

if (sys.nframe() == 0L) {
  build_pemob_interpolation_candidates_file()
}
