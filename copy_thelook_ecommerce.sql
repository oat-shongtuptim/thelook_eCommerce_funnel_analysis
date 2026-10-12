-- Copy theLook eCommerce (all 7 tables) into your own BigQuery dataset.
-- Run in the BigQuery query editor. Unqualified names use the project selected in the editor.

-- STEP 1: Create your own dataset (run once).
-- Location must match the public dataset (US); a mismatch causes a "not found in location" error.
CREATE SCHEMA IF NOT EXISTS thelook_copy
OPTIONS (location = 'US');


-- STEP 2: Check source table sizes BEFORE copying (run this on its own).
-- The sandbox allows 10 GB of storage in total.
SELECT
  table_id,
  row_count,
  ROUND(size_bytes / POW(1024, 3), 3) AS size_gb
FROM `bigquery-public-data.thelook_ecommerce.__TABLES__`
ORDER BY size_bytes DESC;


-- STEP 3: Copy the small lookup tables.
CREATE OR REPLACE TABLE thelook_copy.distribution_centers AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.distribution_centers`;

CREATE OR REPLACE TABLE thelook_copy.products AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.products`;

CREATE OR REPLACE TABLE thelook_copy.users AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.users`;

-- STEP 4: Copy the transaction tables.
CREATE OR REPLACE TABLE thelook_copy.inventory_items AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.inventory_items`;

CREATE OR REPLACE TABLE thelook_copy.orders AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.orders`;

CREATE OR REPLACE TABLE thelook_copy.order_items AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.order_items`;


-- STEP 5: Copy events (usually the largest table).
-- Full copy:
CREATE OR REPLACE TABLE thelook_copy.events AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.events`;

-- Or, if events is too big for the sandbox, copy only a date window instead
-- (replace the statement above with this one):
-- CREATE OR REPLACE TABLE thelook_copy.events AS
-- SELECT * FROM `bigquery-public-data.thelook_ecommerce.events`
-- WHERE created_at >= '2026-04-01' AND created_at < '2026-05-01';
