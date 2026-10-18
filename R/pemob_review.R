source(here::here("R", "pemob_series.R"))

build_pemob_review_candidates_file <- function() {
  output_path <- here::here("data", "pemob_review_candidates.csv")

  series <- read_pemob_target_series() |>
    dplyr::select(-participated)

  candidates <- build_pemob_review_candidates(series) |>
    dplyr::mutate(
      source_file = unname(pemob_municipal_source_files[as.character(year)]),
      candidate_id = build_pemob_candidate_id(code_muni, code_variable, year),
      review_evidence = NA_character_,
      reviewer = NA_character_,
      correction_status = "none",
      evidence_required = paste(
        "Check the source response, reported unit, question wording,",
        "and independent municipal records."
      )
    ) |>
    dplyr::arrange(year, code_variable, code_muni)

  readr::write_csv(candidates, output_path)
  cli::cli_alert_success(
    "Wrote {nrow(candidates)} review candidates to {.file {output_path}}."
  )

  return(invisible(candidates))
}

if (sys.nframe() == 0L) {
  build_pemob_review_candidates_file()
}
