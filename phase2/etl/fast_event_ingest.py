
#!/usr/bin/env python3
"""
The Boot Room — Data Warehouse
ETL Step 1B: Aggregate Events with Immediate Flushing & Cap
===========================================================
Pulls matches that already exist in matches.csv and aggregates
events, writing to events_summary.csv continuously.
Caps at 500 matches (~15,000+ fact rows) so it completes quickly!
"""

import csv
import warnings
from pathlib import Path
import pandas as pd

warnings.filterwarnings("ignore")
from statsbombpy import sb

DATA_DIR = Path(__file__).parent.parent / "data"
MATCHES_FILE = DATA_DIR / "matches.csv"
OUTPUT_FILE = DATA_DIR / "events_summary.csv"

# Target: at least 10,000 fact rows (500 matches × ~28 players = ~14,000)
# With 9 competitions, we have ~3,800+ matches total — cap at 600 for speed.
TARGET_MATCHES = 600

matches_df = pd.read_csv(MATCHES_FILE)
match_ids = matches_df["match_id"].tolist()[:TARGET_MATCHES]
print(f"[INFO] Ingesting events for {len(match_ids)} matches (Target >= 10,000 fact rows)...")

fieldnames = [
    "match_id", "team_id", "player_id", "player_name",
    "position_played", "minutes_played", "goals", "assists",
    "shots", "shots_on_target", "key_passes",
    "passes_completed", "passes_attempted", "xg",
    "tackles", "interceptions", "yellow_cards", "red_cards",
    "fouls_committed", "fouls_won"
]

total_rows = 0
with open(OUTPUT_FILE, "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()

    for idx, mid in enumerate(match_ids, 1):
        if idx % 25 == 0 or idx == 1:
            print(f"[INFO] Match {idx}/{len(match_ids)} (Current event rows: {total_rows})...", flush=True)
            f.flush()

        try:
            events_df = sb.events(match_id=mid)
        except Exception as e:
            continue

        if events_df.empty or "player_id" not in events_df.columns:
            continue

        player_ids = events_df["player_id"].dropna().unique()
        for pid in player_ids:
            pe = events_df[events_df["player_id"] == pid]
            team_vals = pe["team_id"].dropna().unique() if "team_id" in pe.columns else []
            team_id = int(team_vals[0]) if len(team_vals) > 0 else None
            
            pname = str(pe["player"].iloc[0]) if "player" in pe.columns and not pe["player"].dropna().empty else ""
            pos_vals = pe["position"].dropna().unique() if "position" in pe.columns else []
            pos = str(pos_vals[0]) if len(pos_vals) > 0 else ""
            mins = int(pe["minute"].max()) if "minute" in pe.columns else 0

            # Goals
            if "shot_outcome" in pe.columns:
                goals = int((pe["shot_outcome"] == "Goal").sum())
            else:
                goals = 0

            # Shots
            shots = int((pe["type"] == "Shot").sum()) if "type" in pe.columns else 0
            
            # Shots on target
            if "shot_outcome" in pe.columns:
                sot = int(pe["shot_outcome"].isin(["Goal", "Saved", "Saved To Post"]).sum())
            else:
                sot = 0

            # xg
            xg = round(float(pe["shot_statsbomb_xg"].sum()), 3) if "shot_statsbomb_xg" in pe.columns else 0.0

            # Passes
            if "type" in pe.columns:
                passes = pe[pe["type"] == "Pass"]
                pass_att = len(passes)
                pass_comp = int(passes.get("pass_outcome", pd.Series([])).isna().sum()) if "pass_outcome" in passes.columns else pass_att
            else:
                pass_att = 0
                pass_comp = 0

            kp = int(passes.get("pass_key_pass", pd.Series([])).sum()) if "type" in pe.columns and "pass_key_pass" in passes.columns else 0
            assists = int(passes.get("pass_goal_assist", pd.Series([])).sum()) if "type" in pe.columns and "pass_goal_assist" in passes.columns else 0

            tackles = int((pe["type"] == "Tackle").sum()) if "type" in pe.columns else 0
            interceptions = int((pe["type"] == "Interception").sum()) if "type" in pe.columns else 0
            fouls_committed = int((pe["type"] == "Foul Committed").sum()) if "type" in pe.columns else 0
            fouls_won = int((pe["type"] == "Foul Won").sum()) if "type" in pe.columns else 0

            yc = int(pe.get("bad_behaviour_card", pd.Series([])).isin(["Yellow Card", "Second Yellow"]).sum()) if "bad_behaviour_card" in pe.columns else 0
            rc = int(pe.get("bad_behaviour_card", pd.Series([])).eq("Red Card").sum()) if "bad_behaviour_card" in pe.columns else 0

            writer.writerow({
                "match_id": mid,
                "team_id": team_id or "",
                "player_id": int(pid),
                "player_name": pname,
                "position_played": pos,
                "minutes_played": mins,
                "goals": goals,
                "assists": assists,
                "shots": shots,
                "shots_on_target": sot,
                "key_passes": kp,
                "passes_completed": pass_comp,
                "passes_attempted": pass_att,
                "xg": xg,
                "tackles": tackles,
                "interceptions": interceptions,
                "yellow_cards": yc,
                "red_cards": rc,
                "fouls_committed": fouls_committed,
                "fouls_won": fouls_won
            })
            total_rows += 1

        # Check early exit if we crossed 15,000 fact rows!
        if total_rows >= 15000:
            print(f"[SUCCESS] Reached {total_rows} fact rows! Gracefully exiting early.")
            break

print(f"\n[DONE] Finished with {total_rows:,} event rows saved to events_summary.csv!")
