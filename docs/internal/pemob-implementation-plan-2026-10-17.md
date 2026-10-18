# PEMOB codebase review implementation plan

Status: reference. `ROADMAP.md` sets the current order and scope; this plan
records the stage-level acceptance criteria. It translates the findings in
[`codebase-review-2026-10-17.md`](codebase-review-2026-10-17.md)
into implementation stages. It does not authorize publishing treated data.

## Requirements summary

- Keep the original self-reported response and source provenance available.
- Retain all actual responding geographic units across editions; distinguish
  no participation from item nonresponse and nonapplicability.
- Confirm question identity and units before constructing historical series.
- Parse supported response formats without discarding values or inventing
  interpretations for ambiguous text.
- Correct only documented errors, flag suspects, and keep treatment decisions
  auditable by geographic unit, edition, and question.
- Pilot short interior-gap estimates only after comparability and endpoint
  validity are established. Keep estimates distinguishable from observations.
- Preserve the existing municipal portal contract unless its consumer agrees
  to a reviewed contract change.

## Acceptance criteria

1. Each source edition has a reproducible row/key inventory that distinguishes
   respondent rows from headers, footers, notes, and unobserved units.
2. Every harmonized place-year key maps to a source respondent or is explicitly
   classified as nonparticipating; no older respondent disappears through a
   join.
3. Each cross-edition question correspondence has reviewed question text,
   response type, and unit; changed measures do not share a time series.
4. Numeric parsing has tests for decimal commas/points, currency, explicit
   metric units, ambiguous separators, free text, and missing tokens.
5. Reported, parsed, corrected, excluded, and imputed states remain traceable;
   raw source values are preserved.
6. The initial imputation pilot fills only eligible one-year interior gaps with
   two reviewed endpoints. It never extrapolates or fills nonparticipation,
   nonapplicability, or an unresolved endpoint.
7. The fare and cycling pilot reports candidate counts, decisions, validation
   errors, and effects on summaries/dashboard scores before portal use.
8. A documented command regenerates harmonized data and portal artifacts from
   declared inputs; a fresh-checkout run reproduces the validated artifacts.

## Implementation stages

### 1. Lock the baseline and input contracts

**Scope:** `data-raw/`, `tabelas/`, `data/`, current tests, and the 2025 reader
in `R/pemob_2025.R`.

- Inventory files, workbook sheets, editions, geographic identifiers, question
  headers, encodings, response tokens, and file provenance.
- Record which files are raw inputs, manually harmonized baselines, generated
  outputs, and saved portal artifacts. Identify the authoritative metadata
  inputs currently missing from the documented portal chain.
- Add tests around source row selection, code uniqueness, and the existing
  2025 reader before changing its behavior.
- Preserve the source missing token rather than collapsing `NA`, `NR`, `ND`,
  `-`, and blank into one state before eligibility is known.

**Gate:** inventories identify eligible respondent records without counting
numbered notes/footers. Existing 2025 tests still pass. No data is rewritten.

### 2. Repair historical inputs, identity, and question maps

**Scope:** `R/pemob.R`, `R/pemob_metropolitana.R`, code crosswalks, and tests.

- Select `pemob_municipal` explicitly in the municipal crosswalk workbook;
  read the metropolitan map from its named sheet.
- Replace the municipality-to-`name_metro` join with an explicit metropolitan
  dimension and stable regional identity. Include state where needed, and
  document boundary/name changes rather than relying on exact strings.
- Build municipality-year and metro-year coverage from valid respondents.
  Join on the union of geographic identities and preserve a separate
  participation indicator.
- Review all question correspondences against source text, answer format, and
  unit. Resolve known code collisions, beginning with municipal `1.4.1.B`.
  Review positional 2020 code repairs and the 2025 changes to `12.2.1` and
  `1.3.1.A` in the same map.
- Stop the build with a useful error when a required question fails. Produce a
  list of approved omissions for questions that genuinely do not exist in an
  edition.

**Tests first:** source reader selects the correct sheets; a municipality or
metro seen only in an older edition survives; repeated names across states do
not collide; a changed question is not linked; failed required questions block
the output.

**Gate:** all valid respondents appear exactly once per edition, all
place-edition keys are classified, and unresolved question mappings are listed
and excluded from trend comparisons.

### 3. Normalize responses without losing source information

**Scope:** harmonization type conversions and portal parsing in
`R/pemob.R`, `R/pemob_metropolitana.R`, `R/pemob_final.R`, and
`R/pemob_portal_final.R`.

- Preserve the raw response as text and parse to a typed value using
  question-specific formats/units; do not infer a response type from 2024 and
  coerce every earlier edition to it.
- Parse supported currency strings such as `R$ 5.50` and explicit units such as
  `15,24 km`. Treat number-plus-comment and ambiguous `1.320` formats as
  review cases until their meaning is established.
- Keep raw missing tokens, parser failures, nonparticipation, and
  nonapplicability distinct.
- Use fare reference dates and historical/current fare fields where these
  establish timing. Record whether values refer to survey edition, reference
  year, or actual effective date.

**Tests first:** verify numeric values and provenance for currency, commas,
points, `km`, `m`, mixed-class prose, `RS3,45`, and each missing token. Verify a
malformed response raises a review flag rather than silently becoming zero.

**Gate:** all supported formats parse correctly; no conversion loss occurs
without an explicit flag; raw strings remain recoverable.

### 4. Build the correction and outlier review layer

**Scope:** start with fare `3.1.1.A` and cycling `1.6.1.G`/`1.6.1.H`; add a
small exception ledger and derived treated values.

- Generate candidate flags from domain limits, abrupt within-city changes,
  unit shifts, and cross-field inconsistency. Use robust cross-city statistics
  to prioritize review, not to declare values wrong.
- Review São Vicente's ciclovia and ciclofaixa trajectories, Macaé's 2025
  lengths, São Bernardo do Campo's unit/format changes, and other flagged
  records against source cells and, where available, municipal evidence.
- Record the raw value, parsed value/unit, treated value, reason, evidence,
  reviewer decision, and timestamp/edition. Keep anomaly flag, correction,
  exclusion, and imputation states separate.
- Apply a unit correction only with evidence. Keep a confirmed invalid value in
  raw data and represent it as missing in the treated measure with a reason.
  Do not automatically trim, winsorize, or divide values by a fixed factor.

**Tests first:** confirmed correction changes only the treated value; an
unresolved flag cannot become a correction; genuine zeros survive; excluded
values stay present in raw data; ciclovias and ciclofaixas remain distinct.

**Gate:** every treated change has a ledger entry. No candidate is changed
solely because it is a statistical outlier.

### 5. Pilot short-gap interpolation

**Scope:** one-year interior gaps in the two pilot domains, only after Stages
2–4.

- Define the eligible set as item nonresponse with valid participation,
  unchanged service/question/unit, and two adjacent reviewed endpoints.
- Begin with linear interpolation over reference time. Prefer dated fare
  adjustments to estimate the actual fare. Retain linear values as estimates
  when the source cannot establish the actual historical fare.
- Do not fill leading/trailing gaps, multi-edition gaps, nonparticipation,
  nonapplicability, or gaps bounded by flagged/unreviewed observations.
- Do not constrain fares to be monotone or infrastructure to grow monotonically.
  Preserve observed zero fares and zero infrastructure reports pending their
  own validity review.
- Store the estimate, method, endpoint IDs/values/dates, and eligibility reason.

**Tests first:** equal and unequal endpoints; irregular reference dates; valid
zero; missing participation; long gaps; endpoints corrected/excluded/flagged;
no extrapolation; raw series unchanged.

**Validation gate:** mask a reviewed sample of valid observations and report
error and coverage by variable. Compare fare estimates with any known fare
adjustment dates. Publish no imputed series until coverage and error are
reviewed.

### 6. Repair calculations and define the published measure

**Scope:** `R/pemob_final.R`, `R/pemob_data_portal.R`, and portal consumers.

- Preserve missing numerators and denominators; never turn unknown values or
  undefined ratios into numeric zero.
- Choose and document maximum-based score semantics. Calculate scores by
  question and edition, handle constant/all-zero groups explicitly, and ensure
  a group maximum maps to the intended maximum score.
- Define whether dashboard/table outputs use reported or treated data. Produce
  comparison summaries for both, including city ranks/scores that materially
  change under corrections or imputation.
- Check the saved 2019–2024 JSON contract against the consuming frontend before
  changing fields or statuses. Add a way to expose estimate/correction status
  to users before the portal uses treated values.

**Tests first:** real zero versus missing; missing numerator/denominator; zero
denominator; constant/all-zero groups; each score grouped by question/year;
reported-versus-treated output flags and JSON structure.

**Gate:** approved formula and display policy; no missing-to-zero conversion;
JSON contract passes against the actual consumer; score changes are reviewed.

### 7. Make the build reproducible and release in stages

**Scope:** source/export scripts, README, dependency manifest/lockfile, tests,
and generated artifacts.

- Establish one documented entry point and generation order from sources to
  harmonized tables to metadata/calculations to portal export. Remove dependence
  on interactive objects and undocumented file copies.
- Declare required packages and lock the environment after the pipeline runs.
- Run the full build from a clean checkout and compare regenerated artifacts
  with reviewed outputs. Keep a 2024 regression comparison and report expected
  changes from known corrections.
- Publish the 2025 municipal file only after prior gates pass. Keep metropolitan
  harmonized outputs; add metropolitan portal export only after its consumer
  and schema are defined.

**Gate:** one command reproduces validated outputs from declared inputs; tests
pass; coverage and treatment ledgers are complete; a reviewer approves the
reported-versus-treated differences and portal disclosure.

## Cross-cutting risks and mitigations

| Risk | Mitigation |
|---|---|
| Imputation fabricates a fare never charged during the year | Use effective-date evidence; label modelled values as estimates and test on masked observations |
| Outlier rules remove true large cities or real expansion | Generate review candidates; require source/domain evidence for changes; retain raw values |
| Survey cohorts look complete while participation is unknown | Build participation from source respondents, not padded workbook rows |
| Same code means a different question across editions | Compare text, unit, and answer type; exclude unresolved pairs from trends |
| Portal changes misstate prior trends or surprise consumers | Preserve contract until consumer check; compare prior JSONs and disclose treatment status |
| One failed question silently disappears from output | Fail required builds closed and report approved edition-specific omissions |

## Verification sequence

Run the smallest targeted tests at each stage before moving to the next. At
release, run the full source-to-export build from a clean checkout; verify
coverage keys, response-state counts, correction/imputation ledgers, score
boundaries, JSON schema, and comparison reports. Do not regenerate or publish
portal outputs before the semantic, data-quality, and consumer gates pass.
