"""
run_pipeline.py
Runs the whole SQL pipeline with ONE command, in the correct order.

  - runs each SQL file with psql
  - stops immediately if any step fails (so bad data never moves forward)
  - logs every step with its duration to the screen and to logs/pipeline.log

Usage (run from the project folder):
    python run_pipeline.py                      # full pipeline on database retail_db
    python run_pipeline.py --db mydb --user postgres --host localhost --port 5432
    python run_pipeline.py --from-step 7        # start from step 7 (e.g. after a failure)
    python run_pipeline.py --only-incremental   # run only the new-batch steps (7 and 8)

Needs: Python 3.8+ and the `psql` command (installed with PostgreSQL).
No extra Python packages required.
"""

import argparse
import logging
import os
import subprocess
import sys
import time

PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))

# (step number, file, description) -- the order matters!
STEPS = [
    (1, "sql/01_create_tables.sql",        "Create raw, clean and staging tables"),
    (2, "sql/02_load_raw_data.sql",        "Load CSV files into raw tables"),
    (3, "sql/03_data_cleaning.sql",        "Profile and clean data into clean tables"),
    (4, "sql/04_data_quality_checks.sql",  "Run data quality checks"),
    (5, "sql/05_business_analysis.sql",    "Run business analysis queries"),
    (6, "sql/06_star_schema.sql",          "Build star schema (initial load)"),
    (7, "sql/07_scd_type2_customers.sql",  "Apply customer changes (SCD Type 2)"),
    (8, "sql/08_incremental_load.sql",     "Incremental load of new orders (MERGE)"),
    (9, "sql/09_warehouse_analysis.sql",   "Run warehouse analysis queries"),
]
INCREMENTAL_STEPS = {7, 8}


def setup_logging():
    os.makedirs(os.path.join(PROJECT_DIR, "logs"), exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)-7s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        handlers=[
            logging.StreamHandler(sys.stdout),
            logging.FileHandler(os.path.join(PROJECT_DIR, "logs", "pipeline.log")),
        ],
    )


def run_sql_file(path, args):
    """Run one SQL file with psql. Returns (success, output)."""
    cmd = [
        "psql",
        "-d", args.db,
        "-v", "ON_ERROR_STOP=1",   # stop at the first error inside the file
        "-q",                      # quiet: don't print every command
        "-P", "pager=off",
        "-f", path,
    ]
    if args.host:
        cmd += ["-h", args.host]
    if args.port:
        cmd += ["-p", str(args.port)]
    if args.user:
        cmd += ["-U", args.user]

    # cwd = project folder, so the \copy paths like 'data/orders.csv' work
    result = subprocess.run(cmd, cwd=PROJECT_DIR, capture_output=True, text=True)
    return result.returncode == 0, result.stdout + result.stderr


def check_quality_output(output):
    """Quality-check steps print PASS/FAIL. Treat any FAIL as a pipeline failure."""
    return "| FAIL" not in output


def main():
    parser = argparse.ArgumentParser(description="Run the retail sales SQL pipeline")
    parser.add_argument("--db", default="retail_db", help="database name (default: retail_db)")
    parser.add_argument("--host", help="database host, e.g. localhost")
    parser.add_argument("--port", type=int, help="database port, e.g. 5432")
    parser.add_argument("--user", help="database user, e.g. postgres")
    parser.add_argument("--from-step", type=int, default=1, help="start from this step number")
    parser.add_argument("--only-incremental", action="store_true",
                        help="run only the new-batch steps (SCD2 + incremental load)")
    parser.add_argument("--show-output", action="store_true",
                        help="print the query results of every step")
    args = parser.parse_args()

    setup_logging()
    log = logging.getLogger()

    steps = [s for s in STEPS if s[0] >= args.from_step]
    if args.only_incremental:
        steps = [s for s in STEPS if s[0] in INCREMENTAL_STEPS]

    log.info("=" * 60)
    log.info("Pipeline started  | database: %s | steps: %s", args.db, [s[0] for s in steps])
    log.info("=" * 60)
    pipeline_start = time.time()

    for number, path, description in steps:
        log.info("Step %d: %s ...", number, description)
        start = time.time()
        ok, output = run_sql_file(path, args)
        duration = time.time() - start

        if args.show_output:
            print(output)

        if not ok:
            log.error("Step %d FAILED after %.2fs (%s)", number, duration, path)
            log.error("Error details:\n%s", output.strip())
            log.error("Fix the problem, then resume with:  python run_pipeline.py --from-step %d",
                      number)
            sys.exit(1)

        if not check_quality_output(output):
            log.error("Step %d: a data quality check FAILED", number)
            log.error("\n%s", output.strip())
            sys.exit(1)

        log.info("Step %d: done in %.2fs", number, duration)

    log.info("=" * 60)
    log.info("Pipeline finished successfully in %.2fs", time.time() - pipeline_start)
    log.info("=" * 60)


if __name__ == "__main__":
    main()
