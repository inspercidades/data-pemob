# PEMOB indicator review workbook

`pemob_indicator_review.xlsx` has separate municipal and metropolitan question-review sheets, a diagnostics sheet, participation summaries, answer snapshots, and field definitions. The builder includes questions with at least two valid reported answers. Reviewer entries in `Interesse`, `Incluir?`, and `Notas` survive regeneration by questionnaire level and question code; regeneration stops if a reviewed question disappears.

## Rebuild

Run from the repository root with the R packages in `renv.lock` and Python's `openpyxl` installed:

```sh
Rscript review/build_indicator_review.R
python3 review/format_indicator_review.py
```

The R builder accepts `PEMOB_REVIEW_OUTPUT_DIR` for a staged CSV build. Set it to an existing directory; the Python formatter reads the CSVs in `review/` and replaces the workbook only after it builds successfully.

## Inputs and scope

- Municipal and metropolitan answers: `data/dataverse_draft/{municipal,metropolitan}_long.csv` at the PR base. The builder counts `participated` responses whose `parse_status` is not `missing`; imputations do not count.
- Question wording and editions: `data/dataverse_draft/codebook.csv`. Reviewed municipal labels and categories: `data/registry/pemob_questions.csv`. The builder joins each questionnaire separately, so shared codes do not imply shared meaning.
- `site_live_by_year.csv` and `site_labels_snapshot.csv` pin municipal Observatório site evidence from `inspercidades/observatorio` commit `28d2cd8efae2061b01ab58cf785f8fa1e2cfb66f`. The live snapshot aggregates each `pemob-2019.ts` through `pemob-2024.ts` by year, label, question, and dashboard flag; it records whether any city has a value and a nonzero value. The labels snapshot records the site labels and menu options. These committed snapshots remove the need for a sibling website checkout during a workbook rebuild. Site presence describes that 2019–2024 snapshot, not live site state after that commit.
- The metropolitan questionnaire has no 2020 edition. Metropolitan site presence is omitted, and numeric-only diagnostics remain blank because reviewed answer types do not cover the full metropolitan questionnaire and edition range.

The two source snapshots have SHA-256 digests `9cbf93958f3447a0f663c3949385e286f6e8376f9b2b24688a1d7c7ce8be4d34` (`site_live_by_year.csv`) and `e60dddeba6506530e15a88cb5a47c3d35648ee9a8fdb8f16725c407ddaeec27d` (`site_labels_snapshot.csv`).

## Checks

```sh
Rscript tests/test-indicator-review-builder.R
python3 -m unittest discover -s tests -p 'test_indicator_review_formatter.py'
air format --check review/build_indicator_review.R tests/test-indicator-review-builder.R
```
