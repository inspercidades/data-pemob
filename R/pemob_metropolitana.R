library(readxl)
library(tidyverse)
library(cli)
import::from(here, here)
import::from(janitor, clean_names, make_clean_names)
source(here("R/pemob_helpers.R"))

header_to_dictionary <- function(x) {

  as_tibble(as.data.frame(t(as.matrix(x))))

}


# Data --------------------------------------------------------------------

## Dictionaries ------------------------------------------------------------

keydict <- read_excel(here("data-raw/pemob_códigos.xlsx"), sheet = "pemob_metropolitana")

keydict <- keydict |>
  clean_names() |>
  fill(c(bloco, secao))

keydict <- keydict |>
  rename(
    srv_block = bloco,
    srv_section = secao
  )

dict_insper <- read_excel(here("data-raw/Pemob_Renomeado_2024.xlsx"), skip = 3)

class_data <- read_excel(
  here("data-raw/Pemob_Renomeado_2024.xlsx"),
  range = "D1:NH4",
  col_names = FALSE,
  .name_repair = make_clean_names)

class_insper <- as_tibble(as.data.frame(t(as.matrix(class_data))))
names(class_insper) <- c("tema", "subtema", "variavel", "codigo_variavel")

## PEMOB data --------------------------------------------------------------

path_excel_files <- list.files(here("data-raw"), pattern = "\\.xlsx$", full.names = TRUE)

path_pemob <- path_excel_files[!str_detect(path_excel_files, "códigos|Renomeado")]

na_excel <- c("#REF!", "NR", "NA", "ND", "-")

vl_names <- c(
  "code_metro" = "Código IBGE",
  "code_metro" = "CÓDIGO IBGE",
  "code_metro" = "\r\n Código IBGE",
  "code_metro" = "CÓDIGO",
  "abbrev_state" = "\r\n UF",
  "abbrev_state" = "UF",
  "name_metro" = "RM/AU",
  "name_metro" = "REGIÃO METROPOLITANA",
  "name_metro" = "Região Metropolitana",
  "name_metro" = "REGIÃO"
)


# PEMOB -------------------------------------------------------------------

## 2019 --------------------------------------------------------------------

path_19 <- here("data-raw/Pemob2019_Metropolitana.xlsx")

pemob19 <- read_excel(path_19, skip = 1, na = na_excel)

pemob19 <- pemob19 |>
  rename(any_of(vl_names))

dict19 <- read_excel(path_19, range = "C1:LN2", col_names = FALSE, .name_repair = make_clean_names)
dict19 <- header_to_dictionary(dict19)
names(dict19) <- c("name_variable", "code_variable")

survey19 <- read_excel(path_19, sheet = 2, .name_repair = make_clean_names)
names(survey19) <- c("srv_block", "srv_block_name", "srv_section", "srv_section_name", "srv_code", "srv_question")

survey19 <- survey19 |>
  fill(everything()) |>
  mutate(across(where(is.character), str_squish))

## 2020 --------------------------------------------------------------------

# Não há dados!

## 2021 --------------------------------------------------------------------

path_21 <- here("data-raw/pemob21_metropolitana.xlsx")

pemob21 <- read_excel(path_21, skip = 1, na = na_excel)

pemob21 <- pemob21 |>
  rename(any_of(vl_names))

dict21 <- read_excel(path_21, range = "D1:MM2", col_names = FALSE, .name_repair = make_clean_names)
dict21 <- header_to_dictionary(dict21)
names(dict21) <- c("name_variable", "code_variable")

# Não tem survey!


## 2022 --------------------------------------------------------------------

path_22 <- here("data-raw/pemob_metropolitana_2022.xlsx")

pemob22 <- read_excel(path_22, skip = 1, na = na_excel)

pemob22 <- pemob22 |>
  rename(any_of(vl_names))

dict22 <- read_excel(path_22, range = "D1:MM2", col_names = FALSE, .name_repair = make_clean_names)
dict22 <- header_to_dictionary(dict22)
names(dict22) <- c("name_variable", "code_variable")


## 2023 --------------------------------------------------------------------

path_23 <- here("data-raw/pemob2023_metropolitana.xlsx")

pemob23 <- read_excel(path_23, skip = 1, na = na_excel)

pemob23 <- pemob23 |>
  rename(any_of(vl_names))

dict23 <- read_excel(path_23, range = "D1:MG2", col_names = FALSE, .name_repair = make_clean_names)
dict23 <- header_to_dictionary(dict23)
names(dict23) <- c("name_variable", "code_variable")

# Não tem survey!


## 2024 --------------------------------------------------------------------

path_24 <- here("data-raw/pemob_metropolitana_2024.xlsx")

pemob24 <- read_excel(path_24, skip = 1, na = na_excel)

pemob24 <- pemob24 |>
  rename(any_of(vl_names))

dict24 <- read_excel(path_24, range = "D1:MG2", col_names = FALSE, .name_repair = make_clean_names)
dict24 <- header_to_dictionary(dict24)
names(dict24) <- c("name_variable", "code_variable")

# Não tem survey

## Export dictionaries -----------------------------------------------------

pemob_dictionaries <- mget(ls(pattern = "^dict[0-9]{2}"))

for (i in seq_along(pemob_dictionaries)) {
  dict <- pemob_dictionaries[[i]]
  year <- stringr::str_extract(names(pemob_dictionaries)[[i]], "[0-9]{2}")
  year <- paste0("20", year)
  name_file <- str_glue("dicionario_variaveis_pemob_metro_{year}.csv")
  path_file <- here("data", name_file)

  if (file.exists(path_file)) {
    message("File ", name_file, " already exists. Skipping")
  } else {
    readr::write_csv(dict, path_file)
    message("Exported file to: ", path_file)
  }
}

## Harmonization -----------------------------------------------------------

### Functions and dictionary ------------------------------------------------

pemob19 <- add_pemob_metro_identity(pemob19)
pemob21 <- add_pemob_metro_identity(pemob21)
pemob22 <- add_pemob_metro_identity(pemob22)
pemob23 <- add_pemob_metro_identity(pemob23)
pemob24 <- add_pemob_metro_identity(pemob24)

pemobs <- list(pemob24, pemob23, pemob22, pemob21, pemob19)
names(pemobs) <- rev(paste0("year_", c(2019, 2021:2024)))
sel_cols <- rev(paste0("x", c(2019, 2021:2024)))

get_inds <- function(dat) {
  inds <- dat |>
    select(all_of(sel_cols)) |>
    as.matrix() |>
    t() |>
    as.character()

  return(inds)
}

pemob_get_variable <- function(var) {
  # browser()
  # Validate input
  cli_h1("Retrieving Variable: {var}")

  # Find row in keydict
  row <- subset(keydict, x2024 == var)

  # Enhanced error checking with cli
  if (nrow(row) == 0) {
    cli_abort("Variable {.val {var}} not found in keydict")
  }

  if (nrow(row) > 1) {
    cli_abort("Multiple entries found for variable {.val {var}}")
  }

  # Get indicators
  inds <- get_inds(row)
  ref_col_name <- row[["x2024"]]

  # Extract data with progress tracking
  ls <- map2(pemobs, inds, \(x,y) {

    if (is.na(y)) {
      return(NULL)
    } else {
      dat <- select(x, metro_key, abbrev_state, name_metro, any_of(y))
    }

    if (ncol(dat) == 4) {
      return(dat)
    } else {
      return(NULL)
    }
  })

  # Handle missing years with cli warning
  missing_years <- names(ls[sapply(ls, is.null)])

  if (length(missing_years) > 0) {
    cli_warn(c(
      "Variable has missing years",
      "*" = "Missing in years: {str_remove(missing_years, 'year_')}"
    ))
  }

  # Filter out NULL entries
  ls <- ls[!sapply(ls, is.null)]

  ref_class <- class(ls$year_2024[[var]])

  if (is.POSIXct(ls$year_2024[[var]])) {
    ref_class <- "character"
  }

  # Rename columns
  stacked <- map2(ls, names(ls), \(x, y) {
    result <- x[1:3]
    result[[y]] <- do.call(paste0("as.", ref_class), list(x[[4]]))
    return(result)
  })

  # Join and reshape
  id_cols <- c("metro_key", "abbrev_state", "name_metro")
  tbl <- reduce(stacked, full_join, by = id_cols)

  result <- tbl |>
    pivot_longer(
      cols = starts_with("year"),
      names_to = "year",
      values_to = ref_col_name
    ) |>
    mutate(year = as.numeric(str_remove(year, "year_"))) |>
    arrange(name_metro, year)

  # Final cli message
  cli_alert_success("Successfully retrieved {.val {var}} data")

  return(result)
}


safe_pemob_get_variable <- function(var) {
  # Wrap the original function with safely()
  safe_func <- safely(pemob_get_variable)

  # Execute with cli progress and error handling
  cli_progress_step("Processing {.val {var}}")

  result <- safe_func(var)

  # Check for errors
  if (!is.null(result$error)) {
    cli_alert_danger("Error processing {.val {var}}:")
    cli_text(result$error$message)
    return(NULL)
  }

  return(result$result)
}


### Harmonize datasets ------------------------------------------------------

# Create the full list with error handling
iter_pemob <- map(keydict$x2024, safe_pemob_get_variable)

# Check for errors
prob_inds <- which(sapply(iter_pemob, is.null))
if (length(prob_inds) > 0) {
  warning("Null results: ", paste(prob_inds, collapse = ", "))
} else {
  message("No critical errors")
}

# Combine list into a single table
id_cols <- c("metro_key", "abbrev_state", "name_metro", "year")
full_pemob <- reduce(iter_pemob, full_join, by = id_cols)

full_pemob <- full_pemob |>
  select(all_of(id_cols), everything())

# Export
readr::write_excel_csv2(full_pemob, "data/pemob_metro_harmonizada_2024.csv")

## Evaluate errors ---------------------------------------------------------

error_inds <- sapply(iter_pemob, \(x) nrow(unique(x[, 2])) != 5)
pemob_missing <- iter_pemob[error_inds]

all_years <- c(2019, 2021:2024)

find_missing_years <- function(dat) {

  list_years <- unique(dat[["year"]])

  # which is missing
  missing_years <- all_years[!all_years %in% list_years]
  if (length(missing_years) > 1) {
    missing_years <- paste(missing_years, collapse = ", ")
  }
  # control table
  name_variable <- names(dat)[3]

  control <- tibble(
    name_variable = name_variable,
    missing = as.character(missing_years)
  )

  return(control)


}

errors <- map(pemob_missing, find_missing_years)

tbl_errors <- bind_rows(errors)

all_years <- as.character(c(2019, 2021:2024))

indicators <- map(all_years, \(x) as.numeric(str_detect(tbl_errors$missing, as.character(x))))
indicators <- set_names(indicators, paste0("is_missing_", all_years))
indicators <- bind_cols(indicators)

tbl_errors <- bind_cols(tbl_errors, indicators)

pemob_codigos <- keydict |>
  select(x2024:x2019) |>
  filter(if_any(everything(), ~is.na(.x))) |>
  mutate(across(
    everything(),
    ~as.numeric(is.na(.x)),
    .names = "is_missing_{.col}"
  ))

pemob_codigos <- pemob_codigos |>
  mutate(status_variable_pemob = paste0(is_missing_x2024,
                                        is_missing_x2023,
                                        is_missing_x2022,
                                        is_missing_x2021,
                                        is_missing_x2019)) |>
  select(name_variable = x2024, status_variable_pemob) |>
  mutate(uk2 = row_number())

sub_errors <- tbl_errors |>
  mutate(status_variable = paste0(is_missing_2024,
                                  is_missing_2023,
                                  is_missing_2022,
                                  is_missing_2021,
                                  is_missing_2019)) |>
  select(name_variable, status_variable)

control <- left_join(sub_errors, pemob_codigos)

control |>
  mutate(
    flag = ifelse(status_variable != status_variable_pemob | is.na(status_variable_pemob), 1L, 0L)
  ) |>
  filter(flag == 1) |>
  View()

