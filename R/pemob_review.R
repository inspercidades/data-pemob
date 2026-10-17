source(here::here("R/pemob_helpers.R"))
source(here::here("R/pemob_2025.R"))

build_pemob_review_candidates_file <- function() {
  historical_path <- here::here("data/pemob_harmonizada_2024.csv")
  output_path <- here::here("data/pemob_review_candidates.csv")
  target_variables <- c("3.1.1.A", "1.6.1.G", "1.6.1.H")

  if (!file.exists(historical_path)) {
    cli::cli_abort(
      "Run {.file R/pemob.R} to build the historical source data first."
    )
  }
  historical <- readr::read_delim(
    historical_path,
    delim = ";",
    col_types = readr::cols(.default = readr::col_character()),
    na = character(),
    show_col_types = FALSE
  )
  required_cols <- c(
    "code_muni",
    "name_muni",
    "abbrev_state",
    "year",
    target_variables
  )
  if (!all(required_cols %in% names(historical))) {
    cli::cli_abort(
      "The historical output lacks review variables or identifiers."
    )
  }

  historical_long <- do.call(
    rbind,
    lapply(target_variables, function(code) {
      data.frame(
        code_muni = as.numeric(historical$code_muni),
        name_muni = historical$name_muni,
        abbrev_state = historical$abbrev_state,
        year = as.numeric(historical$year),
        code_variable = code,
        raw_response = historical[[code]],
        stringsAsFactors = FALSE
      )
    })
  )

  source_2025 <- read_pemob_2025(here::here(
    "data-raw/pemob_municipal_2025(pemob_municipal_25).csv"
  ))
  current_long <- do.call(
    rbind,
    lapply(target_variables, function(code) {
      data.frame(
        code_muni = as.numeric(source_2025[["CÓDIGO IBGE"]]),
        name_muni = source_2025[["Município"]],
        abbrev_state = source_2025[["UF"]],
        year = 2025,
        code_variable = code,
        raw_response = source_2025[[code]],
        stringsAsFactors = FALSE
      )
    })
  )

  candidates <- build_pemob_review_candidates(
    rbind(historical_long, current_long)
  )
  source_files <- c(
    "2019" = "data-raw/Pemob2019_Municipal.xlsx",
    "2020" = "data-raw/BancodeDados_PemobMunicipal_2020.xlsx",
    "2021" = "data-raw/pemob21_municipal.xlsx",
    "2022" = "data-raw/copy_of_pemob_municipal_2022.xlsx",
    "2023" = "data-raw/pemob2023_municipal.xlsx",
    "2024" = "data-raw/pemob_municipal_2024.xlsx",
    "2025" = "data-raw/pemob_municipal_2025(pemob_municipal_25).csv"
  )
  candidates$source_file <- unname(source_files[as.character(candidates$year)])
  candidates$candidate_id <- paste(
    sprintf("%.0f", candidates$code_muni),
    candidates$code_variable,
    candidates$year,
    sep = "::"
  )
  candidates$review_evidence <- NA_character_
  candidates$reviewer <- NA_character_
  candidates$correction_status <- "none"
  candidates$evidence_required <- paste(
    "Check the source response, reported unit, question wording,",
    "and independent municipal records."
  )
  candidates <- candidates[
    order(
      candidates$year,
      candidates$code_variable,
      candidates$code_muni
    ),
  ]

  readr::write_csv(candidates, output_path)
  cli::cli_alert_success(
    "Wrote {nrow(candidates)} review candidates to {.file {output_path}}."
  )

  return(invisible(candidates))
}

if (sys.nframe() == 0L) {
  build_pemob_review_candidates_file()
}
