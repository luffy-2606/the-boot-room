-- =============================================================================
-- The Boot Room — Data Warehouse
-- Phase 2: Data Quality Validation
-- File: 06_data_quality.sql
-- =============================================================================
-- Runs structured DQ checks across staging and DW schemas and logs results
-- to project_staging.stg_dq_log.
--
-- Check result codes:
--   PASS  — no issues found
--   FAIL  — critical data problem (threshold exceeded)
--   WARN  — advisory problem (non-blocking but noteworthy)
-- =============================================================================

DO $$
DECLARE
    -- Generic reusable variables
    v_total        BIGINT;
    v_failed       BIGINT;
    v_pct          NUMERIC;
    v_detail       TEXT;

    -- Helper: insert one DQ result row
    -- Called inline rather than as a nested function (PL/pgSQL limitation)
BEGIN

    -- Ensure log table is clean for this run
    TRUNCATE TABLE project_staging.stg_dq_log;

    -- =========================================================================
    -- COMPLETENESS CHECKS
    -- =========================================================================

    -- CHECK 1: stg_player — NULL or empty player_name
    SELECT COUNT(*) INTO v_total  FROM project_staging.stg_player;
    SELECT COUNT(*) INTO v_failed FROM project_staging.stg_player
     WHERE player_name IS NULL OR TRIM(player_name) = '';
    v_detail := 'Rows with NULL or empty player_name: ' || v_failed;
    INSERT INTO project_staging.stg_dq_log
        (table_name, check_name, check_result, rows_checked, rows_failed, detail)
    VALUES (
        'stg_player',
        'completeness_player_name',
        CASE WHEN v_failed > 0 THEN 'FAIL' ELSE 'PASS' END,
        v_total, v_failed, v_detail
    );

    -- CHECK 2: stg_match — NULL or empty match_date
    SELECT COUNT(*) INTO v_total  FROM project_staging.stg_match;
    SELECT COUNT(*) INTO v_failed FROM project_staging.stg_match
     WHERE match_date IS NULL OR TRIM(match_date::TEXT) = '';
    v_detail := 'Rows with NULL or empty match_date: ' || v_failed;
    INSERT INTO project_staging.stg_dq_log
        (table_name, check_name, check_result, rows_checked, rows_failed, detail)
    VALUES (
        'stg_match',
        'completeness_match_date',
        CASE WHEN v_failed > 0 THEN 'FAIL' ELSE 'PASS' END,
        v_total, v_failed, v_detail
    );

    -- CHECK 3: stg_match — NULL referee_name (WARN if > 5%)
    SELECT COUNT(*) INTO v_total  FROM project_staging.stg_match;
    SELECT COUNT(*) INTO v_failed FROM project_staging.stg_match
     WHERE referee_name IS NULL;
    v_pct := CASE WHEN v_total = 0 THEN 0
                  ELSE ROUND(v_failed::NUMERIC / v_total * 100, 2) END;
    v_detail := 'Rows with NULL referee_name: ' || v_failed
             || ' (' || v_pct || '% of ' || v_total || ')';
    INSERT INTO project_staging.stg_dq_log
        (table_name, check_name, check_result, rows_checked, rows_failed, detail)
    VALUES (
        'stg_match',
        'completeness_referee_name',
        CASE WHEN v_pct > 5 THEN 'WARN' ELSE 'PASS' END,
        v_total, v_failed, v_detail
    );

    -- CHECK 4: stg_player_match_summary — NULL player_id or match_id
    SELECT COUNT(*) INTO v_total  FROM project_staging.stg_player_match_summary;
    SELECT COUNT(*) INTO v_failed FROM project_staging.stg_player_match_summary
     WHERE player_id IS NULL OR match_id IS NULL;
    v_detail := 'Rows with NULL player_id or match_id: ' || v_failed;
    INSERT INTO project_staging.stg_dq_log
        (table_name, check_name, check_result, rows_checked, rows_failed, detail)
    VALUES (
        'stg_player_match_summary',
        'completeness_player_match_ids',
        CASE WHEN v_failed > 0 THEN 'FAIL' ELSE 'PASS' END,
        v_total, v_failed, v_detail
    );

    -- CHECK 5: dim_player — NULL player_name
    SELECT COUNT(*) INTO v_total  FROM project_dw.dim_player;
    SELECT COUNT(*) INTO v_failed FROM project_dw.dim_player
     WHERE player_name IS NULL;
    v_detail := 'Rows with NULL player_name: ' || v_failed;
    INSERT INTO project_staging.stg_dq_log
        (table_name, check_name, check_result, rows_checked, rows_failed, detail)
    VALUES (
        'dim_player',
        'completeness_player_name',
        CASE WHEN v_failed > 0 THEN 'FAIL' ELSE 'PASS' END,
        v_total, v_failed, v_detail
    );

    -- CHECK 6: dim_match — NULL match_date
    SELECT COUNT(*) INTO v_total  FROM project_dw.dim_match;
    SELECT COUNT(*) INTO v_failed FROM project_dw.dim_match
     WHERE match_date IS NULL;
    v_detail := 'Rows with NULL match_date: ' || v_failed;
    INSERT INTO project_staging.stg_dq_log
        (table_name, check_name, check_result, rows_checked, rows_failed, detail)
    VALUES (
        'dim_match',
        'completeness_match_date',
        CASE WHEN v_failed > 0 THEN 'FAIL' ELSE 'PASS' END,
        v_total, v_failed, v_detail
    );

    -- =========================================================================
    -- ACCURACY CHECKS
    -- =========================================================================

    -- CHECK 7: fact_player_match — goals < 0
    SELECT COUNT(*) INTO v_total  FROM project_dw.fact_player_match;
    SELECT COUNT(*) INTO v_failed FROM project_dw.fact_player_match
     WHERE goals < 0;
    v_detail := 'Rows with negative goals: ' || v_failed;
    INSERT INTO project_staging.stg_dq_log
        (table_name, check_name, check_result, rows_checked, rows_failed, detail)
    VALUES (
        'fact_player_match',
        'accuracy_goals_non_negative',
        CASE WHEN v_failed > 0 THEN 'FAIL' ELSE 'PASS' END,
        v_total, v_failed, v_detail
    );

    -- CHECK 8: fact_player_match — shots_on_target > shots
    SELECT COUNT(*) INTO v_total  FROM project_dw.fact_player_match;
    SELECT COUNT(*) INTO v_failed FROM project_dw.fact_player_match
     WHERE shots_on_target > shots;
    v_detail := 'Rows where shots_on_target > shots: ' || v_failed;
    INSERT INTO project_staging.stg_dq_log
        (table_name, check_name, check_result, rows_checked, rows_failed, detail)
    VALUES (
        'fact_player_match',
        'accuracy_shots_on_target_lte_shots',
        CASE WHEN v_failed > 0 THEN 'FAIL' ELSE 'PASS' END,
        v_total, v_failed, v_detail
    );

    -- CHECK 9: fact_player_match — minutes_played > 120 (WARN)
    SELECT COUNT(*) INTO v_total  FROM project_dw.fact_player_match;
    SELECT COUNT(*) INTO v_failed FROM project_dw.fact_player_match
     WHERE minutes_played > 120;
    v_detail := 'Rows with minutes_played > 120: ' || v_failed;
    INSERT INTO project_staging.stg_dq_log
        (table_name, check_name, check_result, rows_checked, rows_failed, detail)
    VALUES (
        'fact_player_match',
        'accuracy_minutes_played_lte_120',
        CASE WHEN v_failed > 0 THEN 'WARN' ELSE 'PASS' END,
        v_total, v_failed, v_detail
    );

    -- CHECK 10: fact_player_match — xg < 0
    SELECT COUNT(*) INTO v_total  FROM project_dw.fact_player_match;
    SELECT COUNT(*) INTO v_failed FROM project_dw.fact_player_match
     WHERE xg < 0;
    v_detail := 'Rows with negative xG: ' || v_failed;
    INSERT INTO project_staging.stg_dq_log
        (table_name, check_name, check_result, rows_checked, rows_failed, detail)
    VALUES (
        'fact_player_match',
        'accuracy_xg_non_negative',
        CASE WHEN v_failed > 0 THEN 'FAIL' ELSE 'PASS' END,
        v_total, v_failed, v_detail
    );

    -- CHECK 11: dim_match — home_score or away_score < 0
    SELECT COUNT(*) INTO v_total  FROM project_dw.dim_match;
    SELECT COUNT(*) INTO v_failed FROM project_dw.dim_match
     WHERE home_score < 0 OR away_score < 0;
    v_detail := 'Rows with negative home_score or away_score: ' || v_failed;
    INSERT INTO project_staging.stg_dq_log
        (table_name, check_name, check_result, rows_checked, rows_failed, detail)
    VALUES (
        'dim_match',
        'accuracy_scores_non_negative',
        CASE WHEN v_failed > 0 THEN 'FAIL' ELSE 'PASS' END,
        v_total, v_failed, v_detail
    );

    -- CHECK 12: Revenue reconciliation analog — fact goals vs dim_match scoreline
    -- WARN if the number of mismatched matches exceeds 20% of total matches
    -- (StatsBomb event data may not perfectly align with final scorelines)
    DECLARE
        v_total_matches    BIGINT;
        v_mismatch_matches BIGINT;
    BEGIN
        SELECT COUNT(DISTINCT match_key) INTO v_total_matches
          FROM project_dw.fact_player_match;

        SELECT COUNT(*) INTO v_mismatch_matches
          FROM (
            SELECT
                f.match_key,
                SUM(f.goals) AS fact_goals,
                dm.home_score + dm.away_score AS scoreline_total
            FROM project_dw.fact_player_match f
            JOIN project_dw.dim_match dm ON f.match_key = dm.match_key
            GROUP BY f.match_key, dm.home_score, dm.away_score
            HAVING SUM(f.goals) <> dm.home_score + dm.away_score
          ) mismatches;

        v_pct := CASE WHEN v_total_matches = 0 THEN 0
                      ELSE ROUND(v_mismatch_matches::NUMERIC / v_total_matches * 100, 2) END;
        v_detail := 'Matches where fact goals ≠ home+away score: '
                 || v_mismatch_matches || ' of ' || v_total_matches
                 || ' (' || v_pct || '%). StatsBomb event coverage may be incomplete.';
        INSERT INTO project_staging.stg_dq_log
            (table_name, check_name, check_result, rows_checked, rows_failed, detail)
        VALUES (
            'fact_player_match / dim_match',
            'accuracy_goals_vs_scoreline_reconciliation',
            CASE WHEN v_pct > 20 THEN 'WARN' ELSE 'PASS' END,
            v_total_matches, v_mismatch_matches, v_detail
        );
    END;

    -- =========================================================================
    -- INTEGRITY CHECKS
    -- =========================================================================

    -- CHECK 13: fact_player_match — orphaned player_key (not in dim_player)
    SELECT COUNT(*) INTO v_total  FROM project_dw.fact_player_match;
    SELECT COUNT(*) INTO v_failed FROM project_dw.fact_player_match f
     WHERE NOT EXISTS (
         SELECT 1 FROM project_dw.dim_player dp WHERE dp.player_key = f.player_key
     );
    v_detail := 'Fact rows with player_key not in dim_player: ' || v_failed;
    INSERT INTO project_staging.stg_dq_log
        (table_name, check_name, check_result, rows_checked, rows_failed, detail)
    VALUES (
        'fact_player_match',
        'integrity_fk_player_key',
        CASE WHEN v_failed > 0 THEN 'FAIL' ELSE 'PASS' END,
        v_total, v_failed, v_detail
    );

    -- CHECK 14: fact_player_match — orphaned match_key (not in dim_match)
    SELECT COUNT(*) INTO v_total  FROM project_dw.fact_player_match;
    SELECT COUNT(*) INTO v_failed FROM project_dw.fact_player_match f
     WHERE NOT EXISTS (
         SELECT 1 FROM project_dw.dim_match dm WHERE dm.match_key = f.match_key
     );
    v_detail := 'Fact rows with match_key not in dim_match: ' || v_failed;
    INSERT INTO project_staging.stg_dq_log
        (table_name, check_name, check_result, rows_checked, rows_failed, detail)
    VALUES (
        'fact_player_match',
        'integrity_fk_match_key',
        CASE WHEN v_failed > 0 THEN 'FAIL' ELSE 'PASS' END,
        v_total, v_failed, v_detail
    );

    -- CHECK 15: fact_player_match — orphaned team_key (not in dim_team)
    SELECT COUNT(*) INTO v_total  FROM project_dw.fact_player_match;
    SELECT COUNT(*) INTO v_failed FROM project_dw.fact_player_match f
     WHERE NOT EXISTS (
         SELECT 1 FROM project_dw.dim_team dt WHERE dt.team_key = f.team_key
     );
    v_detail := 'Fact rows with team_key not in dim_team: ' || v_failed;
    INSERT INTO project_staging.stg_dq_log
        (table_name, check_name, check_result, rows_checked, rows_failed, detail)
    VALUES (
        'fact_player_match',
        'integrity_fk_team_key',
        CASE WHEN v_failed > 0 THEN 'FAIL' ELSE 'PASS' END,
        v_total, v_failed, v_detail
    );

    -- CHECK 16: fact_matchday_squad — orphaned player_key
    SELECT COUNT(*) INTO v_total  FROM project_dw.fact_matchday_squad;
    SELECT COUNT(*) INTO v_failed FROM project_dw.fact_matchday_squad fms
     WHERE NOT EXISTS (
         SELECT 1 FROM project_dw.dim_player dp WHERE dp.player_key = fms.player_key
     );
    v_detail := 'Squad rows with player_key not in dim_player: ' || v_failed;
    INSERT INTO project_staging.stg_dq_log
        (table_name, check_name, check_result, rows_checked, rows_failed, detail)
    VALUES (
        'fact_matchday_squad',
        'integrity_fk_player_key',
        CASE WHEN v_failed > 0 THEN 'FAIL' ELSE 'PASS' END,
        v_total, v_failed, v_detail
    );

    -- CHECK 17: fact_matchday_squad — orphaned match_key
    SELECT COUNT(*) INTO v_total  FROM project_dw.fact_matchday_squad;
    SELECT COUNT(*) INTO v_failed FROM project_dw.fact_matchday_squad fms
     WHERE NOT EXISTS (
         SELECT 1 FROM project_dw.dim_match dm WHERE dm.match_key = fms.match_key
     );
    v_detail := 'Squad rows with match_key not in dim_match: ' || v_failed;
    INSERT INTO project_staging.stg_dq_log
        (table_name, check_name, check_result, rows_checked, rows_failed, detail)
    VALUES (
        'fact_matchday_squad',
        'integrity_fk_match_key',
        CASE WHEN v_failed > 0 THEN 'FAIL' ELSE 'PASS' END,
        v_total, v_failed, v_detail
    );

    -- CHECK 18: dim_match — orphaned season_key (not in dim_season)
    SELECT COUNT(*) INTO v_total  FROM project_dw.dim_match;
    SELECT COUNT(*) INTO v_failed FROM project_dw.dim_match dm
     WHERE NOT EXISTS (
         SELECT 1 FROM project_dw.dim_season ds WHERE ds.season_key = dm.season_key
     );
    v_detail := 'dim_match rows with season_key not in dim_season: ' || v_failed;
    INSERT INTO project_staging.stg_dq_log
        (table_name, check_name, check_result, rows_checked, rows_failed, detail)
    VALUES (
        'dim_match',
        'integrity_fk_season_key',
        CASE WHEN v_failed > 0 THEN 'FAIL' ELSE 'PASS' END,
        v_total, v_failed, v_detail
    );

    -- CHECK 19: fact_player_match — duplicate (player_key, match_key) combinations
    SELECT COUNT(*) INTO v_total FROM project_dw.fact_player_match;
    SELECT COALESCE(SUM(cnt - 1), 0) INTO v_failed
      FROM (
        SELECT player_key, match_key, COUNT(*) AS cnt
          FROM project_dw.fact_player_match
         GROUP BY player_key, match_key
        HAVING COUNT(*) > 1
      ) dups;
    v_detail := 'Duplicate (player_key, match_key) extra rows in fact_player_match: ' || v_failed;
    INSERT INTO project_staging.stg_dq_log
        (table_name, check_name, check_result, rows_checked, rows_failed, detail)
    VALUES (
        'fact_player_match',
        'integrity_duplicate_player_match_key',
        CASE WHEN v_failed > 0 THEN 'FAIL' ELSE 'PASS' END,
        v_total, v_failed, v_detail
    );

    -- CHECK 20: stg_player — duplicate player_id (WARN)
    SELECT COUNT(*) INTO v_total FROM project_staging.stg_player;
    SELECT COALESCE(SUM(cnt - 1), 0) INTO v_failed
      FROM (
        SELECT player_id, COUNT(*) AS cnt
          FROM project_staging.stg_player
         GROUP BY player_id
        HAVING COUNT(*) > 1
      ) dups;
    v_detail := 'Duplicate player_id extra rows in stg_player: ' || v_failed;
    INSERT INTO project_staging.stg_dq_log
        (table_name, check_name, check_result, rows_checked, rows_failed, detail)
    VALUES (
        'stg_player',
        'integrity_duplicate_player_id',
        CASE WHEN v_failed > 0 THEN 'WARN' ELSE 'PASS' END,
        v_total, v_failed, v_detail
    );

    RAISE NOTICE 'Data quality checks complete. See project_staging.stg_dq_log for results.';

END $$;

-- =============================================================================
-- SUMMARY REPORTS
-- =============================================================================

-- Overall summary: check counts and failed rows by result code
SELECT
    check_result,
    COUNT(*)              AS checks,
    SUM(rows_failed)      AS total_failed_rows
FROM project_staging.stg_dq_log
GROUP BY check_result
ORDER BY check_result;

-- Detail report: FAILs and WARNs only
SELECT
    table_name,
    check_name,
    check_result,
    rows_failed,
    detail
FROM project_staging.stg_dq_log
WHERE check_result IN ('FAIL', 'WARN')
ORDER BY check_result, table_name;
