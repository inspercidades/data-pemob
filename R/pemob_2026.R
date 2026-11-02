source(here::here("R", "pemob_2025.R"))

# Read 2026 sources ---------------------------------------------------------

read_pemob_2026 <- function(path, level) {
  if (!file.exists(path)) {
    cli::cli_abort("The 2026 source file {.file {path}} does not exist.")
  }
  if (!level %in% c("municipal", "metropolitan")) {
    cli::cli_abort("{.arg level} must be municipal or metropolitan.")
  }

  raw <- readxl::read_excel(
    path,
    col_names = FALSE,
    col_types = "text",
    na = character(),
    trim_ws = FALSE,
    .name_repair = "minimal"
  )
  codes <- trimws(as.character(unlist(raw[2, ], use.names = FALSE)))
  populated <- which(!is.na(codes) & nzchar(codes))
  if (length(populated) == 0L || any(diff(populated) != 1L)) {
    cli::cli_abort("The 2026 file {.file {path}} has missing question codes.")
  }
  codes <- codes[populated]
  if (anyDuplicated(codes)) {
    cli::cli_abort("The 2026 file {.file {path}} has duplicate question codes.")
  }

  dat <- raw[-c(1L, 2L), populated, drop = FALSE]
  names(dat) <- codes
  id_names <- if (level == "municipal") {
    c("MUNICÍPIO" = "Município")
  } else {
    c("REGIÃO METROPOLITANA" = "Região Metropolitana")
  }
  names(dat) <- ifelse(
    names(dat) %in% names(id_names),
    id_names[names(dat)],
    names(dat)
  )
  expected <- if (level == "municipal") {
    c("CÓDIGO IBGE", "UF", "Município")
  } else {
    c("UF", "Região Metropolitana")
  }
  if (!identical(head(names(dat), length(expected)), expected)) {
    cli::cli_abort("The 2026 file {.file {path}} has unexpected identifiers.")
  }

  return(as.data.frame(dat, check.names = FALSE))
}

read_pemob_2026_header <- function(path, level) {
  if (!level %in% c("municipal", "metropolitan")) {
    cli::cli_abort("{.arg level} must be municipal or metropolitan.")
  }
  header <- readxl::read_excel(
    path,
    col_names = FALSE,
    col_types = "text",
    n_max = 2L,
    na = character(),
    .name_repair = "minimal"
  )
  id_count <- if (level == "municipal") 3L else 2L
  codes <- as.character(unlist(header[2, ], use.names = FALSE))
  questions <- as.character(unlist(header[1, ], use.names = FALSE))
  present <- which(!is.na(codes) & nzchar(trimws(codes)))
  present <- present[present > id_count]
  return(tibble::tibble(
    source_code = trimws(codes[present]),
    question_text = questions[present]
  ))
}

# Append 2026 ---------------------------------------------------------------

build_pemob_2026 <- function() {
  municipal_source <- read_pemob_2026(
    here::here("data-raw", "pemob_municipal_2026.xlsx"),
    level = "municipal"
  )
  metro_source <- read_pemob_2026(
    here::here("data-raw", "pemob_metropolitana_2026.xlsx"),
    level = "metropolitan"
  )
  municipal_history <- read_pemob_history(
    here::here("data", "pemob_harmonizada_2025.csv")
  )
  metro_history <- read_pemob_history(
    here::here("data", "pemob_metro_harmonizada_2025.csv")
  )

  municipal <- harmonize_municipal_edition(
    municipal_source,
    municipal_history,
    year = 2026
  )
  metro <- harmonize_metro_edition(metro_source, metro_history, year = 2026)

  readr::write_excel_csv2(
    municipal,
    here::here("data", "pemob_harmonizada_2026.csv"),
    na = ""
  )
  readr::write_excel_csv2(
    metro,
    here::here("data", "pemob_metro_harmonizada_2026.csv"),
    na = ""
  )
  cli::cli_alert_success(
    "Wrote the municipal and metropolitan harmonized datasets through 2026."
  )

  return(invisible(list(municipal = municipal, metro = metro)))
}

if (sys.nframe() == 0L) {
  build_pemob_2026()
}
