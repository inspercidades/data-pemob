"""Format level-specific PEMOB indicator review inputs as an Excel workbook."""

import csv
import os
import tempfile
from pathlib import Path

from openpyxl import Workbook, load_workbook
from openpyxl.cell.cell import ILLEGAL_CHARACTERS_RE
from openpyxl.formatting.rule import FormulaRule
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation

HERE = Path(__file__).parent

MUNICIPAL = [
    ("code", 10), ("short_question", 38), ("full_question", 70),
    ("subject", 15), ("type", 14), ("coverage_cities", 17),
    ("coverage_years", 18), ("response_rate_mean", 17),
    ("panel_cities", 19), ("quality_flags", 35),
    ("site_presence", 23), ("interest", 12), ("checklist", 12),
    ("notes", 35),
]
METROPOLITAN = [
    ("code", 10), ("full_question", 70), ("coverage_places", 18),
    ("coverage_years", 18), ("response_rate_mean", 17),
    ("panel_places", 20), ("quality_flags", 35),
    ("interest", 12), ("checklist", 12), ("notes", 35),
]
EXTRA_LABELS = {
    "coverage_places": "Regiões com resposta",
    "coverage_places_positive": "Regiões com valor positivo",
    "panel_places": "Regiões com 4+ edições",
    "panel_places_full": "Regiões em todas de 2021 a 2025",
    "site_presence": "Presença no site",
    "level": "Questionário",
    **{f"cities_{year}": f"Municípios {year}" for year in range(2019, 2026)},
    **{f"places_{year}": f"Regiões {year}" for year in (2019, 2021, 2022, 2023, 2024, 2025)},
}
EXTRA_DEFINITIONS = {
    "coverage_places": "Regiões metropolitanas com resposta válida em ao menos uma edição do questionário metropolitano.",
    "coverage_places_positive": "Regiões metropolitanas com valor numérico positivo.",
    "panel_places": "Regiões metropolitanas com resposta válida em quatro ou mais das seis edições disponíveis (2019 e 2021 a 2025).",
    "panel_places_full": "Regiões metropolitanas com resposta válida em todas as edições de 2021 a 2025.",
    "site_presence": "Resume a presença da pergunta no dashboard e na tabela do site. A pergunta metropolitana não recebe esse campo sem evidência específica.",
    "level": "Questionário municipal ou metropolitano; o código da pergunta só é único dentro de cada questionário.",
    **{f"cities_{year}": f"Municípios com resposta válida em {year}." for year in range(2019, 2026)},
    **{f"places_{year}": f"Regiões metropolitanas com resposta válida em {year}." for year in (2019, 2021, 2022, 2023, 2024, 2025)},
}
INTEGERS = {
    "coverage_cities", "coverage_cities_positive", "coverage_places",
    "coverage_places_positive", "n_years", "n_answers", "question_wording_versions",
    "panel_cities", "panel_cities_full", "panel_places", "panel_places_full",
} | {f"cities_{year}" for year in range(2019, 2026)} | {
    f"places_{year}" for year in (2019, 2021, 2022, 2023, 2024, 2025)
}
SHARES = {
    "response_rate_mean", "response_rate_latest", "zero_share",
    "unparsed_share", "jump_share", "repeat_share",
}
REVIEWER = ("interest", "checklist", "notes")
REVIEW_LABELS = ("Interesse", "Incluir?", "Notas")
CHOICES = {"interest": '"alta,média,baixa"', "checklist": '"sim,não"'}
HEADER_FILL = PatternFill("solid", fgColor="1F3A5F")
REVIEW_FILL = PatternFill("solid", fgColor="FFF4CC")
YES_FILL = PatternFill("solid", fgColor="D9EAD3")
NO_FILL = PatternFill("solid", fgColor="F4CCCC")
WHITE_BOLD = Font(bold=True, color="FFFFFF")


def read_csv(directory, name):
    with (directory / name).open(newline="", encoding="utf-8") as file:
        return list(csv.DictReader(file))


def styled_header(row):
    for cell in row:
        cell.font = WHITE_BOLD
        cell.fill = HEADER_FILL
        cell.alignment = Alignment(wrap_text=True, vertical="center")


def typed_value(name, value):
    if value in ("", None):
        return None
    if name in INTEGERS:
        return int(float(value))
    if name in SHARES:
        return float(value)
    return ILLEGAL_CHARACTERS_RE.sub("", str(value))


def reviewer_entries(path):
    """Read only entered decisions, rejecting ambiguous or orphaned keys."""
    if path is None or not path.exists():
        return {}
    workbook = load_workbook(path, read_only=True, data_only=True)
    entries = {}
    for sheet_name, level in (("revisão", "municipal"), ("municipal", "municipal"),
                              ("metropolitana", "metropolitan")):
        if sheet_name not in workbook:
            continue
        sheet = workbook[sheet_name]
        headers = [cell.value for cell in sheet[1]]
        if "Código" not in headers:
            raise ValueError(f"Missing Código header in {sheet_name}")
        indexes = {name: headers.index(name) for name in REVIEW_LABELS if name in headers}
        if set(indexes) != set(REVIEW_LABELS):
            raise ValueError(f"Missing reviewer columns in {sheet_name}")
        code_index = headers.index("Código")
        for row in sheet.iter_rows(min_row=2, values_only=True):
            code = row[code_index]
            if code is None:
                continue
            key = (level, str(code))
            if key in entries:
                raise ValueError(f"Duplicate reviewed key: {key}")
            entries[key] = {internal: row[indexes[label]]
                            for internal, label in zip(REVIEWER, REVIEW_LABELS)}
    workbook.close()
    return entries


def write_review(sheet, rows, columns, labels):
    sheet.append([labels[name] for name, _ in columns])
    for row in rows:
        sheet.append([typed_value(name, row.get(name)) for name, _ in columns])
    styled_header(sheet[1])
    n = sheet.max_row
    letters = {name: get_column_letter(index)
               for index, (name, _) in enumerate(columns, start=1)}
    for name, width in columns:
        letter = letters[name]
        sheet.column_dimensions[letter].width = width
        if name in REVIEWER:
            sheet[f"{letter}1"].font = Font(bold=True)
            sheet[f"{letter}1"].fill = REVIEW_FILL
    for cells in sheet.iter_rows(min_row=2):
        for (name, _), cell in zip(columns, cells):
            cell.alignment = Alignment(wrap_text=True, vertical="top")
            if name in REVIEWER:
                cell.fill = REVIEW_FILL
            if name in SHARES:
                cell.number_format = "0%"
    if n > 1:
        for name, options in CHOICES.items():
            validation = DataValidation(type="list", formula1=options, allow_blank=True)
            validation.error = "Escolha uma das opções da lista."
            sheet.add_data_validation(validation)
            validation.add(f"{letters[name]}2:{letters[name]}{n}")
        last = get_column_letter(len(columns))
        check = letters["checklist"]
        for answer, fill in (("sim", YES_FILL), ("não", NO_FILL)):
            sheet.conditional_formatting.add(
                f"A2:{last}{n}",
                FormulaRule(formula=[f'${check}2="{answer}"'], fill=fill),
            )
    sheet.freeze_panes = "C2"
    sheet.auto_filter.ref = f"A1:{get_column_letter(len(columns))}{n}"
    sheet.row_dimensions[1].height = 45


def write_diagnostics(sheet, rows, labels):
    if not rows:
        raise ValueError("Diagnostic input has no rows")
    fields = list(rows[0])
    if fields[:2] != ["level", "code"]:
        raise ValueError("Diagnostic input must start with level,code")
    keys = set()
    sheet.append([labels.get(field, field) for field in fields])
    for row in rows:
        key = (row["level"], row["code"])
        if key in keys:
            raise ValueError(f"Duplicate diagnostic key: {key}")
        keys.add(key)
        sheet.append([typed_value(field, row[field]) for field in fields])
    styled_header(sheet[1])
    for index, field in enumerate(fields, 1):
        sheet.column_dimensions[get_column_letter(index)].width = 24 if index > 2 else 18
        if field in SHARES:
            for column in sheet.iter_cols(min_col=index, max_col=index, min_row=2):
                for cell in column:
                    cell.number_format = "0%"
    sheet.freeze_panes = "C2"
    sheet.auto_filter.ref = f"A1:{get_column_letter(len(fields))}{sheet.max_row}"
    return keys


def write_participation(sheet, rows, bounds, unit):
    sheet.append(["Edição", f"{unit} participantes"])
    for row in rows:
        sheet.append([int(row["year"]), int(row["participants"])])
    sheet.append([])
    sheet.append(["Série", f"{unit} participantes"])
    second_header = sheet.max_row
    sheet.append(["4 ou mais edições", int(bounds["participated_4_plus"])])
    sheet.append(["Todas de 2021 a 2025", int(bounds["participated_2021_2025"])])
    styled_header(sheet[1])
    styled_header(sheet[second_header])
    sheet.column_dimensions["A"].width = 27
    sheet.column_dimensions["B"].width = 30


def write_snapshot(sheet, rows, codes, id_fields, id_labels):
    cells = {}
    for row in rows:
        key = tuple(row[field] if field != "year" else int(row[field]) for field in id_fields)
        code = row["code_indicator"]
        answers = cells.setdefault(key, {})
        if code in answers:
            raise ValueError(f"Duplicate snapshot answer: {key}, {code}")
        value = row["value"]
        answers[code] = float(value) if row["is_number"] == "TRUE" else typed_value("value", value)
    sheet.append(id_labels + codes)
    for key, answers in cells.items():
        sheet.append(list(key) + [answers.get(code) for code in codes])
    styled_header(sheet[1])
    for index, field in enumerate(id_fields, 1):
        sheet.column_dimensions[get_column_letter(index)].width = 28 if "name" in field or "key" in field else 10
    sheet.freeze_panes = f"{get_column_letter(len(id_fields) + 1)}2"
    sheet.auto_filter.ref = f"A1:{get_column_letter(sheet.max_column)}{sheet.max_row}"


def write_definitions(sheet, label_rows, diagnostic_fields):
    sheet.append(["Coluna", "Definição"])
    definitions = {row["from"]: (row["to"], row["definition"]) for row in label_rows}
    if "quality_flags" in definitions:
        label, definition = definitions["quality_flags"]
        definitions["quality_flags"] = (
            label, definition.replace("métricas à direita", "métricas na aba diagnósticos")
        )
    for name, label in EXTRA_LABELS.items():
        definition = definitions[name][1] if name in definitions else EXTRA_DEFINITIONS[name]
        definitions[name] = (label, definition)
    used = ({name for name, _ in MUNICIPAL + METROPOLITAN}
            | set(diagnostic_fields)
            | {name for name in definitions if name.startswith("metro_") and name.endswith("_method")})
    for name in definitions:
        if name in used:
            sheet.append(list(definitions[name]))
    styled_header(sheet[1])
    sheet.column_dimensions["A"].width = 37
    sheet.column_dimensions["B"].width = 110
    for row in sheet.iter_rows(min_row=2):
        for cell in row:
            cell.alignment = Alignment(wrap_text=True, vertical="top")


def build_workbook(source_dir=HERE, existing_path=None):
    source_dir = Path(source_dir)
    label_rows = read_csv(source_dir, "column_labels.csv")
    labels = {row["from"]: row["to"] for row in label_rows} | EXTRA_LABELS
    missing = [name for name, _ in MUNICIPAL + METROPOLITAN if name not in labels]
    if missing:
        raise ValueError(f"Columns without a label: {missing}")
    entries = reviewer_entries(Path(existing_path) if existing_path else None)
    municipal = read_csv(source_dir, "indicator_review.csv")
    metropolitan = read_csv(source_dir, "indicator_review_metropolitan.csv")
    review_keys = set()
    for level, rows in (("municipal", municipal), ("metropolitan", metropolitan)):
        for row in rows:
            key = (level, row["code"])
            if key in review_keys:
                raise ValueError(f"Duplicate review key: {key}")
            review_keys.add(key)
            row.update({name: value for name, value in entries.get(key, {}).items()
                        if value not in (None, "")})
    orphaned = {key for key, values in entries.items()
                if any(value not in (None, "") for value in values.values()) and key not in review_keys}
    if orphaned:
        raise ValueError(f"Reviewed keys missing from new workbook: {sorted(orphaned)}")
    for row in municipal:
        dashboard = row.get("dashboard_pemob") == "sim"
        table = row.get("tabela_pemob") == "sim"
        if dashboard and table:
            row["site_presence"] = "Dashboard e tabela"
        elif dashboard:
            row["site_presence"] = "Só dashboard"
        elif table:
            row["site_presence"] = "Só tabela"
        elif row.get("tabela_pemob") == "no menu, sem dados":
            row["site_presence"] = "Menu sem dados"
        else:
            row["site_presence"] = "Não"

    workbook = Workbook()
    workbook.active.title = "municipal"
    write_review(workbook.active, municipal, MUNICIPAL, labels)
    write_review(workbook.create_sheet("metropolitana"), metropolitan, METROPOLITAN, labels)
    diagnostics = read_csv(source_dir, "indicator_diagnostics.csv")
    diagnostic_keys = write_diagnostics(workbook.create_sheet("diagnósticos"), diagnostics, labels)
    if diagnostic_keys != review_keys:
        raise ValueError(f"Review/diagnostic keys differ: {review_keys ^ diagnostic_keys}")
    write_participation(workbook.create_sheet("participação municipal"),
                        read_csv(source_dir, "participants.csv"),
                        read_csv(source_dir, "panel_bounds.csv")[0], "Municípios")
    write_participation(workbook.create_sheet("participação metropolitana"),
                        read_csv(source_dir, "participants_metropolitan.csv"),
                        read_csv(source_dir, "panel_bounds_metropolitan.csv")[0],
                        "Regiões metropolitanas")
    write_snapshot(workbook.create_sheet("dados municipais"),
                   read_csv(source_dir, "snapshot_long.csv"),
                   [row["code_indicator"] for row in read_csv(source_dir, "snapshot_codes.csv")],
                   ["name_city", "abbrev_state", "year"],
                   ["Município", "UF", "Edição"])
    write_snapshot(workbook.create_sheet("dados metropolitanos"),
                   read_csv(source_dir, "snapshot_long_metropolitan.csv"),
                   [row["code_indicator"] for row in read_csv(source_dir, "snapshot_codes_metropolitan.csv")],
                   ["place_key", "place_name", "abbrev_state", "year"],
                   ["Chave", "Região metropolitana", "UF", "Edição"])
    write_definitions(workbook.create_sheet("definições"), label_rows, diagnostics[0])
    return workbook


def main():
    output = HERE / "pemob_indicator_review.xlsx"
    workbook = build_workbook(HERE, existing_path=output)
    descriptor, temporary = tempfile.mkstemp(prefix=".pemob_indicator_review-", suffix=".xlsx", dir=HERE)
    os.close(descriptor)
    try:
        workbook.save(temporary)
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(f"Wrote {output}")


if __name__ == "__main__":
    main()
