# Rebuilt history against the 2024 workbook

18 October 2026 · Internal working document

The rebuilt 2019–2024 municipal history agrees with the source files wherever
it differs from `tabelas/PEMOB Harmonizada 2024.xlsx`. Every difference falls
into a class that traces to the workbook or to an intended pipeline change.
The check also exposed misplaced question codes in the 2019 and 2020 sources,
which both the workbook and the earlier pipeline carried into the published
data. The workbook should not be used as an input or as a reference for
values.

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
| Missing code dropped | 80,552 | The workbook leaves `NA`, `NR`, `ND`, and `-` blank. |
| Number format | 11,271 | Same number, written differently (`0,2408` and `0.2408`, `2,000` and `2`). |
| Logical in place of value | 223 | The workbook holds `TRUE` or `FALSE` where the source has a number; 145 are zeros shown as `FALSE`. Most fall in `1.6.1.L`. |
| Answer dropped | 173 | The workbook is blank where the source has an answer, such as `Sim`/`Não` in 2019 `2.6.1.H` or `45km` in `1.6.1.G`. |
| Excel date serial | 55 | The workbook shows date serials such as `44287`; the rebuild writes ISO dates. One workbook cell shows the year 2046 as the date `1905-08-07`. |
| Whitespace | 31 | Extra spaces or line breaks. |
| Code repair | 223 | Cells moved by the code repairs below. |
| Value not in rebuild | 14 | 2019 `1.4.1.B`, which counts metro/rail stations in 2019 and accessible road terminals in 2024. The rebuild no longer links the two. |
| `NA` removed from text | 11 | The workbook deleted every `NA` inside text: `REGIÃO METROPOLITANA` became `REGIÃO METROPOLITA`, `CAMPINA GRANDE` became `CAMPI GRANDE`. |

Outside the repaired cells, no cell holds two different numbers or two
unrelated texts.

## Misplaced question codes

Two source files reuse a question code for different questions. The pipeline
now repairs them through `tabelas/pemob_code_repairs.csv`, which lists each
column by edition and position with the question text that identifies it.
The build stops if a listed column no longer holds the expected code.

| Edition | Columns | Source code | Correct 2024 code | Effect before the repair |
|---|---|---|---|---|
| 2019 | 363 | `4.8.1.H` | `4.7.1.I`, public-transport mode share | Public-transport share copied the bicycle share |
| 2019 | 403–405 | `7.2.1.A` | `7.2.1.B`–`D`, taxi fleet on electricity, natural gas, and hybrid | Values missing |
| 2020 | 101–103 | `4.4.1`, `4.4.2`, `4.5.1` | `4.5.1`, `4.5.2`, `4.6.1`, Mobility Plan participation, method, and themes | Each question held the answers of an earlier question |

The 2020 crosswalk already pointed to the repeated codes. A positional rename
in `R/pemob.R` then sent the three questions to the wrong columns.

The live dashboard shows the 2019 error. For all 16 cities with a 2019 bicycle
share, "POD - Percentual de viagens por transporte público" equals the bicycle
share; Recife shows 2.4%. The 2020 Mobility Plan questions do not appear on
the site.

## Number formatting

The comparison also exposed a formatting defect in the rebuild. Importing numeric Excel cells as
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
