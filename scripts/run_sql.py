"""Build data/olist.duckdb and run every file in sql/ in order.

Statements are split on ';' at line end. A statement whose first line is
`-- name: <id>` has its result written to results/<id>.csv and printed.
Usage:  python scripts/run_sql.py [db_path]
"""
import pathlib, re, sys
import duckdb

ROOT = pathlib.Path(__file__).resolve().parent.parent
db_path = sys.argv[1] if len(sys.argv) > 1 else str(ROOT / "data" / "olist.duckdb")
con = duckdb.connect(db_path)
con.execute(f"SET file_search_path='{ROOT}'")
(ROOT / "results").mkdir(exist_ok=True)

for f in sorted((ROOT / "sql").glob("*.sql")):
    print(f"\n######## {f.name}")
    for stmt in re.split(r";\s*\n", f.read_text()):
        if not any(l.strip() and not l.strip().startswith("--") for l in stmt.splitlines()):
            continue
        m = re.search(r"--\s*name:\s*(\w+)", stmt)
        rel = con.sql(stmt.strip().rstrip(";"))
        if m and rel is not None:
            df = rel.df()
            df.to_csv(ROOT / "results" / f"{m.group(1)}.csv", index=False)
            print(f"\n== {m.group(1)}")
            print(df.to_string(max_rows=40))
