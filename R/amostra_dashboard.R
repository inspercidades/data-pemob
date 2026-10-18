library(dplyr)
library(tidyr)
library(ggplot2)
library(ggiraph)
library(showtext)
import::from(here, here)
library(stringr)

# Load Google font
font_add_google("Lato", "Lato")
showtext_auto()

# The actual data
pemob <- readxl::read_excel(
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
  mutate(value_num = as.numeric(str_replace(value, ",", ".")))

question_stats <- pemob |>
  filter(year == max(year)) |>
  summarise(
    filled = sum(!is.na(value)),
    total = n(),
    .by = c("code_variable")
  ) |>
  mutate(percent = filled / total)

path_tables <- here("data", "portal", "final", "pemob_tables.rds")
dashboard <- readr::read_rds(path_tables)
names(dashboard) <- c("share", "max", "per_capita")

tbl_shares <- dashboard[["share"]]
tbl_max <- dashboard[["max"]]
tbl_per_capita <- dashboard[["per_capita"]]

tbl_dashboard <- bind_rows(tbl_shares, tbl_max, tbl_per_capita)

count_questions <- pemob |>
  filter(year == max(year)) |>
  select(code_variable, code_muni, year) |>
  left_join(question_stats) |>
  filter(code_variable %in% unique(tbl_dashboard$code_variable)) |>
  distinct(code_variable, filled) |>
  arrange(desc(filled))

get_top_questions <- function(dat, n = 5) {
  questions <- dat |>
    filter(year == max(year)) |>
    left_join(count_questions) |>
    select(code_variable, filled) |>
    distinct() |>
    slice_max(filled, n = n) |>
    pull(code_variable)

  return(questions)
}

get_random_cities <- function(n = 5) {
  return(sample(unique(tbl_dashboard$code_muni), n))
}

get_top_cities <- function(n = 5) {
  cities <- tbl_dashboard |>
    filter(year == max(year)) |>
    mutate(is_filled = if_else(!is.na(value_num), 1L, 0L)) |>
    summarise(
      filled = sum(is_filled),
      .by = c("code_muni", "name_muni", "abbrev_state")
    ) |>
    slice_max(filled, n = n) |>
    pull(code_muni)

  return(cities)
}

year_input <- 2024
sel_questions <- get_top_questions(tbl_per_capita, n = 6)
cities <- get_top_cities(n = 5)

tab <- tbl_per_capita |>
  filter(year == local(year_input), code_variable %in% local(sel_questions)) |>
  mutate(
    highlight = factor(if_else(code_muni %in% cities, name_muni, NA_character_))
  )

# fmt: skip
p_per_capita <- ggplot(tab, aes(x = value_scaled, y = label, color = highlight)) +
  geom_point_interactive(
    data = filter(tab, is.na(highlight)),
    aes(
      tooltip = paste0(
        "<b>", name_muni, " - ", abbrev_state, "</b><br>",
        "Valor: ", round(value_num, 2), "<br>",
        "Valor por 10.000 hab.: ", round(value_pop_scaled * 10000, 0), "<br>",
        "Percentual do máximo: ", round(value_scaled, 1), "%"
      ),
      data_id = code_muni
    ),
    size = 2
  ) +
  geom_point_interactive(
    data = filter(tab, !is.na(highlight)),
    aes(
      tooltip = paste0(
        "<b>", name_muni, " - ", abbrev_state, "</b><br>",
        "Valor (original): ", round(value_num, 2), "<br>",
        "Valor por 10.000 hab.: ", round(value_pop_scaled * 10000, 0), "<br>",
        "Percentual do máximo: ", round(value_scaled, 1), "%"
      ),
      data_id = code_muni
    ),
    size = 3
  ) +
  scale_y_discrete(labels = \(x) str_wrap(x, 21)) +
  scale_color_manual(
    values = MetBrewer::met.brewer("Hokusai1", 5),
    na.value = "gray80"
  ) +
  theme_minimal() +
  theme(
    legend.position = "bottom",
    text = element_text(family = "Lato"),
    plot.title = element_text(family = "Lato"),
    axis.text = element_text(family = "Lato"),
    legend.text = element_text(family = "Lato")
  ) +
  labs(
    x = "Valor escalado (%)",
    y = NULL,
    color = "Municípios destacados"
  )

# Render interactive plot
girafe(
  ggobj = p_per_capita,
  width_svg = 8,
  height_svg = 6,
  options = list(
    opts_hover(css = "fill:#FF6B6B;stroke:#FF6B6B;r:5pt;"),
    opts_tooltip(
      css = "background-color:#333333;color:white;padding:10px;border-radius:5px;font-family:Lato,sans-serif;",
      opacity = 0.9
    ),
    opts_zoom(max = 3)
  )
)


# test visualization

year_input <- 2024
cities <- sample(unique(tbl_max$code_muni), 5)
sel_questions <- get_top_questions(tbl_max, n = 6)

tab_max <- tbl_max |>
  filter(year == year_input, code_variable %in% sel_questions) |>
  mutate(
    highlight = factor(if_else(code_muni %in% cities, name_muni, NA_character_))
  ) |>
  mutate(
    scale_01 = (value_num - min(value_num)) / (max(value_num) - min(value_num)),
    .by = "code_variable"
  )

# fmt: skip
p_scaled_max <- ggplot(
  tab_max,
  aes(x = value_scaled, y = label, color = highlight)
) +
  geom_point_interactive(
    data = filter(tab_max, is.na(highlight)),
    aes(
      tooltip = paste0(
        "<b>",
        name_muni,
        " - ",
        abbrev_state,
        "</b><br>",
        "Valor: ",
        round(value_num, 2),
        "<br>",
        "Percentual do máximo: ",
        round(value_scaled, 1),
        "%"
      ),
      data_id = code_muni
    ),
    size = 2
  ) +
  geom_point_interactive(
    data = filter(tab_max, !is.na(highlight)),
    aes(
      tooltip = paste0(
        "<b>",
        name_muni,
        " - ",
        abbrev_state,
        "</b><br>",
        "Valor: ",
        round(value_num, 2),
        "<br>",
        "Percentual do máximo: ",
        round(value_scaled, 1),
        "%"
      ),
      data_id = code_muni
    ),
    size = 3
  ) +
  scale_y_discrete(labels = \(x) str_wrap(x, 21)) +
  scale_color_manual(
    values = MetBrewer::met.brewer("Hokusai1", 5),
    na.value = "gray80"
  ) +
  theme_minimal() +
  theme(
    legend.position = "bottom",
    text = element_text(family = "Lato"),
    plot.title = element_text(family = "Lato"),
    axis.text = element_text(family = "Lato"),
    legend.text = element_text(family = "Lato")
  ) +
  labs(
    x = "Valor escalado (%)",
    y = NULL,
    color = "Municípios destacados"
  )

girafe(
  ggobj = p_scaled_max,
  width_svg = 8,
  height_svg = 6,
  options = list(
    opts_hover(css = "stroke:#333333;r:4pt;opacity:0.8;"),
    opts_tooltip(
      css = "background-color:#333333;color:white;padding:10px;border-radius:5px;font-family:Lato,sans-serif;",
      opacity = 0.9
    ),
    opts_zoom(max = 3)
  )
)

p_scaled_01 <- ggplot(
  tab_max,
  aes(x = scale_01, y = label, color = highlight)
) +
  geom_point_interactive(
    data = filter(tab_max, is.na(highlight)),
    aes(
      tooltip = paste0(
        "<b>",
        name_muni,
        " - ",
        abbrev_state,
        "</b><br>",
        "Valor: ",
        round(value_num, 2),
        "<br>",
        "Percentual do máximo: ",
        round(scale_01, 1),
        "%"
      ),
      data_id = code_muni
    ),
    size = 2
  ) +
  geom_point_interactive(
    data = filter(tab_max, !is.na(highlight)),
    aes(
      tooltip = paste0(
        "<b>",
        name_muni,
        " - ",
        abbrev_state,
        "</b><br>",
        "Valor: ",
        round(value_num, 2),
        "<br>",
        "Percentual do máximo: ",
        round(scale_01, 1),
        "%"
      ),
      data_id = code_muni
    ),
    size = 3
  ) +
  scale_y_discrete(labels = \(x) str_wrap(x, 21)) +
  scale_color_manual(
    values = MetBrewer::met.brewer("Hokusai1", 5),
    na.value = "gray80"
  ) +
  theme_minimal() +
  theme(
    legend.position = "bottom",
    text = element_text(family = "Lato"),
    plot.title = element_text(family = "Lato"),
    axis.text = element_text(family = "Lato"),
    legend.text = element_text(family = "Lato")
  ) +
  labs(
    x = "Valor escalado (%)",
    y = NULL,
    color = "Municípios destacados"
  )

girafe(
  ggobj = p_scaled_01,
  width_svg = 8,
  height_svg = 6,
  options = list(
    opts_hover(css = "stroke:#333333;r:4pt;opacity:0.8;"),
    opts_tooltip(
      css = "background-color:#333333;color:white;padding:10px;border-radius:5px;font-family:Lato,sans-serif;",
      opacity = 0.9
    ),
    opts_zoom(max = 3)
  )
)

# share
year_input <- 2024
sel_questions <- get_top_questions(tbl_shares, n = 6)

tab_share <- tbl_shares |>
  filter(year == year_input, code_variable %in% sel_questions) |>
  mutate(
    highlight = factor(if_else(code_muni %in% cities, name_muni, NA_character_))
  )

# fmt: skip
p_share <- ggplot(
  tab_share,
  aes(x = value_scaled, y = label, color = highlight)
) +
  geom_point_interactive(
    data = filter(tab_share, is.na(highlight)),
    aes(
      tooltip = paste0("<b>", name_muni," - ", abbrev_state, "</b><br>",
        "Percentual: ", round(value_scaled, 1), "%", "<br>",
        "Valor absoluto: ", value_num
      ),
      data_id = code_muni
    ),
    size = 2
  ) +
  geom_point_interactive(
    data = filter(tab_share, !is.na(highlight)),
    aes(
      tooltip = paste0("<b>", name_muni," - ", abbrev_state, "</b><br>",
        "Valor: ", round(value_scaled, 1), "%", "<br>",
        "Valor absoluto: ", value_num
      ),
      data_id = code_muni
    ),
    size = 3
  ) +
  scale_x_continuous(limits = c(0, 100)) +
  scale_y_discrete(labels = \(x) str_wrap(x, 21)) +
  scale_color_manual(
    values = MetBrewer::met.brewer("Hokusai1", 5),
    na.value = "gray80"
  ) +
  theme_minimal() +
  theme(
    legend.position = "bottom",
    text = element_text(family = "Lato"),
    plot.title = element_text(family = "Lato"),
    axis.text = element_text(family = "Lato"),
    legend.text = element_text(family = "Lato")
  ) +
  labs(
    x = "Percentual (%)",
    y = NULL,
    color = "Municípios destacados"
  )

girafe(
  ggobj = p_share,
  width_svg = 8,
  height_svg = 6,
  options = list(
    opts_hover(css = "stroke:#333333;r:4pt;opacity:0.8;"),
    opts_tooltip(
      css = "background-color:#333333;color:white;padding:10px;border-radius:5px;font-family:Lato,sans-serif;",
      opacity = 0.9
    ),
    opts_zoom(max = 3)
  )
)
