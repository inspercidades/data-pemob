source(here::here("R/pemob_helpers.R"))
source(here::here("R/pemob_2025.R"))

build_pemob_interpolation_candidates_file <- function() {
  historical_path <- here::here("data/pemob_harmonizada_2024.csv")
  review_path <- here::here("docs/internal/pemob-review-ledger.csv")
  output_path <- here::here("data/pemob_interpolation_candidates.csv")
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
    "participated",
    target_variables
  )
  if (!all(required_cols %in% names(historical))) {
    cli::cli_abort(
      "The historical output lacks participation or interpolation variables."
    )
  }

  historical_long <- do.call(
    rbind,
    lapply(target_variables, function(code) {
      year <- as.numeric(historical$year)
      data.frame(
        code_muni = as.numeric(historical$code_muni),
        name_muni = historical$name_muni,
        abbrev_state = historical$abbrev_state,
        year = year,
        reference_time = year,
        code_variable = code,
        raw_response = historical[[code]],
        participated = as.logical(historical$participated),
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
        reference_time = 2025,
        code_variable = code,
        raw_response = source_2025[[code]],
        participated = TRUE,
        stringsAsFactors = FALSE
      )
    })
  )
  series <- rbind(historical_long, current_long)
  series$candidate_id <- paste(
    sprintf("%.0f", series$code_muni),
    series$code_variable,
    series$year,
    sep = "::"
  )
  series$review_decision <- "unreviewed"
  series$review_evidence <- NA_character_

  review_ledger <- readr::read_csv(
    review_path,
    col_types = readr::cols(
      candidate_id = readr::col_character(),
      review_decision = readr::col_character(),
      review_evidence = readr::col_character(),
      .default = readr::col_skip()
    ),
    show_col_types = FALSE
  )
  review_row <- match(series$candidate_id, review_ledger$candidate_id)
  reviewed <- !is.na(review_row)
  series$review_decision[reviewed] <-
    review_ledger$review_decision[review_row[reviewed]]
  series$review_evidence[reviewed] <-
    review_ledger$review_evidence[review_row[reviewed]]
  candidates <- build_pemob_interpolation_candidates(series)
  candidates$source_file <- unname(c(
    "2019" = "data-raw/Pemob2019_Municipal.xlsx",
    "2020" = "data-raw/BancodeDados_PemobMunicipal_2020.xlsx",
    "2021" = "data-raw/pemob21_municipal.xlsx",
    "2022" = "data-raw/copy_of_pemob_municipal_2022.xlsx",
    "2023" = "data-raw/pemob2023_municipal.xlsx",
    "2024" = "data-raw/pemob_municipal_2024.xlsx",
    "2025" = "data-raw/pemob_municipal_2025(pemob_municipal_25).csv"
  )[as.character(candidates$year)])

  readr::write_csv(candidates, output_path, na = "")
  cli::cli_alert_success(
    "Wrote {nrow(candidates)} gap candidates; {sum(candidates$eligible)} eligible for interpolation."
  )

  return(invisible(candidates))
}

if (sys.nframe() == 0L) {
  build_pemob_interpolation_candidates_file()
}
