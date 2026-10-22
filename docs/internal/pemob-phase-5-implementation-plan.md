# Phase 5 question registry implementation plan

## Scope and evidence

Build a local, reproducible registry keyed by `(level, code_variable)` from the
Phase 4 edition codebook and the harmonized panels. The current codebook must
yield 473 municipal and 342 metropolitan pairs; the builder fails if a panel
question is absent. Preserve the edition codebook as the authoritative map of
`year`, `source_code`, and source `question_text`. Keep source-only questions in
the evidence table even when they have no harmonized registry key.

Use the v1 portal dictionary as a *seed* for municipal display labels and
classification, the older dictionaries and category tree as conflicting
evidence, and the sibling live site as read-only evidence. Never treat code
equality, normalized text, or a seed flag as a reviewed concept, unit, type,
or eligibility decision. A separate reviewed override table records any
evidence-backed corrections and concept links, including reviewer and source.
Do not change the 78 pending cycling ledger decisions.

Snapshot the 2024 live labels and category tree with the scripts under
`scripts/`, recording the sibling commit and path. These snapshots let a fresh
checkout rebuild without the sibling repository. Retain live items with a
missing label. Compare v1 category triples with `dim_category.csv` and the
live tree, preserving every discrepancy.
The evidence CSV escapes source-text control characters (for example CR and
LF) so multiline questionnaire cells remain readable without altering raw
inputs.

## Outputs and schema

- `data/registry/pemob_questions.csv`: exactly one row per pair, with source
  and display label, category, subcategory, mode, unit, value type, valid
  editions, concept ID and review provenance. Missing review evidence means a
  missing metadata value, never an inferred value. Labels must be unique
  within each level whenever present.
- `data/registry/pemob_question_evidence.csv`: edition source code/text,
  harmonized key when mapped, seed and legacy labels/classification, and
  unresolved source-only rows. This table must not collapse source evidence
  into a chosen display label.
- `data/registry/pemob_category_evidence.csv`: seed, dimension, and live
  category/label presence flags, discrepancies, and live source provenance.
- `data/registry/pemob_concept_candidates.csv`: provisional text matches with
  explicit pending status unless a reviewed concept link exists.
- `data/registry/pemob_question_eligibility.csv`: per question and product,
  threshold counts, per-edition coverage and response validity, decision
  (`eligible`, `excluded`, or `unresolved`), and explicit reasons.
- Reviewed overrides live in a small source CSV under `tabelas/`; generated
  outputs are rebuilt by R, not manually edited.

## Eligibility rules

Use participating places as the denominator in each edition where the
question is valid. A/table needs at least four valid editions, at least 10%
coverage in each counted edition, and at least 90% type-valid responses.
C/dashboard needs five, 20%, and 98%. Numeric type validity is successful
numeric parsing. Categorical/text validity requires documented response
options or format. Unknown type or undocumented validity remains `unresolved`.
Keep eligibility distinct from the seed's historic product flags.

For provisional numeric screens, require an exact source-question match to
both the v1 and legacy question text and legacy `tipo=numeric`. Store the
supported editions and evidence in `screen_value_type` and `type_basis`;
never promote these into reviewed `value_type` or the long exports. Reviewed
unit/type values carry their reviewed editions; the long export fills those
fields only for those editions.

## Integration and acceptance

Write failing tests first for pair cardinality, evidence preservation,
duplicate labels, concept review requirements, threshold boundaries,
unresolved categorical/text validity, and long-export metadata joins. Then
implement the builder and connect reviewed unit/type to both Phase 4 long
exports without changing any row, treatment status, or missingness field.
Regenerate the local draft and reconcile keys, counts, and manifest checksums.
Run focused and full tests, AIR formatting, and a fresh export rebuild.

## Open review risks

Most metropolitan display metadata and many municipal seed fields lack
review evidence. The 232 normalized-text cross-level candidates are pending
until wording, target measure, and substantive scope are inspected. Geography
alone may differ, but narrower populations or management restrictions require
different concepts. An ID does not by itself establish direct comparability.
The 2020 municipal source has no question-text header and some 2019 crosswalk
links lack source text. Those gaps remain explicit. No site or Dataverse
publication is in scope.

The first build found 149 source-only rows, 160 distinct live
label/question pairs (eight with missing labels), and 87 category-tree
discrepancies. These are snapshot checks, not permanent schema invariants.
Product decisions based on `screen_value_type` are provisional, and questions
without type evidence remain unresolved.
