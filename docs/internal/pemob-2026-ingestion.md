# PEMOB 2026 source record

Downloaded on 1 November 2026 from the [Ministry of Cities PEMOB 2026 page](https://www.gov.br/cidades/pt-br/assuntos/mobilidade-urbana/pesquisa-nacional-de-mobilidade-urbana-pemob-2026).

| Source | Responses | SHA-256 |
|---|---:|---|
| `data-raw/pemob_municipal_2026.xlsx` | 96 municipalities | `215066a6dc506f19d95c13704babb62c4323d3223b54805cd260d3170ad6ea01` |
| `data-raw/pemob_metropolitana_2026.xlsx` | 37 regions | `1317a47952b40ace81543667a77b2d62f6ce3eac105749248ffada2a6eb91776` |

Both workbooks place question text in row 1 and question codes in row 2. The municipal file has two empty trailing columns. After normalizing identifier labels, each questionnaire has the same question codes as its 2025 source. Question wording differs only in calendar-year references. The municipal fund code `12.1.1` continues to map to the historical code `12.2.1`.

The completed 2026 panels retain every earlier response. Nine new cycling observations triggered the review rules and remain pending in `docs/internal/pemob-review-ledger.csv`. The Dataverse draft contains the 2026 observations; reviewed type and unit metadata are left empty for 2026 until reviewed.

Four 2026 metropolitan names changed while their historical regions kept the same identity: Fortaleza, Sobral, Cariri, and Vale do Itajaí/Vale Europeu. The alias table links those responses to the existing keys, leaving 46 distinct regions across editions.
