# Rebuilt history against the 2024 workbook

18 October 2026 · Internal working document

The rebuilt 2019–2024 municipal history agrees with the source files wherever
it differs from `tabelas/PEMOB Harmonizada 2024.xlsx`. Every difference falls
into a class that traces to the workbook or to an intended pipeline change. The
workbook should not be used as an input or as a reference for values.

Run `Rscript R/check_pemob_baseline.R` after `Rscript R/build_pemob.R` to
reproduce the counts. The check writes the cell-level differences to
`data/pemob_baseline_differences.csv`, except for the two bulk classes.

## Coverage

All 420 workbook rows (70 municipalities in each edition) match a rebuilt
place-year. Of these, 268 are respondents; the other 152 rows pad
nonparticipating editions and hold no values in either file. The rebuilt
history adds the respondents the workbook dropped and covers 107
municipalities.

## Differences by class

The comparison covers 198,240 cells in the 472 questions the two files share.

| Class | Cells | Cause |
|---|---:|---|
| Missing code dropped | 80,590 | The workbook leaves `NA`, `NR`, `ND`, and `-` blank. |
| Number format | 11,287 | Same number, written differently (`0,2408` and `0.2408`, `2,000` and `2`). |
| Logical in place of value | 223 | The workbook holds `TRUE` or `FALSE` where the source has a number; 145 are zeros shown as `FALSE`. Most fall in `1.6.1.L`. |
| Answer dropped | 173 | The workbook is blank where the source has an answer, such as `Sim`/`Não` in 2019 `2.6.1.H` or `45km` in `1.6.1.G`. |
| Excel date serial | 55 | The workbook shows date serials such as `44287`; the rebuild writes ISO dates. One workbook cell shows the year 2046 as the date `1905-08-07`. |
| Whitespace | 31 | Extra spaces or line breaks. |
| Value not in rebuild | 14 | 2019 `1.4.1.B`, which counts metro/rail stations in 2019 and accessible road terminals in 2024. The rebuild no longer links the two. |
| `NA` removed from text | 11 | The workbook deleted every `NA` inside text: `REGIÃO METROPOLITANA` became `REGIÃO METROPOLITA`, `CAMPINA GRANDE` became `CAMPI GRANDE`. |

No cell holds two different numbers or two unrelated texts.

## Fixed in the rebuild

The comparison exposed one rebuild defect. Importing numeric Excel cells as
text printed them with 17 significant digits, such as `76.099999999999994`
for 76.1. `read_pemob_source()` now formats numeric cells with 15 significant
digits. The change affected 1,763 cells in the 2025 municipal output, all of
them numerically equal before and after. Long decimals that remain, such as
`0.0466666666666667`, are formula results stored in the source.

## Earlier difference counts

Earlier counts are superseded. The codebase review's 49 differences compared the rebuild with the
workbook-based 2025 file. The reproduction log's 668 and 1,164 cell
differences compared new runs with stale checked-in outputs. The classes above
cover the same cells, including the 35 `1.6.1.F` values, which are workbook
number formatting (`15,410` for 15.41).
