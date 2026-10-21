"""Snapshot PEMOB category options from the read-only observatorio source."""

import argparse
import csv
import json
import re
import subprocess
from pathlib import Path


def extract(source: Path):
    category = subcategory = None
    in_options = False
    rows = []
    for line in source.read_text(encoding="utf-8").splitlines():
        if match := re.fullmatch(r'  ("(?:[^"\\]|\\.)+"): \{', line):
            category = json.loads(match.group(1))
            subcategory = None
        elif match := re.fullmatch(r'    ("(?:[^"\\]|\\.)+"): \{', line):
            subcategory = json.loads(match.group(1))
        elif line == '      "options": [':
            in_options = True
        elif line == "      ]":
            in_options = False
        elif in_options:
            value = line.strip().removesuffix(",")
            if not value.startswith('"'):
                raise ValueError(f"Unexpected category option: {line}")
            rows.append((category, subcategory, json.loads(value)))
    if not rows or any(None in row for row in rows):
        raise ValueError("Could not parse the category tree")
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    source = args.source.resolve()
    repository = subprocess.check_output(
        ["git", "-C", str(source.parent), "rev-parse", "--show-toplevel"],
        text=True,
    ).strip()
    commit = subprocess.check_output(
        ["git", "-C", repository, "rev-parse", "HEAD"], text=True
    ).strip()
    relative = str(source.relative_to(repository))
    rows = extract(source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="") as file:
        writer = csv.writer(file, lineterminator="\n")
        writer.writerow(("category", "subcategory", "label", "source_commit", "source_path"))
        for row in rows:
            writer.writerow((*row, commit, relative))


if __name__ == "__main__":
    main()
