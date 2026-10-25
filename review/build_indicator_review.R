# Build the PEMOB indicator review table (prototype) --------------------------
#
# Level-specific question tables feed format_indicator_review.py,
# which writes the Excel review workbook.

library(readr)
library(dplyr)
library(tidyr)
library(purrr)
library(stringr)

# Inputs ----------------------------------------------------------------------

long <- read_csv(
  here::here("data/dataverse_draft/municipal_long.csv"),
  show_col_types = FALSE,
  guess_max = 1e6
)
codebook <- read_csv(
  here::here("data/dataverse_draft/codebook.csv"),
  show_col_types = FALSE
) |>
  filter(level == "municipal")
dict <- read_csv(
  here::here("data/dict_portal_pemob.csv"),
  show_col_types = FALSE
)
registry <- read_csv(
  here::here("data/registry/pemob_questions.csv"),
  show_col_types = FALSE
) |>
  filter(level == "municipal")

site_snapshot <- read_csv(
  here::here("review/site_labels_snapshot.csv"),
  show_col_types = FALSE
)

# The site snapshots were captured from the Observatório source commit
# recorded in README.md. This builder needs only committed project inputs.
live_by_year <- read_csv(
  here::here("review/site_live_by_year.csv"),
  show_col_types = FALSE
)

live <- live_by_year |>
  distinct(label, question, is_dashboard)

# Years as compact runs: 2019, 2021-2025.
collapse_years <- function(years) {
  years <- sort(unique(years))
  runs <- split(years, cumsum(c(1, diff(years) != 1)))
  map_chr(runs, \(run) {
    if (length(run) == 1) {
      as.character(run)
    } else {
      str_glue("{min(run)}-{max(run)}")
    }
  }) |>
    paste(collapse = ", ")
}

# Live site status per code ---------------------------------------------------

# Match live items to codes by question text (any edition), then by the
# registry label. dict_portal labels repeat across codes, so they are not
# used for matching.
normalize <- function(x) str_to_lower(str_squish(x))

codebook_questions <- codebook |>
  distinct(code_variable, question_key = normalize(question_text))

by_question <- live |>
  mutate(question_key = normalize(question)) |>
  inner_join(codebook_questions, by = "question_key")

by_label <- live |>
  anti_join(by_question, by = c("label", "question")) |>
  inner_join(select(registry, code_variable, label), by = "label")

live_map <- bind_rows(by_question, by_label) |>
  distinct(code_variable, label, question)

live_unmatched <- live |>
  anti_join(live_map, by = c("label", "question"))

# Both pages read only items flagged is_dashboard. The dashboard lists an
# item in a year when it has a label and some city has a nonzero value.
# The table lists the options in filter-categories.ts and shows values only
# for is_dashboard items with the same label.
menu_options <- site_snapshot |>
  filter(evidence_kind == "live_menu_option") |>
  distinct(label)

site_years <- live_by_year |>
  inner_join(live_map, by = c("label", "question")) |>
  mutate(
    on_dashboard = is_dashboard & !is.na(label) & has_nonzero,
    in_menu = label %in% menu_options$label,
    table_data = in_menu & is_dashboard & has_value
  )

collapse_site_years <- function(years) {
  if (length(years) == 0) NA_character_ else collapse_years(years)
}

live_codes <- site_years |>
  summarise(
    dashboard_years = collapse_site_years(year[on_dashboard]),
    table_years = collapse_site_years(year[table_data]),
    in_menu = any(in_menu),
    live_label = paste(unique(na.omit(label)), collapse = " | "),
    .by = code_variable
  ) |>
  mutate(
    dashboard_pemob = if_else(!is.na(dashboard_years), "sim", "não"),
    tabela_pemob = case_when(
      !is.na(table_years) ~ "sim",
      in_menu ~ "no menu, sem dados",
      .default = "não"
    ),
    live_label = na_if(live_label, "")
  )

# Menu options with no site data still appear in the table menu. They map
# to codes through the registry label.
menu_codes <- menu_options |>
  inner_join(select(registry, code_variable, label), by = "label") |>
  distinct(code_variable) |>
  mutate(in_menu_registry = TRUE)

menu_unmatched <- menu_options |>
  filter(
    !label %in% live_map$label,
    !label %in% registry$label
  )

# Questions -------------------------------------------------------------------

# Editions embed the reference year in the text ("em 2024"), so years are
# masked before counting distinct wordings. Only 2021+ editions count: the
# 2019 codebook holds short column headers and 2020 holds no text.
wording_key <- function(x) {
  x |>
    normalize() |>
    str_replace_all("\\b(19|20)\\d{2}\\b", "<ano>") |>
    str_remove_all("[[:punct:]]") |>
    str_squish()
}

questions <- codebook |>
  arrange(code_variable, desc(year)) |>
  summarise(
    full_question = first(question_text),
    question_wording_versions = n_distinct(
      wording_key(question_text[year >= 2021]),
      na.rm = TRUE
    ),
    .by = code_variable
  )

# Coverage --------------------------------------------------------------------

# A city covers a question in a year when it gave a parseable answer
# (not blank, NR, ND, or similar). Imputed values do not count.
answered <- long |>
  filter(participated, parse_status != "missing")

participants <- long |>
  filter(participated) |>
  distinct(year, code_muni) |>
  count(year, name = "participants")

coverage_by_year <- answered |>
  distinct(code_variable, year, code_muni) |>
  count(code_variable, year, name = "cities")


# Zero often means the city lacks the mode, so numeric questions also get a
# count of cities that reported a positive value.
coverage <- answered |>
  summarise(
    coverage_cities = n_distinct(code_muni),
    coverage_cities_positive = n_distinct(code_muni[which(value_num > 0)]),
    coverage_years = collapse_years(year),
    n_years = n_distinct(year),
    .by = code_variable
  )

# Quality ---------------------------------------------------------------------

# Response rate: valid answers over participating cities, in each edition
# that asked the question.
response <- codebook |>
  distinct(code_variable, year) |>
  inner_join(participants, by = "year") |>
  left_join(coverage_by_year, by = c("code_variable", "year")) |>
  mutate(rate = replace_na(cities, 0L) / participants) |>
  summarise(
    response_rate_mean = mean(rate),
    response_rate_latest = last(rate, order_by = year),
    .by = code_variable
  )

# Panel depth: cities with valid answers in four or more editions, and in
# every edition from 2021 to 2025 (the full-questionnaire editions).
panel_years <- 2021:2025

panel <- answered |>
  distinct(code_variable, code_muni, year) |>
  summarise(
    n_editions = n(),
    full_panel = all(panel_years %in% year),
    .by = c(code_variable, code_muni)
  ) |>
  summarise(
    panel_cities = sum(n_editions >= 4),
    panel_cities_full = sum(full_panel),
    .by = code_variable
  )

# Upper bounds for the panel columns: cities that took part in the survey.
panel_bounds <- long |>
  filter(participated) |>
  distinct(code_muni, year) |>
  summarise(
    n_editions = n(),
    full_panel = all(panel_years %in% year),
    .by = code_muni
  ) |>
  summarise(
    participated_4_plus = sum(n_editions >= 4),
    participated_2021_2025 = sum(full_panel)
  )

n_answers <- answered |>
  count(code_variable, name = "n_answers")

# Numeric checks on valid answers. Each city's answer is compared with its
# previous valid answer, which may skip an edition.
jump_ratio <- 3

numeric_codes <- dict |>
  filter(tipo == "numeric") |>
  pull(code_variable)

numeric_answers <- answered |>
  filter(code_variable %in% numeric_codes) |>
  arrange(code_variable, code_muni, year) |>
  mutate(
    previous = lag(value_num),
    previous_year = lag(year),
    .by = c(code_variable, code_muni)
  ) |>
  mutate(
    both_positive = previous > 0 & value_num > 0,
    ratio = value_num / previous
  )

numeric_quality <- numeric_answers |>
  summarise(
    unparsed_share = mean(is.na(value_num)),
    zero_share = sum(value_num == 0, na.rm = TRUE) / n(),
    jump_share = mean(
      ratio[which(both_positive)] > jump_ratio |
        ratio[which(both_positive)] < 1 / jump_ratio
    ),
    repeat_share = mean(ratio[which(both_positive)] == 1),
    n_pairs = sum(both_positive, na.rm = TRUE),
    fraction_share = mean(value_num[which(value_num > 0)] <= 1),
    .by = code_variable
  ) |>
  mutate(
    across(c(jump_share, repeat_share), \(x) if_else(n_pairs < 5, NA, x)),
    across(where(is.double), \(x) if_else(is.nan(x), NA, x))
  )

# Edition breaks: the median city-level change between consecutive editions
# is at least twofold, which points to a change in unit or scale rather than
# in the cities themselves. Needs five cities answering both editions.
edition_breaks <- numeric_answers |>
  filter(both_positive %in% TRUE, year - previous_year <= 2) |>
  summarise(
    median_ratio = median(ratio),
    n_cities = n(),
    .by = c(code_variable, year)
  ) |>
  filter(n_cities >= 5, median_ratio >= 2 | median_ratio <= 1 / 2) |>
  summarise(
    edition_breaks = paste(sort(year), collapse = ", "),
    .by = code_variable
  )

# Flags summarise the metrics in plain words. Thresholds are deliberately
# sensitive: a flag asks for a look, it does not exclude a question.
# Repeated values are suspicious only for annual flows (costs, revenue,
# passengers); stocks and rates often stay fixed for good reason.
# Percent questions answered both as 0.95 and as 95 get a scale flag.
flow_subjects <- c("Custos", "Receita", "Demanda")
rate_pattern <- regex(
  "al[íi]quota|percentual|porcentagem|%",
  ignore_case = TRUE
)

flag_quality <- function(
  subject,
  full_question,
  n_years,
  response_rate_mean,
  panel_cities,
  zero_share,
  unparsed_share,
  jump_share,
  repeat_share,
  fraction_share,
  edition_breaks,
  wording_versions
) {
  is_rate <- str_detect(full_question, rate_pattern)
  flags <- list(
    if_else(n_years <= 3, "poucas edições", NA),
    if_else(response_rate_mean < 0.3, "baixa resposta", NA),
    if_else(panel_cities < 20, "série curta", NA),
    if_else(zero_share > 0.3, "muitos zeros", NA),
    if_else(unparsed_share > 0.05, "respostas não numéricas", NA),
    if_else(jump_share > 0.1, "saltos frequentes", NA),
    if_else(
      subject %in% flow_subjects & !is_rate & repeat_share > 0.2,
      "valores repetidos",
      NA
    ),
    if_else(
      is_rate & between(fraction_share, 0.05, 0.95),
      "escala de % mista",
      NA
    ),
    if_else(
      !is.na(edition_breaks),
      str_glue("quebra entre edições ({edition_breaks})"),
      NA
    ),
    if_else(wording_versions > 1, "enunciado mudou", NA)
  )
  pmap_chr(flags, \(...) {
    found <- discard(c(...), is.na)
    if (length(found) == 0) NA_character_ else paste(found, collapse = "; ")
  })
}

coverage_wide <- coverage_by_year |>
  arrange(year) |>
  pivot_wider(
    names_from = year,
    values_from = cities,
    names_prefix = "cities_",
    values_fill = 0
  )

# Labels ----------------------------------------------------------------------

# Column names shown in the workbook: internal name = label.
column_labels <- c(
  code = "Código",
  short_question = "Pergunta resumida",
  full_question = "Pergunta completa",
  subject = "Tema",
  coverage_cities = "Cidades com resposta",
  coverage_years = "Anos com resposta",
  quality_flags = "Alertas de qualidade",
  interest = "Interesse",
  checklist = "Incluir?",
  notes = "Notas",
  panel_cities = "Cidades com 4+ edições",
  panel_cities_full = "Cidades em todas de 2021 a 2025",
  jump_share = "Saltos bruscos",
  edition_breaks = "Quebras entre edições",
  response_rate_mean = "Taxa de resposta média",
  response_rate_latest = "Taxa de resposta na última edição",
  n_answers = "Respostas válidas",
  coverage_cities_positive = "Cidades com valor positivo",
  zero_share = "Respostas iguais a zero",
  unparsed_share = "Respostas não numéricas",
  repeat_share = "Valores repetidos",
  topic = "Subtema",
  type = "Tipo de resposta",
  dashboard_pemob = "No dashboard",
  dashboard_years = "Anos no dashboard",
  tabela_pemob = "Na tabela",
  table_years = "Anos na tabela",
  live_label = "Rótulo no site",
  n_years = "Edições com resposta",
  question_wording_versions = "Versões do enunciado",
  cities_2019 = "2019",
  cities_2020 = "2020",
  cities_2021 = "2021",
  cities_2022 = "2022",
  cities_2023 = "2023",
  cities_2024 = "2024",
  cities_2025 = "2025"
)

type_labels <- c(
  numeric = "número",
  text = "texto",
  binary = "sim/não",
  date = "data"
)

column_definitions <- c(
  code = "Código da pergunta na PEMOB, harmonizado entre edições.",
  short_question = "Rótulo do registro de perguntas. Sem rótulo no registro, usa o rótulo do site.",
  full_question = "Texto da pergunta na edição mais recente que a fez.",
  subject = "Categoria do registro, a mesma do menu do site.",
  coverage_cities = "Municípios com ao menos uma resposta válida em qualquer edição. Em branco, NR, ND e códigos parecidos não contam; valores imputados também não.",
  coverage_years = "Edições com ao menos uma resposta válida.",
  quality_flags = "Problemas apontados pelas métricas à direita. Os limites são sensíveis de propósito: o alerta pede uma olhada e nunca exclui a pergunta. Poucas edições: 3 ou menos. Baixa resposta: taxa média abaixo de 30%. Série curta: menos de 20 cidades com 4 ou mais edições. Muitos zeros: mais de 30% das respostas. Respostas não numéricas: mais de 5% das respostas a uma pergunta numérica são texto. Saltos frequentes: mais de 10% das respostas consecutivas de uma cidade mudam 3 vezes ou mais. Valores repetidos: mais de 20% das respostas consecutivas idênticas, só em custos, receita e demanda, sem contar taxas. Escala de % mista: pergunta percentual respondida ora como 0,45, ora como 45. Quebra entre edições: ver a coluna própria. Enunciado mudou: ver Versões do enunciado.",
  interest = "Avaliação do revisor: quão útil a pergunta é para nossos objetivos (alta, média ou baixa).",
  checklist = "Decisão do revisor: incluir a pergunta nos produtos finais (sim ou não).",
  notes = "Observações livres do revisor.",
  panel_cities = "Municípios com resposta válida em 4 ou mais edições. O limite máximo está na aba participação.",
  panel_cities_full = "Municípios com resposta válida em todas as edições de 2021 a 2025. O limite máximo está na aba participação.",
  jump_share = "Só perguntas numéricas: parcela das respostas consecutivas positivas de uma cidade que mudam 3 vezes ou mais. Valores altos sugerem erro de unidade ou escala. Fica vazia com menos de 5 pares.",
  edition_breaks = "Só perguntas numéricas: edições em que o valor da cidade mediana dobrou ou caiu à metade em relação à resposta anterior, com ao menos 5 cidades. Sugere mudança de unidade ou escala. Uma quebra em 2021 também pode refletir a pandemia.",
  response_rate_mean = "Respostas válidas divididas pelos municípios participantes, em média nas edições que fizeram a pergunta.",
  response_rate_latest = "A mesma taxa na edição mais recente que fez a pergunta.",
  n_answers = "Respostas válidas, contadas por cidade e edição. A aba lista as perguntas com ao menos duas.",
  coverage_cities_positive = "Só perguntas numéricas: municípios que informaram valor acima de zero. Um número baixo ao lado de muitas cidades com resposta indica que a maioria respondeu zero.",
  zero_share = "Só perguntas numéricas: parcela das respostas válidas iguais a zero. Zero costuma indicar que a cidade não tem o serviço.",
  unparsed_share = "Só perguntas numéricas: parcela das respostas em texto, não em número.",
  repeat_share = "Só perguntas numéricas: parcela das respostas consecutivas positivas de uma cidade que se repetem. Em fluxos anuais, sugere valor copiado. Fica vazia com menos de 5 pares.",
  topic = "Subcategoria do registro, em geral o modo de transporte.",
  type = "Tipo de resposta segundo o dicionário do portal.",
  dashboard_pemob = "Se a pergunta aparece no snapshot de 2019 a 2024 do dashboard da PEMOB (observatorio.insper.edu.br/projetos/dashboard), obtido do commit 28d2cd8. O dashboard lista uma pergunta num ano quando ela está marcada para exibição, tem rótulo e ao menos uma cidade com valor diferente de zero.",
  dashboard_years = "Edições em que a pergunta aparece no dashboard.",
  tabela_pemob = "Se a pergunta aparece no snapshot de 2019 a 2024 da tabela da PEMOB (observatorio.insper.edu.br/projetos/tabela), obtido do commit 28d2cd8. Sim: está no menu e mostra valores. No menu, sem dados: está no menu, mas a tabela fica vazia porque a pergunta não está marcada para exibição. Não: fora do menu.",
  table_years = "Edições em que a tabela mostra valores para a pergunta.",
  live_label = "Rótulo exibido no snapshot de 2019 a 2024 do site (commit 28d2cd8).",
  n_years = "Número de edições com ao menos uma resposta válida.",
  question_wording_versions = "Enunciados distintos nas edições de 2021 a 2025, sem contar o ano de referência. Acima de 1, o texto mudou e a comparabilidade precisa ser conferida. 2019 e 2020 ficam de fora porque o dicionário dessas edições traz só cabeçalhos curtos ou nenhum texto.",
  set_names(
    str_glue("Municípios com resposta válida em {2019:2025}."),
    str_glue("cities_{2019:2025}")
  )
)

# Review table ----------------------------------------------------------------

review <- questions |>
  left_join(
    select(
      registry,
      code_variable,
      registry_label = label,
      subject = category,
      topic = subcategory
    ),
    by = "code_variable"
  ) |>
  left_join(
    select(
      dict,
      code_variable,
      dict_subject = categoria,
      dict_topic = subcategoria,
      type = tipo
    ),
    by = "code_variable"
  ) |>
  left_join(coverage, by = "code_variable") |>
  left_join(live_codes, by = "code_variable") |>
  left_join(menu_codes, by = "code_variable") |>
  left_join(coverage_wide, by = "code_variable") |>
  left_join(response, by = "code_variable") |>
  left_join(panel, by = "code_variable") |>
  left_join(numeric_quality, by = "code_variable") |>
  left_join(edition_breaks, by = "code_variable") |>
  left_join(n_answers, by = "code_variable") |>
  mutate(
    across(c(panel_cities, panel_cities_full, n_answers), \(x) {
      replace_na(x, 0L)
    }),
    across(
      c(
        coverage_cities,
        coverage_cities_positive,
        n_years,
        starts_with("cities_")
      ),
      \(x) replace_na(x, 0L)
    ),
    coverage_years = replace_na(coverage_years, "none"),
    coverage_cities_positive = if_else(
      type == "numeric",
      coverage_cities_positive,
      NA_integer_
    ),
    dashboard_pemob = replace_na(dashboard_pemob, "não"),
    tabela_pemob = case_when(
      !is.na(tabela_pemob) & tabela_pemob != "não" ~ tabela_pemob,
      in_menu_registry %in% TRUE ~ "no menu, sem dados",
      .default = "não"
    ),
    short_question = coalesce(registry_label, live_label),
    subject = coalesce(subject, dict_subject),
    topic = coalesce(topic, dict_topic),
    code_sort = code_variable
  ) |>
  mutate(
    quality_flags = flag_quality(
      subject,
      full_question,
      n_years,
      response_rate_mean,
      panel_cities,
      zero_share,
      unparsed_share,
      jump_share,
      repeat_share,
      fraction_share,
      edition_breaks,
      question_wording_versions
    )
  ) |>
  separate_wider_delim(
    code_sort,
    delim = ".",
    names = c("s1", "s2", "s3", "s4"),
    too_few = "align_start",
    too_many = "merge"
  ) |>
  arrange(
    as.integer(s1),
    as.integer(s2),
    suppressWarnings(as.integer(s3)),
    s3,
    nchar(s4),
    s4
  ) |>
  mutate(
    type = recode_values(type, from = names(type_labels), to = type_labels),
    interest = NA_character_,
    checklist = NA_character_,
    notes = NA_character_
  ) |>
  select(
    code = code_variable,
    short_question,
    full_question,
    subject,
    topic,
    type,
    coverage_cities,
    coverage_years,
    n_years,
    coverage_cities_positive,
    quality_flags,
    interest,
    checklist,
    notes,
    panel_cities,
    panel_cities_full,
    jump_share,
    edition_breaks,
    response_rate_mean,
    response_rate_latest,
    n_answers,
    zero_share,
    unparsed_share,
    repeat_share,
    dashboard_pemob,
    dashboard_years,
    tabela_pemob,
    table_years,
    live_label,
    question_wording_versions,
    starts_with("cities_")
  )

# Data snapshot ---------------------------------------------------------------

# Every answer as reported, one row per city and edition once the workbook
# pivots it. Parsed numbers stay numeric (percents as fractions); yes/no and
# text answers, missing codes included, keep their raw text. Imputed values
# have no raw answer and stay out.
logical_answers <- c("SIM", "NÃO", "NAO", "TRUE", "FALSE")

snapshot <- long |>
  filter(participated, !is.na(value_raw)) |>
  mutate(
    is_number = parse_status == "parsed" &
      !str_to_upper(str_trim(value_raw)) %in% logical_answers,
    value = if_else(
      is_number,
      format(value_num, digits = 15, scientific = FALSE, trim = TRUE),
      value_raw
    ),
    code_order = match(code_variable, review$code)
  ) |>
  arrange(abbrev_state, place_name, year, code_order) |>
  select(
    name_city = place_name,
    abbrev_state,
    year,
    code_indicator = code_variable,
    value,
    is_number
  )

# First pass: questions with at least two valid answers.
min_answers <- 2

review_pass <- review |>
  filter(n_answers >= min_answers)

if (!setequal(names(review_pass), names(column_labels))) {
  cli::cli_abort("Every review column needs exactly one label.")
}

out_dir <- Sys.getenv("PEMOB_REVIEW_OUTPUT_DIR", unset = here::here("review"))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
write_csv(review_pass, file.path(out_dir, "indicator_review.csv"), na = "")
write_csv(participants, file.path(out_dir, "participants.csv"))
write_csv(panel_bounds, file.path(out_dir, "panel_bounds.csv"))
write_csv(live_unmatched, file.path(out_dir, "live_unmatched.csv"), na = "")
write_csv(
  tibble(
    from = names(column_labels),
    to = unname(column_labels),
    definition = unname(column_definitions[names(column_labels)])
  ),
  file.path(out_dir, "column_labels.csv")
)

write_csv(menu_unmatched, file.path(out_dir, "menu_unmatched.csv"), na = "")
write_csv(snapshot, file.path(out_dir, "snapshot_long.csv"), na = "")
write_csv(
  tibble(code_indicator = review$code),
  file.path(out_dir, "snapshot_codes.csv")
)

cli::cli_alert_success(
  "Wrote {nrow(review_pass)} of {nrow(review)} questions; \\
  {nrow(live_unmatched)} site items and {nrow(menu_unmatched)} menu \\
  options unmatched."
)

# Metropolitan questionnaire -------------------------------------------------

metro_long <- read_csv(
  here::here("data/dataverse_draft/metropolitan_long.csv"),
  show_col_types = FALSE,
  guess_max = 1e6
)
metro_codebook <- read_csv(
  here::here("data/dataverse_draft/codebook.csv"),
  show_col_types = FALSE
) |>
  filter(level == "metropolitan")

if (anyDuplicated(metro_long[c("place_key", "year", "code_variable")])) {
  cli::cli_abort(
    "Metropolitan answers have duplicate place, year, and code keys."
  )
}
if (anyDuplicated(metro_codebook[c("year", "code_variable")])) {
  cli::cli_abort("Metropolitan codebook has duplicate year and code keys.")
}

metro_years <- sort(unique(metro_codebook$year))
if (!setequal(metro_years, c(2019, 2021:2025)) || length(metro_years) != 6) {
  cli::cli_abort(
    "Metropolitan codebook editions differ from 2019 and 2021-2025."
  )
}

metro_questions <- metro_codebook |>
  arrange(code_variable, desc(year)) |>
  summarise(
    full_question = first(question_text),
    question_wording_versions = n_distinct(
      wording_key(question_text[year >= 2021]),
      na.rm = TRUE
    ),
    .by = code_variable
  )

metro_answered <- metro_long |>
  filter(participated, parse_status != "missing")
metro_participants <- metro_long |>
  filter(participated) |>
  distinct(year, place_key) |>
  count(year, name = "participants")
metro_coverage_by_year <- metro_answered |>
  distinct(code_variable, year, place_key) |>
  count(code_variable, year, name = "places")
metro_coverage <- metro_answered |>
  summarise(
    coverage_places = n_distinct(place_key),
    coverage_years = collapse_years(year),
    n_years = n_distinct(year),
    n_answers = n_distinct(paste(place_key, year, sep = "::")),
    .by = code_variable
  )

metro_response <- metro_codebook |>
  distinct(code_variable, year) |>
  inner_join(metro_participants, by = "year") |>
  left_join(metro_coverage_by_year, by = c("code_variable", "year")) |>
  mutate(rate = replace_na(places, 0L) / participants) |>
  summarise(
    response_rate_mean = mean(rate),
    response_rate_latest = last(rate, order_by = year),
    .by = code_variable
  )

metro_panel <- metro_answered |>
  distinct(code_variable, place_key, year) |>
  summarise(
    n_editions = n(),
    full_panel = all(panel_years %in% year),
    .by = c(code_variable, place_key)
  ) |>
  summarise(
    panel_places = sum(n_editions >= 4),
    panel_places_full = sum(full_panel),
    .by = code_variable
  )
metro_panel_bounds <- metro_long |>
  filter(participated) |>
  distinct(place_key, year) |>
  summarise(
    n_editions = n(),
    full_panel = all(panel_years %in% year),
    .by = place_key
  ) |>
  summarise(
    participated_4_plus = sum(n_editions >= 4),
    participated_2021_2025 = sum(full_panel)
  )
metro_coverage_wide <- metro_coverage_by_year |>
  arrange(year) |>
  pivot_wider(
    names_from = year,
    values_from = places,
    names_prefix = "places_",
    values_fill = 0
  )

# Metropolitan answer types are not reviewed across the full questionnaire.
# Numeric-only diagnostics remain blank rather than classifying raw answers.
metro_review <- metro_questions |>
  left_join(metro_coverage, by = "code_variable") |>
  left_join(metro_coverage_wide, by = "code_variable") |>
  left_join(metro_response, by = "code_variable") |>
  left_join(metro_panel, by = "code_variable") |>
  mutate(
    across(
      c(coverage_places, n_years, n_answers, panel_places, panel_places_full),
      \(x) replace_na(x, 0L)
    ),
    across(starts_with("places_"), \(x) replace_na(x, 0L)),
    coverage_years = replace_na(coverage_years, "none"),
    quality_flags = pmap_chr(
      list(
        n_years,
        response_rate_mean,
        panel_places,
        question_wording_versions
      ),
      \(editions, rate, panel, wordings) {
        flags <- c(
          if (editions <= 2) "poucas edições",
          if (!is.na(rate) && rate < 0.3) "baixa resposta",
          if (panel < 5) "série curta",
          if (wordings > 1) "enunciado mudou"
        )
        if (length(flags) == 0) NA_character_ else paste(flags, collapse = "; ")
      }
    ),
    coverage_places_positive = NA_integer_,
    jump_share = NA_real_,
    edition_breaks = NA_character_,
    zero_share = NA_real_,
    unparsed_share = NA_real_,
    repeat_share = NA_real_,
    interest = NA_character_,
    checklist = NA_character_,
    notes = NA_character_,
    code_sort = code_variable
  ) |>
  separate_wider_delim(
    code_sort,
    delim = ".",
    names = c("s1", "s2", "s3", "s4"),
    too_few = "align_start",
    too_many = "merge"
  ) |>
  arrange(
    as.integer(s1),
    as.integer(s2),
    suppressWarnings(as.integer(s3)),
    s3,
    nchar(s4),
    s4
  ) |>
  select(
    code = code_variable,
    full_question,
    coverage_places,
    coverage_years,
    n_years,
    coverage_places_positive,
    quality_flags,
    interest,
    checklist,
    notes,
    panel_places,
    panel_places_full,
    jump_share,
    edition_breaks,
    response_rate_mean,
    response_rate_latest,
    n_answers,
    zero_share,
    unparsed_share,
    repeat_share,
    question_wording_versions,
    starts_with("places_")
  )

metro_snapshot <- metro_long |>
  filter(participated, !is.na(value_raw)) |>
  mutate(
    is_number = parse_status == "parsed" &
      !str_to_upper(str_trim(value_raw)) %in% logical_answers,
    value = if_else(
      is_number,
      format(value_num, digits = 15, scientific = FALSE, trim = TRUE),
      value_raw
    ),
    code_order = match(code_variable, metro_review$code)
  ) |>
  arrange(abbrev_state, place_name, place_key, year, code_order) |>
  select(
    place_key,
    place_name,
    abbrev_state,
    year,
    code_indicator = code_variable,
    value,
    is_number
  )

metro_review_pass <- metro_review |>
  filter(n_answers >= min_answers)

municipal_diagnostics <- review_pass |>
  select(
    -short_question,
    -full_question,
    -subject,
    -topic,
    -type,
    -quality_flags,
    -interest,
    -checklist,
    -notes
  ) |>
  mutate(level = "municipal", .before = 1)
metro_diagnostics <- metro_review_pass |>
  select(-full_question, -quality_flags, -interest, -checklist, -notes) |>
  mutate(level = "metropolitan", .before = 1)
diagnostics <- bind_rows(municipal_diagnostics, metro_diagnostics)
if (anyDuplicated(diagnostics[c("level", "code")])) {
  cli::cli_abort("Indicator diagnostics have duplicate level and code keys.")
}

write_csv(
  metro_review_pass,
  file.path(out_dir, "indicator_review_metropolitan.csv"),
  na = ""
)
write_csv(
  metro_participants,
  file.path(out_dir, "participants_metropolitan.csv")
)
write_csv(
  metro_panel_bounds,
  file.path(out_dir, "panel_bounds_metropolitan.csv")
)
write_csv(
  metro_snapshot,
  file.path(out_dir, "snapshot_long_metropolitan.csv"),
  na = ""
)
write_csv(
  tibble(code_indicator = metro_review$code),
  file.path(out_dir, "snapshot_codes_metropolitan.csv")
)
write_csv(diagnostics, file.path(out_dir, "indicator_diagnostics.csv"), na = "")

metro_labels <- c(
  coverage_places = "Regiões com resposta",
  coverage_places_positive = "Regiões com valor positivo",
  panel_places = "Regiões com 4+ edições",
  panel_places_full = "Regiões em todas de 2021 a 2025",
  places_2019 = "2019",
  places_2021 = "2021",
  places_2022 = "2022",
  places_2023 = "2023",
  places_2024 = "2024",
  places_2025 = "2025"
)
metro_definitions <- c(
  coverage_places = "Regiões metropolitanas com ao menos uma resposta válida; respostas ausentes e imputadas não contam.",
  coverage_places_positive = "Não calculado: o tipo de resposta não foi revisado para a maioria das perguntas e edições metropolitanas.",
  panel_places = "Regiões com resposta válida em 4 ou mais edições da pergunta.",
  panel_places_full = "Regiões com resposta válida em todas as edições de 2021 a 2025.",
  set_names(
    str_glue("Regiões com resposta válida em {metro_years}."),
    str_glue("places_{metro_years}")
  )
)
extra_definitions <- tibble(
  from = names(metro_labels),
  to = unname(metro_labels),
  definition = unname(metro_definitions[names(metro_labels)])
)
metro_method_definitions <- tibble(
  from = c(
    "metro_quality_method",
    "metro_response_method",
    "metro_numeric_method"
  ),
  to = c(
    "Alertas da metropolitana",
    "Taxa de resposta metropolitana",
    "Métricas numéricas metropolitanas"
  ),
  definition = c(
    "Poucas edições: até 2 com resposta. Baixa resposta: média abaixo de 30%. Série curta: menos de 5 regiões com resposta em 4 ou mais edições. Enunciado mudou: mais de uma versão entre 2021 e 2025.",
    "Respostas válidas divididas pelas regiões participantes, em média apenas nas edições em que a pergunta foi feita (2019 e/ou 2021-2025). Não há edição metropolitana de 2020.",
    "As métricas de zero, valor positivo, saltos, repetição e respostas não numéricas ficam vazias até haver tipos de resposta revisados para as perguntas e edições metropolitanas avaliadas."
  )
)
read_csv(file.path(out_dir, "column_labels.csv"), show_col_types = FALSE) |>
  bind_rows(extra_definitions, metro_method_definitions) |>
  write_csv(file.path(out_dir, "column_labels.csv"))

cli::cli_alert_success(
  "Wrote {nrow(metro_review_pass)} of {nrow(metro_review)} metropolitan questions."
)
