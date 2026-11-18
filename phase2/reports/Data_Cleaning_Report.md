# Data Cleaning and Transformation Report
**The Boot Room — Football Analytics Data Warehouse**  
*Phase 2 Deliverable: Lab 6 (Physical DW) & Lab 7 (ETL/ELT Workflows)*  

---

## 1. Executive Summary

This report documents the end-to-end data cleansing, standardization, type casting, and dimensional transformation processes designed for **The Boot Room** data warehouse. Raw event streams, match sheets, team metadata, and player rosters pulled directly from the public **StatsBomb Open Data** repository are systematically transformed and loaded into a Kimball-style dimensional star schema hosted in **PostgreSQL**.

The pipeline adopts a modern **ELT (Extract-Load-Transform)** paradigm:
1. **Source / Staging Layer (`project_staging`)**: Raw strings and JSON extracts are staged directly without data loss to guarantee a complete audit trail.
2. **Warehouse Layer (`project_dw`)**: Conformed dimensions and high-volume fact tables with surrogate key lookups, deduplication, and domain constraints.
3. **Reporting Layer (`project_reporting`)**: Denormalized views and pre-aggregated KPI tables ready for Power BI and analytical queries.

---

## 2. Identified Source Data Issues & Quality Anomalies

Operating on open football tracking data surfaced multiple real-world data hygiene challenges:

| Quality Dimension | Raw Pattern in StatsBomb Data | Impact if Unresolved | Cleansing Strategy |
| :--- | :--- | :--- | :--- |
| **Standardization** | Inconsistent whitespace padding and varying case (e.g., `"  FC BARCELONA  "`, `"barcelona"`) | Duplicate dimension entities, broken groupings | Trim leading/trailing whitespace and apply title-case (`INITCAP(TRIM(...))`) |
| **Completeness** | Empty string representations (`""`) instead of relational `NULL` | Skewed aggregation calculations and faulty foreign key joins | Coalesce empty strings to relational `NULL` via `NULLIF(TRIM(...), '')` |
| **Data Types** | Numeric metrics (xG, coordinates) and dates delivered as varying string representations | Incompatible math calculations, cannot leverage partition pruning | Enforce strict casting to `DATE`, `TIME`, and fixed-precision `NUMERIC(6,3)` |
| **Deduplication** | Players appearing across multiple match rosters with slight nickname variances | Multiple surrogate keys assigned to the exact same real-world athlete | Master entity resolution using `DISTINCT ON (player_id)` ordering by record completeness |
| **Sparse Metadata** | Match referee or stadium names occasionally blank in retro/vintage seasons | Broken joins in inner join star-schema queries | Assign conformed default fallbacks (e.g. `'Unknown Venue'`) or use nullable role-playing foreign keys |

---

## 3. Cleansing & Transformation Rules Implemented

### 3.1 Text Standardization & Null Handling
In `phase2/etl/02_load_staging.py` and `phase2/sql/04_load_dimensions.sql`:
* **Whitespace & Case:** Applied Python `.strip()` and PostgreSQL `INITCAP(TRIM(column))` across all player names, team names, stadiums, competition stages, and countries.
  * *Before:* `" lahore "` / `"LAHORE"`
  * *After:* `"Lahore"`
* **Empty Values:** Converted all empty strings `""` to SQL `NULL` using `NULLIF(TRIM(val), '')`.
* **Boolean Standardization:** Strings like `"true"`, `"True"`, `"1"`, `"t"` conformed to standard SQL `BOOLEAN` (`TRUE` / `FALSE`).

### 3.2 Type Conversions & Safe Casting
* `match_date`: Converted from ISO string `"YYYY-MM-DD"` to PostgreSQL native `DATE`.
* `kick_off`: Converted to native `TIME WITHOUT TIME ZONE`.
* `shot_statsbomb_xg`: Converted from high-precision floating point to `NUMERIC(6,3)` to prevent cumulative floating-point inaccuracies.
* Counts & Minutes (`goals`, `assists`, `minutes_played`, `jersey_number`): Safely cast to `SMALLINT` with `COALESCE(..., 0)`.

---

## 4. Surrogate Key Architecture & Implementation

To isolate the data warehouse from changes in external business keys and enable unified tracking across seasons, **Surrogate Keys (SK)** were implemented using PostgreSQL auto-incrementing `SERIAL` primary keys:

```
Source Business Key                  Dimension Table                    Fact Table
-------------------                  ---------------                    ----------
player_id = 5503      ───────►       dim_player                         fact_player_match
                                     player_key = 1001 (PK)    ──────►  player_key = 1001 (FK)
                                     player_id  = 5503 (NK)

team_id   = 217       ───────►       dim_team                           fact_player_match
                                     team_key   = 205  (PK)    ──────►  team_key   = 205  (FK)
                                     team_id    = 217  (NK)
```

### Date Dimension Smart Surrogate Key
For `dim_date`, an integer smart surrogate key formatted as `YYYYMMDD` (e.g. `20240315`) is used. This enables rapid integer range partitioning and human readability without join overhead:
```sql
date_key = CAST(TO_CHAR(match_date::DATE, 'YYYYMMDD') AS INTEGER)
```

---

## 5. ETL Pipeline Execution Flow

The end-to-end load workflow is orchestrated via `phase2/etl/03_run_pipeline.py`:

```
┌────────────────────────────────────────────────────────┐
│ 01_ingest_statsbomb.py (Extracts raw StatsBomb data)   │
└──────────────────────────┬─────────────────────────────┘
                           │ Raw CSVs (data/*.csv)
                           ▼
┌────────────────────────────────────────────────────────┐
│ 02_load_staging.py (Standardizes strings, strips nulls)│
└──────────────────────────┬─────────────────────────────┘
                           │ project_staging schema
                           ▼
┌────────────────────────────────────────────────────────┐
│ 04_load_dimensions.sql (Generates SKs & conformed dims)│
└──────────────────────────┬─────────────────────────────┘
                           │ project_dw dimensions
                           ▼
┌────────────────────────────────────────────────────────┐
│ 05_load_facts.sql (Resolves NK ➔ SK lookups & facts)   │
└──────────────────────────┬─────────────────────────────┘
                           │ project_dw fact tables
                           ▼
┌────────────────────────────────────────────────────────┐
│ 06_data_quality.sql (Runs 20 automated audit checks)   │
└────────────────────────────────────────────────────────┘
```

---

## 6. Verification & Sign-Off

The data cleaning pipeline was tested against full event streams from La Liga, Premier League, Bundesliga, and Champions League matches. It meets all Phase 2 criteria:
* **Dimension records:** 100+ distinct teams and 500+ master player profiles conformed.
* **Fact records:** Over 10,000 granular player-match performance rows and squad entries loaded without referential integrity failure.
