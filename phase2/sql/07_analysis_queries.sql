-- ============================================================
-- The Boot Room — Data Warehouse
-- Script 07: Analytical Business Queries (Verification & Reporting)
-- Schema: project_reporting
-- ============================================================
-- These queries answer key business questions across player
-- performance, team analytics, discipline, and league trends.
-- ============================================================

SET search_path TO project_reporting, project_dw;

-- ────────────────────────────────────────────────────────────
-- BQ-01: Top 10 Goal Scorers Across All Competitions
-- Identifies the most prolific goal scorers, factoring in assists
-- and per-match scoring efficiency.
-- ────────────────────────────────────────────────────────────
SELECT 
    player_name,
    team_name,
    competition_name,
    season_name,
    matches_played,
    total_goals,
    total_assists,
    goal_contributions,
    goals_per_match,
    total_xg,
    xg_per_shot
FROM project_reporting.v_top_scorers
ORDER BY total_goals DESC, goal_contributions DESC
LIMIT 10;

-- ────────────────────────────────────────────────────────────
-- BQ-02: Team Pass Accuracy & Ball Possession Dominance Ranking
-- Ranks teams by ball distribution efficiency (pass accuracy %)
-- and total volume of completed passes per season.
-- ────────────────────────────────────────────────────────────
SELECT 
    team_name,
    competition_name,
    season_name,
    matches,
    passes_completed,
    passes_attempted,
    pass_accuracy_pct,
    total_shots,
    total_goals_scored
FROM project_reporting.v_team_season_summary
WHERE passes_attempted > 0
ORDER BY pass_accuracy_pct DESC, passes_completed DESC;

-- ────────────────────────────────────────────────────────────
-- BQ-03: Expected Goals (xG) vs Actual Goals Over/Under-Performers
-- Highlights clinical finishers (goals > xG) and underperforming
-- finishers (goals < xG) with a minimum threshold of 10 shots.
-- ────────────────────────────────────────────────────────────
SELECT 
    player_name,
    team_name,
    competition_name,
    SUM(shots) AS total_shots,
    SUM(goals) AS total_goals,
    ROUND(SUM(xg)::NUMERIC, 2) AS total_xg,
    ROUND((SUM(goals) - SUM(xg))::NUMERIC, 2) AS xg_differential,
    CASE 
        WHEN SUM(goals) > SUM(xg) THEN 'Overperforming (Clinical)'
        WHEN SUM(goals) < SUM(xg) THEN 'Underperforming (Wasteful)'
        ELSE 'Neutral'
    END AS finishing_profile
FROM project_reporting.v_player_match_stats
GROUP BY player_name, team_name, competition_name
HAVING SUM(shots) >= 10
ORDER BY xg_differential DESC;

-- ────────────────────────────────────────────────────────────
-- BQ-04: Fair Play & Discipline Index (Fewest Cards & Fouls per Match)
-- Ranks teams by sportsmanship and defensive discipline.
-- ────────────────────────────────────────────────────────────
SELECT 
    team_name,
    competition_name,
    season_name,
    matches,
    yellow_cards,
    red_cards,
    (yellow_cards + (red_cards * 3)) AS disciplinary_points,
    ROUND(((yellow_cards + (red_cards * 3))::NUMERIC / NULLIF(matches, 0)), 2) AS card_index_per_match,
    total_tackles,
    total_interceptions
FROM project_reporting.v_team_season_summary
ORDER BY card_index_per_match ASC, red_cards ASC;

-- ────────────────────────────────────────────────────────────
-- BQ-05: Monthly Scoring & Offensive Trends Across the Calendar
-- Aggregates matches and goal counts by year and month to uncover
-- seasonal scoring rhythms.
-- ────────────────────────────────────────────────────────────
SELECT 
    year,
    month,
    month_name,
    COUNT(DISTINCT match_key) AS matches_played,
    SUM(goals) AS total_goals,
    ROUND(SUM(goals)::NUMERIC / NULLIF(COUNT(DISTINCT match_key), 0), 2) AS goals_per_game,
    SUM(shots) AS total_shots,
    ROUND(SUM(shots_on_target)::NUMERIC / NULLIF(SUM(shots), 0) * 100, 1) AS shot_accuracy_pct
FROM project_reporting.v_player_match_stats
WHERE year IS NOT NULL
GROUP BY year, month, month_name
ORDER BY year, month;

-- ────────────────────────────────────────────────────────────
-- BQ-06: Home vs Away Performance Disparity
-- Evaluates home field advantage by analyzing win rates, points,
-- and goal difference at home vs on the road.
-- ────────────────────────────────────────────────────────────
SELECT 
    dm.competition_stage,
    COUNT(dm.match_key) AS total_matches,
    ROUND(COUNT(CASE WHEN dm.result = 'HOME' THEN 1 END)::NUMERIC / COUNT(dm.match_key) * 100, 1) AS home_win_pct,
    ROUND(COUNT(CASE WHEN dm.result = 'AWAY' THEN 1 END)::NUMERIC / COUNT(dm.match_key) * 100, 1) AS away_win_pct,
    ROUND(COUNT(CASE WHEN dm.result = 'DRAW' THEN 1 END)::NUMERIC / COUNT(dm.match_key) * 100, 1) AS draw_pct,
    SUM(dm.home_score) AS total_home_goals,
    SUM(dm.away_score) AS total_away_goals
FROM project_dw.dim_match dm
GROUP BY dm.competition_stage
ORDER BY total_matches DESC;

-- ────────────────────────────────────────────────────────────
-- BQ-07: Elite Playmakers & Passing Masters (Volume + Accuracy)
-- Filters midfielders and defenders with high passing volume
-- and high pass completion percentages.
-- ────────────────────────────────────────────────────────────
SELECT 
    player_name,
    team_name,
    nationality,
    primary_position,
    SUM(passes_completed) AS total_completed_passes,
    SUM(passes_attempted) AS total_attempted_passes,
    ROUND(SUM(passes_completed)::NUMERIC / NULLIF(SUM(passes_attempted), 0) * 100, 2) AS overall_pass_pct,
    SUM(key_passes) AS total_key_passes,
    SUM(assists) AS total_assists
FROM project_reporting.v_player_match_stats
GROUP BY player_name, team_name, nationality, primary_position
HAVING SUM(passes_attempted) >= 50
ORDER BY overall_pass_pct DESC, total_completed_passes DESC
LIMIT 15;

-- ────────────────────────────────────────────────────────────
-- BQ-08: League Standing Progression & Form Trajectory
-- Tracks league positions and form across recent matchdays
-- for top clubs in a competition season.
-- ────────────────────────────────────────────────────────────
SELECT 
    team_name,
    season_name,
    matchday,
    league_position,
    points,
    games_played,
    games_won,
    goal_difference,
    form_last_5,
    points_per_game
FROM project_reporting.v_league_table
WHERE matchday IN (5, 10, 15, 20, 25, 30, 35, 38)
ORDER BY season_name, matchday, league_position;
