"""Snapshot 2024 PEMOB labels from the read-only observatorio source."""

import argparse
import csv
import json
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    source = args.source.resolve()
    content = source.read_text(encoding="utf-8")
    start = content.find("[\n")
    end = content.rfind("]")
    if start < 0 or end <= start:
        raise ValueError("Could not locate the PEMOB city array")
    cities = json.loads(content[start : end + 1])
    repository = subprocess.check_output(
        ["git", "-C", str(source.parent), "rev-parse", "--show-toplevel"],
        text=True,
    ).strip()
    commit = subprocess.check_output(
        ["git", "-C", repository, "rev-parse", "HEAD"], text=True
    ).strip()
    relative = str(source.relative_to(repository))
    items = {}
    for city in cities:
        for item in city["data"]:
            key = (item.get("label"), item.get("label_pergunta"))
            if key not in items:
                items[key] = item.get("is_dashboard")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="") as file:
        writer = csv.writer(file, lineterminator="\n")
        writer.writerow(("label", "label_pergunta", "is_dashboard", "source_commit", "source_path"))
        for (label, question), dashboard in sorted(
            items.items(), key=lambda pair: (pair[0][0] or "", pair[0][1] or "")
        ):
            writer.writerow((
                label,
                question,
                str(dashboard).lower(),
                commit,
                relative,
            ))


if __name__ == "__main__":
    main()
