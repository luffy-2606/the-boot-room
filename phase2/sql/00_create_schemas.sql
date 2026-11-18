-- ============================================================
-- The Boot Room — Data Warehouse
-- Script 00: Create Database Schemas
-- ============================================================
-- Run this first before any other script.
-- Creates three schemas: staging → DW → reporting.
-- ============================================================

-- Drop schemas (cascade) if re-running from scratch
-- (comment out if you want to preserve existing data)
DROP SCHEMA IF EXISTS project_staging   CASCADE;
DROP SCHEMA IF EXISTS project_dw        CASCADE;
DROP SCHEMA IF EXISTS project_reporting CASCADE;

-- Create schemas
CREATE SCHEMA project_staging;
CREATE SCHEMA project_dw;
CREATE SCHEMA project_reporting;

-- Grant usage to current user (adjust role name as needed)
GRANT USAGE ON SCHEMA project_staging   TO PUBLIC;
GRANT USAGE ON SCHEMA project_dw        TO PUBLIC;
GRANT USAGE ON SCHEMA project_reporting TO PUBLIC;

COMMENT ON SCHEMA project_staging   IS 'Raw / lightly cleaned source data before transformation';
COMMENT ON SCHEMA project_dw        IS 'Conformed star-schema dimensions and fact tables';
COMMENT ON SCHEMA project_reporting IS 'Flattened views and aggregations for BI consumption';

SELECT 'Schemas created: project_staging, project_dw, project_reporting' AS status;
