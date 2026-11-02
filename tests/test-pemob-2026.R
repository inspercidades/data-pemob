source(here::here("R", "pemob_2026.R"))

municipal_source <- read_pemob_2026(
  here::here("data-raw", "pemob_municipal_2026.xlsx"),
  level = "municipal"
)
metro_source <- read_pemob_2026(
  here::here("data-raw", "pemob_metropolitana_2026.xlsx"),
  level = "metropolitan"
)

stopifnot(
  nrow(municipal_source) == 96L,
  nrow(metro_source) == 37L,
  !anyDuplicated(names(municipal_source)),
  !anyDuplicated(names(metro_source)),
  all(
    c("CÓDIGO IBGE", "UF", "Município", "12.1.1") %in% names(municipal_source)
  ),
  all(c("UF", "Região Metropolitana") %in% names(metro_source)),
  sum(municipal_source[["1.3.1.A"]] == "NA", na.rm = TRUE) == 90L,
  sum(municipal_source[["1.3.1.A"]] == "NR", na.rm = TRUE) == 2L
)

renamed_metro_names <- c(
  "Região Metropolitana de Fortaleza",
  "Região Metropolitana de Sobral",
  "Região Metropolitana do Cariri",
  "Região Metropolitana do Vale do Itajaí/RM do Vale Europeu"
)
historical_metro_names <- c(
  "RM Fortaleza",
  "RM Sobral",
  "RM Cariri",
  "Região Metropolitana do Vale do Itajaí"
)
renamed_states <- c("CE", "CE", "CE", "SC")
stopifnot(
  all(renamed_metro_names %in% metro_source[["Região Metropolitana"]]),
  identical(
    canonicalize_pemob_metro_name(
      renamed_states,
      renamed_metro_names,
      pemob_metro_aliases
    ),
    historical_metro_names
  )
)

municipal_history <- tibble::tibble(
  code_muni = 1200401,
  name_muni = "Rio Branco",
  abbrev_state = "AC",
  year = 2025,
  participated = TRUE,
  `12.2.1` = "Sim"
)
municipal_sample <- municipal_source[
  municipal_source[["CÓDIGO IBGE"]] == "1200401",
]
municipal_sample <- municipal_sample[c(
  "CÓDIGO IBGE",
  "UF",
  "Município",
  "12.1.1",
  "1.3.1.A"
)]
municipal_panel <- harmonize_municipal_edition(
  municipal_sample,
  municipal_history,
  year = 2026
)

stopifnot(
  identical(municipal_panel$year, c(2025, 2026)),
  identical(municipal_panel[["12.2.1"]][1], "Sim"),
  identical(municipal_panel[["12.2.1"]][2], municipal_sample[["12.1.1"]]),
  !"12.1.1" %in% names(municipal_panel)
)

for (level in c("municipal", "metro")) {
  prefix <- if (level == "metro") "pemob_metro_" else "pemob_"
  old <- read_pemob_history(here::here(
    "data",
    paste0(prefix, "harmonizada_2025.csv")
  ))
  current <- read_pemob_history(here::here(
    "data",
    paste0(prefix, "harmonizada_2026.csv")
  ))
  key <- if (level == "metro") "metro_key" else "code_muni"
  retained <- dplyr::semi_join(current, old, by = c(key, "year"))
  stopifnot(
    identical(old, retained[names(old)]),
    !anyDuplicated(current[c(key, "year")]),
    sum(current$year == 2026 & current$participated) ==
      if (level == "metro") 37L else 96L
  )
}

metro_panel <- read_pemob_history(
  here::here("data", "pemob_metro_harmonizada_2026.csv")
)
historical_keys <- build_pemob_metro_key(
  renamed_states,
  historical_metro_names
)
stopifnot(
  dplyr::n_distinct(metro_panel$metro_key) == 46L,
  all(
    historical_keys %in%
      metro_panel$metro_key[
        metro_panel$year == 2026 & metro_panel$participated
      ]
  ),
  !any(
    build_pemob_metro_key(renamed_states, renamed_metro_names) %in%
      metro_panel$metro_key
  )
)
