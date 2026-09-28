-- Northloom: list the real schema of the raw tables (step 3)
-- Export the result (or paste it back to Claude) to write docs/schema.md.

SELECT
  table_name,
  ordinal_position,
  column_name,
  data_type,
  is_nullable
FROM `northloom_raw.INFORMATION_SCHEMA.COLUMNS`
ORDER BY table_name, ordinal_position;
