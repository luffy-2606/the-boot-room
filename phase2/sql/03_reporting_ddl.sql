-- ============================================================
-- The Boot Room — Data Warehouse
-- Script 03: Reporting Schema DDL
-- Schema: project_reporting
-- ============================================================
-- Flattened, denormalized views consumed by Power BI / SQL clients.
-- No data is stored here — all objects are VIEWs over project_dw.
-- ============================================================

SET search_path TO project_reporting;

-- ─────────────────────────────────────────
-- v_player_match_stats
-- Power BI page: Player Performance
-- ─────────────────────────────────────────
DROP VIEW IF EXISTS project_reporting.v_player_match_stats CASCADE;
CREATE VIEW project_reporting.v_player_match_stats AS
SELECT
    -- Player
    dp.player_key,
    dp.player_id,
    dp.player_name,
    dp.player_nickname,
    dp.nationality,
    dp.primary_position,
    -- Team
    dt.team_key,
    dt.team_id,
    dt.team_name,
    dt.country_name                     AS team_country,
    -- Season / competition
    ds.season_key,
    ds.season_id,
    ds.season_name,
    ds.competition_name,
    ds.country_name                     AS competition_country,
    -- Match
    dm.match_key,
    dm.match_id,
    dm.match_date,
    dm.match_week,
    dm.competition_stage,
    dm.result                           AS match_result,
    -- Date
    dd.year,
    dd.month,
    dd.month_name,
    dd.quarter,
    dd.day_name,
    dd.is_weekend,
    -- Performance measures
    fpm.position_played,
    fpm.minutes_played,
    fpm.goals,
    fpm.assists,
    fpm.shots,
    fpm.shots_on_target,
    fpm.key_passes,
    fpm.passes_completed,
    fpm.passes_attempted,
    fpm.pass_completion_pct,
    fpm.xg,
    fpm.tackles,
    fpm.interceptions,
    fpm.yellow_cards,
    fpm.red_cards,
    fpm.fouls_committed,
    fpm.fouls_won,
    -- Derived
    CASE WHEN fpm.shots > 0
         THEN ROUND(fpm.goals::NUMERIC / fpm.shots * 100, 1)
         ELSE 0 END                     AS shot_conversion_pct,
    CASE WHEN fpm.shots > 0
         THEN ROUND(fpm.xg / fpm.shots, 3)
         ELSE 0 END                     AS xg_per_shot
FROM  project_dw.fact_player_match   fpm
JOIN  project_dw.dim_player          dp  ON fpm.player_key = dp.player_key
JOIN  project_dw.dim_team            dt  ON fpm.team_key   = dt.team_key
JOIN  project_dw.dim_season          ds  ON fpm.season_key = ds.season_key
JOIN  project_dw.dim_match           dm  ON fpm.match_key  = dm.match_key
LEFT  JOIN project_dw.dim_date       dd  ON fpm.date_key   = dd.date_key;

COMMENT ON VIEW project_reporting.v_player_match_stats IS
    'Fully denormalized player-per-match stats for BI consumption';

-- ─────────────────────────────────────────
-- v_league_table
-- Power BI page: League Table / Standings
-- ─────────────────────────────────────────
DROP VIEW IF EXISTS project_reporting.v_league_table CASCADE;
CREATE VIEW project_reporting.v_league_table AS
SELECT
    dt.team_key,
    dt.team_name,
    dt.country_name                     AS team_country,
    ds.season_key,
    ds.season_name,
    ds.competition_name,
    ds.country_name                     AS competition_country,
    dd.full_date                        AS snapshot_date,
    dd.year,
    dd.month,
    fls.matchday,
    fls.league_position,
    fls.points,
    fls.games_played,
    fls.games_won,
    fls.games_drawn,
    fls.games_lost,
    fls.goals_for,
    fls.goals_against,
    fls.goal_difference,
    fls.form_last_5,
    -- Derived
    CASE WHEN fls.games_played > 0
         THEN ROUND(fls.points::NUMERIC / fls.games_played, 2)
         ELSE 0 END                     AS points_per_game,
    CASE WHEN fls.games_played > 0
         THEN ROUND(fls.games_won::NUMERIC / fls.games_played * 100, 1)
         ELSE 0 END                     AS win_pct
FROM  project_dw.fact_league_standing fls
JOIN  project_dw.dim_team             dt  ON fls.team_key   = dt.team_key
JOIN  project_dw.dim_season           ds  ON fls.season_key = ds.season_key
LEFT  JOIN project_dw.dim_date        dd  ON fls.date_key   = dd.date_key;

COMMENT ON VIEW project_reporting.v_league_table IS
    'Periodic league standings with derived KPIs';

-- ─────────────────────────────────────────
-- v_squad_selection
-- Power BI page: Squad / Availability
-- ─────────────────────────────────────────
DROP VIEW IF EXISTS project_reporting.v_squad_selection CASCADE;
CREATE VIEW project_reporting.v_squad_selection AS
SELECT
    dp.player_key,
    dp.player_name,
    dp.nationality,
    dp.primary_position,
    dt.team_name,
    ds.season_name,
    ds.competition_name,
    dm.match_id,
    dm.match_date,
    dm.match_week,
    dm.competition_stage,
    fms.is_starter,
    fms.jersey_number,
    -- Opponent
    CASE
        WHEN fms.team_key = dm.home_team_key THEN aw.team_name
        ELSE ht.team_name
    END                                 AS opponent,
    CASE
        WHEN fms.team_key = dm.home_team_key THEN 'Home'
        ELSE 'Away'
    END                                 AS home_away
FROM  project_dw.fact_matchday_squad fms
JOIN  project_dw.dim_player          dp  ON fms.player_key    = dp.player_key
JOIN  project_dw.dim_team            dt  ON fms.team_key      = dt.team_key
JOIN  project_dw.dim_season          ds  ON fms.season_key    = ds.season_key
JOIN  project_dw.dim_match           dm  ON fms.match_key     = dm.match_key
JOIN  project_dw.dim_team            ht  ON dm.home_team_key  = ht.team_key
JOIN  project_dw.dim_team            aw  ON dm.away_team_key  = aw.team_key;

COMMENT ON VIEW project_reporting.v_squad_selection IS
    'Factless squad selection — who was named in the matchday squad and whether starter';

-- ─────────────────────────────────────────
-- v_top_scorers  (aggregated — season level)
-- ─────────────────────────────────────────
DROP VIEW IF EXISTS project_reporting.v_top_scorers CASCADE;
CREATE VIEW project_reporting.v_top_scorers AS
SELECT
    dp.player_key,
    dp.player_name,
    dp.nationality,
    dp.primary_position,
    dt.team_name,
    ds.season_name,
    ds.competition_name,
    SUM(fpm.goals)              AS total_goals,
    SUM(fpm.assists)            AS total_assists,
    SUM(fpm.goals + fpm.assists) AS goal_contributions,
    SUM(fpm.xg)                 AS total_xg,
    SUM(fpm.shots)              AS total_shots,
    COUNT(*)                    AS matches_played,
    ROUND(SUM(fpm.goals)::NUMERIC / NULLIF(COUNT(*), 0), 2)  AS goals_per_match,
    ROUND(SUM(fpm.xg)   ::NUMERIC / NULLIF(SUM(fpm.shots), 0), 3) AS xg_per_shot
FROM  project_dw.fact_player_match   fpm
JOIN  project_dw.dim_player          dp  ON fpm.player_key = dp.player_key
JOIN  project_dw.dim_team            dt  ON fpm.team_key   = dt.team_key
JOIN  project_dw.dim_season          ds  ON fpm.season_key = ds.season_key
GROUP BY
    dp.player_key, dp.player_name, dp.nationality, dp.primary_position,
    dt.team_name, ds.season_name, ds.competition_name;

COMMENT ON VIEW project_reporting.v_top_scorers IS
    'Season-level goal-scoring summary per player';

-- ─────────────────────────────────────────
-- v_team_season_summary  (aggregated)
-- ─────────────────────────────────────────
DROP VIEW IF EXISTS project_reporting.v_team_season_summary CASCADE;
CREATE VIEW project_reporting.v_team_season_summary AS
SELECT
    dt.team_name,
    ds.season_name,
    ds.competition_name,
    COUNT(DISTINCT fpm.match_key)       AS matches,
    SUM(fpm.goals)                      AS total_goals_scored,
    SUM(fpm.shots)                      AS total_shots,
    SUM(fpm.shots_on_target)            AS shots_on_target,
    SUM(fpm.passes_completed)           AS passes_completed,
    SUM(fpm.passes_attempted)           AS passes_attempted,
    ROUND(SUM(fpm.passes_completed)::NUMERIC /
          NULLIF(SUM(fpm.passes_attempted),0) * 100, 1) AS pass_accuracy_pct,
    SUM(fpm.tackles)                    AS total_tackles,
    SUM(fpm.interceptions)              AS total_interceptions,
    SUM(fpm.yellow_cards)               AS yellow_cards,
    SUM(fpm.red_cards)                  AS red_cards
FROM  project_dw.fact_player_match   fpm
JOIN  project_dw.dim_team            dt  ON fpm.team_key   = dt.team_key
JOIN  project_dw.dim_season          ds  ON fpm.season_key = ds.season_key
GROUP BY dt.team_name, ds.season_name, ds.competition_name;

COMMENT ON VIEW project_reporting.v_team_season_summary IS
    'Team season aggregates for executive dashboard';

SELECT 'Reporting schema DDL complete' AS status;
