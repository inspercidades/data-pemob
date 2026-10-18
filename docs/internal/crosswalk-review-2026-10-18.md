# Cross-edition question links

18 October 2026 · Internal working document

The crosswalk in `data-raw/pemob_códigos.xlsx` links most questions
correctly, but several 2019 and 2020 blocks were paired by position after the
questionnaire changed its item order. The pipeline now replaces those links
through `tabelas/pemob_crosswalk_corrections.csv`. Each row names the code the
crosswalk holds, the code that replaces it (empty to unlink), and the reason.
The build stops if the crosswalk no longer holds the expected code, or if one
source column feeds two questions in the same edition.

The live dashboard shows at least one of these errors: its 2020 bike-lane
length ("Extensão de Ciclovias Exclusivas") is 0 for Recife and Curitiba,
which is the 2020 rail length. The sources report 18 km and 31 km.

## Method

Each link was checked against the question text of both editions. The 2021–2024
files carry the question in their header row; 2019 carries an item label in
the header and the question in the questionnaire sheet; 2020 carries only the
questionnaire sheet.

1. Text overlap between each edition's question and the linked 2024 question,
   and against every other 2024 question in the same section. Links where
   another 2024 question matched clearly better were reviewed by hand.
2. Value agreement between adjacent editions for numeric questions. A place
   that reports 108 km of bike lanes in 2019 and 111 km in 2020 should do so
   under the same 2024 code.
3. Source columns linked to more than one 2024 question.
4. 2025 against 2024 by code. They match except for typo fixes.

Where text and values disagreed, the text decided: the 2019 labels come from
the data file itself, and the values are sparse and noisy.

## Corrections

| Level | Edition | Questions | Problem | Correction |
|---|---|---|---|---|
| Municipal | 2019 | `1.4.1.B`–`G`, terminals and stations | 2019 alternates road terminals and rail stations; 2024 lists terminals first | Relink by item text; 2019 stations now feed `1.4.1.E` |
| Municipal | 2019 | `3.2.1.A`–`3.2.8.E`, revenue by mode | 2019 groups revenue by type, then mode; the crosswalk paired them by position | Relink fare revenue, advertising, and other sources by mode |
| Municipal | 2019 | `3.2.k.B` and `C`, subsidies | 2019 asks for one public subsidy; 2024 splits it into two | Unlink |
| Municipal | 2019 | `3.1.2`, `3.1.2.A`, other fares | The 2019 description fed a yes/no question | Description feeds `3.1.2.A`; `3.1.2` unlinked |
| Municipal | 2019 | `2.6.1.A`–`H`, punctuality data by mode | One 2019 answer for all modes was copied to eight modes | Unlink |
| Municipal | 2020 | `1.6.1.A`–`M`, network length | 2020 omits the pedestrian items and monorail, so its letters start at BRT | Relink by item text |
| Municipal | 2020 | `2.1.1.A`, `2.1.1.C`, speed | 2020 asks for exclusive bus lanes only, which is 2024 `2.1.1.C` | Relink |
| Metropolitan | 2019 | `1.3.1.D`, `1.3.1.E`, bus fleet | 2019 counts buses with lifts, which is 2024 `1.3.1.E` | Relink |
| Metropolitan | 2019 | `3.1.1.A`–`I`, three largest flows | One 2019 cell lists all three flows, and was copied to each | Split the cell; see below |
| Metropolitan | 2019 | `3.1.8`, fare integration | The list of integration types fed a yes/no question | Unlink `3.1.8`; keep `3.1.8.A` |
| Metropolitan | 2019 | `3.2.k.B` and `C`, subsidies | One 2019 subsidy was copied to both 2024 subsidy questions | Unlink |
| Metropolitan | 2022 | `2.4.6.A`–`2.4.7.B`, punctuality | 2022 orders monorail and aeromóvel opposite to 2021, 2023, and 2024 | Swap |

Some 2024 questionnaires are inconsistent within a block. In the metropolitan
`2.4.6` block, the parent question names the aeromóvel and the items name the
monorail; respondents follow the item text. The harmonized data keep the 2024
codes, so `2.4.6.A` means monorail punctuality in every edition.

## Split cells

The 2019 metropolitan file lists the three largest intermunicipal flows, their
fares, and their previous fares in one cell each, separated by `;` or line
breaks. `split_pemob_list_cells()` writes the parts to `3.1.2.A[1]`–`[3]`,
`3.1.2.B[1]`–`[3]`, and `3.1.4[1]`–`[3]`, which feed 2024 `3.1.1.A`–`I`. A
missing code fills all three parts. A cell with one value fills the first part
only.

## Checked and left unchanged

- Taxes by mode (`3.3.1`), cost shares (`3.7.1`, metropolitan `3.6.1`), taxi
  fares (`3.6.1`), and punctuality by mode (`2.6.2`) differ in wording only.
- 2021–2023 links match 2024 apart from years in the text, except the 2022
  swap above.
- Two value flags in 2021–2023 (`3.1.1.A`, `1.5.1.E`) have matching question
  text and look like reporting changes rather than link errors.

## Open questions

- 2019 "Subsídio público" could map to 2024 direct subsidy (`3.2.k.C`, subvenção)
  rather than being unlinked. Confirm with SIMU or the questionnaire notes.
