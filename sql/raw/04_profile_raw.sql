-- Northloom: profile the raw data before building staging (step 3b)
-- Returns one tall result: section / item / value. Export as CSV and send it over.
-- Answers: how big is each table, what date range does it cover, what values do the
-- key dimensions actually take, and how bad is the future-dated-row problem.

WITH row_counts AS (
  SELECT 'row_count' AS section, 'users' AS item, CAST(COUNT(*) AS STRING) AS value FROM `northloom_raw.users`
  UNION ALL SELECT 'row_count', 'orders', CAST(COUNT(*) AS STRING) FROM `northloom_raw.orders`
  UNION ALL SELECT 'row_count', 'order_items', CAST(COUNT(*) AS STRING) FROM `northloom_raw.order_items`
  UNION ALL SELECT 'row_count', 'products', CAST(COUNT(*) AS STRING) FROM `northloom_raw.products`
  UNION ALL SELECT 'row_count', 'inventory_items', CAST(COUNT(*) AS STRING) FROM `northloom_raw.inventory_items`
  UNION ALL SELECT 'row_count', 'distribution_centers', CAST(COUNT(*) AS STRING) FROM `northloom_raw.distribution_centers`
  UNION ALL SELECT 'row_count', 'events', CAST(COUNT(*) AS STRING) FROM `northloom_raw.events`
),
date_range AS (
  SELECT 'date_range' AS section, 'users.created_at' AS item,
         CONCAT(CAST(DATE(MIN(created_at)) AS STRING), ' .. ', CAST(DATE(MAX(created_at)) AS STRING)) AS value
  FROM `northloom_raw.users`
  UNION ALL SELECT 'date_range', 'orders.created_at',
         CONCAT(CAST(DATE(MIN(created_at)) AS STRING), ' .. ', CAST(DATE(MAX(created_at)) AS STRING))
  FROM `northloom_raw.orders`
  UNION ALL SELECT 'date_range', 'order_items.created_at',
         CONCAT(CAST(DATE(MIN(created_at)) AS STRING), ' .. ', CAST(DATE(MAX(created_at)) AS STRING))
  FROM `northloom_raw.order_items`
  UNION ALL SELECT 'date_range', 'events.created_at',
         CONCAT(CAST(DATE(MIN(created_at)) AS STRING), ' .. ', CAST(DATE(MAX(created_at)) AS STRING))
  FROM `northloom_raw.events`
  UNION ALL SELECT 'date_range', 'inventory_items.created_at',
         CONCAT(CAST(DATE(MIN(created_at)) AS STRING), ' .. ', CAST(DATE(MAX(created_at)) AS STRING))
  FROM `northloom_raw.inventory_items`
),
-- Future-dated rows: thelook is regenerated on a schedule and seeds rows ahead of today.
-- The analysis cut-off date depends on how many there are.
future_rows AS (
  SELECT 'future_rows' AS section, 'orders after today' AS item,
         CAST(COUNTIF(created_at > CURRENT_TIMESTAMP()) AS STRING) AS value
  FROM `northloom_raw.orders`
  UNION ALL SELECT 'future_rows', 'order_items after today',
         CAST(COUNTIF(created_at > CURRENT_TIMESTAMP()) AS STRING)
  FROM `northloom_raw.order_items`
  UNION ALL SELECT 'future_rows', 'events after today',
         CAST(COUNTIF(created_at > CURRENT_TIMESTAMP()) AS STRING)
  FROM `northloom_raw.events`
  UNION ALL SELECT 'future_rows', 'last order date before today',
         CAST(DATE(MAX(created_at)) AS STRING)
  FROM `northloom_raw.orders` WHERE created_at <= CURRENT_TIMESTAMP()
),
order_status AS (
  SELECT 'order_status' AS section, status AS item, CAST(COUNT(*) AS STRING) AS value
  FROM `northloom_raw.orders` GROUP BY status
),
item_status AS (
  SELECT 'order_item_status' AS section, status AS item, CAST(COUNT(*) AS STRING) AS value
  FROM `northloom_raw.order_items` GROUP BY status
),
event_type AS (
  SELECT 'event_type' AS section, event_type AS item, CAST(COUNT(*) AS STRING) AS value
  FROM `northloom_raw.events` GROUP BY event_type
),
event_channel AS (
  SELECT 'events.traffic_source' AS section, traffic_source AS item, CAST(COUNT(*) AS STRING) AS value
  FROM `northloom_raw.events` GROUP BY traffic_source
),
user_channel AS (
  SELECT 'users.traffic_source' AS section, traffic_source AS item, CAST(COUNT(*) AS STRING) AS value
  FROM `northloom_raw.users` GROUP BY traffic_source
),
departments AS (
  SELECT 'product_department' AS section, department AS item, CAST(COUNT(*) AS STRING) AS value
  FROM `northloom_raw.products` GROUP BY department
),
categories AS (
  SELECT 'product_category' AS section, category AS item, CAST(COUNT(*) AS STRING) AS value
  FROM `northloom_raw.products` GROUP BY category
),
catalog_size AS (
  SELECT 'catalog' AS section, 'distinct brands' AS item, CAST(COUNT(DISTINCT brand) AS STRING) AS value
  FROM `northloom_raw.products`
  UNION ALL SELECT 'catalog', 'distinct categories', CAST(COUNT(DISTINCT category) AS STRING)
  FROM `northloom_raw.products`
  UNION ALL SELECT 'catalog', 'price range (retail)',
         CONCAT(CAST(ROUND(MIN(retail_price), 2) AS STRING), ' .. ', CAST(ROUND(MAX(retail_price), 2) AS STRING))
  FROM `northloom_raw.products`
  UNION ALL SELECT 'catalog', 'avg gross margin pct at list price',
         CAST(ROUND(100 * SAFE_DIVIDE(SUM(retail_price - cost), SUM(retail_price)), 1) AS STRING)
  FROM `northloom_raw.products`
),
dcs AS (
  SELECT 'distribution_center' AS section, name AS item, CAST(id AS STRING) AS value
  FROM `northloom_raw.distribution_centers`
),
countries AS (
  SELECT 'top_countries' AS section, country AS item, CAST(COUNT(*) AS STRING) AS value
  FROM `northloom_raw.users` GROUP BY country ORDER BY COUNT(*) DESC LIMIT 15
)
SELECT * FROM row_counts
UNION ALL SELECT * FROM date_range
UNION ALL SELECT * FROM future_rows
UNION ALL SELECT * FROM order_status
UNION ALL SELECT * FROM item_status
UNION ALL SELECT * FROM event_type
UNION ALL SELECT * FROM event_channel
UNION ALL SELECT * FROM user_channel
UNION ALL SELECT * FROM departments
UNION ALL SELECT * FROM categories
UNION ALL SELECT * FROM catalog_size
UNION ALL SELECT * FROM dcs
UNION ALL SELECT * FROM countries
ORDER BY section, item;
