-- =============================================================================
-- THE BOOT ROOM — Data Warehouse
-- File   : 05_load_facts.sql
-- Phase  : 2 — Fact Loading
-- Run after: 04_load_dimensions.sql
--
-- Loads all three fact tables from project_staging into project_dw:
--   1. fact_player_match      (Transactional)
--   2. fact_matchday_squad    (Factless)
--   3. fact_league_standing   (Periodic Snapshot — derived/computed)
--
-- Design pattern: Business Key → Surrogate Key via JOIN to dimension tables.
--   e.g. spm.player_id (INTEGER biz key) → dp.player_key (SERIAL surrogate)
-- =============================================================================

DO $$
DECLARE
  v_count INTEGER;
BEGIN

  -- ===========================================================================
  -- FACT 1: fact_player_match  (Transactional Fact)
  -- Source : project_staging.stg_player_match_summary  (from events_summary.csv)
  --
  -- Surrogate-key mapping:
  --   Business key lookup: spm.player_id (e.g. 123)  → dp.player_key (e.g. 1001)
  --   Business key lookup: spm.match_id  (e.g. 42)   → dm.match_key  (e.g. 2001)
  --   Business key lookup: spm.team_id   (e.g. 7)    → dt.team_key   (e.g. 3001)
  --   season_key and date_key are inherited from dim_match (already resolved there)
  -- ===========================================================================
  INSERT INTO project_dw.fact_player_match (
    player_key,
    match_key,
    team_key,
    season_key,
    date_key,
    position_played,
    minutes_played,
    goals,
    assists,
    shots,
    shots_on_target,
    key_passes,
    passes_completed,
    passes_attempted,
    xg,
    tackles,
    interceptions,
    yellow_cards,
    red_cards,
    fouls_committed,
    fouls_won
  )
  SELECT
    dp.player_key,
    dm.match_key,
    dt.team_key,
    dm.season_key,
    dm.date_key,
    INITCAP(TRIM(NULLIF(spm.position_played, ''))),
    COALESCE(NULLIF(spm.minutes_played,     '')::SMALLINT,      0),
    COALESCE(NULLIF(spm.goals,              '')::SMALLINT,      0),
    COALESCE(NULLIF(spm.assists,            '')::SMALLINT,      0),
    COALESCE(NULLIF(spm.shots,              '')::SMALLINT,      0),
    COALESCE(NULLIF(spm.shots_on_target,    '')::SMALLINT,      0),
    COALESCE(NULLIF(spm.key_passes,         '')::SMALLINT,      0),
    COALESCE(NULLIF(spm.passes_completed,   '')::SMALLINT,      0),
    COALESCE(NULLIF(spm.passes_attempted,   '')::SMALLINT,      0),
    COALESCE(NULLIF(spm.xg,                 '')::NUMERIC(6,3),  0),
    COALESCE(NULLIF(spm.tackles,            '')::SMALLINT,      0),
    COALESCE(NULLIF(spm.interceptions,      '')::SMALLINT,      0),
    COALESCE(NULLIF(spm.yellow_cards,       '')::SMALLINT,      0),
    COALESCE(NULLIF(spm.red_cards,          '')::SMALLINT,      0),
    COALESCE(NULLIF(spm.fouls_committed,    '')::SMALLINT,      0),
    COALESCE(NULLIF(spm.fouls_won,          '')::SMALLINT,      0)
  FROM project_staging.stg_player_match_summary spm
  -- Business key lookup: spm.player_id (C123) → dp.player_key (1001)
  JOIN project_dw.dim_player dp ON dp.player_id = CAST(spm.player_id AS INTEGER)
  -- Business key lookup: spm.match_id  (C42)  → dm.match_key  (2001)
  JOIN project_dw.dim_match  dm ON dm.match_id  = CAST(spm.match_id  AS INTEGER)
  -- Business key lookup: spm.team_id   (C7)   → dt.team_key   (3001)
  JOIN project_dw.dim_team   dt ON dt.team_id   = CAST(spm.team_id   AS INTEGER)
  WHERE spm.player_id IS NOT NULL AND spm.player_id != ''
    AND spm.match_id  IS NOT NULL AND spm.match_id  != ''
    AND spm.team_id   IS NOT NULL AND spm.team_id   != ''
  ON CONFLICT (player_key, match_key) DO UPDATE SET
    goals          = EXCLUDED.goals,
    assists        = EXCLUDED.assists,
    minutes_played = EXCLUDED.minutes_played;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE 'fact_player_match: % rows inserted/updated', v_count;


  -- ===========================================================================
  -- FACT 2: fact_matchday_squad  (Factless Fact)
  -- Source : project_staging.stg_lineup_entry
  --
  -- Surrogate-key mapping:
  --   Business key lookup: sle.player_id (e.g. 123)  → dp.player_key (e.g. 1001)
  --   Business key lookup: sle.match_id  (e.g. 42)   → dm.match_key  (e.g. 2001)
  --   Business key lookup: sle.team_id   (e.g. 7)    → dt.team_key   (e.g. 3001)
  --   season_key and date_key are inherited from dim_match
  -- ===========================================================================
  INSERT INTO project_dw.fact_matchday_squad (
    player_key,
    match_key,
    team_key,
    season_key,
    date_key,
    is_starter,
    jersey_number
  )
  SELECT DISTINCT
    dp.player_key,
    dm.match_key,
    dt.team_key,
    dm.season_key,
    dm.date_key,
    (LOWER(TRIM(COALESCE(sle.is_starter, 'false'))) = 'true'),
    NULLIF(sle.jersey_number, '')::SMALLINT
  FROM project_staging.stg_lineup_entry sle
  -- Business key lookup: sle.player_id (C123) → dp.player_key (1001)
  JOIN project_dw.dim_player dp ON dp.player_id = CAST(sle.player_id AS INTEGER)
  -- Business key lookup: sle.match_id  (C42)  → dm.match_key  (2001)
  JOIN project_dw.dim_match  dm ON dm.match_id  = CAST(sle.match_id  AS INTEGER)
  -- Business key lookup: sle.team_id   (C7)   → dt.team_key   (3001)
  JOIN project_dw.dim_team   dt ON dt.team_id   = CAST(sle.team_id   AS INTEGER)
  WHERE sle.player_id IS NOT NULL AND sle.player_id != ''
    AND sle.match_id  IS NOT NULL AND sle.match_id  != ''
    AND sle.team_id   IS NOT NULL AND sle.team_id   != ''
  ON CONFLICT (player_key, match_key) DO UPDATE SET
    is_starter    = EXCLUDED.is_starter,
    jersey_number = EXCLUDED.jersey_number;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE 'fact_matchday_squad: % rows inserted/updated', v_count;


  -- ===========================================================================
  -- FACT 3: fact_league_standing  (Periodic Snapshot — Derived/Computed)
  -- Source : project_dw.dim_match  +  project_dw.fact_player_match
  --
  -- StatsBomb does not supply league standings directly, so we derive them
  -- analytically from match results already in the DW.
  --
  -- Surrogate-key mapping:
  --   dim_match already carries team_key, season_key, date_key (all resolved).
  --   We produce one row per team per matchday per season.
  --
  -- CTE pipeline:
  --   1. match_results  — one row per team per match, with own_score / opponent_score / points
  --   2. cumulative     — running window totals (SUM OVER ... ROWS UNBOUNDED PRECEDING)
  --   3. ranked         — RANK() for league position per season+matchday
  --   4. Final SELECT   — adds form_last_5 string ('WDLWW' etc.)
  -- ===========================================================================
  INSERT INTO project_dw.fact_league_standing (
    team_key,
    season_key,
    date_key,
    matchday,
    league_position,
    points,
    games_played,
    games_won,
    games_drawn,
    games_lost,
    goals_for,
    goals_against,
    form_last_5
  )
  WITH match_results AS (
    -- Expand each match into two rows: one for the home team, one for the away team.
    -- Business key lookup: dm.home_team_key / dm.away_team_key → already surrogate keys.
    SELECT
      dm.home_team_key                                      AS team_key,
      dm.season_key,
      dm.date_key,
      dm.match_week AS matchday,
      TRUE                                                   AS is_home,
      COALESCE(dm.home_score, 0)                             AS own_score,
      COALESCE(dm.away_score, 0)                             AS opponent_score,
      CASE
        WHEN COALESCE(dm.home_score, 0) > COALESCE(dm.away_score, 0) THEN 3
        WHEN COALESCE(dm.home_score, 0) = COALESCE(dm.away_score, 0) THEN 1
        ELSE 0
      END                                                    AS points,
      CASE
        WHEN COALESCE(dm.home_score, 0) > COALESCE(dm.away_score, 0) THEN 'W'
        WHEN COALESCE(dm.home_score, 0) = COALESCE(dm.away_score, 0) THEN 'D'
        ELSE 'L'
      END                                                    AS result_char
    FROM project_dw.dim_match dm
    WHERE dm.home_team_key IS NOT NULL

    UNION ALL

    SELECT
      dm.away_team_key                                       AS team_key,
      dm.season_key,
      dm.date_key,
      dm.match_week AS matchday,
      FALSE                                                  AS is_home,
      COALESCE(dm.away_score, 0)                             AS own_score,
      COALESCE(dm.home_score, 0)                             AS opponent_score,
      CASE
        WHEN COALESCE(dm.away_score, 0) > COALESCE(dm.home_score, 0) THEN 3
        WHEN COALESCE(dm.away_score, 0) = COALESCE(dm.home_score, 0) THEN 1
        ELSE 0
      END                                                    AS points,
      CASE
        WHEN COALESCE(dm.away_score, 0) > COALESCE(dm.home_score, 0) THEN 'W'
        WHEN COALESCE(dm.away_score, 0) = COALESCE(dm.home_score, 0) THEN 'D'
        ELSE 'L'
      END                                                    AS result_char
    FROM project_dw.dim_match dm
    WHERE dm.away_team_key IS NOT NULL
  ),

  cumulative AS (
    -- Running window totals partitioned by team + season, ordered by matchday.
    SELECT
      team_key,
      season_key,
      date_key,
      matchday,
      result_char,
      SUM(points)       OVER w                               AS points,
      COUNT(*)          OVER w                               AS games_played,
      SUM(CASE WHEN result_char = 'W' THEN 1 ELSE 0 END) OVER w AS games_won,
      SUM(CASE WHEN result_char = 'D' THEN 1 ELSE 0 END) OVER w AS games_drawn,
      SUM(CASE WHEN result_char = 'L' THEN 1 ELSE 0 END) OVER w AS games_lost,
      SUM(own_score)      OVER w                             AS goals_for,
      SUM(opponent_score) OVER w                             AS goals_against,
      SUM(own_score)      OVER w
        - SUM(opponent_score) OVER w                         AS goal_diff
    FROM match_results
    WINDOW w AS (
      PARTITION BY team_key, season_key
      ORDER BY matchday
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )
  ),

  ranked AS (
    -- Assign league position for each team at each matchday snapshot.
    SELECT
      team_key,
      season_key,
      date_key,
      matchday,
      result_char,
      points,
      games_played,
      games_won,
      games_drawn,
      games_lost,
      goals_for,
      goals_against,
      goal_diff,
      RANK() OVER (
        PARTITION BY season_key, matchday
        ORDER BY points DESC, goal_diff DESC
      )                                                      AS league_position
    FROM cumulative
  )

  -- Final projection: attach form_last_5 string using a sub-window over the
  -- most-recent 5 result characters per team+season up to and including this matchday.
  SELECT DISTINCT ON (r.team_key, r.season_key, r.matchday)
    r.team_key,
    r.season_key,
    r.date_key,
    r.matchday,
    r.league_position,
    r.points,
    r.games_played,
    r.games_won,
    r.games_drawn,
    r.games_lost,
    r.goals_for,
    r.goals_against,
    -- form_last_5: comma-free string of last 5 results, oldest → newest
    -- e.g. 'WDLWW'.  array_agg window collects the last 5 result chars.
    array_to_string(
      ARRAY(
        SELECT mr2.result_char
        FROM match_results mr2
        WHERE mr2.team_key   = r.team_key
          AND mr2.season_key = r.season_key
          AND mr2.matchday  <= r.matchday
        ORDER BY mr2.matchday DESC
        LIMIT 5
      ),
      ''
    )                                                        AS form_last_5
  FROM ranked r
  ORDER BY r.team_key, r.season_key, r.matchday, r.date_key
  ON CONFLICT (team_key, season_key, matchday) DO UPDATE SET
    league_position = EXCLUDED.league_position,
    points          = EXCLUDED.points;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE 'fact_league_standing: % rows inserted/updated', v_count;

END $$;
