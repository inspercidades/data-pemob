# Initial codebase review for the PEMOB 2025 roadmap

Internal working document. Reviewed on 17 October 2026.

## Assessment

The repository contains the source data, question maps, historical exports, and
a working provisional 2025 extension. It does not yet provide a reproducible,
validated path from historical sources to a refreshed portal export. Repair
historical coverage, question mapping, and dashboard calculations before
publishing 2025 or undertaking a broader refactor.

This review covers the current working tree, including the uncommitted
`R/pemob_2025.R`, its tests, and `ROADMAP-2025.md`. It supplements the roadmap;
it does not implement its fixes. Existing code, data, and roadmap files were
left unchanged. The sequenced implementation plan is in
`.omx/plans/pemob-codebase-review-implementation.md`.

## Current workflow

| Stage | Files | Current role |
|---|---|---|
| Inputs | `data-raw/`, `tabelas/` | Survey spreadsheets and 2025 CSVs; question-code maps; manually prepared harmonized workbook |
| Historical harmonization | `R/pemob.R`, `R/pemob_metropolitana.R` | Read editions through 2024, align questions, join places, export wide CSVs |
| Provisional 2025 extension | `R/pemob_2025.R` | Append 2025 respondents to the existing workbook history; write municipal and metropolitan CSVs |
| Portal metadata | `R/pemob_portal.R`, `R/pemob_portal_final.R` | Classify questions, prepare labels and categories, produce table exports |
| Dashboard calculations | `R/pemob_final.R` | Calculate shares, maximum-based scores, and population-adjusted values; write intermediate tables |
| Versioned portal JSON | `R/pemob_data_portal.R` | Read dashboard intermediates, transform values, export nested municipal JSON |
| Supporting work | `R/amostra_dashboard.R`, `R/pemob_errors.R`, `generate_filter_categories.R` | Chart exploration, error diagnostics, and frontend filter generation |

The historical scripts write CSVs, but the portal scripts read a harmonized
Excel workbook. The repository does not define an automated step that refreshes
that workbook from those CSVs. The 2025 extension also writes CSVs without
connecting them to the portal pipeline.

Several scripts share function and object names and execute work at the top
level. They should not be treated as a sequence of safely sourceable modules.

## Prioritized findings

### 1. Historical joins remove earlier respondents — publication blocker

**Evidence; high confidence.** `R/pemob.R:270-345` orders editions from 2024
backward, then joins each variable with `reduce(stacked, left_join, ...)`.
`R/pemob_metropolitana.R:176-255` does the same for region names. A left join
retains the first edition's places; subsequent outer joins across variables
cannot recover places already removed inside each variable.

A direct comparison of the municipal 2019 source with the harmonized workbook
found the following counts.

| Measure | Count |
|---|---:|
| Distinct 2019 source codes with seven-digit numeric IDs and nonmissing municipality names | 64 |
| Workbook rows assigned to 2019 | 70 |
| Codes in both | 40 |
| Source respondent codes absent from the workbook's 2019 rows | 24 |
| Workbook codes absent from the 2019 source respondents | 30 |

The workbook has 70 municipal rows in every year from 2019 through 2024.
Its metropolitan sheet has 29 rows in each available historical edition
(2019 and 2021–2024). These are fixed cohorts rather than validated annual
participation lists. A workbook row alone does not establish participation.

**Roadmap correction.** The roadmap's 96 nonmissing source entries include
footer text and survey notes. Numeric conversion alone still counts 88 entries,
because numbered notes 1–24 also occur in the identifier column. The correct
respondent comparison above excludes both kinds of footer. The claim that 56
respondent codes are absent should therefore become 24. This review identifies
the correction without editing the existing roadmap.

**Required next step.** Establish valid respondent rows for each source, retain
the union of geographic keys across editions, and record participation
separately from unanswered questions. Test this before changing joins. Keep
2025 outputs provisional while their inherited history remains unreconciled
(`R/pemob_2025.R:30-35,123-128`).

### 2. Dashboard rescaling mixes questions and years — publication blocker

**Evidence; high confidence.** `R/pemob_final.R:146-152` computes maximum-based
scores within question and year. `R/pemob_data_portal.R:13-30` binds the three
indicator families and recalculates those scores with an ungrouped minimum and
maximum. Each question is then scaled against unrelated quantities from other
questions and years.

The saved 2024 JSON has 37 maximum-based groups when identified by label and
question text. None reaches 100; the largest such score is 0.003. The same
absence of a group reaching 100 occurs in all six saved annual JSONs. These
artifact checks support the code finding, although they do not prove the exact
script revision that produced those files.

**Required next step.** Choose the intended formula (percentage of maximum or
min–max scaling) and apply it once within question and edition. Test separate
units, missing values, all-zero groups, and constant groups before regenerating
historical or 2025 JSONs. Changing scores will change dashboard interpretation
and needs a documented release comparison.

**Follow-up status (2026-10-17).** The selected definition is percent of the
question-year maximum. The portal's global min–max rescaling was removed, and
tests cover ordinary, constant, all-zero, and all-missing groups. Portal output
regeneration remains pending.

### 3. Missing responses become measured zeros — publication blocker

**Evidence; high confidence.** `R/pemob_final.R:108-127` converts missing share
numerators to zero and assigns zero when the denominator is zero.
`R/pemob_final.R:216-224` then replaces missing numeric values across formatted
dashboard tables with zero. An unanswered count can consequently become a
zero count and a zero percentage. A zero denominator can become a reported
percentage despite the ratio being undefined.

The 2024 JSON contains zero-valued share records and no null `value` fields.
That does not establish which individual zeros are erroneous; that attribution
requires tracing source cells through the repaired pipeline.

**Required next step.** Preserve missing responses and undefined ratios through
serialization. Test genuine zero, unanswered numerator, missing denominator,
zero denominator, and inconsistent numerator/denominator separately.

**Follow-up status (2026-10-17).** The parser now preserves raw responses and
missing reasons. Missing numeric values remain missing, and missing or zero
share denominators produce missing percentages. The portal outputs have not
been regenerated.

### 4. Historical scripts have execution blockers — required before rebuilding

**Evidence; high confidence.** `R/pemob.R:20-24` reads the code workbook's first
sheet without naming it. The current workbook's sheets are `changes`,
`pemob_municipal`, and `pemob_metropolitana`. The first sheet contains a note
about 2025 codes. Reading it and applying the existing `fill(bloco, secao)`
fails because those columns do not exist.

`R/pemob_metropolitana.R:16-17` constructs `dim_muni` from municipality
geometries, but `R/pemob_metropolitana.R:313` joins it using `name_metro`.
The constructed municipality dimension does not provide that regional key.

**Required next step.** Select the municipal map sheet explicitly and define
the metropolitan identity table from the appropriate source. Check geographic
key uniqueness before joining. These repairs are prerequisites for a complete
historical rerun, rather than evidence that all remaining execution paths work.

**Follow-up status (2026-10-17).** The municipal map sheet is selected
explicitly. The metropolitan pipeline now uses state plus exact reviewed
aliases and no longer joins regional records to municipality geometries. Tests
check key uniqueness against the source workbooks. A full historical run has
not been attempted.

### 5. Portal inputs and outputs do not form a reproducible chain

**Evidence; high confidence.** `R/pemob_final.R:14-18`,
`R/pemob_portal.R:9-13`, and `R/pemob_portal_final.R:8-12` reference
`data/PEMOB Harmonizada 2024.xlsx`, which is absent. The available workbook is
under `tabelas/`.

Other absent inputs are `data/portal/dicionario_v1.xlsx`,
`data/portal/dict_portal_parcial.csv`, and
`data/portal/final/pemob_tables.rds`. Related CSV metadata exists under
`data/portal/v1/`, but equivalence to the missing inputs has not been established.
The expected `data/portal/final/` directory is also absent.

`generate_filter_categories.R:5` reads `data/portal/dim_category.csv`; the saved
category CSV instead sits under `data/portal/v1/`. The exploratory tail of
`R/pemob_portal_final.R:185-194` also refers to `portal` and `swap_names`, which
are not established at that script's top level.

**Required next step.** Define one input/output manifest and execution order.
Identify the authoritative metadata and replace missing manual steps with
explicit, reviewable steps. First prove a local run using existing dependencies;
then freeze the environment and verify a fresh checkout. Do not copy files
between paths merely to make scripts run without checking their contents.

### 6. The historical crosswalk combines different measures — publication blocker

**Evidence; high confidence.** Direct inspection of the source headers and
municipal crosswalk confirms that `1.4.1.B` means metro/rail stations in 2019
and accessible road terminals in 2024. The crosswalk links those codes as one
measure. This confirms the concern recorded in `R/pemob_final.R:129-132`.
Mechanical code matching therefore produces a semantically invalid series.

Both historical harmonizers derive each question's type from 2024 and coerce
earlier values to that type before joining (`R/pemob.R:327-341`;
`R/pemob_metropolitana.R:237-251`). Earlier text or differently formatted
numbers can lose information under this rule. For example, a 2019 respondent's
`3.1.1.A` value is `RS3,45`, which numeric coercion converts to missing. The
extent of such loss across the dataset has not been quantified.
Failed question processing is
logged and returned as `NULL`, while the pipeline proceeds toward export
(`R/pemob.R:364-405`; `R/pemob_metropolitana.R:274-317`).

**Required next step.** Preserve original responses, audit conversions, compare
question texts and units across editions, and reject incomplete publication
when required questions fail. Repair the confirmed `1.4.1.B` correspondence
before calculating accessibility shares. Verify the positional 2020 header corrections
in `R/pemob.R:117-125` against their actual question text as part of this audit.

### 7. Metropolitan identity currently relies on names alone

**Evidence; high confidence for implementation; matching policy unresolved.**
Historical joins use `name_metro`. The 2025 extension requires `UF` but discards
it when constructing output, and checks uniqueness only on region name and year
(`R/pemob_2025.R:131-158`). Name changes or spelling differences can split one
region into apparent new participants; identical names across states cannot be
represented independently under that key.

The 2019 source has 25 metropolitan respondent rows with two-letter UFs;
none of their names exactly matches the 2024 names. For example, `RM Maceió`
becomes `Região Metropolitana de Maceió`. This is a matching failure, not
evidence that every metropolitan respondent changed.

The existing test establishes two 2025 names absent from 2024. It does not
establish that these are two newly participating geographic entities.

**Required next step.** Reconcile names across editions and retain state
information. Define a stable regional key and document boundary changes where
relevant before interpreting longitudinal coverage. A metropolitan portal
contract remains a separate product decision.

**Follow-up status (2026-10-17).** The approved rule is state plus an exact,
reviewed alias table. Clear abbreviation-to-name changes that point to a
same-state 2024 region are canonicalized; unreviewed names, including the 2019
Teresina RIDE, remain separate. The 2025 output retains state, composite key,
canonical name, and submitted name. Boundary equivalence and the historical
pipeline rerun remain open.

### 8. Existing tests validate the provisional append, not publication readiness

**Evidence; high confidence.** `tests/test-pemob-2025.R` passes. It checks
82 municipal and 29 metropolitan 2025 rows; 502 and 174 combined rows;
unique place-year keys; the fund-question rename; the new all-missing question;
state metadata; and selected historical preservation checks.

The tests intentionally preserve the existing workbook cohort and therefore
cannot certify historical completeness. They do not exercise dashboard
scaling, missing-to-zero behavior, the portal JSON contract, historical readers,
or error branches. There is no repository test runner or CI configuration, and
no dependency lockfile. Their absence is a maintenance gap, not a reason to
expand this into an R package migration.

**Required next step.** Add small regression cases for findings 1–7 before
implementation, then connect them to one documented validation command.
Retain the useful 2025 input and append checks while replacing expectations
that encode the known incomplete historical cohort.

## Self-reported data: correction, outliers, and interpolation

Added on 17 October 2026 following the requested review of reporting errors.
The treatment below is a proposed implementation policy. No observations have
been corrected, removed, or imputed in this review.

### Evidence from fares and cycling infrastructure

The pilot examined `3.1.1.A` (current predominant municipal fare), `1.6.1.G`
(exclusive ciclovias, km), and `1.6.1.H` (exclusive ciclofaixas, km). The question
texts come from `data/dicionario_variaveis_pemob_2024.csv` and the first header
row of the 2025 municipal source. The fare question does not itself identify a
transport mode, despite its dashboard use as a bus-fare indicator. Confirm the
applicable service before comparing or interpolating it.

The provisional `data/pemob_harmonizada_2025.csv` contains the following fare
coverage. Historical cells were read as decimal-comma numbers; currency text
was deliberately not stripped for this first parsing diagnostic.

| Edition | Rows in provisional dataset | Numeric fare | Missing token | Other text |
|---|---:|---:|---:|---:|
| 2019 | 70 | 38 | 32 | 0 |
| 2020 | 70 | 21 | 49 | 0 |
| 2021 | 70 | 39 | 31 | 0 |
| 2022 | 70 | 44 | 26 | 0 |
| 2023 | 70 | 54 | 16 | 0 |
| 2024 | 70 | 70 | 0 | 0 |
| 2025 | 82 | 0 | 1 | 81 |

All 81 nonmissing 2025 fares contain `R$` in the source CSV. The existing portal
conversion replaces a comma and calls `as.numeric()`
(`R/pemob_final.R:32-34`, `R/pemob_portal_final.R:94-100`); it does not remove
currency text. Feeding those strings through that conversion would turn the
entire reported 2025 fare series into missing values. That is a parser defect,
not a reason to interpolate 2025 fares.

Within the provisional 2019–2024 cohort, 30 missing fare cells have numeric
observations in both immediately adjacent editions, matched by municipality
code. Thirteen have equal endpoints. These are candidate gaps, not 30 approved
imputations: the workbook includes synthetic cohort rows and does not establish
participation or applicability in each missing year.

| Example | Values in the provisional series | Interpretation for review |
|---|---|---|
| Manaus fare | 2020: 3.80; 2021: missing; 2022: 3.80 | Candidate estimate of 3.80 after checking service and participation; equal endpoints alone do not establish the intervening fare |
| Campinas fare | 2020: 4.95; 2021: missing; 2022: 5.15 | Linear estimate would be 5.05, but may never have been a charged fare |
| São Vicente ciclovias | 2022: 17; 2024: 17,600; 2025: 17.6 | Strong candidate for a metres/km reporting error; the 2024 and 2025 source files confirm the discrepancy, not its definitive correction |
| São Vicente ciclofaixas | 2021–2022: 760; 2024: 1,460; 2025: 1.46 | Possible repeated unit error; adjacent observations may themselves be contaminated |
| Macaé, 2025 | Ciclovias: 16,430; ciclofaixas: 13,163 | Both appear verbatim in the source CSV under questions asking for km; investigate units before applying any factor |
| São Bernardo do Campo ciclofaixas | 2021: 2.3; 2022: 2,350; 2024: `1.320 Km`; 2025: `1,320` | Potential unit and decimal-separator ambiguity; punctuation alone cannot justify a correction |
| Manaus ciclofaixas, 2024 | `15,24 km` | Explicit km suffix can be parsed without estimating a missing observation |
| Chapecó ciclofaixas, 2023 | `21,6 total de ciclovias/ciclofaixas` | Combines two infrastructure classes; extracting 21.6 into ciclofaixas alone would change its meaning |

The São Vicente, São Bernardo do Campo, and Manaus 2024 examples were traced
to `data-raw/pemob_municipal_2024.xlsx`; Macaé and the quoted 2025 values were
traced to the Latin-1 municipal CSV. Other historical examples above were
profiled in the provisional harmonized CSV and still need a complete source
and question-map trace. No municipal administrative records were consulted.

For ciclofaixas in 2024, the provisional file has 39 directly numeric cells,
16 missing tokens, and 15 other strings. Some strings contain explicit units;
others need semantic review. A numeric-parser failure must remain distinct
from an unanswered question.

### Recommended treatment order

1. **Restore comparability and identify actual gaps.** Repair historical
   coverage, geographic matching, and question correspondences first. Preserve
   the original response string and missing token. The current 2025 reader
   collapses `NA`, `NR`, `ND`, `-`, and blanks, so retain their original meanings
   upstream before applying eligibility rules. Distinguish nonparticipation,
   unanswered applicable questions, nonapplicability, and parsing failures.
2. **Parse recoverable reported values.** Handle explicit currency and unit
   suffixes using variable-specific rules; record the declared unit. Ambiguous
   separators and text combining indicators go to review. Do not extract the
   first number indiscriminately. This also covers historical text such as
   `RS3,45`, noted in finding 6.
3. **Flag and adjudicate suspect observations.** Use domain validity, a city's
   trajectory, neighbouring valid observations, and cross-field consistency.
   Search for factors such as 1,000 where they suggest a unit error. Compare
   ciclovias and ciclofaixas separately and check their sum for possible
   reclassification or double counting. Cross-city robust statistics can
   produce a review queue, but cannot prove an error in a heterogeneous sample.
4. **Correct supported errors; exclude unresolved invalid values from the
   treated measure.** Prefer source clarification or municipal administrative
   evidence when available. A documented unit correction can replace a bad
   treated value; an unresolved suspect value stays flagged rather than being
   silently divided by 1,000. Exclusion means a missing treated value with a
   reason, while preserving its raw value and row. Do not delete respondents,
   automatically trim tails, or winsorize every indicator.
5. **Estimate only eligible residual gaps.** Use reviewed endpoints after
   parsing and corrections. Never let a flagged endpoint influence an
   interpolation. Calculate dashboard transforms and denominators from the
   resulting data only after defining how treated values enter those outputs.

`R/pemob_final.R:154-164` currently prints an exploratory IQR-based outlier
selection. It neither corrects nor excludes those observations, and it groups
across years. There is no implemented interpolation or auditable correction
stage. A very large reported value can therefore distort maximum-based scores
for every other city even after the scaling bug is fixed.

### Pilot interpolation policy

Start with one missing interior year bounded by two reviewed observations for
the same municipality, question, unit, and applicable service. Propose linear
interpolation for an analytical series, using elapsed reference time rather
than row position. Do not extrapolate endpoints or fill longer runs in the
initial pilot. Preserve actual zeros; a zero fare may be valid under fare-free
service and must not be recoded merely because it is small.

For fares, prefer reconstructing the value from verified adjustment dates and
previous/current fares (`3.1.1.B`, `3.1.1.C`) when those records support the
relevant observation date. Otherwise label linear fills as estimates. Do not
assume fares change smoothly, are monotone, or remained unchanged merely
because two editions report the same amount. Edition year is not necessarily
the date when a reported “current” fare took effect.

For cycling infrastructure, short interior interpolation is a candidate only
after checking units, definitions, and possible reclassification. Infrastructure
can open in discrete projects or be remeasured; do not impose monotonic growth.
Keep new participants without two endpoints, mixed-definition responses, and
structural/nonapplicable gaps unfilled in the pilot. Any proposal to estimate
nonparticipating editions should be explicit and separate from filling item
nonresponse.

The one-year limit and these eligibility rules are proposed defaults. Evaluate
them before expanding coverage; they are not empirically validated thresholds.

### Deliverables and checks before publishing treated data

- Keep reported and treated values available separately. Record municipality,
  edition/reference date, question, source file, original response/unit,
  parsed value, treated value, flags, decision/reason, and method. Record a
  supporting source for corrections and endpoint years for interpolation.
  Keep anomaly flags separate from correction/imputation status.
- Maintain a small reviewed exception ledger keyed by municipality, edition,
  and question. Do not bury city-specific overrides in transformation code.
- Add regression cases before implementation for currency parsing, explicit
  km/metre conversion, ambiguous separators, combined infrastructure text,
  genuine zero, structural gaps, contaminated endpoints, one-year interior
  interpolation, no extrapolation, and preservation of original responses.
- Mask a small sample of reviewed valid observations to compare short-gap
  estimates with known values. Report error and coverage by variable; compare
  fare interpolation with verified step changes where available. This checks
  plausibility, not whether missingness is random.
- Produce per-variable/year counts of reported, parsed, flagged, corrected,
  excluded, and imputed cells; include before/after distributions and changes
  in dashboard scores. Report how many of the 30 fare candidates survive the
  participation and comparability checks.
- Define whether portal tables and charts show reported or treated values,
  and disclose estimates and exclusions in the export/UI. The existing nested
  JSON does not carry provenance fields; agree how its consumer will display
  or retrieve them before switching published values.

This pilot addresses reporting quality, not survey representativeness.
Interpolation does not recover absent cities or make the sample representative.

## Recommended roadmap order and acceptance gates

| Order | Work | Acceptance evidence |
|---|---|---|
| 1 | Lock inputs, respondent rules, geographic keys, and question correspondences | Per-edition coverage ledger; footer exclusion; duplicate-key checks; reviewed text/unit differences and 2025 changes |
| 2 | Repair historical readers, joins, and failure handling | Regression tests pass; source respondents survive harmonization; every exclusion and failed conversion is explained |
| 3 | Add the fare/cycling reporting-quality pilot | Raw responses retained; parser tests; reviewed anomaly ledger; short-gap policy tested; treatment coverage and sensitivity report |
| 4 | Repair dashboard formulas and define treatment use | Tests distinguish missing from zero and cover scaling boundaries; population source/reference year recorded; reported/treated policy explicit |
| 5 | Connect harmonized outputs and metadata to one portal build | Documented command works without interactive objects, undocumented file copies, or manual workbook edits |
| 6 | Validate and prepare municipal 2025 publication | Valid nested schema; unique municipality keys; source-to-export value checks; category/label consistency; historical difference report; estimates disclosed |
| 7 | Freeze dependencies and add routine validation | Declared dependencies; lockfile; fresh-checkout run; automated checks for the agreed outputs |

Keep the metropolitan harmonized dataset in scope. Decide its consumer and
export schema before implementing a metropolitan portal export. Defer broad
cleanup and architectural changes until the corrected data contract is tested.

## Verification performed and limits

- Ran `Rscript tests/test-pemob-2025.R` successfully against local inputs.
- Parsed every R script and the existing test successfully. Parsing establishes
  syntax validity, not successful execution.
- Inspected all processing/export scripts and supporting filter generation.
- Read workbook sheet names, historical cohort sizes, and 2019 source IDs;
  reproduced the municipal map-sheet failure with the current workbook.
- Loaded all six saved portal JSONs; checked municipality-key uniqueness,
  edition fields, nested field names, and maximum-based score groups. Each
  contains 70 municipal objects and no duplicate outer municipal code.
- Confirmed that several expected intermediate paths are absent.

No full pipeline build, source-data correction, dependency installation,
network retrieval, frontend test, or publication was performed. Full execution
would overwrite artifacts and currently encounters the blockers above. The
portal consumer is outside this repository, so compatibility with its current
frontend remains unverified. Population retrieval and its reference-year policy
also remain unverified; the current script calls SIDRA during processing
(`R/pemob_final.R:172-193`).

The source comparison establishes coverage and key discrepancies; it does not
certify every historical response or every inter-edition question mapping.
Files already tracked by Git remain tracked despite matching `.gitignore`:
the harmonized workbook and many raw files are tracked in this checkout.
Do not infer missing source data from ignore patterns alone.
