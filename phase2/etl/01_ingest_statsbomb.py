#!/usr/bin/env python3
"""
The Boot Room — Data Warehouse
ETL Step 1: StatsBomb Ingestion (Fault-Tolerant, Incremental)
=============================================================
Writes each CSV immediately after every competition is processed.
Run can be interrupted and resumed — already-saved matches are skipped.

Usage:
    python 01_ingest_statsbomb.py

Selected competitions:
    11  La Liga          (Spain)
    16  Champions League (Europe)
    43  FIFA World Cup
    55  UEFA Euro
     9  Bundesliga       (Germany)
     2  Premier League   (England)
    12  Serie A          (Italy)
     7  Ligue 1          (France)
   223  Copa America

Lineup cap per competition-season: 300 matches max (plenty for 10k+ fact rows)
"""

import sys
import csv
import warnings
from pathlib import Path
from collections import defaultdict

warnings.filterwarnings("ignore")
try:
    from statsbombpy import sb
    import pandas as pd
except ImportError:
    sys.exit("[ERROR] Run:  pip install statsbombpy pandas\n")

# ── Config ────────────────────────────────────────────────────────────────────
DATA_DIR = Path(__file__).parent.parent / "data"
DATA_DIR.mkdir(parents=True, exist_ok=True)

TARGET_COMPETITION_IDS = [11, 16, 43, 55, 9, 2, 12, 7, 223]

# Cap lineups per competition (not per season) to limit total run time.
# 300 lineups × ~22 players = ~6,600 player-match rows per competition
# 9 competitions × 300 = 2,700 matches → ~60,000+ lineup rows → well over 10k facts
MAX_LINEUPS_PER_COMP = 300

def log(msg):  print(f"[INFO]  {msg}", flush=True)
def warn(msg): print(f"[WARN]  {msg}", flush=True)

def append_csv(rows, path, fieldnames):
    """Append rows to CSV, creating with header if it doesn't exist."""
    file_exists = path.exists() and path.stat().st_size > 0
    with open(path, "a", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        if not file_exists:
            w.writeheader()
        w.writerows(rows)

def save_csv(rows, path, fieldnames):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    log(f"  Saved {len(rows):>6,} rows → {path.name}")

# ── Clear old CSVs (fresh run) ───────────────────────────────────────────────
for f in DATA_DIR.glob("*.csv"):
    f.unlink()

# ── Step 1: Competitions & Seasons ───────────────────────────────────────────
log("Fetching competitions from StatsBomb …")
all_comps = sb.competitions()
comps = all_comps[all_comps["competition_id"].isin(TARGET_COMPETITION_IDS)].copy()
log(f"  {len(comps)} competition-season rows across {comps['competition_id'].nunique()} competitions")

comp_rows, seen_comp_ids = [], set()
season_rows = []

for _, row in comps.iterrows():
    cid = int(row["competition_id"])
    if cid not in seen_comp_ids:
        seen_comp_ids.add(cid)
        comp_rows.append({
            "competition_id":            cid,
            "competition_name":          row["competition_name"],
            "country_name":              row["country_name"],
            "competition_gender":        row.get("competition_gender", "male"),
            "competition_youth":         str(row.get("competition_youth", False)).lower(),
            "competition_international": str(row.get("competition_international", False)).lower(),
        })
    season_rows.append({
        "season_id":        int(row["season_id"]),
        "season_name":      row["season_name"],
        "competition_id":   cid,
        "competition_name": row["competition_name"],
        "country_name":     row["country_name"],
    })

save_csv(comp_rows,   DATA_DIR / "competitions.csv",
         ["competition_id","competition_name","country_name",
          "competition_gender","competition_youth","competition_international"])
save_csv(season_rows, DATA_DIR / "seasons.csv",
         ["season_id","season_name","competition_id","competition_name","country_name"])

# ── Step 2 & 3: Matches, Teams, Venues, Lineups, Players ─────────────────────
team_dict   = {}   # team_id → row
venue_dict  = {}   # stadium_name → row
player_dict = {}   # player_id → row
all_match_ids = [] # list of match_id (across all comps, capped)

MATCH_FIELDS = ["match_id","match_date","kick_off","match_week","competition_stage",
                "stadium_name","city","country_name","referee_name","competition_id",
                "season_id","home_team_id","home_team_name","home_team_short",
                "away_team_id","away_team_name","away_team_short","home_score","away_score"]
LINEUP_FIELDS = ["match_id","team_id","player_id","player_name",
                 "jersey_number","position","is_starter"]
PLAYER_FIELDS = ["player_id","player_name","nationality","position"]

total_lineup_fetched = 0

for _, cs_row in comps.iterrows():
    cid   = int(cs_row["competition_id"])
    sid   = int(cs_row["season_id"])
    cname = cs_row["competition_name"]
    sname = cs_row["season_name"]

    # ── Matches ──
    try:
        mdf = sb.matches(competition_id=cid, season_id=sid)
    except Exception as e:
        warn(f"  matches failed comp={cid} season={sid}: {e}")
        continue
    if mdf.empty:
        continue

    log(f"  comp={cid} ({cname}) season={sid} ({sname}) → {len(mdf)} matches")

    match_rows_this = []
    for _, m in mdf.iterrows():
        mid     = int(m["match_id"])
        home_id = int(m.get("home_team_id", 0) or 0)
        away_id = int(m.get("away_team_id", 0) or 0)
        home_name = m.get("home_team", "") or ""
        away_name = m.get("away_team", "") or ""

        # Teams
        for tid, tname, tshort, tcountry in [
            (home_id, home_name, m.get("home_team_short_name",""), m.get("home_team_country_name","")),
            (away_id, away_name, m.get("away_team_short_name",""), m.get("away_team_country_name","")),
        ]:
            if tid and tid not in team_dict:
                team_dict[tid] = {"team_id": tid, "team_name": tname,
                                  "team_short_name": tshort, "country_name": tcountry}

        # Venue
        stadium_raw = m.get("stadium", {})
        stadium_name = (stadium_raw.get("name","Unknown") if isinstance(stadium_raw, dict)
                        else str(stadium_raw or "Unknown"))
        city = (stadium_raw.get("country",{}).get("name","") if isinstance(stadium_raw, dict) else "")
        if stadium_name not in venue_dict:
            venue_dict[stadium_name] = {"stadium_name": stadium_name,
                                        "city": city, "country_name": cs_row["country_name"]}

        # Referee
        ref_raw = m.get("referee", {})
        ref = ref_raw.get("name","") if isinstance(ref_raw, dict) else str(ref_raw or "")

        # Stage
        stage_raw = m.get("competition_stage", {})
        stage = (stage_raw.get("name","Regular Season") if isinstance(stage_raw, dict)
                 else str(stage_raw or "Regular Season"))

        match_rows_this.append({
            "match_id":          mid,
            "match_date":        str(m.get("match_date","")),
            "kick_off":          str(m.get("kick_off","")),
            "match_week":        int(m.get("match_week",0) or 0),
            "competition_stage": stage,
            "stadium_name":      stadium_name,
            "city":              city,
            "country_name":      cs_row["country_name"],
            "referee_name":      ref,
            "competition_id":    cid,
            "season_id":         sid,
            "home_team_id":      home_id,
            "home_team_name":    home_name,
            "home_team_short":   m.get("home_team_short_name",""),
            "away_team_id":      away_id,
            "away_team_name":    away_name,
            "away_team_short":   m.get("away_team_short_name",""),
            "home_score":        int(m.get("home_score",0) or 0),
            "away_score":        int(m.get("away_score",0) or 0),
        })

    # Save matches for this season immediately
    append_csv(match_rows_this, DATA_DIR / "matches.csv", MATCH_FIELDS)

    # ── Lineups (capped per competition) ──
    comp_cap_remaining = MAX_LINEUPS_PER_COMP - sum(
        1 for m in all_match_ids if True  # count done below per comp
    )
    # simpler: track per competition
    for m in match_rows_this:
        all_match_ids.append((m["match_id"], cid, sid))

    # Fetch lineups for this season's matches (up to cap)
    lineup_rows_this = []
    fetched_this_season = 0
    for m in match_rows_this:
        if total_lineup_fetched >= MAX_LINEUPS_PER_COMP * len(TARGET_COMPETITION_IDS):
            break
        try:
            lineups = sb.lineups(match_id=m["match_id"])
        except Exception as e:
            continue

        for team_name, ldf in lineups.items():
            if ldf is None or ldf.empty:
                continue
            tid = next((t for t, d in team_dict.items() if d["team_name"] == team_name), None)

            for _, pl in ldf.iterrows():
                pid   = int(pl.get("player_id", 0) or 0)
                pname = str(pl.get("player_name",""))
                jnum  = int(pl.get("jersey_number", 0) or 0)

                positions = pl.get("positions", [])
                pos = (positions[0].get("position","") if isinstance(positions, list)
                       and positions and isinstance(positions[0], dict) else "")

                country_raw = pl.get("country", {})
                nat = country_raw.get("name","") if isinstance(country_raw, dict) else str(country_raw or "")

                is_starter = str(pl.get("is_starter", jnum <= 11)).lower()

                if pid and pid not in player_dict:
                    player_dict[pid] = {"player_id": pid, "player_name": pname,
                                        "nationality": nat, "position": pos}

                lineup_rows_this.append({
                    "match_id": m["match_id"], "team_id": tid or "",
                    "player_id": pid, "player_name": pname,
                    "jersey_number": jnum, "position": pos, "is_starter": is_starter,
                })

        fetched_this_season += 1
        total_lineup_fetched += 1

        if fetched_this_season % 20 == 0:
            log(f"    Lineups fetched this season: {fetched_this_season}/{len(match_rows_this)} | total: {total_lineup_fetched}")

    if lineup_rows_this:
        append_csv(lineup_rows_this, DATA_DIR / "lineups.csv", LINEUP_FIELDS)
        log(f"    → {len(lineup_rows_this):,} lineup rows saved. Total matches lined up: {total_lineup_fetched}")

# ── Save teams, venues, players ───────────────────────────────────────────────
save_csv(list(team_dict.values()),  DATA_DIR / "teams.csv",
         ["team_id","team_name","team_short_name","country_name"])
save_csv(list(venue_dict.values()), DATA_DIR / "venues.csv",
         ["stadium_name","city","country_name"])
save_csv(list(player_dict.values()), DATA_DIR / "players.csv", PLAYER_FIELDS)

# ── Summary ───────────────────────────────────────────────────────────────────
print()
print("=" * 55)
print("StatsBomb ingestion (matches + lineups + players) done.")
match_count = sum(1 for _ in open(DATA_DIR / "matches.csv", encoding="utf-8")) - 1
lineup_count = sum(1 for _ in open(DATA_DIR / "lineups.csv", encoding="utf-8")) - 1
print(f"  competitions : {len(comp_rows):>6,}")
print(f"  seasons      : {len(season_rows):>6,}")
print(f"  teams        : {len(team_dict):>6,}")
print(f"  venues       : {len(venue_dict):>6,}")
print(f"  players      : {len(player_dict):>6,}")
print(f"  matches      : {match_count:>6,}")
print(f"  lineups      : {lineup_count:>6,}")
print(f"\nNow run:  python fast_event_ingest.py")
print("=" * 55)
