source("R/pemob_helpers.R")

municipal_names <- c(
  code_muni = "Código IBGE",
  code_muni = "CÓDIGO IBGE",
  code_muni = "\r\n Código IBGE",
  code_muni = "CÓDIGO",
  abbrev_state = "\r\n UF",
  abbrev_state = "UF",
  name_muni = "\r\n Município",
  name_muni = "Município",
  name_muni = "MUNICÍPIO",
  name_muni = "MUNICIPIO"
)
missing_values <- c("#REF!", "NR", "NA", "ND", "-")
keydict <- readxl::read_excel(
  "data-raw/pemob_códigos.xlsx",
  sheet = "pemob_municipal"
) |>
  janitor::clean_names() |>
  tidyr::fill(bloco, secao)
keydict <- repair_pemob_municipal_crosswalk(keydict)
accessible_terminals <- keydict[keydict$x2024 == "1.4.1.B", ]

stopifnot(
  nrow(accessible_terminals) == 1L,
  is.na(accessible_terminals$x2019)
)

source_files <- c(
  `2019` = "data-raw/Pemob2019_Municipal.xlsx",
  `2020` = "data-raw/BancodeDados_PemobMunicipal_2020.xlsx",
  `2021` = "data-raw/pemob21_municipal.xlsx",
  `2022` = "data-raw/copy_of_pemob_municipal_2022.xlsx",
  `2023` = "data-raw/pemob2023_municipal.xlsx",
  `2024` = "data-raw/pemob_municipal_2024.xlsx"
)

read_municipal_source <- function(year) {
  dat <- readxl::read_excel(
    source_files[[year]],
    skip = if (year == "2020") 0 else 1,
    na = missing_values,
    col_types = "text"
  )

  if (year == "2020") {
    names(dat)[101:103] <- c("4.5.1", "4.5.2", "4.6.1")
  }

  dat <- dplyr::rename(dat, dplyr::any_of(municipal_names))
  dat <- filter_pemob_municipal_respondents(dat)

  return(dat)
}

municipal_sources <- lapply(names(source_files), read_municipal_source)
names(municipal_sources) <- names(source_files)
respondent_counts <- vapply(municipal_sources, nrow, integer(1))

source_2019 <- dplyr::select(municipal_sources[["2019"]], code_muni)
source_2024 <- dplyr::select(municipal_sources[["2024"]], code_muni)
joined_coverage <- join_pemob_editions(
  list(year_2024 = source_2024, year_2019 = source_2019),
  by = "code_muni"
)

stopifnot(
  identical(
    respondent_counts,
    c(
      `2019` = 64L,
      `2020` = 32L,
      `2021` = 62L,
      `2022` = 64L,
      `2023` = 67L,
      `2024` = 70L
    )
  ),
  nrow(joined_coverage) == 94L,
  length(setdiff(source_2019$code_muni, source_2024$code_muni)) == 24L
)
