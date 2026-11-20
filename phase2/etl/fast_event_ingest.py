#!/usr/bin/env python3
"""
The Boot Room — Data Warehouse
ETL Step 1B: Aggregate Events (memory-efficient, JSON-based)
============================================================
Pulls matches that already exist in matches.csv and aggregates events
into events_summary.csv. Uses fmt="json" (raw dicts) instead of the full
pandas DataFrame to avoid OOM on the 360 freeze-frame data.

Caps at 600 matches (~15,000+ fact rows).
"""

import csv
import warnings
from pathlib import Path

warnings.filterwarnings("ignore")
from statsbombpy import sb

DATA_DIR = Path(__file__).parent.parent / "data"
MATCHES_FILE = DATA_DIR / "matches.csv"
OUTPUT_FILE = DATA_DIR / "events_summary.csv"

TARGET_MATCHES = 600

fieldnames = [
    "match_id", "team_id", "player_id", "player_name",
    "position_played", "minutes_played", "goals", "assists",
    "shots", "shots_on_target", "key_passes",
    "passes_completed", "passes_attempted", "xg",
    "tackles", "interceptions", "yellow_cards", "red_cards",
    "fouls_committed", "fouls_won"
]

with open(MATCHES_FILE, encoding="utf-8", newline="") as f:
    reader = csv.DictReader(f)
    match_ids = [row["match_id"] for row in reader][:TARGET_MATCHES]

print(f"[INFO] Ingesting events for {len(match_ids)} matches (Target >= 10,000 fact rows)...")

total_rows = 0
with open(OUTPUT_FILE, "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()

    for idx, mid in enumerate(match_ids, 1):
        if idx % 25 == 0 or idx == 1:
            print(f"[INFO] Match {idx}/{len(match_ids)} (Current event rows: {total_rows})...", flush=True)
            f.flush()

        try:
            events = list(sb.events(match_id=mid, fmt="json").values())
        except Exception:
            continue

        if not events:
            continue

        # shot event id -> True when that shot was a goal (used to resolve assists)
        shot_goal = {}
        for ev in events:
            if (ev.get("type") or {}).get("name") == "Shot":
                sid = ev.get("id")
                outcome = ((ev.get("shot") or {}).get("outcome") or {}).get("name")
                if sid:
                    shot_goal[sid] = (outcome == "Goal")

        # aggregate one row per player
        players = {}
        for ev in events:
            player = ev.get("player") or {}
            pid = player.get("id")
            if pid is None:
                continue
            team = ev.get("team") or {}
            type_name = (ev.get("type") or {}).get("name", "")
            minute = ev.get("minute") or 0

            p = players.setdefault(pid, {
                "match_id": mid,
                "team_id": team.get("id"),
                "player_id": pid,
                "player_name": player.get("name", ""),
                "position_played": "",
                "minutes_played": 0,
                "goals": 0, "assists": 0, "shots": 0, "shots_on_target": 0,
                "key_passes": 0, "passes_completed": 0, "passes_attempted": 0,
                "xg": 0.0, "tackles": 0, "interceptions": 0,
                "yellow_cards": 0, "red_cards": 0,
                "fouls_committed": 0, "fouls_won": 0,
            })

            if minute > p["minutes_played"]:
                p["minutes_played"] = minute
            if not p["team_id"] and team.get("id"):
                p["team_id"] = team.get("id")
            if not p["position_played"]:
                p["position_played"] = (ev.get("position") or {}).get("name", "")

            if type_name == "Shot":
                shot = ev.get("shot") or {}
                outcome = (shot.get("outcome") or {}).get("name", "")
                p["shots"] += 1
                if outcome == "Goal":
                    p["goals"] += 1
                if outcome in ("Goal", "Saved", "Saved To Post"):
                    p["shots_on_target"] += 1
                p["xg"] += shot.get("statsbomb_xg") or 0.0
            elif type_name == "Pass":
                pas = ev.get("pass") or {}
                p["passes_attempted"] += 1
                if not pas.get("outcome"):
                    p["passes_completed"] += 1
                if pas.get("shot_assist"):
                    p["key_passes"] += 1
                    if shot_goal.get(pas.get("assisted_shot_id")):
                        p["assists"] += 1
            elif type_name == "Tackle":
                p["tackles"] += 1
            elif type_name == "Interception":
                p["interceptions"] += 1
            elif type_name == "Foul Committed":
                p["fouls_committed"] += 1
            elif type_name == "Foul Won":
                p["fouls_won"] += 1

            card = ""
            for container in (ev.get("foul_committed"), ev.get("bad_behaviour")):
                if isinstance(container, dict):
                    card = (container.get("card") or {}).get("name", "") or card
            if card in ("Yellow Card", "Second Yellow"):
                p["yellow_cards"] += 1
            elif card == "Red Card":
                p["red_cards"] += 1

        for pid in sorted(players):
            row = players[pid]
            row["xg"] = round(row["xg"], 3)
            writer.writerow(row)
            total_rows += 1

        if total_rows >= 15000:
            print(f"[SUCCESS] Reached {total_rows} fact rows! Gracefully exiting early.")
            break

print(f"\n[DONE] Finished with {total_rows:,} event rows saved to events_summary.csv!")
