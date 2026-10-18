# PEMOB roadmap

Updated 18 October 2026. This file is the single source for priorities and
status. Dated documents under `docs/internal/` record the evidence behind it.

## Deliverables, in order

1. **Harmonized dataset on Dataverse.** Municipal and metropolitan PEMOB
   2019–2025, rebuilt from the source files, with reported values, treated
   values, and treatment flags. This is the first release of the pipeline.
2. **Question registry.** One tracked table that replaces the manual
   classification of survey questions behind the Observatório products.
3. **Redesigned dashboard and table.** Rebuild
   [the dashboard](https://observatorio.insper.edu.br/projetos/dashboard) and
   [the table](https://observatorio.insper.edu.br/projetos/tabela) first. Serve
   2025 data to the site only after the redesign.

The live site keeps its current 2019–2024 data until deliverable 3 ships.

## Decisions

| Date | Decision |
|---|---|
| 2026-10-17 | Dashboard scores are percent of the question-year maximum. |
| 2026-10-17 | Metropolitan regions are keyed by state plus a reviewed alias table. |
| 2026-10-18 | The Dataverse dataset is the first deliverable; the site is not updated before the redesign. |
| 2026-10-18 | Interpolation enters the first release, limited to the easy cases defined below. |
| 2026-10-18 | The `refactor/r-coding-guidelines` branch is merged (PR #5) before further pipeline work. |
| 2026-10-18 | The table shows a curated subset of questions selected by a quality rule, not every harmonized question. Both products are redesigned. |
| 2026-10-18 | Frontend work goes to Lucas Tavares as a data handoff; we build `observatorio` locally to check it. |
| 2026-10-18 | The dashboard and the table support municipal and metropolitan data. |

## Status

| Area | State |
|---|---|
| Historical rebuild | `R/pemob.R` and `R/pemob_metropolitana.R` run from sources: 107 municipalities and 42 regions across 2019–2024. Union joins; raw responses and missing reasons retained. |
| 2025 extension | `Rscript R/build_pemob.R` rebuilds 2019–2025 from the sources in one run. Municipal: 113 places, with 64, 32, 62, 64, 67, 70, and 82 respondents from 2019 to 2025. Metropolitan: 43 regions, with 22, 13, 6, 13, 29, and 29 respondents in 2019 and 2021–2025. Every place-year carries `participated`. |
| Parsing | Currency, decimal commas, `km` suffixes, Excel dates, and missing tokens (`NA`, `NR`, `ND`, `-`) are parsed and tested. Ambiguous separators go to review. |
| Review layer | 134 cycling candidates in `docs/internal/pemob-review-ledger.csv`, all pending. `apply_pemob_review_decisions()` applies ledger decisions. No fare value was flagged. |
| Interpolation | Candidate extract and gate exist. The gate currently admits no case. |
| Dashboard formulas | Scaling and missing-to-zero fixed in code; portal outputs not regenerated. |
| Portal export | Not reproducible: `data/portal/dicionario_v1.xlsx` and `data/portal/final/pemob_tables.rds` are missing. The live site does not read `data/portal/v1/*.json` (see deliverable 2). |
| Environment | No `renv.lock`; no CI. All tests pass with `Rscript tests/test-pemob.R`. |

## Phase 1. Consolidate

- [x] Merge the refactor branch.
- [x] Move the implementation plan to `docs/internal/` and replace
  `ROADMAP-2025.md` with this file.
- [ ] Commit the review-decision layer and the reproduction log.
- [x] Update the README to describe the current scripts and outputs.

## Phase 2. One connected harmonization pipeline

Build 2019–2025 from the source files in one chain, so that every fix in the
historical readers reaches the released data.

- [x] Make `R/pemob_2025.R` append 2025 to the rebuilt history instead of the
  workbook. Keep the workbook only as a regression baseline.
- [x] Add one entry point, `R/build_pemob.R`, that runs municipal and
  metropolitan harmonization in order and writes the release files.
- [x] Track metropolitan participation by edition, as for municipalities.
- [x] Write missing cells as empty in the CSVs, so they no longer look like a
  written `NA`.
- Reconcile the known differences before release: 49 cells between the rebuilt
  2024 history and the workbook (35 in `1.6.1.F`), and the cell differences
  reported in `docs/internal/pipeline-reproduction-log-2026-10-18.md`.
- Classify the import and coercion warnings; fail the build on unexpected ones.
- Review cross-edition question correspondences against question text and
  unit. The known collision is `1.4.1.B` (metro/rail stations in 2019,
  accessible road terminals in 2024).
- Record the 2025 code changes reported by SIMU. In 2025, `12.1.1` is the
  municipal fund question that was `12.2.1` until 2024. `1.3.1.A` is new and
  has no reported values in the 2025 file.
- Add `renv` once the chain runs.

**Done when** one command rebuilds both datasets from `data-raw/` and
`tabelas/pemob_códigos.xlsx` in a fresh checkout, keys are unique, every
place-year is a source respondent or marked as nonparticipating, and the
listed differences are explained.

## Phase 3. Reporting quality and interpolation

Scope: fares (`3.1.1.A`) and cycling infrastructure (`1.6.1.G` ciclovias,
`1.6.1.H` ciclofaixas). Other variables ship as reported values.

### Corrections

Review the cycling candidates with the most leverage first: São Vicente
(17,600 km in 2024, 17.6 in 2025), Macaé 2025 (16,430 and 13,163 km), and São
Bernardo do Campo (`1.320 Km`). Correct a value only with evidence; record
unresolved suspects as excluded from the treated series or leave them flagged.
Never divide by 1,000 automatically.

### Interpolation: easy cases

The current candidate extract
(`data/pemob_interpolation_candidates.csv`) shows where interpolation can help.

| Gap type | Fare | Ciclovia | Ciclofaixa |
|---|---:|---:|---:|
| One-year gap, municipality did not answer that edition, numeric endpoints | 48 | 37 | 36 |
| of which equal endpoints | 16 | 8 | 10 |
| One-year gap, municipality answered but marked `NR`, numeric endpoints | 0 | 7 | 4 |

Most usable gaps are editions the municipality skipped, mainly 2020 (39 of
121). Filling them imputes a whole missed edition, not a skipped question, so
the release must flag these values as imputed. The current gate rejects them;
it needs to change.

Apply these rules in the first release:

1. **Fares, reconstructed.** When the next edition reports the previous fare
   (`3.1.1.B`) and the last adjustment date (`3.1.1.C`), use them to recover
   the fare in force during the gap year. Flag the value as reconstructed.
2. **Equal endpoints.** Carry the common value when both endpoints are parsed,
   unflagged, and in the same unit. Flag it as interpolated.
3. **Cycling, unequal endpoints.** Use linear interpolation between unflagged,
   same-unit endpoints. Flag it as interpolated.
4. **Not filled.** Unequal fare endpoints without adjustment records, gaps
   longer than one edition, leading or trailing gaps, flagged endpoints, and
   unparsed responses.

Validate by masking observed values that satisfy the same rules and report
the error by variable. Report counts of reported, corrected, excluded, and
imputed cells by variable and year.

**Done when** the treated series carries a status for every cell, the counts
and masking errors are reported, and raw responses remain unchanged.

## Phase 4. Dataverse release

Publish long files, one row per place, edition, and question. Mixed response
types fit in two value columns, the same split the parser already produces.

| Column | Content |
|---|---|
| `code_muni` or `metro_key`, `year`, `code_variable` | Key |
| `value_raw` | Response as submitted, always text |
| `value_num` | Parsed number; missing for text, categorical, and unparsed responses |
| `value_type`, `unit` | From the registry |
| `missing_code` | Missing-value code as written in the source cell (`NA`, `NR`, `ND`, `-`, blank, and written-out forms); no inference |
| `value_treated`, `treatment_status` | Reported, corrected, excluded, reconstructed, or interpolated |

The municipal 2019–2024 history has about 150,000 nonempty cells, so the long
file stays small. Rows for nonparticipating editions can be dropped, since the
participation table records them.

- Publish municipal and metropolitan long files, a participation table, the
  codebook (question codes and text by edition), and the treatment ledger.
  Record the Git commit that produced them.
- Generate a wide file from the long file only if Dataverse users need one.

**Done when** the dataset is published and the files match a fresh rebuild.

## Phase 5. Question registry

The site's labels, categories, and dashboard flags come from manual
classification spread across several files, and their original source is lost.

| Layer | Location |
|---|---|
| Original classification sheet | `Dicionario Portal` in the workbook; absent from the copy in `tabelas/` |
| Regex rules for mode and category | `R/pemob_portal.R` |
| Three diverging dictionaries | `data/dict_portal_pemob.csv`, `data/portal/v1/dict_portal_parcial.csv`, `data/portal/v1/dict_portal_v1.csv` |
| Category tree | `data/portal/v1/dim_category.csv`, `data-raw/filter-categories.ts`, and the diverged copy in `observatorio` |
| Live data | `observatorio/.../dashboard/lib/data/pemob-20xx.ts`, 160 items per city, 111 dashboard labels |

Build one registry for both levels, with one row per question code and level:
label, category, subcategory, mode, unit, value type, editions where the
question is valid, and separate table and dashboard flags. Seed it from
`dict_portal_v1.csv`, check it against the live TS labels and
`filter-categories.ts`, and add the 2025 rows.

Add a shared concept ID that links a municipal question to its metropolitan
counterpart. Only 83 codes appear in both 2024 questionnaires, and only 36 of
them have near-identical text, so codes cannot be the link. Question text is a
better start: 232 of 342 metropolitan questions match a municipal question
after removing place words. Review those matches by hand.

Select table and dashboard questions with a quality rule computed from the
harmonized data: coverage by edition, comparability across editions, and
parse success. Questions that fail stay in the Dataverse files but leave the
site products. The thresholds are set when the rule is first run.

**Done when** every label and menu entry on the site traces to one registry
row, the registry has no duplicate labels, and each excluded question has a
recorded reason.

## Phase 6. Dashboard and table redesign

Lucas Tavares implements the frontend from a data handoff. We build
`observatorio` locally from a fresh `origin/main` worktree to check each
handoff before sending it. The local `main` checkout has diverged from origin.

Redesign both products, following
`docs/internal/pemob-dashboard-brief-and-fix-plan.md` for the dashboard. The
table keeps only questions that pass the registry quality rule. Both products
get a municipal/metropolitan switch. A question appears at both levels only
when it has a reviewed concept link; the dashboard does not plot the two
levels on one axis.

Issues found in the current frontend, which the redesign must remove:

- Values are joined by label string, not question code. Labels contain typos
  and one repeats within a city.
- `getVariableData()` turns a real zero into missing, and fill percentages
  treat zero as unanswered. The evolution chart draws missing years as zero.
- The table only shows variables flagged for the dashboard; `is_tabela` is
  unused. Its menu lists options that have no data, and some entries are
  empty.
- Data ship as bundled TS modules and year ranges are hard-coded, so each
  update needs hand edits and a rebuild.

## Phase 7. Data handoff to the site

Write a handoff specification and export from this repository. The export
holds, for each level, values keyed by place, question code, and edition,
with value, status, and the registry fields the site needs. The handoff also
holds the category tree, the year list, and a schema check. The site derives
menus and year ranges from these files instead of hard-coding them.

Hand the frontend work over in four changes, each shippable on its own and
checked with a local build before it goes out.

1. **Data source.** The site reads the new export keyed by question code,
   with the current charts. This also fixes the zero handling.
2. **Table.** Apply the quality rule, generate the menu from the registry, and
   drop empty entries.
3. **Dashboard.** Time series as the main view, a one-year comparison plot,
   and no radar chart.
4. **Level switch.** Add the municipal/metropolitan switch.

**Done when** a local `observatorio` build renders both products from the
export without hand edits.

## Open questions

1. **Dataverse layout.** Confirm the long layout in Phase 4.
2. **Meaning of the missing codes.** Ask SIMU what `NA`, `NR`, and `ND` mean
   in each edition. The parser also records an empty cell as `NA`; the release
   should keep empty cells and a written `NA` apart.
3. **Same view or separate views.** Decide after the concept links are
   reviewed: if few dashboard indicators exist at both levels, give
   metropolitan data its own view instead of a switch.

## Related documents

- `docs/internal/codebase-review-2026-10-17.md` — findings and evidence.
- `docs/internal/pemob-implementation-plan-2026-10-17.md` — staged plan and
  acceptance criteria behind phases 2–3.
- `docs/internal/pipeline-reproduction-log-2026-10-18.md` — reproduction run.
- `docs/internal/pemob-dashboard-brief-and-fix-plan.md` — dashboard redesign.
