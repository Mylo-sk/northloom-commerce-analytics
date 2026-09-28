-- Northloom: smoke test the staging views before building the marts
-- Confirms the views run, the row counts make sense, and the money rules behave.
-- Export as CSV.

WITH counts AS (
  SELECT 'row_count' AS section, 'stg_users' AS item, CAST(COUNT(*) AS STRING) AS value
  FROM `northloom_staging.stg_users`
  UNION ALL SELECT 'row_count', 'stg_orders', CAST(COUNT(*) AS STRING)
  FROM `northloom_staging.stg_orders`
  UNION ALL SELECT 'row_count', 'stg_order_items', CAST(COUNT(*) AS STRING)
  FROM `northloom_staging.stg_order_items`
  UNION ALL SELECT 'row_count', 'stg_products', CAST(COUNT(*) AS STRING)
  FROM `northloom_staging.stg_products`
  UNION ALL SELECT 'row_count', 'stg_inventory_items', CAST(COUNT(*) AS STRING)
  FROM `northloom_staging.stg_inventory_items`
  UNION ALL SELECT 'row_count', 'stg_events', CAST(COUNT(*) AS STRING)
  FROM `northloom_staging.stg_events`
),
-- Did the country cleanup work, and does the market ranking now look right?
markets AS (
  SELECT 'top_markets' AS section, market AS item, CAST(COUNT(*) AS STRING) AS value
  FROM `northloom_staging.stg_users`
  GROUP BY market ORDER BY COUNT(*) DESC LIMIT 8
),
regions AS (
  SELECT 'region' AS section, region AS item, CAST(COUNT(*) AS STRING) AS value
  FROM `northloom_staging.stg_users` GROUP BY region
),
-- Both systems should now speak the same channel language.
channels AS (
  SELECT 'signup_channel' AS section, signup_channel AS item, CAST(COUNT(*) AS STRING) AS value
  FROM `northloom_staging.stg_users` GROUP BY signup_channel
  UNION ALL
  SELECT 'event_channel', channel, CAST(COUNT(*) AS STRING)
  FROM `northloom_staging.stg_events` GROUP BY channel
),
-- Any 'Unknown' channel means the mapping missed a value.
mapping_gaps AS (
  SELECT 'mapping_gap' AS section, 'users with Unknown channel' AS item,
         CAST(COUNTIF(signup_channel = 'Unknown') AS STRING) AS value
  FROM `northloom_staging.stg_users`
  UNION ALL SELECT 'mapping_gap', 'events with Unknown channel',
         CAST(COUNTIF(channel = 'Unknown') AS STRING)
  FROM `northloom_staging.stg_events`
  UNION ALL SELECT 'mapping_gap', 'order items with no unit cost',
         CAST(COUNTIF(unit_cost IS NULL) AS STRING)
  FROM `northloom_staging.stg_order_items`
),
-- The headline numbers the CEO would recognise (NL-111).
money AS (
  SELECT 'money (lifetime)' AS section, 'gross revenue' AS item,
         FORMAT('%.0f', SUM(gross_revenue)) AS value
  FROM `northloom_staging.stg_order_items`
  UNION ALL SELECT 'money (lifetime)', 'net revenue', FORMAT('%.0f', SUM(net_revenue))
  FROM `northloom_staging.stg_order_items`
  UNION ALL SELECT 'money (lifetime)', 'gross margin', FORMAT('%.0f', SUM(gross_margin))
  FROM `northloom_staging.stg_order_items`
  UNION ALL SELECT 'money (lifetime)', 'realised margin pct',
         FORMAT('%.1f', 100 * SAFE_DIVIDE(SUM(gross_margin), SUM(net_revenue)))
  FROM `northloom_staging.stg_order_items`
  UNION ALL SELECT 'money (lifetime)', 'revenue lost to cancellations',
         FORMAT('%.0f', SUM(IF(is_cancelled, sale_price, 0)))
  FROM `northloom_staging.stg_order_items`
  UNION ALL SELECT 'money (lifetime)', 'revenue lost to returns',
         FORMAT('%.0f', SUM(IF(is_returned, sale_price, 0)))
  FROM `northloom_staging.stg_order_items`
  UNION ALL SELECT 'money (lifetime)', 'average order value (net)',
         FORMAT('%.2f', SAFE_DIVIDE(SUM(net_revenue), COUNT(DISTINCT IF(is_net_sale, order_id, NULL))))
  FROM `northloom_staging.stg_order_items`
),
-- Fulfillment coverage: how much of the data survives the timestamp problem.
fulfillment AS (
  SELECT 'fulfillment' AS section, 'items with a valid ship timeline' AS item,
         FORMAT('%d of %d (%.1f%%)', COUNTIF(has_valid_ship_timeline), COUNT(*),
                100 * SAFE_DIVIDE(COUNTIF(has_valid_ship_timeline), COUNT(*))) AS value
  FROM `northloom_staging.stg_order_items`
  -- TIMESTAMP_DIFF returns INT64, so these cast rather than format as a decimal.
  UNION ALL SELECT 'fulfillment', 'median hours ship to delivery',
         CAST(APPROX_QUANTILES(hours_ship_to_delivery, 100)[OFFSET(50)] AS STRING)
  FROM `northloom_staging.stg_order_items`
  UNION ALL SELECT 'fulfillment', 'median days delivered to return',
         CAST(APPROX_QUANTILES(days_delivered_to_return, 100)[OFFSET(50)] AS STRING)
  FROM `northloom_staging.stg_order_items`
),
-- Stock on hand as at the analysis date (NL-104).
stock AS (
  SELECT 'inventory' AS section, 'units on hand' AS item,
         CAST(COUNTIF(is_on_hand) AS STRING) AS value
  FROM `northloom_staging.stg_inventory_items`
  UNION ALL SELECT 'inventory', 'units sold',
         CAST(COUNTIF(NOT is_on_hand) AS STRING)
  FROM `northloom_staging.stg_inventory_items`
)
SELECT * FROM counts
UNION ALL SELECT * FROM markets
UNION ALL SELECT * FROM regions
UNION ALL SELECT * FROM channels
UNION ALL SELECT * FROM mapping_gaps
UNION ALL SELECT * FROM money
UNION ALL SELECT * FROM fulfillment
UNION ALL SELECT * FROM stock
ORDER BY section, item;
