-- Northloom: the raw schema as one row per table, for copying out of the Console
-- when "Save results" is disabled. Each row lists column:type in column order.

SELECT
  table_name,
  STRING_AGG(CONCAT(column_name, ':', data_type), ', ' ORDER BY ordinal_position) AS columns
FROM `northloom_raw.INFORMATION_SCHEMA.COLUMNS`
GROUP BY table_name
ORDER BY table_name;
