source(here::here("R", "pemob_helpers.R"))
source(here::here("R", "pemob_2025.R"))

# Source files ---------------------------------------------------------------

pemob_municipal_source_files <- c(
  "2019" = "data-raw/Pemob2019_Municipal.xlsx",
  "2020" = "data-raw/BancodeDados_PemobMunicipal_2020.xlsx",
  "2021" = "data-raw/pemob21_municipal.xlsx",
  "2022" = "data-raw/copy_of_pemob_municipal_2022.xlsx",
  "2023" = "data-raw/pemob2023_municipal.xlsx",
  "2024" = "data-raw/pemob_municipal_2024.xlsx",
  "2025" = "data-raw/pemob_municipal_2025(pemob_municipal_25).csv"
)


# Target series --------------------------------------------------------------

# Long series of the review targets, one row per municipality, question, and
# edition. Responses stay as raw text.
read_pemob_target_series <- function() {
  historical_path <- here::here("data", "pemob_harmonizada_2024.csv")
  id_cols <- c("code_muni", "name_muni", "abbrev_state", "year", "participated")

  if (!file.exists(historical_path)) {
    cli::cli_abort(
      "Run {.file R/pemob.R} to build the historical source data first."
    )
  }
  historical <- readr::read_delim(
    historical_path,
    delim = ";",
    col_types = readr::cols(.default = readr::col_character()),
    na = "",
    show_col_types = FALSE
  )
  required_cols <- c(id_cols, pemob_target_variables)
  missing_cols <- setdiff(required_cols, names(historical))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(
      "The historical output lacks {.field {missing_cols}}; rerun {.file R/pemob.R}."
    )
  }

  source_2025 <- read_pemob_2025(here::here(pemob_municipal_source_files[[
    "2025"
  ]]))
  current <- source_2025 |>
    dplyr::select(
      code_muni = "CÓDIGO IBGE",
      name_muni = "Município",
      abbrev_state = "UF",
      dplyr::all_of(pemob_target_variables)
    ) |>
    dplyr::mutate(year = "2025", participated = "TRUE")

  wide <- dplyr::bind_rows(
    dplyr::select(historical, dplyr::all_of(required_cols)),
    current
  )

  result <- wide |>
    tidyr::pivot_longer(
      dplyr::all_of(pemob_target_variables),
      names_to = "code_variable",
      values_to = "raw_response"
    ) |>
    dplyr::mutate(
      code_muni = as.numeric(code_muni),
      year = as.numeric(year),
      participated = as.logical(participated)
    )

  return(result)
}
