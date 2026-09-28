-- Northloom: investigate the 35,699 items with shipped_at before created_at
-- Decides how the fulfillment analysis (NL-110) handles them: are they a small
-- rounding problem, or a systematic bug in one status, period or warehouse?
-- Export as CSV.

WITH items AS (
  SELECT
    oi.id,
    oi.status,
    oi.created_at,
    oi.shipped_at,
    oi.delivered_at,
    p.distribution_center_id,
    TIMESTAMP_DIFF(oi.shipped_at, oi.created_at, HOUR) AS ship_lag_hours,
    EXTRACT(YEAR FROM oi.created_at) AS order_year
  FROM `northloom_raw.order_items` oi
  LEFT JOIN `northloom_raw.products` p ON oi.product_id = p.id
  WHERE oi.shipped_at IS NOT NULL
    AND oi.created_at <= TIMESTAMP('2026-09-17 23:59:59')
),
-- How bad is it? A few minutes is a clock problem; days apart is a data bug.
magnitude AS (
  SELECT 'magnitude' AS section,
    CASE
      WHEN ship_lag_hours >= 0 THEN 'valid (shipped after order)'
      WHEN ship_lag_hours >= -1 THEN 'invalid by up to 1 hour'
      WHEN ship_lag_hours >= -24 THEN 'invalid by up to 1 day'
      WHEN ship_lag_hours >= -168 THEN 'invalid by up to 1 week'
      ELSE 'invalid by more than a week'
    END AS item,
    CAST(COUNT(*) AS STRING) AS value
  FROM items GROUP BY item
),
-- Does the problem sit in particular order states?
by_status AS (
  SELECT 'invalid share by status' AS section, status AS item,
    CONCAT(CAST(COUNTIF(ship_lag_hours < 0) AS STRING), ' of ', CAST(COUNT(*) AS STRING),
           ' (', CAST(ROUND(100 * SAFE_DIVIDE(COUNTIF(ship_lag_hours < 0), COUNT(*)), 1) AS STRING), '%)') AS value
  FROM items GROUP BY status
),
-- Is it historical, or still happening now?
by_year AS (
  SELECT 'invalid share by year' AS section, CAST(order_year AS STRING) AS item,
    CONCAT(CAST(COUNTIF(ship_lag_hours < 0) AS STRING), ' of ', CAST(COUNT(*) AS STRING),
           ' (', CAST(ROUND(100 * SAFE_DIVIDE(COUNTIF(ship_lag_hours < 0), COUNT(*)), 1) AS STRING), '%)') AS value
  FROM items GROUP BY order_year
),
-- Is one warehouse's system at fault?
by_dc AS (
  SELECT 'invalid share by distribution center' AS section, COALESCE(dc.name, 'unknown') AS item,
    CONCAT(CAST(COUNTIF(i.ship_lag_hours < 0) AS STRING), ' of ', CAST(COUNT(*) AS STRING),
           ' (', CAST(ROUND(100 * SAFE_DIVIDE(COUNTIF(i.ship_lag_hours < 0), COUNT(*)), 1) AS STRING), '%)') AS value
  FROM items i
  LEFT JOIN `northloom_raw.distribution_centers` dc
    ON i.distribution_center_id = dc.id
  GROUP BY item
),
-- Do the bad rows still have a sane ship-to-delivery leg we could keep?
delivery_leg AS (
  SELECT 'delivery leg on invalid rows' AS section, 'delivered_at after shipped_at' AS item,
    CONCAT(CAST(COUNTIF(delivered_at > shipped_at) AS STRING), ' of ',
           CAST(COUNTIF(delivered_at IS NOT NULL) AS STRING), ' delivered rows') AS value
  FROM items WHERE ship_lag_hours < 0
),
-- Typical lag on the rows that are valid, as the baseline for NL-110
valid_baseline AS (
  SELECT 'baseline on valid rows' AS section, 'median hours order to ship' AS item,
    CAST(ROUND(APPROX_QUANTILES(ship_lag_hours, 100)[OFFSET(50)], 1) AS STRING) AS value
  FROM items WHERE ship_lag_hours >= 0
  UNION ALL
  SELECT 'baseline on valid rows', 'median hours ship to delivery',
    CAST(ROUND(APPROX_QUANTILES(TIMESTAMP_DIFF(delivered_at, shipped_at, HOUR), 100)[OFFSET(50)], 1) AS STRING)
  FROM items WHERE ship_lag_hours >= 0 AND delivered_at IS NOT NULL
)
SELECT * FROM magnitude
UNION ALL SELECT * FROM by_status
UNION ALL SELECT * FROM by_year
UNION ALL SELECT * FROM by_dc
UNION ALL SELECT * FROM delivery_leg
UNION ALL SELECT * FROM valid_baseline
ORDER BY section, item;
