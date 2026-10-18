source(here::here("R", "pemob_helpers.R"))

aliases <- data.frame(
  abbrev_state = "AL",
  source_name = "RM Maceió",
  canonical_name = "Região Metropolitana de Maceió"
)

names <- canonicalize_pemob_metro_name(
  c("AL", "SP", "AL"),
  c("RM Maceió", "RM Maceió", "RM Agreste"),
  aliases
)
keys <- build_pemob_metro_key(
  c("AL", "SP", "AL"),
  names
)

stopifnot(
  identical(
    names,
    c(
      "Região Metropolitana de Maceió",
      "RM Maceió",
      "RM Agreste"
    )
  ),
  length(unique(keys)) == 3L
)

placeholder_regions <- add_pemob_metro_identity(data.frame(
  abbrev_state = c("SP", "NR", "ND"),
  name_metro = c(
    "Região Metropolitana de São Paulo",
    "Não Respondeu",
    "Não Disponível"
  )
))
stopifnot(
  nrow(placeholder_regions) == 1L,
  placeholder_regions$abbrev_state == "SP"
)

metro_2024_source <- readxl::read_excel(
  here::here("data-raw", "pemob_metropolitana_2024.xlsx"),
  skip = 1
)
metro_2024_names <- canonicalize_pemob_metro_name(
  metro_2024_source$UF,
  metro_2024_source$REGIÃO,
  pemob_metro_aliases
)
historical_name <- canonicalize_pemob_metro_name(
  c("AL", "SP"),
  c("RM Maceió", "RM São Paulo"),
  pemob_metro_aliases
)
expected_name <- c(
  "Região Metropolitana de Maceió",
  "Região Metropolitana de São Paulo"
)

stopifnot(identical(historical_name, expected_name))
stopifnot(all(expected_name %in% metro_2024_names))
alias_keys <- build_pemob_metro_key(
  pemob_metro_aliases$abbrev_state,
  pemob_metro_aliases$canonical_name
)
metro_2024_keys <- build_pemob_metro_key(
  metro_2024_source$UF,
  metro_2024_names
)
stopifnot(all(alias_keys %in% metro_2024_keys))

source_files <- c(
  here::here("data-raw", "Pemob2019_Metropolitana.xlsx"),
  here::here("data-raw", "pemob21_metropolitana.xlsx"),
  here::here("data-raw", "pemob_metropolitana_2022.xlsx"),
  here::here("data-raw", "pemob2023_metropolitana.xlsx"),
  here::here("data-raw", "pemob_metropolitana_2024.xlsx")
)
for (path in source_files) {
  source_data <- readxl::read_excel(path, skip = 1)
  region_col <- intersect(
    c("RM/AU", "REGIÃO", "Região Metropolitana", "REGIÃO METROPOLITANA"),
    names(source_data)
  )[[1]]
  identity_data <- data.frame(
    abbrev_state = source_data$UF,
    name_metro = source_data[[region_col]],
    stringsAsFactors = FALSE
  )
  identity_data <- add_pemob_metro_identity(identity_data)
  stopifnot(!anyDuplicated(identity_data$metro_key))
}

source(here::here("R", "pemob_2025.R"))
metro_survey <- read_pemob_2025(
  here::here(
    "data-raw",
    "pemob_metropolitana_2025(pemob_metropolitana_2025).csv"
  )
)
metro <- harmonize_metro_2025(metro_survey)

stopifnot(
  all(c("abbrev_state", "metro_key", "name_metro_source") %in% names(metro)),
  all(!is.na(metro$abbrev_state)),
  !anyDuplicated(metro[c("metro_key", "year")]),
  length(unique(metro$metro_key[metro$year == 2025])) == 29L,
  sum(
    metro$year == 2025 &
      metro$metro_key %in% metro$metro_key[metro$year == 2024]
  ) ==
    27L
)
