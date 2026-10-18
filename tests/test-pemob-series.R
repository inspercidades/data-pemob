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
  all(series$participated[series$year == 2025]),
  !anyDuplicated(series[c("code_muni", "code_variable", "year")]),
  all(
    as.character(unique(series$year)) %in% names(pemob_municipal_source_files)
  )
)
