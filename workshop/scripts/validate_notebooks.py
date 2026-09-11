from __future__ import annotations

import argparse
import ast
import json
from pathlib import Path


def validate_notebook(path: Path) -> tuple[int, int]:
    document = json.loads(path.read_text(encoding="utf-8"))
    if document.get("nbformat") != 4 or not isinstance(document.get("cells"), list):
        raise ValueError(f"Invalid notebook structure: {path}")

    code_cells = 0
    for index, cell in enumerate(document["cells"], start=1):
        if cell.get("cell_type") != "code":
            continue
        code_cells += 1
        source = "".join(cell.get("source", []))
        try:
            ast.parse(source, filename=f"{path}:cell-{index}")
        except SyntaxError as exc:
            raise SyntaxError(f"{path}: code cell {index}: {exc.msg}") from exc
        if cell.get("outputs"):
            raise ValueError(f"Saved output found in {path}, code cell {index}")
        if cell.get("execution_count") is not None:
            raise ValueError(f"Execution count found in {path}, code cell {index}")
    return len(document["cells"]), code_cells


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate workshop notebooks")
    parser.add_argument("paths", nargs="+", type=Path)
    args = parser.parse_args()

    notebooks: list[Path] = []
    for path in args.paths:
        if path.is_dir():
            notebooks.extend(sorted(path.rglob("*.ipynb")))
        else:
            notebooks.append(path)
    if not notebooks:
        raise FileNotFoundError("No notebooks found")

    total_cells = 0
    total_code_cells = 0
    for notebook in notebooks:
        cells, code_cells = validate_notebook(notebook)
        total_cells += cells
        total_code_cells += code_cells
        print(f"PASS {notebook}: {cells} cells, {code_cells} code")
    print(
        f"Validated {len(notebooks)} notebooks, {total_cells} cells, "
        f"and {total_code_cells} code cells."
    )


if __name__ == "__main__":
    main()
