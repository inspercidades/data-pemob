source(here::here("R", "check_pemob_baseline.R"))

# Difference classes -------------------------------------------------------

baseline <- c(
  "",
  "",
  "TRUE",
  "44287",
  "2,000",
  "Linha  A",
  "5",
  "4,50",
  "Centro",
  "1,5",
  "3,3330",
  "REGIÃO METROPOLITA DO RECIFE",
  "1905-08-07"
)
rebuilt <- c(
  "NR",
  "Sim",
  "0.05",
  "2021-04-01",
  "2",
  "Linha A",
  "",
  "5.1",
  "Centro histórico",
  "1.5",
  "3.333",
  "REGIÃO METROPOLITANA DO RECIFE",
  "2046"
)

classes <- classify_pemob_difference(baseline, rebuilt)

stopifnot(identical(
  classes,
  c(
    "missing_code_dropped",
    "answer_dropped",
    "logical_in_place_of_value",
    "excel_date_serial",
    "number_format",
    "whitespace",
    "value_not_in_rebuild",
    "different_number",
    "different_text",
    "number_format",
    "number_format",
    "na_removed_from_text",
    "excel_date_serial"
  )
))


# Cell comparison ----------------------------------------------------------

baseline_table <- tibble::tibble(
  code_muni = c(1, 1, 2),
  year = c(2023, 2024, 2024),
  `1.1.1` = c("Sim", "", "TRUE"),
  `1.4.1.B` = c("5", "2", "")
)
rebuilt_table <- tibble::tibble(
  code_muni = c(1, 1, 2),
  year = c(2023, 2024, 2024),
  `1.1.1` = c("Sim", "NR", "3"),
  `1.4.1.B` = c("5", "", NA),
  `9.9.9` = c("x", "y", "z")
)

differences <- compare_pemob_baseline(
  baseline_table,
  rebuilt_table,
  key_cols = c("code_muni", "year")
)

stopifnot(
  nrow(differences) == 3L,
  identical(
    differences$difference,
    c(
      "missing_code_dropped",
      "value_not_in_rebuild",
      "logical_in_place_of_value"
    )
  ),
  !"9.9.9" %in% differences$code_variable
)

repaired_differences <- compare_pemob_baseline(
  baseline_table,
  rebuilt_table,
  key_cols = c("code_muni", "year"),
  repairs = data.frame(edition = 2024, code_2024 = "1.1.1")
)
stopifnot(identical(
  repaired_differences$difference,
  c("code_repair", "value_not_in_rebuild", "code_repair")
))

combined_differences <- compare_pemob_baseline(
  baseline_table,
  rebuilt_table,
  key_cols = c("code_muni", "year"),
  combined = data.frame(edition = 2024, code_2024 = "1.1.1")
)
stopifnot(identical(
  combined_differences$difference,
  c("range_combined", "value_not_in_rebuild", "range_combined")
))
