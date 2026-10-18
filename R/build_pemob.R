# Rebuild the harmonized PEMOB datasets from the source files.
#
# Run from the project root with `Rscript R/build_pemob.R`. The historical
# scripts write the 2019–2024 histories to `data/`; the 2025 step appends the
# 2025 survey to those histories.

source(here::here("R", "pemob_2025.R"))

run_pemob_script <- function(file) {
  cli::cli_h1("Running {.file {file}}")
  source(here::here("R", file), local = new.env())
  return(invisible(NULL))
}


# Build --------------------------------------------------------------------

run_pemob_script("pemob.R")
run_pemob_script("pemob_metropolitana.R")

cli::cli_h1("Appending 2025")
pemob <- build_pemob_2025()


# Checks -------------------------------------------------------------------

check_pemob_keys <- function(dat, key_col, label) {
  if (anyDuplicated(dat[c(key_col, "year")])) {
    cli::cli_abort("The {label} output has duplicate place-year keys.")
  }

  coverage <- dat |>
    dplyr::summarise(
      places = dplyr::n(),
      respondents = sum(participated),
      .by = year
    ) |>
    dplyr::arrange(year)

  cli::cli_h2("{label} coverage")
  cli::cli_bullets(stats::setNames(
    paste0(
      coverage$year,
      ": ",
      coverage$respondents,
      " respondents of ",
      coverage$places,
      " places"
    ),
    rep("*", nrow(coverage))
  ))
  return(invisible(coverage))
}

check_pemob_keys(pemob$municipal, "code_muni", "Municipal")
check_pemob_keys(pemob$metro, "metro_key", "Metropolitan")
