# 18/09 - this is the most up to date version of this script

library(dplyr)
library(jsonlite)

path_tables <- here::here("data", "portal", "final", "pemob_tables.rds")
dashboard <- readr::read_rds(path_tables)
names(dashboard) <- c("share", "max", "per_capita")

tbl_shares <- dashboard[["share"]]
tbl_max <- dashboard[["max"]]
tbl_per_capita <- dashboard[["per_capita"]]

tbl_dashboard <- bind_rows(tbl_shares, tbl_max, tbl_per_capita)

tbl_dashboard <- tbl_dashboard |>
  mutate(
    value_num = if_else(
      desc_scaled == "per_capita",
      value_pop_scaled * 10000,
      value_num
    )
  )

pemob_portal <- tbl_dashboard |>
  select(
    code_muni,
    name_muni,
    abbrev_state,
    label,
    label_pergunta,
    value = value_num,
    value_scaled,
    desc_scaled,
    is_dashboard,
    year
  )

get_pemob_names <- function() {
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

  return(swap_names)
}

get_pemob_cols <- function() {
  sel_cols <- c(
    "code_muni",
    "name_muni",
    "abbrev_state",
    "label",
    "value",
    "label_pergunta",
    "is_dashboard",
    "desc_scaled",
    "value_scaled",
    "value",
    "year"
  )

  return(sel_cols)
}

export_pemob <- function(
  dat,
  y = 2023,
  outdir = here::here("data/portal/v1"),
  export = TRUE,
  print = FALSE
) {
  swap_names <- get_pemob_names()
  sel_cols <- get_pemob_cols()
  subpemob <- subset(dat, year == y)

  if (nrow(subpemob) == 0) {
    cli::cli_abort("No data for year {y}")
  }

  # Check if all columns are present
  missing_cols <- setdiff(sel_cols, names(subpemob))
  if (length(missing_cols) > 0) {
    cli::cli_abort("Missing columns: {paste(missing_cols, collapse = ', ')}")
  }

  data_portal <- subpemob |>
    dplyr::select(dplyr::all_of(sel_cols)) |>
    dplyr::group_by(code_muni, name_muni, abbrev_state) |>
    tidyr::nest() |>
    dplyr::rename(dplyr::any_of(swap_names))

  if (export) {
    # Check if directory exists
    if (!dir.exists(outdir)) {
      dir.create(outdir, recursive = TRUE)
    }

    # Export to JSON
    jsonlite::write_json(
      data_portal,
      here::here(outdir, glue::glue("pemob_{y}.json")),
      na = "null"
    )
  }

  if (print) {
    return(data_portal)
  } else {
    return(invisible(NULL))
  }
}

# Export for all years
purrr::walk(
  unique(tbl_dashboard$year),
  ~ export_pemob(pemob_portal, y = .x, outdir = here::here("data/portal/v1"))
)
