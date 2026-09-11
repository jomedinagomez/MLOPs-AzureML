import argparse
import json
from pathlib import Path

import pandas as pd


def resolve_csv(path: Path) -> Path:
    if path.is_file():
        return path
    matches = sorted(path.rglob("*.csv"))
    if len(matches) != 1:
        raise RuntimeError(f"Expected one CSV beneath {path}, found {len(matches)}")
    return matches[0]


parser = argparse.ArgumentParser(description="Summarize a taxi CSV")
parser.add_argument("--input-data", required=True)
parser.add_argument("--output-data", required=True)
args = parser.parse_args()

source_path = resolve_csv(Path(args.input_data))
frame = pd.read_csv(source_path)
output_dir = Path(args.output_data)
output_dir.mkdir(parents=True, exist_ok=True)

summary = {
    "source_file": source_path.name,
    "row_count": len(frame),
    "column_count": len(frame.columns),
    "columns": frame.columns.tolist(),
}
(output_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(json.dumps(summary, indent=2))