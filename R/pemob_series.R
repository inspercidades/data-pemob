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
# edition. The series follows the completed municipal panel, so editions a
# municipality skipped appear as nonparticipating rows. Responses stay as raw
# text.
read_pemob_target_series <- function(variables = pemob_target_variables) {
  municipal_path <- here::here("data", "pemob_harmonizada_2025.csv")
  id_cols <- c("code_muni", "name_muni", "abbrev_state", "year", "participated")

  if (!file.exists(municipal_path)) {
    cli::cli_abort(
      "Run {.code Rscript R/build_pemob.R} to build the municipal panel first."
    )
  }
  municipal <- read_pemob_history(municipal_path)
  required_cols <- c(id_cols, variables)
  missing_cols <- setdiff(required_cols, names(municipal))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(
      "The municipal panel lacks {.field {missing_cols}}; rerun {.file R/build_pemob.R}."
    )
  }

  result <- municipal |>
    dplyr::select(dplyr::all_of(required_cols)) |>
    tidyr::pivot_longer(
      dplyr::all_of(variables),
      names_to = "code_variable",
      values_to = "raw_response"
    )

  return(result)
}
