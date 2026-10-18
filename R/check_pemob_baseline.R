# Compare the rebuilt history with the 2024 harmonized workbook.
#
# Run from the project root with `Rscript R/check_pemob_baseline.R` after
# `R/build_pemob.R`. Prints counts by class and writes one row per differing
# cell to `data/pemob_baseline_differences.csv`, except for blanked missing
# codes and number formatting outside repaired cells.

source(here::here("R", "pemob_2025.R"))

# Classify differences -----------------------------------------------------

classify_pemob_difference <- function(baseline, rebuilt) {
  baseline <- dplyr::coalesce(baseline, "")
  rebuilt <- dplyr::coalesce(rebuilt, "")
  parsed_baseline <- parse_pemob_response(baseline)
  parsed_rebuilt <- parse_pemob_response(rebuilt)
  number_baseline <- parsed_baseline$parsed_value
  # The rebuild prints numeric cells with a decimal point and no separators.
  number_rebuilt <- dplyr::coalesce(
    parsed_rebuilt$parsed_value,
    suppressWarnings(as.numeric(rebuilt))
  )
  # The workbook writes decimals with a comma; "2,000" is the number 2.
  comma_decimal <- suppressWarnings(as.numeric(
    sub(",", ".", baseline, fixed = TRUE)
  ))
  number_baseline <- dplyr::coalesce(
    number_baseline,
    dplyr::if_else(grepl("^-?[0-9]+,[0-9]+$", baseline), comma_decimal, NA)
  )
  squish <- function(x) trimws(gsub("[[:space:]]+", " ", x))

  result <- dplyr::case_when(
    baseline == "" & !is.na(parsed_rebuilt$missing_reason) ~
      "missing_code_dropped",
    baseline == "" ~ "answer_dropped",
    rebuilt == "" ~ "value_not_in_rebuild",
    baseline %in% c("TRUE", "FALSE") ~ "logical_in_place_of_value",
    grepl("^[0-9]{5}$", baseline) &
      grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}", rebuilt) ~
      "excel_date_serial",
    grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", baseline) &
      grepl("^[0-9]{1,5}$", rebuilt) ~
      "excel_date_serial",
    squish(baseline) == squish(rebuilt) ~ "whitespace",
    !is.na(number_baseline) &
      !is.na(number_rebuilt) &
      abs(number_baseline - number_rebuilt) <=
        1e-9 * pmax(1, abs(number_baseline)) ~
      "number_format",
    !is.na(number_baseline) & !is.na(number_rebuilt) ~ "different_number",
    # The workbook lost every "NA" inside text, as after a find-and-replace.
    gsub("NA", "", rebuilt, fixed = TRUE) == baseline ~ "na_removed_from_text",
    .default = "different_text"
  )
  return(result)
}


# Compare cells ------------------------------------------------------------

compare_pemob_baseline <- function(
  baseline,
  rebuilt,
  key_cols,
  repairs = NULL,
  allowed_missing = character()
) {
  baseline_codes <- setdiff(names(baseline), key_cols)
  missing_codes <- setdiff(
    baseline_codes,
    c(names(rebuilt), allowed_missing)
  )
  if (length(missing_codes) > 0L) {
    cli::cli_abort(c(
      "{length(missing_codes)} workbook question{?s} {?is/are} missing from the rebuild.",
      "i" = "Missing: {.val {missing_codes}}."
    ))
  }
  codes <- intersect(baseline_codes, names(rebuilt))
  to_long <- function(dat, value_col) {
    dat |>
      dplyr::select(dplyr::all_of(c(key_cols, codes))) |>
      tidyr::pivot_longer(
        dplyr::all_of(codes),
        names_to = "code_variable",
        values_to = value_col,
        values_transform = as.character
      ) |>
      dplyr::mutate(
        "{value_col}" := dplyr::coalesce(.data[[value_col]], "")
      )
  }

  result <- dplyr::inner_join(
    to_long(baseline, "baseline_value"),
    to_long(rebuilt, "rebuilt_value"),
    by = c(key_cols, "code_variable")
  ) |>
    dplyr::filter(baseline_value != rebuilt_value) |>
    dplyr::mutate(
      difference = classify_pemob_difference(baseline_value, rebuilt_value)
    )

  # Cells the repair table moves to another column differ by design; the flag
  # keeps their difference class so a value regression stays visible.
  result$code_repair <- rep(FALSE, nrow(result))
  if (!is.null(repairs)) {
    result$code_repair <- paste(result$year, result$code_variable) %in%
      paste(repairs$edition, repairs$code_2024)
  }
  return(result)
}


# Run ----------------------------------------------------------------------

check_pemob_baseline <- function() {
  workbook <- here::here("tabelas", "PEMOB Harmonizada 2024.xlsx")
  baseline <- readxl::read_excel(
    workbook,
    sheet = "PEMOB Muni Harmonizada 24",
    col_types = "text"
  )
  baseline$code_muni <- as.numeric(baseline$code_muni)
  baseline$year <- as.numeric(baseline$year)
  rebuilt <- read_pemob_history(
    here::here("data", "pemob_harmonizada_2024.csv")
  )

  extra_rows <- dplyr::anti_join(
    baseline,
    rebuilt,
    by = c("code_muni", "year")
  )
  if (nrow(extra_rows) > 0L) {
    cli::cli_abort(
      "{nrow(extra_rows)} workbook row{?s} {?has/have} no rebuilt counterpart."
    )
  }

  key_cols <- c("code_muni", "year")
  baseline_cols <- c(key_cols, setdiff(names(baseline), names(baseline)[1:8]))
  differences <- compare_pemob_baseline(
    baseline[baseline_cols],
    rebuilt,
    key_cols = key_cols,
    repairs = read_pemob_code_repairs()
  )

  # Blanked missing codes and number formatting are counted, not listed,
  # except in repaired cells.
  bulk_classes <- c("missing_code_dropped", "number_format")
  readr::write_excel_csv2(
    dplyr::filter(differences, !difference %in% bulk_classes | code_repair),
    here::here("data", "pemob_baseline_differences.csv"),
    na = ""
  )

  counts <- dplyr::count(differences, difference, sort = TRUE)
  cli::cli_h2("Rebuilt history against the 2024 workbook")
  cli::cli_bullets(stats::setNames(
    paste0(counts$difference, ": ", counts$n),
    rep("*", nrow(counts))
  ))
  cli::cli_alert_info(
    "{sum(differences$code_repair)} differing cell{?s} come{?s/} from code repairs."
  )
  return(invisible(differences))
}

if (sys.nframe() == 0L) {
  check_pemob_baseline()
}
