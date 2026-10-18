library(readxl)
library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)
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

dict <- read_excel(here("data/portal/dicionario_v1.xlsx"))

full_pemob <- pemob |>
  left_join(dict) |>
  left_join(question_stats)

dashboard <- full_pemob |>
  filter(is_dashboard == 1, filled >= 3)

dashboard <- dashboard |>
  mutate(
    # If variable is not a percentage and not classified set to max
    # e.g. valor da atual tarifa...
    desc_scaled = if_else(
      is.na(desc_scaled) & is_percentage == 0,
      "max",
      desc_scaled
    )
  )

# dashboard |>
#   filter(desc_scaled == "share") |>
#   select(
#     code_variable,
#     code_muni,
#     year,
#     label,
#     value,
#     desc_scaled,
#     share_total
#   ) |>
#   mutate(value_num = as_numeric_comma(value))

## Share variables ------------------------------------------------

### Compute totals -----------------------------------------------

# Valores de referência para calcular os shares
dim_shares <- dashboard |>
  filter(desc_scaled == "share", !is.na(share_total)) |>
  select(code_muni, year, share_total) |>
  distinct()

dim_shares <- left_join(
  dim_shares,
  select(dashboard, code_muni, year, code_variable, value_num),
  by = c("code_muni", "year", "share_total" = "code_variable")
)

dim_shares <- dim_shares |>
  rename(share_value = value_num)

### Compute shares -----------------------------------------------

tbl_shares <- dashboard |>
  filter(desc_scaled == "share") |>
  left_join(dim_shares, by = c("code_muni", "year", "share_total")) |>
  mutate(
    value_scaled = scale_pemob_share(value_num, share_value),
    label = str_replace(label, "Número de ", "Percentual de "),
    label = if_else(
      !str_detect(label, "Percentual|percen"),
      paste(label, "- Percentual do total"),
      label
    )
  )

# Sanity check
tbl_shares <- tbl_shares |>
  mutate(value_scaled = if_else(value_scaled > 100, NA, value_scaled))

# OBS: a chave no Min. das Cidades está errada
# ex: 1.4.1.B (2019) - Nº de estações metroferroviárias
#     1.4.1.B (2024) - Qual o número total de terminais rodoviários acessíveis com rampas, plataformas de embarque em nível?
# Na chave: 1.4.1.B	(2019) = 1.4.1.B (2024)

# tbl_shares |>
#   filter(value_scaled < 0)

# pemob |>
#   filter(code_muni == 2211001, year == 2019, code_variable == "1.5.1.A")

# dict |>
#   filter(code_variable == "1.5.1.A") |>
#   pull(label_pergunta)

## Max variables ------------------------------------------------

tbl_max <- dashboard |>
  filter(desc_scaled == "max") |>
  mutate(
    value_scaled = scale_pemob_max(value_num),
    .by = c("code_variable", "year")
  ) |>
  filter(!is.na(value_num))

# Não adianta tentar limpar outliers de maneira sistemática...
tbl_max |>
  mutate(
    flag = if_else(
      value_num > 2 * fivenum(value_num)[4] + 2 * IQR(value_num),
      1L,
      0L
    ),
    .by = "code_variable"
  ) |>
  filter(flag == 1)

# Salvador tem 87 terminais rodoviários...
tbl_max |>
  filter(code_variable == "1.4.1.A", name_muni == "Salvador")

## Per capita variables -------------------------------------------

pop <- sidrar::get_sidra(
  4709,
  geo = "City"
)

pop_muni <- pop |>
  janitor::clean_names() |>
  as_tibble() |>
  filter(variavel_codigo == "93") |>
  select(
    code_muni = municipio_codigo,
    pop = valor
  ) |>
  mutate(code_muni = as.numeric(code_muni))

tbl_per_capita <- dashboard |>
  filter(desc_scaled == "per_capita") |>
  left_join(pop_muni, by = "code_muni") |>
  mutate(value_pop_scaled = value_num / pop) |>
  mutate(
    value_scaled = scale_pemob_max(value_pop_scaled),
    .by = c("code_variable", "year")
  )

# Merge tables --------------------------------------------------

# fmt: skip
sel_cols <- c(
  "code_variable",
  "code_muni", "name_muni", "abbrev_state", "label", "label_pergunta",
  "is_dashboard", "desc_scaled", "value", "value_scaled", "value_num",
  "parsed_unit", "parse_status", "missing_reason", "year", "value_pop_scaled"
)

txt_cols <- c(
  "value",
  "parsed_unit",
  "parse_status",
  "missing_reason",
  "name_muni",
  "abbrev_state",
  "label",
  "label_pergunta",
  "desc_scaled"
)
lgl_cols <- c("is_dashboard")
num_cols <- c("value_scaled", "value_num", "year", "value_pop_scaled")

format_tables <- function(dat) {
  dat |>
    select(any_of(sel_cols)) |>
    mutate(across(all_of(txt_cols), as.character)) |>
    mutate(across(all_of(lgl_cols), ~ ifelse(.x == 1, TRUE, FALSE))) |>
    mutate(across(any_of(num_cols), as.numeric)) |>
    arrange(code_variable) |>
    arrange(year)
}

pemob_tables <- list(tbl_shares, tbl_max, tbl_per_capita)
pemob_tables <- lapply(pemob_tables, format_tables)

tbl_dashboard <- bind_rows(pemob_tables)

readr::write_rds(
  pemob_tables,
  here("data", "portal", "final", "pemob_tables.rds")
)
readr::write_csv(
  tbl_dashboard,
  here("data", "portal", "final", "dashboard.csv")
)


export_pemob <- function(dat, y = 2023, destination = "tabela", print = FALSE) {
  swap_names <- c(
    "CÓDIGO" = "code_muni",
    "UF" = "abbrev_state",
    "Município" = "name_muni",
    "label" = "label",
    "valor" = "value",
    "pergunta" = "label_pergunta",
    "valor_transformado" = "value_scaled",
    "descricao_transformado" = "desc_scaled"
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
    sel_cols <- c(
      "code_muni",
      "name_muni",
      "abbrev_state",
      "label",
      "label_pergunta",
      "is_dashboard",
      "desc_scaled",
      "value_scaled",
      "value_num"
    )
  }

  subpemob <- subset(dat, year == y)

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
    here("data/portal/final", glue::glue("pemob_{destination}_{y}.json")),
    na = "null"
  )

  if (print) {
    return(data_portal)
  } else {
    return(invisible(NULL))
  }
}

years <- unique(tbl_dashboard$year)

for (y in years) {
  export_pemob(tbl_dashboard, y, "dashboard")
}
