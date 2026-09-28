-- Northloom: remove the 60-day sandbox expiration from every dataset and table
-- Run ONLY after a billing account is linked to the selected project.
-- In sandbox mode this fails with "Billing has not been enabled for this project".
--
-- Loops over whatever tables exist, so it works no matter how far the build has got.

ALTER SCHEMA `northloom_raw`     SET OPTIONS (default_table_expiration_days = NULL);
ALTER SCHEMA `northloom_staging` SET OPTIONS (default_table_expiration_days = NULL);
ALTER SCHEMA `northloom_marts`   SET OPTIONS (default_table_expiration_days = NULL);

FOR record IN (
  SELECT table_schema, table_name
  FROM `region-us.INFORMATION_SCHEMA.TABLES`
  WHERE table_schema IN ('northloom_raw', 'northloom_staging', 'northloom_marts')
    AND table_type = 'BASE TABLE'
)
DO
  EXECUTE IMMEDIATE FORMAT(
    'ALTER TABLE `%s.%s` SET OPTIONS (expiration_timestamp = NULL)',
    record.table_schema, record.table_name);
END FOR;

-- Confirm: expiration_time should be NULL for every row.
SELECT table_schema, table_name, creation_time, expiration_time
FROM `region-us.INFORMATION_SCHEMA.TABLES`
WHERE table_schema IN ('northloom_raw', 'northloom_staging', 'northloom_marts')
ORDER BY table_schema, table_name;
