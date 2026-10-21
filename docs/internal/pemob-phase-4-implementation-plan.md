# Phase 4 export implementation plan

Phase 4 prepares local Dataverse files. Publication remains a separate gate.

1. Read the rebuilt 2019–2025 municipal and metropolitan panels and the
   Phase 3 treated series. Check place-year and place-year-question keys.
2. Pivot participating rows to long form. Keep the source-derived response
   text, parsed number, parse status, and the literal missing token. Mark a
   source blank as `blank`; omit absent question-year cells instead of
   presenting them as submitted blanks. Retain imputed cells for skipped
   editions with `participated = FALSE`. Apply reviewed municipal treatments
   by exact key and response match. Keep other numeric values as reported.
3. Export participation for every place-year, edition question text and codes,
   the review/treatment ledger, and a manifest with the Git HEAD, worktree
   state, and file checksums. Build into a temporary directory, validate, then
   replace the local draft export directory.
4. Leave `value_type` and registry `unit` empty until Phase 5 supplies a
   reviewed registry. Keep parser-observed units in a separate column. Do not
   infer survey units or the meanings of missing codes.

Acceptance checks: regression tests cover literal `NA` versus a blank cell,
unasked questions, text and numeric values, treatment overlay integrity,
participation, codebook and provenance schemas. Run the connected rebuild,
focused tests, the full test suite, AIR, and output reconciliation. Do not
mark Phase 4 done or publish to Dataverse or the site.

The manifest's commit identifies the build only when
`working_tree_dirty = FALSE`. Regenerate the draft after committing the
pipeline before external publication.

Limits: harmonization has already combined some 2019 checkbox columns and
normalized numeric Excel cells. `value_raw` is the response text retained by
the rebuilt panel, not a byte-for-byte extract of each source workbook.
The 2020 municipal workbook exposes codes but no question-text header, so
its codebook text remains empty. Twenty 2019 crosswalk entries also lack a
direct match in the saved edition dictionaries; their text remains empty
pending source-level review.

Release schema: keep `value_raw` as text, `value_num` and `value_treated` as
nullable numbers, `missing_code` as the literal source token or `blank`, and
`parse_status` and `treatment_status` as separate fields. Keep `value_type`
and registry `unit` nullable. `parsed_unit` records only a unit visible in a
response. The codebook records both the edition's `source_code` and the
harmonized `code_variable`; it does not claim that every source question has
a one-to-one harmonized counterpart.
