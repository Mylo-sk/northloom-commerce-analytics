-- NL-113 | Head of Ecommerce
-- "Nearly 15% of orders are cancelled. Which ones, and what do they have in common?"
--
-- Technique: one view at item level carrying every attribute a cancellation could
-- plausibly depend on, then the same rate measured across every cut, so the
-- comparison is like for like.
-- Grain of the result: one row per dimension value, then one per month.
--
-- This is the largest unmanaged loss in the business: $1.58M of revenue never
-- collected, roughly $790K of margin at Northloom's 51.9% rate, which is about
-- 1.5x what returns cost (NL-108).
--
-- The question is diagnostic, so the query is built to give an honest negative if
-- there isn't one: if every cut comes back at the same rate, the cause is not in
-- the warehouse and the next step is the order pipeline, not more SQL.

CREATE OR REPLACE VIEW `northloom_marts.vw_cancellations` AS
SELECT
  f.order_item_id,
  f.order_id,
  f.user_id,
  f.order_date,
  f.order_month,
  EXTRACT(YEAR FROM f.order_date)                       AS order_year,
  FORMAT_DATE('%A', f.order_date)                       AS order_day_name,
  f.is_cancelled,
  f.sale_price,
  -- customer_type and customer_order_seq are both defined over orders that
  -- weren't cancelled, so cutting cancellations by them just restates the label
  -- (Cancelled 100%, everything else 0%). To ask whether first-time buyers
  -- cancel more, the position has to be counted over EVERY order the customer
  -- placed, cancelled ones included.
  DENSE_RANK() OVER (PARTITION BY f.user_id ORDER BY f.order_date, f.order_id) AS order_position_all_orders,
  p.category,
  p.department,
  p.brand,
  p.price_band,
  dc.distribution_center_name,
  c.market,
  c.region,
  c.signup_channel,
  c.age,
  c.gender,
  -- Basket size at the time of order: are big orders cancelled more?
  COUNT(*) OVER (PARTITION BY f.order_id)               AS items_in_order,
  ROUND(SUM(f.sale_price) OVER (PARTITION BY f.order_id), 2) AS order_value
FROM `northloom_marts.fact_order_items` f
JOIN `northloom_marts.dim_products` p USING (product_id)
-- Explicit, because dim_products carries a warehouse id too (where the product is
-- meant to be stocked). The fact's id is where the stock physically sat.
LEFT JOIN `northloom_marts.dim_distribution_centers` dc
  ON f.distribution_center_id = dc.distribution_center_id
LEFT JOIN `northloom_marts.dim_customers_current` c USING (user_id);

-- ---------------------------------------------------------------------------
-- Result 1: the same cancellation rate, cut every way that might matter.
--
-- Read the SPREAD, not the individual rows. A cause shows up as one cut where the
-- rates fan out; noise shows up as every cut landing on the company average.
-- ---------------------------------------------------------------------------
WITH base AS (SELECT * FROM `northloom_marts.vw_cancellations`),

overall AS (
  SELECT 'ALL ITEMS' AS cut, 'company average' AS value,
         COUNT(*) AS items, COUNTIF(is_cancelled) AS cancelled,
         ROUND(100 * SAFE_DIVIDE(COUNTIF(is_cancelled), COUNT(*)), 1) AS cancellation_rate_pct,
         ROUND(SUM(IF(is_cancelled, sale_price, 0)), 0) AS revenue_lost
  FROM base
),
by_customer_type AS (
  SELECT 'order position',
         CASE
           WHEN order_position_all_orders = 1 THEN 'First order they ever placed'
           WHEN order_position_all_orders = 2 THEN 'Their second order'
           ELSE                                    'Third order or later'
         END,
         COUNT(*), COUNTIF(is_cancelled),
         ROUND(100 * SAFE_DIVIDE(COUNTIF(is_cancelled), COUNT(*)), 1),
         ROUND(SUM(IF(is_cancelled, sale_price, 0)), 0)
  FROM base GROUP BY 2
),
by_region AS (
  SELECT 'region', region, COUNT(*), COUNTIF(is_cancelled),
         ROUND(100 * SAFE_DIVIDE(COUNTIF(is_cancelled), COUNT(*)), 1),
         ROUND(SUM(IF(is_cancelled, sale_price, 0)), 0)
  FROM base GROUP BY region
),
by_market AS (
  SELECT 'market (top 8)', market, COUNT(*), COUNTIF(is_cancelled),
         ROUND(100 * SAFE_DIVIDE(COUNTIF(is_cancelled), COUNT(*)), 1),
         ROUND(SUM(IF(is_cancelled, sale_price, 0)), 0)
  FROM base GROUP BY market ORDER BY COUNT(*) DESC LIMIT 8
),
by_channel AS (
  SELECT 'signup channel', signup_channel, COUNT(*), COUNTIF(is_cancelled),
         ROUND(100 * SAFE_DIVIDE(COUNTIF(is_cancelled), COUNT(*)), 1),
         ROUND(SUM(IF(is_cancelled, sale_price, 0)), 0)
  FROM base GROUP BY signup_channel
),
by_price_band AS (
  SELECT 'price band', price_band, COUNT(*), COUNTIF(is_cancelled),
         ROUND(100 * SAFE_DIVIDE(COUNTIF(is_cancelled), COUNT(*)), 1),
         ROUND(SUM(IF(is_cancelled, sale_price, 0)), 0)
  FROM base GROUP BY price_band
),
by_basket_size AS (
  SELECT 'items in order',
         CASE WHEN items_in_order = 1 THEN '1 item'
              WHEN items_in_order = 2 THEN '2 items'
              WHEN items_in_order = 3 THEN '3 items'
              ELSE '4+ items' END,
         COUNT(*), COUNTIF(is_cancelled),
         ROUND(100 * SAFE_DIVIDE(COUNTIF(is_cancelled), COUNT(*)), 1),
         ROUND(SUM(IF(is_cancelled, sale_price, 0)), 0)
  FROM base GROUP BY 2
),
by_warehouse AS (
  SELECT 'warehouse', distribution_center_name, COUNT(*), COUNTIF(is_cancelled),
         ROUND(100 * SAFE_DIVIDE(COUNTIF(is_cancelled), COUNT(*)), 1),
         ROUND(SUM(IF(is_cancelled, sale_price, 0)), 0)
  FROM base GROUP BY distribution_center_name
),
by_department AS (
  SELECT 'department', department, COUNT(*), COUNTIF(is_cancelled),
         ROUND(100 * SAFE_DIVIDE(COUNTIF(is_cancelled), COUNT(*)), 1),
         ROUND(SUM(IF(is_cancelled, sale_price, 0)), 0)
  FROM base GROUP BY department
),
by_day AS (
  SELECT 'day of week', order_day_name, COUNT(*), COUNTIF(is_cancelled),
         ROUND(100 * SAFE_DIVIDE(COUNTIF(is_cancelled), COUNT(*)), 1),
         ROUND(SUM(IF(is_cancelled, sale_price, 0)), 0)
  FROM base GROUP BY order_day_name
),
by_year AS (
  SELECT 'year', CAST(order_year AS STRING), COUNT(*), COUNTIF(is_cancelled),
         ROUND(100 * SAFE_DIVIDE(COUNTIF(is_cancelled), COUNT(*)), 1),
         ROUND(SUM(IF(is_cancelled, sale_price, 0)), 0)
  FROM base GROUP BY order_year
),
combined AS (
  SELECT * FROM overall
  UNION ALL SELECT * FROM by_customer_type
  UNION ALL SELECT * FROM by_region
  UNION ALL SELECT * FROM by_market
  UNION ALL SELECT * FROM by_channel
  UNION ALL SELECT * FROM by_price_band
  UNION ALL SELECT * FROM by_basket_size
  UNION ALL SELECT * FROM by_warehouse
  UNION ALL SELECT * FROM by_department
  UNION ALL SELECT * FROM by_day
  UNION ALL SELECT * FROM by_year
)
SELECT
  cut,
  value,
  items,
  cancelled,
  cancellation_rate_pct,
  revenue_lost,
  -- Distance from the company average, which is what makes a cause visible.
  ROUND(cancellation_rate_pct
        - MAX(IF(cut = 'ALL ITEMS', cancellation_rate_pct, NULL)) OVER (), 1) AS points_vs_average,
  -- How far apart the values within this cut are. A spread near zero means this
  -- dimension explains nothing.
  ROUND(MAX(cancellation_rate_pct) OVER (PARTITION BY cut)
        - MIN(cancellation_rate_pct) OVER (PARTITION BY cut), 1) AS spread_within_cut
FROM combined
ORDER BY spread_within_cut DESC, cut, cancellation_rate_pct DESC;

-- ---------------------------------------------------------------------------
-- Result 2: are these whole orders or single items, and is it getting worse?
--
-- A cancelled ORDER is a customer changing their mind. A single cancelled ITEM
-- inside an otherwise shipped order is usually stock that wasn't really there.
-- The two have completely different fixes, and the split says which one this is.
-- ---------------------------------------------------------------------------
WITH order_level AS (
  SELECT
    order_id,
    ANY_VALUE(order_month)                              AS order_month,
    COUNT(*)                                            AS items,
    COUNTIF(is_cancelled)                               AS items_cancelled,
    ROUND(SUM(sale_price), 2)                           AS order_value,
    ROUND(SUM(IF(is_cancelled, sale_price, 0)), 2)      AS value_cancelled
  FROM `northloom_marts.vw_cancellations`
  GROUP BY order_id
),
classified AS (
  SELECT
    *,
    CASE
      WHEN items_cancelled = 0                THEN '1. Nothing cancelled'
      WHEN items_cancelled = items            THEN '2. Whole order cancelled'
      ELSE                                         '3. Part of the order cancelled'
    END                                                 AS cancellation_type
  FROM order_level
)
SELECT
  cancellation_type,
  COUNT(*)                                              AS orders,
  ROUND(100 * SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()), 1) AS pct_of_orders,
  ROUND(AVG(items), 2)                                  AS avg_items_per_order,
  ROUND(AVG(order_value), 2)                            AS avg_order_value,
  ROUND(SUM(value_cancelled), 0)                        AS revenue_lost,
  -- Is the rate moving? Comparing the first and last full year says whether this
  -- is a new problem or a permanent feature.
  ROUND(100 * SAFE_DIVIDE(
    COUNTIF(EXTRACT(YEAR FROM order_month) = 2019),
    SUM(COUNTIF(EXTRACT(YEAR FROM order_month) = 2019)) OVER ()), 1) AS pct_of_2019_orders,
  ROUND(100 * SAFE_DIVIDE(
    COUNTIF(EXTRACT(YEAR FROM order_month) = 2025),
    SUM(COUNTIF(EXTRACT(YEAR FROM order_month) = 2025)) OVER ()), 1) AS pct_of_2025_orders
FROM classified
GROUP BY cancellation_type
ORDER BY cancellation_type;
