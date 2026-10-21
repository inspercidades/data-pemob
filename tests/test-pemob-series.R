source(here::here("R", "pemob_series.R"))

stopifnot(
  identical(
    build_pemob_candidate_id(3550308, "3.1.1.A", 2024),
    "3550308::3.1.1.A::2024"
  ),
  identical(
    build_pemob_candidate_id(c("1", "2"), "1.6.1.G", c(2020, 2021)),
    c("1::1.6.1.G::2020", "2::1.6.1.G::2021")
  ),
  setequal(names(pemob_expected_units), pemob_target_variables)
)

series <- read_pemob_target_series()

stopifnot(
  identical(
    names(series),
    c(
      "code_muni",
      "name_muni",
      "abbrev_state",
      "year",
      "participated",
      "code_variable",
      "raw_response"
    )
  ),
  is.numeric(series$code_muni),
  is.numeric(series$year),
  is.logical(series$participated),
  is.character(series$raw_response),
  setequal(series$code_variable, pemob_target_variables),
  all(2019:2025 %in% series$year),
  !anyDuplicated(series[c("code_muni", "code_variable", "year")]),
  all(
    as.character(unique(series$year)) %in% names(pemob_municipal_source_files)
  )
)

# The series follows the completed municipal panel, so municipalities that
# skipped 2025 or joined in 2025 keep one row per edition.
municipal <- read_pemob_history(
  here::here("data", "pemob_harmonizada_2025.csv")
)

stopifnot(
  nrow(series) == nrow(municipal) * length(pemob_target_variables),
  nrow(dplyr::anti_join(
    dplyr::distinct(municipal, code_muni, year),
    dplyr::distinct(series, code_muni, year),
    by = c("code_muni", "year")
  )) == 0L,
  all(is.na(series$raw_response[!series$participated]))
)
