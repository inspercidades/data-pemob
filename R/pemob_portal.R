library(readxl)
library(dplyr)
library(stringr)
library(cli)
library(tidyr)
import::from(here, here)
import::from(janitor, clean_names, make_clean_names)

pemob_dict <- read_excel(
  here("data/PEMOB Harmonizada 2024.xlsx"),
  sheet = "Dicionario Portal",
  na = "NA"
)

# Simple column classification

modais <- c(
  "ônibus",
  "microônibus",
  "metrô",
  "trem",
  "monotrilho",
  "Monotrilho",
  "VLT",
  "táxi",
  "mototáxi",
  "bicicleta",
  "barco",
  "fretamento",
  "escolar",
  "aeromóvel",
  "transporte remunerado privado",
  "pedestres"
)

pemob_dict <- pemob_dict |>
  mutate(
    modal = str_extract(name_variable, paste0(modais, collapse = "|")),
    modal = if_else(
      is.na(modal),
      str_extract(label, paste0(str_to_title(modais), collapse = "|")),
      modal
    ),
    modal = str_to_title(modal),
    modal = if_else(modal == "Vlt", "VLT", modal),
    is_average = if_else(str_detect(name_variable, "média|Média"), 1L, 0L),
    is_percentage = if_else(
      str_detect(name_variable, "Percent|percent"),
      1L,
      0L
    ),
    is_absolute = if_else(
      tipo == "numeric" & is_average == 0L & is_percentage == 0L,
      1L,
      0L
    )
  )

pemob_dict |>
  mutate(
    label = if_else(
      modal != "Ônibus" & str_detect(label, "ônibus|Ônibus"),
      str_replace(label, "ônibus|Ônibus", modal),
      label
    ),
    label = str_replace(label, "MicroMicroônibus", "Microônibus"),
  ) |>
  select(label, modal) |>
  View()


# The actual data
pemob <- read_excel(
  here("data/PEMOB Harmonizada 2024.xlsx"),
  sheet = "PEMOB Muni Harmonizada 24",
  na = "NA"
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
  ) |>
  mutate(
    code_question = str_sub(code_variable, 1, 5)
  )

candidate_questions <- pemob |>
  mutate(filled = if_else(is.na(value), 0L, 1L)) |>
  summarise(
    total = n(),
    filled = sum(filled, na.rm = TRUE),
    percent = filled / total,
    .by = c("year", "code_variable")
  ) |>
  arrange(desc(percent)) |>
  filter(filled >= 1, year == 2024)

dim_questions <- pemob_dict |>
  select(code_variable, label_pergunta, label, is_portal, is_dashboard)

pemob_dict <- pemob_dict |>
  mutate(
    is_candidate = if_else(
      code_variable %in% candidate_questions$code_variable,
      1L,
      0L
    )
  )

dict_tabela <- pemob_dict |>
  select(
    code_variable,
    name_variable,
    label_pergunta,
    label,
    subcategoria,
    tipo,
    modal,
    starts_with("is")
  )

categorias_tabela <- c(
  "Infraestrutura",
  "Frota",
  "Tarifas",
  "Receita",
  "Custos",
  "Demanda",
  "Arrecadação"
)

dict_tabela |>
  count(subcategoria)

dict_tabela <- dict_tabela |>
  mutate(
    categoria = case_when(
      subcategoria == "Infraestrutura" ~ "Infraestrutura",
      subcategoria == "Frota" ~ "Frota",
      subcategoria == "Estacionamento" ~ "Infraestrutura",
      subcategoria == "Passageiros Transportados" ~ "Demanda",
      subcategoria == "Eficiência e Indicadores" ~ "Frota",
      subcategoria == "Sustentabilidade" ~ "Frota",
      str_detect(label_pergunta, "receita|Receita") ~ "Receita",
      str_detect(label, "Impostos") ~ "Custos",
      str_detect(label, "Custo") ~ "Custos",
      str_detect(subcategoria, "Tarifa") ~ "Tarifas",
      str_detect(label, "tarifa|Tarifa") ~ "Tarifas",
      str_detect(label, "Desconto|desconto") ~ "Tarifas",
      str_detect(label, "^Táxi") ~ "Tarifas",
      str_detect(label, "^Baixa|^Idos|^Defi") ~ "Tarifas",
      TRUE ~ "missing"
    )
  ) |>
  select(-subcategoria) |>
  filter(is_candidate == 1, tipo == "numeric")

readr::write_csv(pemob_dict, here("data", "dict_portal_pemob.csv"))
readr::write_csv(dict_tabela, here("data", "dict_tabela_pemob.csv"))

dict_tabela <- pemob_dict |>
  select(
    code_variable,
    name_variable,
    label_pergunta,
    label,
    subcategoria,
    tipo,
    modal,
    starts_with("is")
  )

dict_tabela <- dict_tabela |>
  mutate(
    categoria = case_when(
      subcategoria == "Infraestrutura" ~ "Infraestrutura",
      subcategoria == "Frota" ~ "Frota",
      subcategoria == "Estacionamento" ~ "Infraestrutura",
      subcategoria == "Passageiros Transportados" ~ "Demanda",
      subcategoria == "Eficiência e Indicadores" ~ "Frota",
      subcategoria == "Sustentabilidade" ~ "Frota",
      str_detect(label_pergunta, "receita|Receita") ~ "Receita",
      str_detect(label, "Impostos") ~ "Custos",
      str_detect(label, "Custo") ~ "Custos",
      str_detect(subcategoria, "Tarifa") ~ "Tarifa",
      str_detect(label, "tarifa|Tarifa") ~ "Tarifa",
      str_detect(label, "Desconto|desconto") ~ "Tarifa",
      str_detect(label, "^Táxi") ~ "Tarifa",
      str_detect(label, "^Baixa|^Idos|^Defi") ~ "Tarifa",
      TRUE ~ "missing"
    )
  )

dim_category <- dict_tabela |>
  select(
    code_variable,
    name_variable,
    label_pergunta,
    label,
    categoria,
    old_subcategoria = subcategoria,
    modal
  )

dim_category <- dim_category |>
  mutate(
    categoria = case_when(
      label == "Táxi no Corredor de Ônibus" ~ "Infraestrutura",
      label == "Agentes de Trânsito em Exercício" ~ "Infraestrutura",
      label == "Equipamentos de Fiscalização" ~ "Infraestrutura",
      label == "Valor Arrecadado com Multas de Trânsito" ~ "Arrecadação",
      old_subcategoria == "Pesquisa Origem e Destino" ~ "Origem e Destino",
      code_variable %in%
        c("2.5.1", "4.1.1", "4.1.1.A", "4.1.2", "4.3.1", "8.1.1") ~
        "Governança e Leis",
      TRUE ~ categoria
    )
  ) |>
  mutate(
    modal = case_when(
      old_subcategoria == "Estacionamento" ~ "Automóvel",
      str_detect(label, "rodoviá|Rodoviá|BRT") ~ "Ônibus",
      str_detect(label_pergunta, "ciclo") ~ "Bicicleta",
      str_detect(label, "metroferrov|Metroferrov|metroviá|Metroviá") ~
        "Metrô/Trem",
      str_detect(label_pergunta, "pontos de embarque e desembarque") ~ "Ônibus",
      label %in%
        c(
          "Pontos de Embarque Georreferenciados",
          "Extensão de Faixas Exclusivas",
          "Velocidade Média do Transporte Público em Vias Mistas"
        ) ~
        "Ônibus",
      TRUE ~ modal
    )
  ) |>
  mutate(
    subcategoria = modal,
    subcategoria = if_else(
      subcategoria == "Microônibus",
      "Vans/Microônibus",
      subcategoria
    ),
    subcategoria = if_else(
      modal %in% c("Escolar", "Fretamento"),
      "Ônibus",
      subcategoria
    ),
    subcategoria = if_else(
      label == "Agentes de Trânsito em Exercício",
      "Trabalhadores",
      subcategoria
    ),
    subcategoria = if_else(
      label == "Equipamentos de Fiscalização",
      "Equipamentos",
      subcategoria
    ),
    subcategoria = if_else(
      modal == "Transporte Remunerado Privado",
      "Automóvel",
      subcategoria
    )
  )

rm_variables <- c(
  "3.3.1.A",
  "3.3.1.H",
  "3.3.1.O",
  "3.3.1.V",
  "3.3.1.AC",
  "3.3.1.AJ",
  "3.3.1.AQ",
  "3.3.1.AX",
  "3.7.1",
  "3.7.2",
  "3.7.3",
  "3.7.4",
  "3.7.5",
  "3.7.6",
  "3.7.7",
  "3.7.8"
)

pat_infra <- "(^Extensão da m)|(pontualidade e regular)|(^Velocidade Mé)|(^Viagens.+Incompl)|(^Viagens.+Horário)"
pat_frota <- "(capacidade média)|(^Frota)|(composição)|(^Idade Média da F)|(^Quilômetros Percorridos)"

dim_category <- dim_category |>
  filter(!is.na(label)) |>
  mutate(
    categoria = case_when(
      str_detect(label, pat_infra) ~ "Infraestrutura",
      str_detect(label, pat_frota) ~ "Frota",
      TRUE ~ categoria
    ),
    categoria = if_else(
      !is.na(modal) & modal == "Pedestres",
      "Infraestrutura",
      categoria
    ),
    label = if_else(
      str_detect(label, "^Informações sobre"),
      str_glue("Existe informação sobre pontualidade e regularidade ({modal})"),
      label
    ),
    categoria = if_else(
      label == "Valor Arrecadado com Cobrança de Estacionamento",
      "Arrecadação",
      categoria
    ),
    subcategoria = if_else(
      label == "Valor Arrecadado com Cobrança de Estacionamento",
      "Tributos",
      subcategoria
    ),
    subcategoria = if_else(
      code_variable %in% c("3.1.1.A", "3.1.1.B"),
      "Valores",
      subcategoria
    ),
    subcategoria = if_else(
      code_variable %in%
        c("3.5.1.A", "3.5.1.B", "3.5.1.C", "3.5.1.D", "3.5.1.E"),
      "Subsídios",
      subcategoria
    ),
    subcategoria = if_else(
      categoria == "Tarifas" & modal %in% c("Mototáxi", "Táxi"),
      "Bandeira",
      subcategoria
    ),
    label = if_else(
      categoria == "Receita" & !is.na(subcategoria),
      str_replace(label, "(?<=\\()[^)]+(?=\\))", subcategoria),
      label
    ),
    label = if_else(
      categoria == "Custos",
      str_replace(label, "Percentual dos Custos", "Custos (%)"),
      label
    ),
    label = if_else(
      categoria == "Custos",
      str_replace(label, "(?<=\\()[^)]+(?=\\))", subcategoria),
      label
    ),
    label = if_else(
      categoria == "Demanda",
      str_replace(label, "Ônibus", subcategoria),
      label
    ),
    subcategoria = if_else(
      code_variable == "9.1.4",
      "Multas",
      subcategoria
    ),
    subcategoria = if_else(
      code_variable == "9.1.2",
      "Trabalhadores",
      subcategoria
    ),
    subcategoria = if_else(
      code_variable == "9.1.3",
      "Equipamentos",
      subcategoria
    )
  ) |>
  filter(
    !code_variable %in% rm_variables
  )

code_outros <- c("2.5.1", "4.1.1", "4.1.1.A", "4.1.2", "4.3.1", "8.1.1")

dim_category <- dim_category |>
  mutate(
    categoria = if_else(
      str_detect(label, "^POD") | code_variable %in% code_outros,
      "Outros",
      categoria
    ),
    subcategoria = case_when(
      categoria == "Outros" & str_detect(label, "^POD") ~ "Origem e Destino",
      categoria == "Outros" & code_variable %in% code_outros ~
        "Governança e Leis",
      TRUE ~ subcategoria
    )
  )

export_category <- dim_category |>
  filter(!is.na(subcategoria)) |>
  select(
    code_variable,
    label,
    categoria,
    subcategoria
  )

export_category <- export_category |>
  select(categoria, subcategoria, label)

readr::write_csv(export_category, here("data", "portal", "dim_category.csv"))

dct <- dim_category |>
  select(
    code_variable,
    label,
    categoria,
    subcategoria,
    modal
  )

dpt <- pemob_dict |>
  select(
    code_variable,
    name_variable,
    label_pergunta,
    tipo,
    is_dashboard,
    is_portal,
    is_average,
    is_percentage,
    is_absolute
  )

dict_portal <- left_join(dpt, dct, by = "code_variable")

readr::write_csv(dict_portal, here("data", "portal", "dict_portal_parcial.csv"))


# 9.1.2
# 9.1.3

dim_category |>
  filter(str_detect(label, "^POD"))


# dim_category |>
#   filter(str_detect(label, "(^Planilha de Custos)|(^Impostos Incidentes)")) |>
#   pull(code_variable) |>
#   dput()

# Remove 3.3.1.A

dim_category |>
  filter(categoria == "missing") |>
  View()


View(dict_tabela)

swap_names <- c(
  "CÓDIGO" = "code_muni",
  "UF" = "abbrev_state",
  "Município" = "name_muni",
  "label" = "label",
  "valor" = "value",
  "pergunta" = "label_pergunta"
)

portal <- pemob |>
  left_join(dict_tabela, by = "code_variable") |>
  # Depois remover o filtro de ano
  filter(is_portal == 1 | is_dashboard == 1, year == 2024) |>
  select(code_muni, name_muni, abbrev_state, value, label, label_pergunta)

# Acertar o formato primeiro

as_numeric_comma <- function(x) {
  stopifnot(is.character(x))
  return(as.numeric(gsub(",", ".", x)))
}

portal <- pemob |>
  left_join(dict_tabela, by = "code_variable") |>
  mutate(
    value = as_numeric_comma(value),
    value = if_else(is_percentage == 1, value * 100, value)
  ) |>
  # Depois remover o filtro de ano
  filter(is_portal == 1 | is_dashboard == 1, year == 2024) |>
  select(code_muni, name_muni, abbrev_state, label, value, label_pergunta)

head(portal_dashboard)

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

portal


# portal |>
#   summarise(
#     count = n(),
#     filled = sum(is.na(value)),
#     .by = "code_muni"
#   ) |>
#   arrange(desc(filled)) |>
#   pull(code_muni)

pemob |>
  left_join(dict_tabela, by = "code_variable") |>
  filter(is_portal == 1 | is_dashboard == 1) |>
  readr::write_csv(here("data", "pemob_portal_teste.csv"))

test <- pemob |>
  filter(code_question %in% c("7.1.1", "7.2.1")) |>
  left_join(dim_questions, by = "code_variable") |>
  filter(is_portal == 1 | is_dashboard == 1) |>
  mutate(
    modal = str_extract(label_pergunta, paste0(modais, collapse = "|")),
    modal = if_else(
      is.na(modal),
      str_extract(label, paste0(str_to_title(modais), collapse = "|")),
      modal
    ),
    modal = str_to_lower(modal)
  ) |>
  mutate(
    value = as.numeric(str_replace(value, ",", "."))
  ) |>
  filter(modal == "ônibus")

library(ggplot2)

ggplot(subset(test, year == 2024), aes(x = label, y = value)) +
  geom_point() +
  coord_flip() +
  scale_x_discrete(labels = \(x) str_wrap(x, 13))
