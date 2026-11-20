-- ============================================================
-- The Boot Room — Data Warehouse
-- Script 02: DW Schema DDL (Star Schema)
-- Schema: project_dw
-- ============================================================
-- Six conformed dimensions + three fact tables.
-- All surrogate keys are SERIAL (auto-increment) integers
-- generated during dimension load; natural/business keys
-- are retained as separate columns for traceability.
-- ============================================================

SET search_path TO project_dw;

-- ═══════════════════════════════════════════════════════════
--  DIMENSION TABLES
-- ═══════════════════════════════════════════════════════════

-- ─────────────────────────────────────────
-- dim_date  (date spine — built by Python generator)
-- ─────────────────────────────────────────
DROP TABLE IF EXISTS project_dw.dim_date CASCADE;
CREATE TABLE project_dw.dim_date (
    date_key        INTEGER         PRIMARY KEY,   -- YYYYMMDD integer
    full_date       DATE            NOT NULL UNIQUE,
    year            SMALLINT        NOT NULL,
    quarter         SMALLINT        NOT NULL CHECK (quarter BETWEEN 1 AND 4),
    month           SMALLINT        NOT NULL CHECK (month   BETWEEN 1 AND 12),
    month_name      VARCHAR(15)     NOT NULL,
    day_of_month    SMALLINT        NOT NULL,
    day_of_week     SMALLINT        NOT NULL CHECK (day_of_week BETWEEN 1 AND 7), -- 1=Mon
    day_name        VARCHAR(15)     NOT NULL,
    is_weekend      BOOLEAN         NOT NULL,
    week_of_year    SMALLINT        NOT NULL,
    is_leap_year    BOOLEAN         NOT NULL
);

COMMENT ON TABLE  project_dw.dim_date IS 'Date dimension — one row per calendar day';
COMMENT ON COLUMN project_dw.dim_date.date_key IS 'Surrogate key: YYYYMMDD integer (e.g. 20240301)';

-- ─────────────────────────────────────────
-- dim_season
-- ─────────────────────────────────────────
DROP TABLE IF EXISTS project_dw.dim_season CASCADE;
CREATE TABLE project_dw.dim_season (
    season_key          SERIAL          PRIMARY KEY,
    season_id           INTEGER         NOT NULL,  -- business key (unique per competition)
    season_name         VARCHAR(50)     NOT NULL,
    competition_id      INTEGER         NOT NULL,
    competition_name    VARCHAR(200)    NOT NULL,
    country_name        VARCHAR(100)    NOT NULL,
    competition_gender  VARCHAR(20)     NOT NULL DEFAULT 'male',
    is_youth            BOOLEAN         NOT NULL DEFAULT FALSE,
    is_international    BOOLEAN         NOT NULL DEFAULT FALSE,
    _inserted_at        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _updated_at         TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_season_competition UNIQUE (competition_id, season_id)
);

COMMENT ON TABLE  project_dw.dim_season IS 'Competition-season dimension';
COMMENT ON COLUMN project_dw.dim_season.season_key IS 'Surrogate key (auto-generated)';
COMMENT ON COLUMN project_dw.dim_season.season_id  IS 'Natural key from StatsBomb source';

-- ─────────────────────────────────────────
-- dim_team
-- ─────────────────────────────────────────
DROP TABLE IF EXISTS project_dw.dim_team CASCADE;
CREATE TABLE project_dw.dim_team (
    team_key            SERIAL          PRIMARY KEY,
    team_id             INTEGER         NOT NULL UNIQUE,  -- business key
    team_name           VARCHAR(200)    NOT NULL,
    team_short_name     VARCHAR(100),
    country_name        VARCHAR(100),
    _inserted_at        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _updated_at         TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE  project_dw.dim_team IS 'Football club / national team dimension';
COMMENT ON COLUMN project_dw.dim_team.team_key IS 'Surrogate key (auto-generated)';
COMMENT ON COLUMN project_dw.dim_team.team_id  IS 'Natural key from StatsBomb source';

-- ─────────────────────────────────────────
-- dim_player
-- ─────────────────────────────────────────
DROP TABLE IF EXISTS project_dw.dim_player CASCADE;
CREATE TABLE project_dw.dim_player (
    player_key          SERIAL          PRIMARY KEY,
    player_id           INTEGER         NOT NULL UNIQUE,  -- business key
    player_name         VARCHAR(200)    NOT NULL,
    player_nickname     VARCHAR(200),
    nationality         VARCHAR(100),
    primary_position    VARCHAR(50),
    _inserted_at        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    _updated_at         TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE  project_dw.dim_player IS 'Player master dimension';
COMMENT ON COLUMN project_dw.dim_player.player_key IS 'Surrogate key (auto-generated)';
COMMENT ON COLUMN project_dw.dim_player.player_id  IS 'Natural key from StatsBomb source';

-- ─────────────────────────────────────────
-- dim_venue
-- ─────────────────────────────────────────
DROP TABLE IF EXISTS project_dw.dim_venue CASCADE;
CREATE TABLE project_dw.dim_venue (
    venue_key           SERIAL          PRIMARY KEY,
    stadium_name        VARCHAR(200)    NOT NULL UNIQUE,
    city                VARCHAR(100),
    country_name        VARCHAR(100),
    _inserted_at        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE project_dw.dim_venue IS 'Stadium / venue dimension';
COMMENT ON COLUMN project_dw.dim_venue.venue_key IS 'Surrogate key (auto-generated)';

-- ─────────────────────────────────────────
-- dim_match  (role-playing via home/away team keys)
-- ─────────────────────────────────────────
DROP TABLE IF EXISTS project_dw.dim_match CASCADE;
CREATE TABLE project_dw.dim_match (
    match_key           SERIAL          PRIMARY KEY,
    match_id            INTEGER         NOT NULL UNIQUE,  -- business key
    match_date          DATE            NOT NULL,
    kick_off            TIME,
    match_week          SMALLINT,
    competition_stage   VARCHAR(100),
    home_score          SMALLINT,
    away_score          SMALLINT,
    result              VARCHAR(10)     -- HOME / AWAY / DRAW
        GENERATED ALWAYS AS (
            CASE
                WHEN home_score > away_score THEN 'HOME'
                WHEN away_score > home_score THEN 'AWAY'
                ELSE 'DRAW'
            END
        ) STORED,
    referee             VARCHAR(150),
    -- FK to other dims
    season_key          INTEGER         NOT NULL REFERENCES project_dw.dim_season(season_key),
    home_team_key       INTEGER         NOT NULL REFERENCES project_dw.dim_team  (team_key),
    away_team_key       INTEGER         NOT NULL REFERENCES project_dw.dim_team  (team_key),
    venue_key           INTEGER                  REFERENCES project_dw.dim_venue (venue_key),
    date_key            INTEGER                  REFERENCES project_dw.dim_date  (date_key),
    _inserted_at        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE  project_dw.dim_match IS 'Match dimension — degenerate fact / mini-dimension';
COMMENT ON COLUMN project_dw.dim_match.match_key IS 'Surrogate key (auto-generated)';
COMMENT ON COLUMN project_dw.dim_match.match_id  IS 'Natural key from StatsBomb source';
COMMENT ON COLUMN project_dw.dim_match.result    IS 'Computed: HOME | AWAY | DRAW';

-- ═══════════════════════════════════════════════════════════
--  FACT TABLES
-- ═══════════════════════════════════════════════════════════

-- ─────────────────────────────────────────
-- fact_player_match  (Transactional — grain: one player per match)
-- ─────────────────────────────────────────
DROP TABLE IF EXISTS project_dw.fact_player_match CASCADE;
CREATE TABLE project_dw.fact_player_match (
    -- Composite PK (no surrogate needed)
    player_key              INTEGER     NOT NULL REFERENCES project_dw.dim_player(player_key),
    match_key               INTEGER     NOT NULL REFERENCES project_dw.dim_match (match_key),
    -- Conformed dimensions
    team_key                INTEGER     NOT NULL REFERENCES project_dw.dim_team  (team_key),
    season_key              INTEGER     NOT NULL REFERENCES project_dw.dim_season(season_key),
    date_key                INTEGER              REFERENCES project_dw.dim_date  (date_key),
    -- Attributes
    position_played         VARCHAR(50),
    -- Additive measures
    minutes_played          SMALLINT    NOT NULL DEFAULT 0,
    goals                   SMALLINT    NOT NULL DEFAULT 0,
    assists                 SMALLINT    NOT NULL DEFAULT 0,
    shots                   SMALLINT    NOT NULL DEFAULT 0,
    shots_on_target         SMALLINT    NOT NULL DEFAULT 0,
    key_passes              SMALLINT    NOT NULL DEFAULT 0,
    passes_completed        SMALLINT    NOT NULL DEFAULT 0,
    passes_attempted        SMALLINT    NOT NULL DEFAULT 0,
    -- Semi-additive / derived
    xg                      NUMERIC(6,3)         DEFAULT 0,
    pass_completion_pct     NUMERIC(5,2)
        GENERATED ALWAYS AS (
            CASE WHEN passes_attempted > 0
                 THEN ROUND(passes_completed::NUMERIC / passes_attempted * 100, 2)
                 ELSE NULL END
        ) STORED,
    -- Defensive
    tackles                 SMALLINT    NOT NULL DEFAULT 0,
    interceptions           SMALLINT    NOT NULL DEFAULT 0,
    -- Disciplinary
    yellow_cards            SMALLINT    NOT NULL DEFAULT 0,
    red_cards               SMALLINT    NOT NULL DEFAULT 0,
    fouls_committed         SMALLINT    NOT NULL DEFAULT 0,
    fouls_won               SMALLINT    NOT NULL DEFAULT 0,
    -- Audit
    _inserted_at            TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (player_key, match_key)
);

COMMENT ON TABLE project_dw.fact_player_match IS
    'Transactional fact — one row per player per match. Grain: (player_key, match_key).';

-- ─────────────────────────────────────────
-- fact_league_standing  (Periodic Snapshot — grain: team × matchday)
-- ─────────────────────────────────────────
DROP TABLE IF EXISTS project_dw.fact_league_standing CASCADE;
CREATE TABLE project_dw.fact_league_standing (
    team_key            INTEGER     NOT NULL REFERENCES project_dw.dim_team  (team_key),
    season_key          INTEGER     NOT NULL REFERENCES project_dw.dim_season(season_key),
    date_key            INTEGER              REFERENCES project_dw.dim_date  (date_key),
    matchday            SMALLINT    NOT NULL,
    -- Snapshot measures
    league_position     SMALLINT    NOT NULL,
    points              SMALLINT    NOT NULL DEFAULT 0,
    games_played        SMALLINT    NOT NULL DEFAULT 0,
    games_won           SMALLINT    NOT NULL DEFAULT 0,
    games_drawn         SMALLINT    NOT NULL DEFAULT 0,
    games_lost          SMALLINT    NOT NULL DEFAULT 0,
    goals_for           SMALLINT    NOT NULL DEFAULT 0,
    goals_against       SMALLINT    NOT NULL DEFAULT 0,
    goal_difference     SMALLINT
        GENERATED ALWAYS AS (goals_for - goals_against) STORED,
    -- Semi-additive
    form_last_5         VARCHAR(10),   -- e.g. 'W W D L W'
    _inserted_at        TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (team_key, season_key, matchday)
);

COMMENT ON TABLE project_dw.fact_league_standing IS
    'Periodic snapshot — league table after each matchday. Grain: (team_key, season_key, matchday).';

-- ─────────────────────────────────────────
-- fact_matchday_squad  (Factless — grain: player × match)
-- ─────────────────────────────────────────
DROP TABLE IF EXISTS project_dw.fact_matchday_squad CASCADE;
CREATE TABLE project_dw.fact_matchday_squad (
    player_key          INTEGER     NOT NULL REFERENCES project_dw.dim_player(player_key),
    match_key           INTEGER     NOT NULL REFERENCES project_dw.dim_match (match_key),
    team_key            INTEGER     NOT NULL REFERENCES project_dw.dim_team  (team_key),
    season_key          INTEGER     NOT NULL REFERENCES project_dw.dim_season(season_key),
    date_key            INTEGER              REFERENCES project_dw.dim_date  (date_key),
    is_starter          BOOLEAN     NOT NULL DEFAULT FALSE,
    jersey_number       SMALLINT,
    _inserted_at        TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (player_key, match_key)
);

COMMENT ON TABLE project_dw.fact_matchday_squad IS
    'Factless fact — squad availability per match. Grain: (player_key, match_key).';

-- ═══════════════════════════════════════════════════════════
--  INDEXES
-- ═══════════════════════════════════════════════════════════

-- dim_date
CREATE INDEX idx_dim_date_year_month  ON project_dw.dim_date (year, month);

-- dim_season
CREATE INDEX idx_dim_season_comp      ON project_dw.dim_season (competition_id);

-- dim_match
CREATE INDEX idx_dim_match_date       ON project_dw.dim_match (match_date);
CREATE INDEX idx_dim_match_season     ON project_dw.dim_match (season_key);
CREATE INDEX idx_dim_match_home       ON project_dw.dim_match (home_team_key);
CREATE INDEX idx_dim_match_away       ON project_dw.dim_match (away_team_key);

-- fact_player_match
CREATE INDEX idx_fpm_player           ON project_dw.fact_player_match (player_key);
CREATE INDEX idx_fpm_match            ON project_dw.fact_player_match (match_key);
CREATE INDEX idx_fpm_team             ON project_dw.fact_player_match (team_key);
CREATE INDEX idx_fpm_season           ON project_dw.fact_player_match (season_key);
CREATE INDEX idx_fpm_date             ON project_dw.fact_player_match (date_key);

-- fact_league_standing
CREATE INDEX idx_fls_team             ON project_dw.fact_league_standing (team_key);
CREATE INDEX idx_fls_season           ON project_dw.fact_league_standing (season_key);

-- fact_matchday_squad
CREATE INDEX idx_fms_player           ON project_dw.fact_matchday_squad (player_key);
CREATE INDEX idx_fms_match            ON project_dw.fact_matchday_squad (match_key);
CREATE INDEX idx_fms_team             ON project_dw.fact_matchday_squad (team_key);

SELECT 'DW schema DDL complete' AS status;
