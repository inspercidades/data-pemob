library(readxl)
library(dplyr)
library(tidyr)
library(stringr)
library(here)

source(here("R/pemob_helpers.R"))

# The actual data
pemob <- read_excel(
  here("tabelas/PEMOB Harmonizada 2024.xlsx"),
  sheet = "PEMOB Muni Harmonizada 24",
  na = ""
)

pemob <- pemob |>
  pivot_longer(
    cols = !code_muni:year,
    names_to = "code_variable",
    values_transform = as.character
  ) |>
  separate(
    code_variable,
    into = c("code_group", "code_subgroup", "code_subsubgroup", "code_modal"),
    sep = "\\.",
    remove = FALSE
  )

parsed_responses <- parse_pemob_response(pemob$value)
pemob <- dplyr::bind_cols(
  pemob,
  dplyr::select(parsed_responses, -raw_response)
) |>
  rename(value_num = parsed_value)

question_stats <- pemob |>
  filter(year == max(year)) |>
  summarise(
    filled = sum(parse_status != "missing"),
    total = n(),
    avg = mean(value_num, na.rm = TRUE),
    min = min(value_num, na.rm = TRUE),
    max = max(value_num, na.rm = TRUE),
    sd = sd(value_num, na.rm = TRUE),
    .by = c("code_variable")
  ) |>
  mutate(
    percent = filled / total
  ) |>
  filter(filled >= 3) |>
  arrange(desc(filled))

dict <- readr::read_delim(
  here("data/portal/v1/dict_portal_parcial.csv"),
  delim = ","
)

full_pemob <- pemob |>
  left_join(dict) |>
  left_join(question_stats)

full_pemob <- full_pemob |>
  mutate(
    type = if_else(is.na(value_num), "non-numeric", "numeric"),
    is_dashboard = if_else(
      type == "numeric" & filled >= 5 & is_percentage,
      1L,
      is_dashboard
    ),
    is_portal = if_else(filled >= 1, 1L, is_portal)
  )

dict_portal <- dict |>
  left_join(question_stats) |>
  rename(is_tabela = is_portal) |>
  mutate(
    # Convert NA values to 0
    is_dashboard = if_else(is.na(is_dashboard), 0L, is_dashboard),
    is_tabela = if_else(is.na(is_tabela), 0L, is_tabela),
    # Include all percentage variables that are filled at least 5 times
    is_dashboard = if_else(is_percentage == 1 & filled >= 5, 1L, is_dashboard),
    # Drop from tabela if not enough filled
    is_tabela = if_else(filled <= 1, 0L, is_tabela),
  ) |>
  select(
    code_variable,
    label,
    label_pergunta,
    categoria,
    subcategoria,
    is_dashboard,
    is_tabela,
    is_absolute,
    is_average,
    is_percentage
  )

# Export to Excel (here)
readr::write_excel_csv2(dict_portal, "data/portal/dict_portal_v1.csv")

# Por enquanto usando somente variáveis numéricas e binárias
# Acredito que teria que ajustar UI para incorporar variáveis de texto
pemob_final <- pemob |>
  left_join(dict_portal) |>
  mutate(
    raw_value = value,
    value = value_num
  )

pemob_final <- pemob_final |>
  mutate(
    # small fix (anything going to the dashboard should also go to the table)
    is_tabela = if_else(is_dashboard == 1 & is_tabela == 0, 1L, is_tabela),
    is_dashboard = if_else(is.na(is_dashboard), 0L, is_dashboard),
    is_dashboard = if_else(is_dashboard == 1L, TRUE, FALSE)
  )

export_pemob <- function(y = 2023, destination = "tabela", print = FALSE) {
  swap_names <- c(
    "CÓDIGO" = "code_muni",
    "UF" = "abbrev_state",
    "Município" = "name_muni",
    "label" = "label",
    "valor" = "value",
    "pergunta" = "label_pergunta"
  )

  if (destination %in% c("tabela", "combined")) {
    subpemob <- subset(pemob_final, is_tabela == 1)

    sel_cols <- c(
      "code_muni",
      "name_muni",
      "abbrev_state",
      "label",
      "value",
      "label_pergunta",
      "is_dashboard"
    )
  } else if (destination == "dashboard") {
    subpemob <- subset(pemob_final, is_dashboard == 1)

    sel_cols <- c(
      "code_muni",
      "name_muni",
      "abbrev_state",
      "label",
      "value",
      "label_pergunta"
    )
  }

  subpemob <- subset(subpemob, year == y)

  if (nrow(subpemob) == 0) {
    cli::cli_abort("No data for year {y}")
  }
  data_portal <- subpemob |>
    select(all_of(sel_cols)) |>
    # rename(valor = value, pergunta = label_pergunta) |>
    group_by(code_muni, name_muni, abbrev_state) |>
    tidyr::nest() |>
    rename(any_of(swap_names))

  jsonlite::write_json(
    data_portal,
    here("data/portal", glue::glue("pemob_{destination}_{y}.json")),
    na = "null"
  )

  if (print) {
    return(data_portal)
  } else {
    return(NULL)
  }
}

lapply(
  unique(pemob_final$year),
  \(y) {
    export_pemob(y, "combined")
  }
)

lapply(
  unique(pemob_final$year),
  \(y) {
    export_pemob(y, "tabela")
    export_pemob(y, "dashboard")
  }
)

portal_dashboard <- portal |>
  rename(valor = value, pergunta = label_pergunta) |>
  group_by(code_muni, name_muni, abbrev_state) |>
  tidyr::nest() |>
  rename(any_of(swap_names))

jsonlite::write_json(
  portal_dashboard,
  here("data/pemob_dashboard_2024.json"),
  na = "null"
)

pemob |>
  filter(code_variable == "1.1.1", year == 2024)

# library(DataEditR)

# data_edit(big_table, save_as = "data/portal/portal_selecao_variaveis.csv")
