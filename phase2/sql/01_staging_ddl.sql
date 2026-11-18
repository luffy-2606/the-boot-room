-- ============================================================
-- The Boot Room — Data Warehouse
-- Script 01: Staging Schema DDL
-- Schema: project_staging
-- ============================================================
-- Staging tables mirror source JSON structure (flattened).
-- All columns are VARCHAR / TEXT so we accept any dirty value;
-- type coercion and cleansing happen in the DW load scripts.
-- ============================================================

SET search_path TO project_staging;

-- ─────────────────────────────────────────
-- stg_competition
-- ─────────────────────────────────────────
DROP TABLE IF EXISTS project_staging.stg_competition CASCADE;
CREATE TABLE project_staging.stg_competition (
    competition_id      VARCHAR(20),
    competition_name    VARCHAR(200),
    competition_gender  VARCHAR(20),
    competition_youth   VARCHAR(10),
    competition_international VARCHAR(10),
    country_name        VARCHAR(100),
    _loaded_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    _source_file        VARCHAR(300)
);

-- ─────────────────────────────────────────
-- stg_season
-- ─────────────────────────────────────────
DROP TABLE IF EXISTS project_staging.stg_season CASCADE;
CREATE TABLE project_staging.stg_season (
    season_id           VARCHAR(20),
    season_name         VARCHAR(50),
    competition_id      VARCHAR(20),
    competition_name    VARCHAR(200),
    country_name        VARCHAR(100),
    _loaded_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    _source_file        VARCHAR(300)
);

-- ─────────────────────────────────────────
-- stg_match
-- ─────────────────────────────────────────
DROP TABLE IF EXISTS project_staging.stg_match CASCADE;
CREATE TABLE project_staging.stg_match (
    match_id            VARCHAR(20),
    match_date          VARCHAR(30),    -- raw string; cast later
    kick_off            VARCHAR(20),
    match_week          VARCHAR(10),
    competition_stage   VARCHAR(100),
    stadium_name        VARCHAR(200),
    city                VARCHAR(100),
    country_name        VARCHAR(100),
    referee_name        VARCHAR(150),
    competition_id      VARCHAR(20),
    season_id           VARCHAR(20),
    home_team_id        VARCHAR(20),
    home_team_name      VARCHAR(200),
    home_team_short     VARCHAR(100),
    away_team_id        VARCHAR(20),
    away_team_name      VARCHAR(200),
    away_team_short     VARCHAR(100),
    home_score          VARCHAR(10),
    away_score          VARCHAR(10),
    _loaded_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    _source_file        VARCHAR(300)
);

-- ─────────────────────────────────────────
-- stg_team
-- ─────────────────────────────────────────
DROP TABLE IF EXISTS project_staging.stg_team CASCADE;
CREATE TABLE project_staging.stg_team (
    team_id             VARCHAR(20),
    team_name           VARCHAR(200),
    team_short_name     VARCHAR(100),
    country_name        VARCHAR(100),
    _loaded_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    _source_file        VARCHAR(300)
);

-- ─────────────────────────────────────────
-- stg_player
-- ─────────────────────────────────────────
DROP TABLE IF EXISTS project_staging.stg_player CASCADE;
CREATE TABLE project_staging.stg_player (
    player_id           VARCHAR(20),
    player_name         VARCHAR(200),
    player_nickname     VARCHAR(200),
    jersey_number       VARCHAR(10),
    position            VARCHAR(50),
    nationality         VARCHAR(100)
    team_id             VARCHAR(20),
    match_id            VARCHAR(20),
    _loaded_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    _source_file        VARCHAR(300)
);

-- ─────────────────────────────────────────
-- stg_lineup_entry  (one row = one player in a match)
-- ─────────────────────────────────────────
DROP TABLE IF EXISTS project_staging.stg_lineup_entry CASCADE;
CREATE TABLE project_staging.stg_lineup_entry (
    match_id            VARCHAR(20),
    team_id             VARCHAR(20),
    player_id           VARCHAR(20),
    player_name         VARCHAR(200),
    jersey_number       VARCHAR(10),
    position            VARCHAR(50),
    is_starter          VARCHAR(10),    -- 'true'/'false'
    _loaded_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    _source_file        VARCHAR(300)
);

-- ─────────────────────────────────────────
-- stg_event  (one row = one on-ball event from match JSON)
-- ─────────────────────────────────────────
DROP TABLE IF EXISTS project_staging.stg_event CASCADE;
CREATE TABLE project_staging.stg_event (
    event_id            VARCHAR(50),
    match_id            VARCHAR(20),
    team_id             VARCHAR(20),
    player_id           VARCHAR(20),
    index_in_match      VARCHAR(10),
    period              VARCHAR(10),
    timestamp           VARCHAR(30),
    minute              VARCHAR(10),
    second              VARCHAR(10),
    type_id             VARCHAR(20),
    type_name           VARCHAR(100),
    outcome_id          VARCHAR(20),
    outcome_name        VARCHAR(100),
    under_pressure      VARCHAR(10),
    off_camera          VARCHAR(10),
    -- shot-specific
    shot_xg             VARCHAR(20),
    -- pass-specific
    pass_outcome        VARCHAR(100),
    -- carry / dribble
    carry_end_location  VARCHAR(100),
    _loaded_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    _source_file        VARCHAR(300)
);

-- ─────────────────────────────────────────
-- stg_player_match_summary  (one row = one player per match)
-- ─────────────────────────────────────────
DROP TABLE IF EXISTS project_staging.stg_player_match_summary CASCADE;
CREATE TABLE project_staging.stg_player_match_summary (
    match_id            VARCHAR(20),
    team_id             VARCHAR(20),
    player_id           VARCHAR(20),
    player_name         VARCHAR(200),
    position_played     VARCHAR(50),
    minutes_played      VARCHAR(10),
    goals               VARCHAR(10),
    assists             VARCHAR(10),
    shots               VARCHAR(10),
    shots_on_target     VARCHAR(10),
    key_passes          VARCHAR(10),
    passes_completed    VARCHAR(10),
    passes_attempted    VARCHAR(10),
    xg                  VARCHAR(20),
    tackles             VARCHAR(10),
    interceptions       VARCHAR(10),
    yellow_cards        VARCHAR(10),
    red_cards           VARCHAR(10),
    fouls_committed     VARCHAR(10),
    fouls_won           VARCHAR(10),
    _loaded_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ─────────────────────────────────────────
-- Data-quality log (for all staging tables)
-- ─────────────────────────────────────────
DROP TABLE IF EXISTS project_staging.stg_dq_log CASCADE;
CREATE TABLE project_staging.stg_dq_log (
    log_id          SERIAL PRIMARY KEY,
    table_name      VARCHAR(100),
    check_name      VARCHAR(200),
    check_result    VARCHAR(20),   -- PASS / FAIL / WARN
    rows_checked    INTEGER,
    rows_failed     INTEGER,
    detail          TEXT,
    checked_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ─────────────────────────────────────────
-- Indexes (staging — keep light; full scan OK at load time)
-- ─────────────────────────────────────────
CREATE INDEX idx_stg_match_id    ON project_staging.stg_match       (match_id);
CREATE INDEX idx_stg_player_id   ON project_staging.stg_player      (player_id);
CREATE INDEX idx_stg_event_mid   ON project_staging.stg_event       (match_id);
CREATE INDEX idx_stg_event_pid   ON project_staging.stg_event       (player_id);
CREATE INDEX idx_stg_lineup_mid  ON project_staging.stg_lineup_entry(match_id);

SELECT 'Staging schema DDL complete' AS status;
