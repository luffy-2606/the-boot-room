# The Boot Room

Football analytics data warehouse built on StatsBomb Open Data — a player-match,
league-standing, and squad-selection star schema in PostgreSQL, surfaced in Power BI.

## What this is

The Boot Room is a data warehouse that turns raw, event-level football data into
decision-ready analytics for a club's analysis and recruitment staff. It models three
business processes — match performance, league standing, and squad selection — as a
star schema with three fact tables of three different types.

## Data source

Built on [StatsBomb Open Data](https://github.com/statsbomb/open-data) — free,
event-level JSON covering professional competitions (La Liga, Premier League,
World Cup, and more). The JSON is the *source*; it is flattened, cleaned, and
conformed into the warehouse schema during later phases.

> **Attribution:** any analysis published from this project must credit StatsBomb as
> the source, per their terms.

## Star schema (Gold layer)

Six conformed dimensions around three fact tables:

| Fact table | Type | Grain |
|---|---|---|
| `fact_player_match` | Transactional | one player per match |
| `fact_league_standing` | Periodic snapshot | one team per matchday |
| `fact_matchday_squad` | Factless | one player per match |

Dimensions: `dim_season`, `dim_date`, `dim_team`, `dim_player`, `dim_match`, `dim_venue`.

See `phase1/06_schema.pdf`, `phase1/schema.dbml` (dbdiagram.io), and
`phase1/schema diagram.png`.

## Tech stack

- **PostgreSQL** — the warehouse (target database)
- **Power BI** — reporting and dashboards (DAX)
- **Python** — ingestion and transformation helpers
- **dbdiagram.io / draw.io** — schema design

## Project structure

```
phase1/        Phase 1 deliverables: proposal, requirements, business questions,
               schema (PDF), data dictionary (Excel), schema diagram (PNG + DBML)
data/          (Phase 2+) raw StatsBomb JSON — gitignored, fetched separately
sql/           (Phase 2+) DDL, ETL/ELT, and analysis queries
```

## Phase 1 — Business Analysis & Dimensional Design

The `phase1/` folder is the complete Phase 1 submission: project proposal, business
requirements document, 12 business questions, fact/dimension identification, grain
definitions, star schema, and data dictionary.

## Status

- [x] Phase 1 — dimensional design
- [ ] Phase 2 — PostgreSQL staging + DW implementation
- [ ] Phase 3 — ETL/ELT, indexing, partitioning, BI dashboard
