# PEMOB pipeline reproduction log

Run date: 18 October 2026  
Repository: current working tree in `/Users/viniciusreginatto/GitHub/data-pemob`  
R: 4.5.1  
Run location: isolated copy under `/tmp/data-pemob-repro.fNV9wo`

## Scope and safety

Reproduced the available harmonized municipal and metropolitan CSV pipeline
through 2025. The source files under `data-raw/` and `tabelas/` were only read.
The scripts ran in a separate copy of the project, so they did not replace
outputs in the working checkout. SHA-256 inventories of the 18 raw/reference
files matched between the checkout and the reproduction copy after the run.

This run did not attempt to generate dashboard or portal exports. Their current
input files `data/portal/dicionario_v1.xlsx` and
`data/portal/final/pemob_tables.rds` are absent.

## Steps and results

| Step | Command | Result |
|---|---|---|
| 1. Rebuild municipal history through 2024 | `Rscript R/pemob.R` | Completed; 642 rows, 477 columns, 107 place-year rows for each year 2019–2024; zero duplicate municipality-year keys. |
| 2. Rebuild metropolitan history through 2024 | `Rscript R/pemob_metropolitana.R` | Completed; 210 rows, 346 columns, 42 region-year rows for each available year 2019 and 2021–2024; zero duplicate region-year keys. Script reported no critical indicator errors. |
| 3. Append 2025 to the workbook-based history | `Rscript R/pemob_2025.R` | Completed; municipal output 502 rows and 481 columns (70 rows per year 2019–2024, 82 for 2025); metropolitan output 174 rows and 347 columns (29 per available year 2019, 2021–2025). Both have unique place-year keys. |

The four generated files and their SHA-256 hashes:

| File | SHA-256 |
|---|---|
| `data/pemob_harmonizada_2024.csv` | `d87c15ebfab1c358105aa44ad35d38f82f89dc537dd1d5ba088544888860f26a` |
| `data/pemob_metro_harmonizada_2024.csv` | `6eb052468fd5a11302425ce58d844b633b2bb8f77dc793e515c88438cd4a5564` |
| `data/pemob_harmonizada_2025.csv` | `f17e20b36626a52b3498089cf280dd5394214ffa425e314d096847f017f56471` |
| `data/pemob_metro_harmonizada_2025.csv` | `13f270dbb64f6c4f7e09f047920b95687790c9b49d0da3b874e9ba07605eeee1` |

## Reproducibility findings

- The municipal and metropolitan scripts through 2024 run from the available
  sources. Their runs emitted 50 or more warnings; indicator processing did
  not report a fatal error, but the warnings still need classification.
- The reproduced metropolitan 2024 file has 210 rows, while the existing local
  file has 145 rows. This confirms that the existing file is stale relative to
  the current pipeline, which now retains state-aware region keys and broader
  historical coverage.
- The reproduced municipal 2024 file has the same 642-by-477 shape and keys as
  the existing local file, but 668 cell values differ in three columns:
  `3.1.1.C` (323), `8.2.3` (137), and `11.2.2.B` (208).
- The reproduced municipal 2025 file has the same shape and keys as the
  existing local file, but 1,164 cell values differ in 13 columns. This should
  be reconciled before treating the checked-in local artifact as current.
- The reproduced metropolitan 2025 file is byte-identical to its existing
  local counterpart.
- The 2025 builder reads the fixed 2024 harmonized workbook directly. It does
  not consume the freshly rebuilt 2024 CSVs. Consequently, the municipal
  2025 output retains 70 places in each historical year, compared with 107 in
  the independently rebuilt municipal history. The metropolitan 2025 output
  similarly has 29 rows per year, compared with 42 in the rebuilt history.
  The scripts are individually runnable, but outputs through 2025 are not yet
  one connected, reproducible chain.
- The dashboard/portal export is not currently reproducible from this checkout:
  required intermediate inputs are missing. This run therefore establishes
  reproducibility only through harmonized CSVs.

## Warnings and environment

R completed all three commands successfully. Startup reported several packages
built under R 4.5.2 while the available runtime is R 4.5.1. Historical scripts
also emitted import and coercion warnings, and R reported 50 or more warnings
in each historical run. Full console logs were retained in `/tmp` during the
run; warning classification remains open. The repository has no `renv.lock`,
so the run does not establish a pinned, fresh-checkout environment.
