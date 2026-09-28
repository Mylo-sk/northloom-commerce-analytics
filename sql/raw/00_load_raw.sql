-- Northloom: create the layer datasets and load the raw tables (one-time copy)
-- Run as a single script in the BigQuery Console. Dataset names are unqualified, so
-- they resolve to whichever project is selected in the Console (northloom-analytics).
-- The source dataset is in the US multi-region, so all datasets are created in US too.

CREATE SCHEMA IF NOT EXISTS `northloom_raw`
  OPTIONS (location = 'US', description = 'Raw tables copied once from bigquery-public-data.thelook_ecommerce. Never edited.');

CREATE SCHEMA IF NOT EXISTS `northloom_staging`
  OPTIONS (location = 'US', description = 'Cleaned, renamed, typed views over raw, with shared metric definitions applied.');

CREATE SCHEMA IF NOT EXISTS `northloom_marts`
  OPTIONS (location = 'US', description = 'Star schema (dimensions and facts) used by analysis and the dashboard.');

-- Raw copies of all 7 source tables
CREATE OR REPLACE TABLE `northloom_raw.users` AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.users`;

CREATE OR REPLACE TABLE `northloom_raw.orders` AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.orders`;

CREATE OR REPLACE TABLE `northloom_raw.order_items` AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.order_items`;

CREATE OR REPLACE TABLE `northloom_raw.products` AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.products`;

CREATE OR REPLACE TABLE `northloom_raw.inventory_items` AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.inventory_items`;

CREATE OR REPLACE TABLE `northloom_raw.distribution_centers` AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.distribution_centers`;

CREATE OR REPLACE TABLE `northloom_raw.events` AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.events`;

-- Confirm the load: row counts and date range per table
SELECT 'users' AS table_name, COUNT(*) AS row_count, MIN(created_at) AS min_created, MAX(created_at) AS max_created FROM `northloom_raw.users`
UNION ALL SELECT 'orders', COUNT(*), MIN(created_at), MAX(created_at) FROM `northloom_raw.orders`
UNION ALL SELECT 'order_items', COUNT(*), MIN(created_at), MAX(created_at) FROM `northloom_raw.order_items`
UNION ALL SELECT 'inventory_items', COUNT(*), MIN(created_at), MAX(created_at) FROM `northloom_raw.inventory_items`
UNION ALL SELECT 'events', COUNT(*), MIN(created_at), MAX(created_at) FROM `northloom_raw.events`
UNION ALL SELECT 'products', COUNT(*), NULL, NULL FROM `northloom_raw.products`
UNION ALL SELECT 'distribution_centers', COUNT(*), NULL, NULL FROM `northloom_raw.distribution_centers`
ORDER BY table_name;
