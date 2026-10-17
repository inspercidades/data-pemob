# PEMOB dashboard: comparison brief and fix plan

17 October 2026 · Internal working draft

## Decision to guide the redesign

Make the dashboard useful for comparing municipalities and following changes over time. Show fewer indicators by default if their units, denominators, or observations cannot support those tasks. Keep the full reported data available in a table, with quality status and missing reasons. A chart eligibility rule must never delete a source response.

Use one indicator per plot. The main view should show time series for a small set of cities; the comparison view should show a dot plot for one year and one indicator. Put several indicators in separate, aligned small facets. Each facet keeps its own unit and scale. Remove the radar chart and its requirement to select three to five variables.

## Evidence from the current dashboard

- The live distribution chart converts each city value to its share of the sum of all cities' values, then fixes the axis at 0–100%. The radar uses the same transformation across fares, counts, and existing percentages. A city share of survey responses is not a measure of mobility provision or performance. See `observatorio/.../distribution-chart.tsx:104-169` and `radar-chart.tsx:63-79`.
- The evolution chart inserts zero for a missing city–year observation. This draws false collapses and recoveries. See `observatorio/.../evolucao-chart.tsx:58-72`.
- The frontend reads bundled annual TypeScript data, while this repository has a separate portal JSON export. Their values and treatments differ. The publishing source and field semantics need to be reconciled before regenerating the dashboard.
- The current PEMOB roadmap identifies historical respondent losses, missing values that can become zero, unit and parsing problems, and unresolved outliers. Its one-year interpolation pilot is conditional on source and definition checks. See `ROADMAP-2025.md` and `docs/internal/codebase-review-2026-10-17.md`.

The bundled frontend files for 2019–2024 contain 110 chart-marked indicator labels and 70 municipality slots per year. Of the 7,700 possible municipality–indicator series, 500 have a non-null value in 2024 and at least five non-null values across the six years; 146 have all six. Among the five default cities and five default indicators, the five-of-six rule leaves eight of 25 series. These counts describe the current files, not survey quality or applicability. Historical processing errors may change them after repair.

## Indicator contract

Create a reviewed registry for chart candidates. Each entry records the PEMOB question code and text by edition, unit, geographic and service scope, reference period, whether zero is valid, any numerator and denominator, and allowed comparison modes. Record the source and reference year of every external denominator. Keep the reported value, treated value, and treatment status separate.

Use a denominator only when it answers the comparison question.

| Indicator family | Candidate display | Main condition |
| --- | --- | --- |
| Fares, speeds, shares, and percentages | Native currency, km/h, or percentage points | Check units and definitions; do not divide by population or city totals. |
| Vehicle fleets and staff | Count plus rate per relevant population or service population | State service boundaries and the population year. |
| Cycling infrastructure and stops | Length or count plus a measure per urbanized area, road length, or network size | Choose the denominator by the infrastructure question and validate geographic coverage. |
| Passenger demand and operating finance | Raw amount plus a rate per resident, passenger, trip, or vehicle-km where appropriate | Match the numerator and denominator's service, place, and period. |
| Accessible facilities and other parts of a known total | Share of that total | Validate both fields and keep an undefined ratio missing. |

Municipal area and urbanized area are not interchangeable. An area rate may help compare infrastructure density, but it should not become a universal mobility score. Some measures should remain in their original units. Peer groups by city size or urban form may help interpretation, but they do not repair a bad measure.

## Proposed quality gate

Apply three gates in sequence. The thresholds below are release candidates, not validated statistical cutoffs.

1. **Indicator gate.** Chart an indicator only after its question mapping, unit, reference period, and denominator have been reviewed across displayed editions. Withhold indicators with unresolved definition or unit changes, contaminated ratios, or known severe source errors. Mark specialized indicators as applicable only to their relevant cities.
2. **Observation gate.** Plot a municipality–year value only if it is a valid reported observation or an explicitly approved correction. Preserve true zero. Leave unanswered, nonparticipating, nonapplicable, and unresolved suspicious cells blank with distinct reasons. Display an approved estimate with a distinct marker; an estimate does not count as an observed year for eligibility.
3. **View gate.** For the default six-edition time view, start with at least five observed years, including the latest edition, and no more than one interior gap. For a one-year comparison, start with at least 20 valid, applicable municipalities in the selected year and show the denominator and coverage count beside the plot. Let users inspect a sparse indicator in a labeled exploratory view, but do not silently present it as a comparable default.

Test the view gate after repairing historical coverage. Report eligible indicators and cities by edition, subject, and municipality size; inspect whether the rule removes particular services or city groups. If a strict gate leaves no useful comparison for a topic, publish the coverage gap rather than relax the definition or fill it with unreviewed estimates.

## Display rules

- Start with one indicator, its unit, its source question, and a small set of cities. Show an observed point for each valid year and break the line at missing years. Do not join across a gap by default.
- In the one-year view, plot observed city values on a scale suited to that indicator. Show selected cities against the eligible city distribution and state how many cities contributed. Avoid a fixed 0–100 axis except for genuine percentages.
- When several indicators are selected, use small facets. Give each facet its own axis and unit; do not imply that values on different facets share a common scale. Keep city colors consistent.
- Show raw and derived measures as separate, clearly named choices. Every rate names its denominator, multiplier, and reference year. A tooltip or table identifies reported, corrected, and estimated values.
- Never use a missing value as zero in chart calculations, fill badges, or tooltips. Avoid an interpolated line that looks identical to observed data.

## Fix sequence and acceptance checks

| Step | Work | Evidence required before moving on |
| --- | --- | --- |
| 1. Stop false chart values | Replace missing-as-zero in the evolution view; preserve gaps and valid zeros. Remove share-of-city-total calculations from radar and distribution. | Tests with missing, genuine zero, negative or undefined ratios where relevant; visual checks on a known sparse series. |
| 2. Reconcile publication data | Trace bundled frontend files to source outputs. Compare IDs, question labels, units, and values with portal JSON. Repair respondent losses, missing-value handling, and parsing before regeneration. | Reproducible export; per-edition municipality and indicator reconciliation; documented differences from the live data. |
| 3. Review chart indicators | Build the indicator contract and choose a small first set with meaningful native and derived measures. Define external denominators only where the numerator matches them. | Reviewed question and unit map; denominator provenance; invalid and undefined-ratio tests. |
| 4. Apply the quality gate | Calculate status and eligibility after source review. Evaluate five-of-six and one-year coverage thresholds against every subject and city-size group. Keep excluded observations in the table. | Coverage report, list of withheld indicators, sensitivity to the proposed thresholds, and a decision on the final gate. |
| 5. Rebuild the interface | Make time series primary; add a single-indicator comparison plot and small facets; remove the radar and forced multi-variable selection. | Task-based checks: compare two differently sized cities, explain a rate, spot a missing year, and identify an estimate. |
| 6. Pilot gap treatment | Review one-year interior gaps only after source, service, and endpoint checks. Show estimates distinctly and keep reported-only comparisons available. | Exception ledger, masked-observation error check, and before/after coverage and chart comparison. |

Do not publish regenerated data until the frontend and data pipeline agree on the same value, unit, missing status, and treatment meaning. The first useful release can ship a narrow set of audited indicators; it does not need a rate for every PEMOB question.
