#!/usr/bin/env python3
"""
The Boot Room — Data Warehouse
ETL Step 2: Load Staging Tables
=================================
Reads cleaned CSV files from phase2/data/ and bulk-loads them into the
project_staging schema in PostgreSQL using psycopg2 COPY.

Data quality transformations applied on-the-fly:
  - Strip leading/trailing whitespace from all string fields
  - Title-case: team_name, player_name, stadium_name, country_name,
                competition_name
  - Replace empty string "" with NULL
  - Standardise boolean strings → "true" / "false"

Usage
-----
  pip install psycopg2-binary
  python etl/02_load_staging.py

Environment
-----------
  DATABASE_URL  (default: postgresql://postgres:postgres@localhost:5432/the_boot_room)
"""

import csv
import io
import os
import sys
from pathlib import Path

try:
    import psycopg2
    import psycopg2.extras
except ImportError:
    sys.exit(
        "\n[ERROR] psycopg2 is not installed.\n"
        "Run:  pip install psycopg2-binary\n"
    )

# ─── Paths ───────────────────────────────────────────────────────────────────
PHASE2_DIR = Path(__file__).parent.parent
DATA_DIR   = PHASE2_DIR / "data"

# ─── Database ────────────────────────────────────────────────────────────────
DEFAULT_DSN = "postgresql://postgres:postgres@localhost:5432/the_boot_room"

# ─── Fields that should be title-cased ───────────────────────────────────────
TITLE_CASE_FIELDS = {
    "team_name", "player_name", "stadium_name",
    "country_name", "competition_name",
}

# ─── Boolean normalisation map ───────────────────────────────────────────────
_TRUE_VALUES  = {"true", "1"}
_FALSE_VALUES = {"false", "0"}


# ─── Table manifest ──────────────────────────────────────────────────────────
# (csv_filename, staging_table, [explicit_column_list | None for auto-detect])
TABLE_MAP = [
    ("competitions.csv",   "project_staging.stg_competition",         None),
    ("seasons.csv",        "project_staging.stg_season",              None),
    ("teams.csv",          "project_staging.stg_team",                None),
    ("players.csv",        "project_staging.stg_player",              None),
    ("matches.csv",        "project_staging.stg_match",               None),
    ("lineups.csv",        "project_staging.stg_lineup_entry",        None),
    ("events_summary.csv", "project_staging.stg_player_match_summary", None),
]

# DDL for the ad-hoc stg_player_match_summary table (all VARCHAR + _loaded_at)
STG_PLAYER_MATCH_SUMMARY_DDL = """
DROP TABLE IF EXISTS project_staging.stg_player_match_summary;
CREATE TABLE project_staging.stg_player_match_summary (
    match_id            VARCHAR,
    team_id             VARCHAR,
    player_id           VARCHAR,
    player_name         VARCHAR,
    position_played     VARCHAR,
    minutes_played      VARCHAR,
    goals               VARCHAR,
    assists             VARCHAR,
    shots               VARCHAR,
    shots_on_target     VARCHAR,
    key_passes          VARCHAR,
    passes_completed    VARCHAR,
    passes_attempted    VARCHAR,
    xg                  VARCHAR,
    tackles             VARCHAR,
    interceptions       VARCHAR,
    yellow_cards        VARCHAR,
    red_cards           VARCHAR,
    fouls_committed     VARCHAR,
    fouls_won           VARCHAR,
    _loaded_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
"""


# ─── Data-quality helpers ─────────────────────────────────────────────────────

def _normalise_bool(value: str) -> str:
    """Return 'true', 'false', or the original string if not boolean-like."""
    lower = value.lower()
    if lower in _TRUE_VALUES:
        return "true"
    if lower in _FALSE_VALUES:
        return "false"
    return value


def clean_row(row: dict) -> dict:
    """
    Apply all data-quality transformations to a single CSV row (dict).

    Returns a new dict; never mutates the original.
    """
    cleaned = {}
    for key, value in row.items():
        # 1. Strip whitespace
        if isinstance(value, str):
            value = value.strip()

        # 2. Empty string → None (→ NULL in PostgreSQL)
        if value == "":
            cleaned[key] = None
            continue

        # 3. Title-case selected text fields
        if key in TITLE_CASE_FIELDS and isinstance(value, str):
            value = value.title()

        # 4. Normalise boolean-like strings
        if isinstance(value, str):
            value = _normalise_bool(value)

        cleaned[key] = value
    return cleaned


# ─── DQ log helper ────────────────────────────────────────────────────────────

def _ensure_dq_log(conn) -> None:
    """Create stg_dq_log if it doesn't already exist."""
    with conn.cursor() as cur:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS project_staging.stg_dq_log (
                log_id       SERIAL PRIMARY KEY,
                table_name   VARCHAR(100),
                check_name   VARCHAR(200),
                check_result VARCHAR(20),
                rows_checked INTEGER,
                rows_failed  INTEGER,
                detail       TEXT,
                checked_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)
    conn.commit()


def log_dq_issue(conn, table_name: str, row_number: int,
                 issue: str, raw_data: str) -> None:
    """Insert one row into stg_dq_log."""
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO project_staging.stg_dq_log
                (table_name, check_name, check_result, rows_checked, rows_failed, detail)
            VALUES (%s, %s, %s, %s, %s, %s)
            """,
            (table_name, "staging_load_error", "FAIL", 1, 1,
             f"row {row_number}: {issue} | raw: {raw_data}"),
        )
    conn.commit()


# ─── Core load function ───────────────────────────────────────────────────────

def load_csv_to_table(
    conn,
    csv_path: Path,
    table: str,
    columns: list[str] | None = None,
) -> int:
    """
    Truncate *table* then COPY rows from *csv_path* into it.

    1. Reads the CSV, applies clean_row() to every row.
    2. Bad rows (those that raise an exception during cleaning) are skipped
       and recorded in stg_dq_log.
    3. Builds an in-memory CSV buffer and uses cursor.copy_expert() for speed.

    Returns the number of rows successfully loaded.
    """
    good_rows: list[dict] = []
    bad_count = 0

    with open(csv_path, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        raw_columns = reader.fieldnames or []

        for line_no, raw_row in enumerate(reader, start=2):   # 1-based, header = 1
            try:
                cleaned = clean_row(raw_row)
                good_rows.append(cleaned)
            except Exception as exc:                           # noqa: BLE001
                bad_count += 1
                raw_text = str(dict(raw_row))
                log_dq_issue(conn, table, line_no, str(exc), raw_text)

    # Determine column list
    if columns is None:
        columns = raw_columns   # use whatever the CSV header says

    # ── Build in-memory CSV buffer (cleaned data only) ──
    buf = io.StringIO()
    writer = csv.DictWriter(
        buf,
        fieldnames=columns,
        extrasaction="ignore",   # drop any extra keys not in columns
        lineterminator="\n",
        quoting=csv.QUOTE_MINIMAL,
    )
    writer.writeheader()
    for row in good_rows:
        # Replace None with "" for the CSV buffer (COPY interprets "" as NULL
        # only when not quoted; we use an explicit NULL representation instead)
        writer.writerow({col: ("" if row.get(col) is None else row.get(col, ""))
                         for col in columns})
    buf.seek(0)

    # Rebuild buffer using \N for NULL so PostgreSQL COPY handles it properly
    null_buf = io.StringIO()
    csv_reader = csv.reader(io.StringIO(buf.read()))
    csv_writer = csv.writer(null_buf, lineterminator="\n")
    buf.seek(0)
    for i, row_vals in enumerate(csv.reader(buf)):
        if i == 0:
            csv_writer.writerow(row_vals)   # header
            continue
        csv_writer.writerow(
            [v if v != "" else r"\N" for v in row_vals]
        )
    null_buf.seek(0)

    col_list = ", ".join(f'"{c}"' for c in columns)
    copy_sql  = (
        f"COPY {table} ({col_list}) "
        f"FROM STDIN WITH (FORMAT csv, HEADER true, NULL '\\N')"
    )

    with conn.cursor() as cur:
        # Truncate first (idempotent re-runs)
        cur.execute(f"TRUNCATE TABLE {table} RESTART IDENTITY CASCADE;")
        cur.copy_expert(copy_sql, null_buf)
    conn.commit()

    loaded = len(good_rows)
    print(
        f"  {'✓':<2} {table:<50}  {loaded:>8,} rows loaded"
        + (f"  ({bad_count} skipped)" if bad_count else "")
    )
    return loaded


# ─── Special table: stg_player_match_summary ─────────────────────────────────

def ensure_stg_player_match_summary(conn) -> None:
    """DROP + CREATE stg_player_match_summary (all-VARCHAR design)."""
    with conn.cursor() as cur:
        cur.execute(STG_PLAYER_MATCH_SUMMARY_DDL)
    conn.commit()
    print("  [DDL] project_staging.stg_player_match_summary (re)created")


# ─── Main ─────────────────────────────────────────────────────────────────────

def main() -> None:
    dsn = os.environ.get("DATABASE_URL", DEFAULT_DSN)

    print("\n── The Boot Room: Load Staging ──────────────────────────────")
    print(f"  DSN  : {dsn}")
    print(f"  Data : {DATA_DIR}\n")

    try:
        conn = psycopg2.connect(dsn)
    except psycopg2.OperationalError as exc:
        sys.exit(f"[ERROR] Cannot connect to database:\n  {exc}")

    try:
        _ensure_dq_log(conn)

        # Ensure the ad-hoc summary table exists before loading
        ensure_stg_player_match_summary(conn)

        totals: dict[str, int] = {}

        for csv_name, table, columns in TABLE_MAP:
            csv_path = DATA_DIR / csv_name

            if not csv_path.exists():
                print(f"  [SKIP] {csv_name} not found — skipping {table}")
                continue

            try:
                count = load_csv_to_table(conn, csv_path, table, columns)
                totals[table] = count
            except Exception as exc:                           # noqa: BLE001
                print(f"  [ERROR] Failed to load {table}: {exc}")
                conn.rollback()

        # ── Summary ──────────────────────────────────────────────────────────
        print("\n── Summary ──────────────────────────────────────────────────")
        grand_total = 0
        for tbl, cnt in totals.items():
            print(f"  {tbl:<50}  {cnt:>8,}")
            grand_total += cnt
        print(f"\n  {'TOTAL':<50}  {grand_total:>8,}")
        print("─────────────────────────────────────────────────────────────\n")

    finally:
        conn.close()


if __name__ == "__main__":
    main()
