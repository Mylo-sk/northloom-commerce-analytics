-- Northloom: validate the star schema before any analysis runs on it
-- A star schema that silently double-counts is worse than no star schema, so
-- these checks prove the grain, the history and the totals. Export as CSV.

WITH cfg AS (SELECT * FROM `northloom_staging.analysis_config`),

counts AS (
  SELECT 'row_count' AS section, 'dim_date' AS item, CAST(COUNT(*) AS STRING) AS value FROM `northloom_marts.dim_date`
  UNION ALL SELECT 'row_count', 'dim_products', CAST(COUNT(*) AS STRING) FROM `northloom_marts.dim_products`
  UNION ALL SELECT 'row_count', 'dim_distribution_centers', CAST(COUNT(*) AS STRING) FROM `northloom_marts.dim_distribution_centers`
  UNION ALL SELECT 'row_count', 'dim_customers (all spells)', CAST(COUNT(*) AS STRING) FROM `northloom_marts.dim_customers`
  UNION ALL SELECT 'row_count', 'dim_customers (distinct customers)', CAST(COUNT(DISTINCT user_id) AS STRING) FROM `northloom_marts.dim_customers`
  UNION ALL SELECT 'row_count', 'fact_order_items', CAST(COUNT(*) AS STRING) FROM `northloom_marts.fact_order_items`
  UNION ALL SELECT 'row_count', 'fact_sessions', CAST(COUNT(*) AS STRING) FROM `northloom_marts.fact_sessions`
  UNION ALL SELECT 'row_count', 'fact_inventory_snapshot', CAST(COUNT(*) AS STRING) FROM `northloom_marts.fact_inventory_snapshot`
),

-- GRAIN: every key must be unique, or every join downstream multiplies rows.
grain AS (
  SELECT 'grain (0 = pass)' AS section, 'duplicate fact_order_items.order_item_id' AS item,
         CAST(COUNT(*) - COUNT(DISTINCT order_item_id) AS STRING) AS value FROM `northloom_marts.fact_order_items`
  UNION ALL SELECT 'grain (0 = pass)', 'duplicate fact_sessions.session_id',
         CAST(COUNT(*) - COUNT(DISTINCT session_id) AS STRING) FROM `northloom_marts.fact_sessions`
  UNION ALL SELECT 'grain (0 = pass)', 'duplicate dim_products.product_id',
         CAST(COUNT(*) - COUNT(DISTINCT product_id) AS STRING) FROM `northloom_marts.dim_products`
  UNION ALL SELECT 'grain (0 = pass)', 'duplicate dim_customers.customer_sk',
         CAST(COUNT(*) - COUNT(DISTINCT customer_sk) AS STRING) FROM `northloom_marts.dim_customers`
  UNION ALL SELECT 'grain (0 = pass)', 'customers with more than one current row',
         CAST((SELECT COUNT(*) FROM (
            SELECT user_id FROM `northloom_marts.dim_customers` WHERE is_current
            GROUP BY user_id HAVING COUNT(*) > 1)) AS STRING)
),

-- SCD TYPE 2 INTEGRITY: spells must not overlap and must not leave gaps,
-- otherwise an "as at date" join returns two rows or none.
scd AS (
  SELECT 'scd2 (0 = pass)' AS section, 'overlapping spells' AS item,
         CAST(COUNTIF(next_valid_from IS NOT NULL AND next_valid_from <= valid_to_actual) AS STRING) AS value
  FROM (
    SELECT valid_from,
           LEAST(valid_to, (SELECT as_of_date FROM cfg)) AS valid_to_actual,
           LEAD(valid_from) OVER (PARTITION BY user_id ORDER BY valid_from) AS next_valid_from
    FROM `northloom_marts.dim_customers`
  )
  UNION ALL
  SELECT 'scd2 (0 = pass)', 'gaps between spells',
         CAST(COUNTIF(next_valid_from IS NOT NULL
                      AND next_valid_from != DATE_ADD(LEAST(valid_to, (SELECT as_of_date FROM cfg)), INTERVAL 1 DAY)) AS STRING)
  FROM (
    SELECT valid_from, valid_to,
           LEAD(valid_from) OVER (PARTITION BY user_id ORDER BY valid_from) AS next_valid_from
    FROM `northloom_marts.dim_customers`
  )
  UNION ALL
  SELECT 'scd2', 'avg spells per customer',
         FORMAT('%.2f', SAFE_DIVIDE(COUNT(*), COUNT(DISTINCT user_id)))
  FROM `northloom_marts.dim_customers`
  UNION ALL
  SELECT 'scd2', 'customers who ever reached VIP',
         CAST(COUNT(DISTINCT IF(segment = 'VIP', user_id, NULL)) AS STRING)
  FROM `northloom_marts.dim_customers`
  UNION ALL
  SELECT 'scd2', 'customers who were VIP but are not now',
         CAST((SELECT COUNT(DISTINCT user_id) FROM `northloom_marts.dim_customers`
               WHERE segment = 'VIP' AND NOT is_current
                 AND user_id NOT IN (SELECT user_id FROM `northloom_marts.dim_customers`
                                     WHERE segment = 'VIP' AND is_current)) AS STRING)
),

-- RECONCILIATION: the facts must agree with staging, or something was dropped.
reconcile AS (
  SELECT 'reconcile (0 = pass)' AS section, 'net revenue difference vs staging' AS item,
         FORMAT('%.2f',
           (SELECT SUM(net_revenue) FROM `northloom_marts.fact_order_items`)
           - (SELECT SUM(net_revenue) FROM `northloom_staging.stg_order_items`)) AS value
  UNION ALL SELECT 'reconcile (0 = pass)', 'item count difference vs staging',
         CAST((SELECT COUNT(*) FROM `northloom_marts.fact_order_items`)
              - (SELECT COUNT(*) FROM `northloom_staging.stg_order_items`) AS STRING)
  UNION ALL SELECT 'reconcile (0 = pass)', 'fact items with no matching product',
         CAST((SELECT COUNT(*) FROM `northloom_marts.fact_order_items` f
               LEFT JOIN `northloom_marts.dim_products` p USING (product_id)
               WHERE p.product_id IS NULL) AS STRING)
  UNION ALL SELECT 'reconcile (0 = pass)', 'fact items with no current customer row',
         CAST((SELECT COUNT(*) FROM `northloom_marts.fact_order_items` f
               LEFT JOIN `northloom_marts.dim_customers_current` c USING (user_id)
               WHERE c.user_id IS NULL) AS STRING)
),

-- Current segment mix: the CRM team's headline view (NL-102).
segments AS (
  SELECT 'current segment' AS section, segment AS item,
         FORMAT('%d customers, $%.0f lifetime value', COUNT(*), SUM(net_revenue_to_date)) AS value
  FROM `northloom_marts.dim_customers_current`
  GROUP BY segment
),

-- DISCOUNTING: does Northloom actually discount, or is everything sold at list?
-- This decides whether a discount analysis is possible at all.
discounting AS (
  SELECT 'discounting' AS section, 'items sold below list price' AS item,
         FORMAT('%d of %d (%.1f%%)', COUNTIF(discount_amount > 0), COUNT(*),
                100 * SAFE_DIVIDE(COUNTIF(discount_amount > 0), COUNT(*))) AS value
  FROM `northloom_marts.fact_order_items`
  UNION ALL SELECT 'discounting', 'items sold at exactly list price',
         FORMAT('%d of %d (%.1f%%)', COUNTIF(discount_amount = 0), COUNT(*),
                100 * SAFE_DIVIDE(COUNTIF(discount_amount = 0), COUNT(*)))
  FROM `northloom_marts.fact_order_items`
  UNION ALL SELECT 'discounting', 'average discount where discounted',
         FORMAT('%.2f', AVG(IF(discount_amount > 0, discount_amount, NULL)))
  FROM `northloom_marts.fact_order_items`
),

-- New versus returning revenue: the split the CEO asks about (NL-111).
customer_mix AS (
  SELECT 'customer mix' AS section, customer_type AS item,
         FORMAT('%d items, $%.0f net revenue', COUNT(*), SUM(net_revenue)) AS value
  FROM `northloom_marts.fact_order_items`
  WHERE is_net_sale
  GROUP BY customer_type
),

-- Funnel sanity at session grain (NL-109).
funnel AS (
  SELECT 'funnel' AS section, 'sessions' AS item, CAST(COUNT(*) AS STRING) AS value FROM `northloom_marts.fact_sessions`
  UNION ALL SELECT 'funnel', 'session conversion rate',
         FORMAT('%.2f%%', 100 * SAFE_DIVIDE(COUNTIF(reached_purchase), COUNT(*))) FROM `northloom_marts.fact_sessions`
  UNION ALL SELECT 'funnel', 'signed-in share of sessions',
         FORMAT('%.1f%%', 100 * SAFE_DIVIDE(COUNTIF(is_signed_in), COUNT(*))) FROM `northloom_marts.fact_sessions`
  UNION ALL SELECT 'funnel', 'items purchased in sessions vs fact rows',
         CAST((SELECT SUM(items_purchased) FROM `northloom_marts.fact_sessions`)
              - (SELECT COUNT(*) FROM `northloom_marts.fact_order_items`) AS STRING)
),

-- Stock position (NL-104).
stock AS (
  SELECT 'stock status' AS section, stock_status AS item,
         FORMAT('%d product-DC rows, $%.0f at cost', COUNT(*), SUM(stock_value_at_cost)) AS value
  FROM `northloom_marts.fact_inventory_snapshot`
  GROUP BY stock_status
)

SELECT * FROM counts
UNION ALL SELECT * FROM grain
UNION ALL SELECT * FROM scd
UNION ALL SELECT * FROM reconcile
UNION ALL SELECT * FROM segments
UNION ALL SELECT * FROM discounting
UNION ALL SELECT * FROM customer_mix
UNION ALL SELECT * FROM funnel
UNION ALL SELECT * FROM stock
ORDER BY section, item;
