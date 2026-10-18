# PEMOB 2025 roadmap

## Goal

Add the 2025 municipal and metropolitan survey files to the harmonized datasets. Update the municipal portal files after checking that the 2025 data and metadata fit the existing portal contract. Decide whether the metropolitan dataset also needs a portal export before building one.

Add an auditable treatment of self-reported input errors, starting with fares
and cycling infrastructure. Preserve reported responses alongside corrected or
estimated analytical values. The [internal codebase review](docs/internal/codebase-review-2026-10-17.md)
contains the evidence, candidate cases, and proposed treatment policy.
The implementation sequence and acceptance gates are recorded in
`.omx/plans/pemob-codebase-review-implementation.md`.

## Source and code changes

The repository already contains the 2025 municipal and metropolitan CSVs in `data-raw/`. They use Latin-1 encoding, a first row with question text, and a second row with variable codes. The existing readers expect Excel files. Treat `NA`, `NR`, `ND`, and `-` as missing values where they occur, and keep the survey edition (`2025`) distinct from reference years mentioned inside questions.

SIMU told the ONMS team that the 2025 edition made only two changes to PEMOB question codes:

> A pergunta que até 2024 tinha o código 12.2.1 - "O município possui fundo municipal específico de transporte e/ou mobilidade urbana?" - passou ter o código 12.1.1;
>
> além disso, foi adicionada a pergunta 1.3.1.A - "Qual outro tipo de integração física entre os diferentes modos de transporte urbano existe em seu município?".

Record both changes in the municipal code map before harmonizing. Link `12.1.1` in 2025 to `12.2.1` in earlier editions as the same question. Add `1.3.1.A` as a new question with no earlier values. Check question text alongside codes; do not assume that matching codes always mean matching measures. The metropolitan 2025 codes match the existing 2024 map, subject to the same text check.

## Work sequence

1. **Review the existing pipeline for data errors.** Trace each source through code mapping, joins, type conversion, dashboard calculations, and exports. Check for lost places, changed question meanings, duplicated keys, missing values converted to zero, and stale file paths. Record confirmed errors and add regression checks before fixing them.
2. **Lock the input contract.** Record the source files, encoding, header rows, row counts, identifiers, and code sets. Add small tests for the 2025 CSV reader and the two municipal mapping changes before changing the pipeline.
3. **Extend harmonization.** Read the 2025 files, extend the year maps, and retain the union of places across editions. The municipal file has 82 places, including 25 absent from 2024; the metropolitan file has 29 regions, with two names absent from the 2024 file. Keep missing responses distinct from places that did not participate in a given edition.
4. **Validate the datasets.** Check unique place-year keys, expected years, row coverage, variable coverage, missing-value handling, and the two changed municipal codes. Review the 2025 values of indicators used in the dashboard for unit or question changes. Compare 2024 outputs before and after the pipeline change to detect regressions.
5. **Pilot corrections, outlier review, and short-gap interpolation.** After rebuilding comparable histories, preserve raw response strings and missing reasons; parse reported currency and units before identifying gaps. Review fare (`3.1.1.A`), ciclovia (`1.6.1.G`), and ciclofaixa (`1.6.1.H`) anomalies using within-city trajectories, units, question definitions, and supporting records. Correct supported errors through an exception ledger; retain flagged raw values and exclude confirmed invalid observations only from the treated measure. Test one-year interior interpolation using reviewed endpoints, without extrapolation or automatic filling of nonparticipation/nonapplicability. Keep estimates separate from observations and assess their errors and coverage before expanding this pilot.
6. **Update the municipal portal export.** Resolve the current mismatch between the workbook path used by the scripts and the workbook under `tabelas/`. Regenerate the required intermediate data and the 2025 `data/portal/v1/pemob_2025.json`. Check its schema against the 2024 JSON, its municipality coverage, and the labels and transformations used by the dashboard. Define whether the portal displays reported or treated values and how it discloses estimates and exclusions. Recalculate scores after the treatment stage and compare them with the reported-only series. Update the README's year range.
7. **Decide the metropolitan publication target.** The repo currently has a metropolitan harmonized CSV but no metropolitan portal JSON contract. Keep a harmonized 2025 metropolitan output as the required deliverable. Specify the fields, labels, and consuming application before adding a metropolitan portal export.

## Initial pipeline review

These findings need resolution before publishing a refreshed portal dataset.

- **Historical coverage was truncated.** After excluding footer text and numbered notes, the 2019 municipal source has 64 distinct seven-digit respondent codes with nonmissing municipality names. The 2024 harmonized workbook has 70 rows for 2019: 40 source codes appear, 24 source respondent codes are absent, and 30 workbook codes were not in that source. The earlier count of 96 included footer entries. The municipal pipeline now uses union joins and tracks participation by edition, so older-only respondents are retained when it is rebuilt. The 2025 harmonized CSVs still use the checked-in 2024 historical cohort and inherit its omissions.
- **Dashboard scaling mixes unrelated indicators.** `R/pemob_final.R` scales maximum-based indicators within variable and year. `R/pemob_data_portal.R` then recalculates that scale using the minimum and maximum across the entire combined table. The selected definition is percent of each question-year maximum. The portal step now preserves that scale, and tests cover ordinary, constant, all-zero, and all-missing groups. Portal outputs have not yet been regenerated.
- **Missing values were being converted to zero.** The dashboard pipeline now retains raw responses and missing reasons, leaves missing numeric values missing, and leaves undefined shares missing when their denominator is absent or zero. The export outputs have not yet been regenerated.
- **The new municipal question has no reported values in this file.** Every `1.3.1.A` cell in the provided 2025 municipal CSV is `NA` or `NR`. Keep the question in the harmonized schema, but do not present it as a measured 2025 indicator.
- **The export chain is not reproducible from the checkout.** The portal scripts reference a workbook under `data/` and intermediate files under `data/portal/final/`; those paths are absent. The checked-in workbook is under `tabelas/`. Resolve the file paths and generation order before treating a portal export as complete.
- **Metropolitan identity now uses state and reviewed aliases.** Historical and 2025 data retain `abbrev_state` and a composite `metro_key`; the 2025 CSV also retains the submitted name in `name_metro_source`. Only exact state-specific aliases that match a 2024 source region are merged. The CSV has 174 rows and 31 region keys, including 29 2025 respondents; two regions have no 2024 match and remain separate. The historical full rebuild and boundary review remain outstanding.

## Reporting-quality pilot

The initial profile found 30 single-year missing fare cells bounded by numeric
observations in the provisional 2019–2024 series; 13 have equal endpoints.
These are candidates for review, not approved imputations. For example, Manaus
reports 3.80 in 2020 and 2022 with a gap in 2021. Campinas reports 4.95 in 2020
and 5.15 in 2022; a linear estimate of 5.05 for 2021 might never have been a
charged fare. Confirm participation, service, and observation/reference dates
before estimating either gap. Prefer verified adjustment dates and previous
fares (`3.1.1.B`, `3.1.1.C`) when they can reconstruct the actual value.

Parsing must precede interpolation. The 2025 source has 81 currency-prefixed
fares and one missing fare; the existing comma-replacement/numeric conversion
would reject all 81 reported strings. The 2024 ciclofaixa series also contains
responses such as `15,24 km`, which should be parsed rather than imputed, and
mixed-class responses that require review rather than extraction of a number.

Cycling infrastructure needs a unit and definition audit. São Vicente reports
17,600 km of ciclovias in 2024 and 17.6 in 2025; Macaé reports 16,430 and 13,163
for ciclovias and ciclofaixas in 2025. These values occur in the raw sources.
They suggest unit errors, but the evidence does not yet establish the corrected
values. Do not automatically divide large values by 1,000, delete all upper-tail
observations, or enforce monotonic growth. Real projects, reclassification, and
remeasurement can also produce jumps.

### Short-gap interpolation gate (2026-10-17)

`R/pemob_interpolation.R` now extracts one-year interior missing cells for
review, but calculates an estimate only when the missing cell is an explicit
`NR` during confirmed participation and both adjacent endpoints are explicitly
accepted with review evidence. The parser's other missing markers (`NA`, `ND`,
dashes, blanks, and Excel error strings) remain distinct and are not treated as
item nonresponse. The generator found 738 bracketed missing cells in the
2019–2025 pilot: 71 marked `NR` in cycling variables and 667 marked `NA`; none
is currently eligible because no endpoints have been accepted with evidence.
It produced no estimates. The actual pipeline uses edition year as the time
coordinate because source-specific observation dates have not been verified.
Masked-value validation and comparison with dated fare adjustments remain
pending until an endpoint sample is reviewed.

Implement this pilot with the following constraints and deliverables.

- Keep source response, missing reason, parsed value, treated value, flags,
  method, and correction evidence or interpolation endpoints traceable by
  municipality, edition, and question. Keep raw data unchanged.
- Use cross-city statistics to flag candidates, then review within-city
  changes and cross-field consistency. Correct supported errors; represent
  confirmed invalid values as missing in the treated series without deleting
  the original observation. Keep unresolved suspects flagged and ineligible
  as interpolation endpoints.
- Propose linear interpolation only for one missing interior year with two
  reviewed, comparable endpoints. Preserve valid zeros, including fare-free
  service. Do not fill structural gaps, extrapolate, or interpolate across
  service/unit/definition changes. Treat this as an analytical estimate unless
  dated records support an actual reported-value correction.
- Write regression tests before implementing parsing, unit correction,
  exclusion, and interpolation. Cover ambiguous separators, mixed indicator
  text, missing reasons, contaminated endpoints, and no extrapolation.
- Validate estimates by masking reviewed observations; report errors and
  treatment counts by variable/year. Compare reported-only and treated
  distributions and dashboard scores, and disclose treatment in the portal.

Resolve the historical identity and question-map issues before applying these
rules. Interpolation must not conceal pipeline losses or be used to claim that
the survey represents municipalities that did not respond.

## Completion checks

- The harmonized municipal and metropolitan datasets include 2025 and preserve earlier years and newly participating places.
- The municipal code map documents the `12.2.1` to `12.1.1` link and the new `1.3.1.A` question.
- Fare and cycling parsers recover supported formats without silently interpreting ambiguous responses; original responses and missing reasons remain available.
- The reviewed anomaly ledger records correction/exclusion decisions and their evidence. Suspicion alone does not trigger automatic deletion or rescaling.
- Short-gap estimates satisfy the agreed participation/comparability rules, preserve valid observations, and have methods and endpoints recorded. Treatment coverage, validation error, and dashboard effects are reviewed before publication.
- The 2025 municipal portal JSON passes the same structural checks as the 2024 file, with any excluded places or variables documented.
- The publication contract identifies reported versus treated values and exposes correction, exclusion, and imputation status to the consumer.
- Tests and a clean run from a fresh checkout reproduce the committed outputs without relying on untracked files.
