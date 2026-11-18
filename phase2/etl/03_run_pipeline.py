"""
03_run_pipeline.py
==================
Master orchestrator for The Boot Room — Phase 2 ETL Pipeline.

Usage:
    python 03_run_pipeline.py [--skip-ingest] [--skip-ddl] [--only-dq]

Flags:
    --skip-ingest   Skip Step 5 (Python ETL ingest) if CSVs already loaded.
    --skip-ddl      Skip Steps 1-4 (schema/DDL creation) if already applied.
    --only-dq       Run only Step 8 (data quality check).

Environment:
    DATABASE_URL    PostgreSQL DSN (default: postgresql://postgres:postgres@localhost:5432/the_boot_room)
"""

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

import psycopg2

# ── Paths ──────────────────────────────────────────────────────────────────────
PHASE2_DIR: Path = Path(__file__).parent.parent   # phase2/
SQL_DIR: Path    = PHASE2_DIR / "sql"
ETL_DIR: Path    = PHASE2_DIR / "etl"

# ── Database ───────────────────────────────────────────────────────────────────
DEFAULT_DATABASE_URL = "postgresql://postgres:postgres@localhost:5432/the_boot_room"


# ── Helpers ────────────────────────────────────────────────────────────────────

def run_sql_file(conn, path: Path) -> None:
    """Read and execute a SQL file, committing after."""
    sql = path.read_text(encoding="utf-8")
    with conn.cursor() as cur:
        cur.execute(sql)
    conn.commit()
    print(f"  [SQL] {path.name} ✓")


def run_python_etl(script_path: Path) -> None:
    """Run a Python ETL script as a subprocess."""
    result = subprocess.run(
        [sys.executable, str(script_path)],
        capture_output=False,   # let output stream to console
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"ETL script {script_path.name} failed with code {result.returncode}"
        )
    print(f"  [PY]  {script_path.name} ✓")


def print_row_counts(conn) -> None:
    """Print row counts for all DW tables."""
    tables = [
        ("project_dw",      "dim_date"),
        ("project_dw",      "dim_season"),
        ("project_dw",      "dim_team"),
        ("project_dw",      "dim_player"),
        ("project_dw",      "dim_venue"),
        ("project_dw",      "dim_match"),
        ("project_dw",      "fact_player_match"),
        ("project_dw",      "fact_league_standing"),
        ("project_dw",      "fact_matchday_squad"),
        ("project_staging", "stg_dq_log"),
    ]
    print("\n── DW Row Counts ─────────────────────────")
    with conn.cursor() as cur:
        for schema, table in tables:
            cur.execute(f"SELECT COUNT(*) FROM {schema}.{table}")
            count = cur.fetchone()[0]
            print(f"  {schema}.{table:<30} {count:>8,}")
    print("──────────────────────────────────────────")


# ── Step runner ────────────────────────────────────────────────────────────────

def run_step(label: str, fn, *args, **kwargs) -> float:
    """Run a pipeline step, print timing, and return elapsed seconds."""
    print(f"\n▶  {label}")
    t0 = time.perf_counter()
    fn(*args, **kwargs)
    elapsed = time.perf_counter() - t0
    print(f"   ↳ done in {elapsed:.2f}s")
    return elapsed


# ── Main ───────────────────────────────────────────────────────────────────────

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="The Boot Room — Phase 2 ETL Pipeline runner"
    )
    parser.add_argument(
        "--skip-ingest",
        action="store_true",
        help="Skip Step 5 (Python ETL ingest); use when CSVs are already loaded.",
    )
    parser.add_argument(
        "--skip-ddl",
        action="store_true",
        help="Skip Steps 1-4 (schema/DDL creation); use when schemas already exist.",
    )
    parser.add_argument(
        "--only-dq",
        action="store_true",
        help="Run only Step 8 (data quality check) and row-count summary.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    # ── Banner ─────────────────────────────────────────────────────────────────
    print(
        "\n"
        "╔══════════════════════════════════════╗\n"
        "║   The Boot Room — ETL Pipeline       ║\n"
        "║   Phase 2: PostgreSQL Implementation ║\n"
        "╚══════════════════════════════════════╝"
    )

    database_url = os.environ.get("DATABASE_URL", DEFAULT_DATABASE_URL)
    print(f"\nDatabase : {database_url}")
    print(f"SQL dir  : {SQL_DIR}")
    print(f"ETL dir  : {ETL_DIR}")

    pipeline_start = time.perf_counter()
    step_times: dict[str, float] = {}

    # ── Step 0: Verify PostgreSQL connection ───────────────────────────────────
    print("\n▶  Step 0 — Verify PostgreSQL connection")
    t0 = time.perf_counter()
    try:
        conn = psycopg2.connect(database_url)
        conn.autocommit = False
    except Exception as exc:
        print(f"  [ERROR] Cannot connect to PostgreSQL: {exc}", file=sys.stderr)
        sys.exit(1)
    elapsed = time.perf_counter() - t0
    print(f"  [OK]  Connected ✓")
    print(f"   ↳ done in {elapsed:.2f}s")
    step_times["Step 0 — DB connect"] = elapsed

    try:
        # ── --only-dq shortcut ─────────────────────────────────────────────────
        if args.only_dq:
            step_times["Step 8 — DQ check"] = run_step(
                "Step 8 — Data quality check",
                run_sql_file, conn, SQL_DIR / "06_data_quality.sql",
            )
            step_times["Step 9 — Row counts"] = run_step(
                "Step 9 — Row count summary",
                print_row_counts, conn,
            )

        else:
            # ── Steps 1-4: DDL ─────────────────────────────────────────────────
            if not args.skip_ddl:
                step_times["Step 1 — Schemas"] = run_step(
                    "Step 1 — Create schemas  (00_create_schemas.sql)",
                    run_sql_file, conn, SQL_DIR / "00_create_schemas.sql",
                )
                step_times["Step 2 — Staging DDL"] = run_step(
                    "Step 2 — Staging DDL     (01_staging_ddl.sql)",
                    run_sql_file, conn, SQL_DIR / "01_staging_ddl.sql",
                )
                step_times["Step 3 — DW DDL"] = run_step(
                    "Step 3 — DW DDL          (02_dw_ddl.sql)",
                    run_sql_file, conn, SQL_DIR / "02_dw_ddl.sql",
                )
                step_times["Step 4 — Reporting DDL"] = run_step(
                    "Step 4 — Reporting DDL   (03_reporting_ddl.sql)",
                    run_sql_file, conn, SQL_DIR / "03_reporting_ddl.sql",
                )
            else:
                print("\n  [SKIP] Steps 1-4 — DDL (--skip-ddl)")

            # ── Step 5: Python ingest ──────────────────────────────────────────
            if not args.skip_ingest:
                step_times["Step 5 — Python ingest"] = run_step(
                    "Step 5 — Python ETL ingest (02_load_staging.py)",
                    run_python_etl, ETL_DIR / "02_load_staging.py",
                )
            else:
                print("\n  [SKIP] Step 5 — Python ingest (--skip-ingest)")

            # ── Steps 6-8: SQL loads + DQ ──────────────────────────────────────
            step_times["Step 6 — Load dimensions"] = run_step(
                "Step 6 — Load dimensions (04_load_dimensions.sql)",
                run_sql_file, conn, SQL_DIR / "04_load_dimensions.sql",
            )
            step_times["Step 7 — Load facts"] = run_step(
                "Step 7 — Load facts      (05_load_facts.sql)",
                run_sql_file, conn, SQL_DIR / "05_load_facts.sql",
            )
            step_times["Step 8 — DQ check"] = run_step(
                "Step 8 — Data quality check (06_data_quality.sql)",
                run_sql_file, conn, SQL_DIR / "06_data_quality.sql",
            )

            # ── Step 9: Row counts ─────────────────────────────────────────────
            step_times["Step 9 — Row counts"] = run_step(
                "Step 9 — Row count summary",
                print_row_counts, conn,
            )

    except Exception as exc:
        print(f"\n  [FATAL] Pipeline aborted: {exc}", file=sys.stderr)
        conn.rollback()
        conn.close()
        sys.exit(1)
    finally:
        conn.close()

    # ── Timing summary ─────────────────────────────────────────────────────────
    total = time.perf_counter() - pipeline_start
    print("\n── Step Timings ──────────────────────────")
    for step_label, t in step_times.items():
        print(f"  {step_label:<35} {t:>7.2f}s")
    print(f"{'  TOTAL':<37} {total:>7.2f}s")
    print("──────────────────────────────────────────")
    print("\n✅  Pipeline completed successfully.\n")


if __name__ == "__main__":
    main()
