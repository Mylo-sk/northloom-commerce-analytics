-- Northloom: star schema dimensions (step 4b)
-- Built as tables, because the marts are read repeatedly by the analysis queries
-- and by Looker Studio, and the SCD Type 2 build is too heavy to repeat per query.
-- Run after sql/staging/01_stg_views.sql.

-- ---------------------------------------------------------------------------
-- dim_date: a row per calendar day from the first order to the analysis date.
-- Gives every trend query a spine, so months with no activity still appear
-- instead of silently vanishing from a chart.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `northloom_marts.dim_date` AS
WITH cfg AS (SELECT * FROM `northloom_staging.analysis_config`)
SELECT
  d                                                    AS date_key,
  EXTRACT(YEAR    FROM d)                              AS year,
  EXTRACT(QUARTER FROM d)                              AS quarter,
  EXTRACT(MONTH   FROM d)                              AS month_number,
  FORMAT_DATE('%b %Y', d)                              AS month_label,
  DATE_TRUNC(d, MONTH)                                 AS month_start,
  LAST_DAY(d, MONTH)                                   AS month_end,
  DATE_TRUNC(d, WEEK(MONDAY))                          AS week_start,
  EXTRACT(DAYOFWEEK FROM d)                            AS day_of_week,
  FORMAT_DATE('%a', d)                                 AS day_name,
  EXTRACT(DAYOFWEEK FROM d) IN (1, 7)                  AS is_weekend,
  -- Retail seasons drive the buying calendar, so the buying team asks in these terms.
  CASE
    WHEN EXTRACT(MONTH FROM d) IN (12, 1, 2)  THEN 'Winter'
    WHEN EXTRACT(MONTH FROM d) IN (3, 4, 5)   THEN 'Spring'
    WHEN EXTRACT(MONTH FROM d) IN (6, 7, 8)   THEN 'Summer'
    ELSE 'Autumn'
  END                                                  AS retail_season,
  -- Peak trading: the weeks that decide a fashion retailer's year.
  (EXTRACT(MONTH FROM d) = 11 AND EXTRACT(DAY FROM d) >= 20)
    OR EXTRACT(MONTH FROM d) = 12                      AS is_peak_trading,
  d <= (SELECT as_of_date FROM cfg)                    AS is_complete_day,
  DATE_TRUNC(d, MONTH) < (SELECT last_complete_month FROM cfg)
    OR DATE_TRUNC(d, MONTH) = (SELECT last_complete_month FROM cfg) AS is_complete_month
FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2019-01-01', (SELECT as_of_date FROM cfg))) AS d;

-- ---------------------------------------------------------------------------
-- dim_products
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `northloom_marts.dim_products` AS
SELECT
  p.product_id,
  p.product_name,
  p.category,
  p.brand,
  p.department,
  p.sku,
  p.list_cost,
  p.retail_price,
  p.list_margin_amount,
  p.list_margin_pct,
  -- Price bands let merchandising compare like with like, since a $15 tee and a
  -- $400 coat should never be judged by the same return rate.
  CASE
    WHEN p.retail_price < 25  THEN '1. Under $25'
    WHEN p.retail_price < 50  THEN '2. $25-$50'
    WHEN p.retail_price < 100 THEN '3. $50-$100'
    WHEN p.retail_price < 250 THEN '4. $100-$250'
    ELSE '5. $250+'
  END                                                  AS price_band,
  p.distribution_center_id,
  dc.distribution_center_name,
  p.is_price_suspect,
  p.has_missing_attributes
FROM `northloom_staging.stg_products` p
LEFT JOIN `northloom_staging.stg_distribution_centers` dc
  USING (distribution_center_id);

-- ---------------------------------------------------------------------------
-- dim_distribution_centers, with the stock it holds and how much cash that ties up
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `northloom_marts.dim_distribution_centers` AS
SELECT
  dc.distribution_center_id,
  dc.distribution_center_name,
  dc.dc_city,
  dc.dc_state,
  dc.latitude,
  dc.longitude,
  -- GEOGRAPHY can't be grouped, so it's carried through as ANY_VALUE. Safe here
  -- because there's exactly one row per distribution center.
  ANY_VALUE(dc.dc_geom)                                AS dc_geom,
  COUNTIF(ii.is_on_hand)                               AS units_on_hand,
  ROUND(SUM(IF(ii.is_on_hand, ii.unit_cost, 0)), 2)    AS stock_value_at_cost,
  COUNT(DISTINCT ii.product_id)                        AS products_stocked
FROM `northloom_staging.stg_distribution_centers` dc
LEFT JOIN `northloom_staging.stg_inventory_items` ii USING (distribution_center_id)
GROUP BY dc.distribution_center_id, dc.distribution_center_name, dc.dc_city,
         dc.dc_state, dc.latitude, dc.longitude;

-- ---------------------------------------------------------------------------
-- dim_customers: SLOWLY CHANGING DIMENSION, TYPE 2
--
-- A customer's segment is not a fact about them, it's a fact about them at a
-- point in time. A Type 1 dimension would overwrite it and lose the history, so
-- "how many VIPs did we lose last year?" becomes unanswerable. This keeps one row
-- per customer per spell in a segment, with valid_from / valid_to.
--
-- Built in five steps: a monthly spine per customer, their behaviour to that
-- month end, the VIP threshold for that month, the segment rule, then collapsing
-- runs of identical segments into date ranges.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `northloom_marts.dim_customers` AS
WITH cfg AS (SELECT * FROM `northloom_staging.analysis_config`),

-- Orders that count: cancelled ones never happened as far as the customer
-- relationship is concerned.
customer_orders AS (
  SELECT
    user_id,
    order_id,
    MIN(order_date)                                    AS order_date,
    SUM(net_revenue)                                   AS order_net_revenue
  FROM `northloom_staging.stg_order_items`
  WHERE NOT is_cancelled
  GROUP BY user_id, order_id
),

-- The spine: every month from a customer's signup to the analysis date.
--
-- It starts at signup, not at their first order, so the dimension covers all
-- 100,000 registered customers rather than only the ones who bought something.
-- Two reasons: a customer who never converts is a real business fact (they sit
-- in the Prospect segment), and starting at first order leaves the sales fact
-- with rows whose customer has no dimension row at all, which quietly breaks
-- inner joins. Customers whose only orders were cancelled stay Prospect,
-- because a cancelled order never became a purchase.
customer_span AS (
  SELECT
    u.user_id,
    DATE_TRUNC(LEAST(u.signup_date, COALESCE(fo.first_order_date, u.signup_date)), MONTH) AS first_order_month
  FROM `northloom_staging.stg_users` u
  LEFT JOIN (
    SELECT user_id, MIN(order_date) AS first_order_date
    FROM customer_orders GROUP BY user_id
  ) fo USING (user_id)
),
customer_months AS (
  SELECT s.user_id, m AS month_start
  FROM customer_span s
  CROSS JOIN cfg
  CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(
    s.first_order_month,
    DATE_TRUNC(cfg.as_of_date, MONTH),
    INTERVAL 1 MONTH)) AS m
),

-- What happened in each month
monthly_activity AS (
  SELECT
    user_id,
    DATE_TRUNC(order_date, MONTH)                      AS month_start,
    COUNT(DISTINCT order_id)                           AS orders_in_month,
    SUM(order_net_revenue)                             AS revenue_in_month,
    MAX(order_date)                                    AS last_order_in_month
  FROM customer_orders
  GROUP BY user_id, month_start
),

-- Running totals to each month end: the state the customer was in at that time.
running_state AS (
  SELECT
    cm.user_id,
    cm.month_start,
    LAST_DAY(cm.month_start, MONTH)                    AS month_end,
    COALESCE(ma.orders_in_month, 0)                    AS orders_in_month,
    COALESCE(ma.revenue_in_month, 0)                   AS revenue_in_month,
    SUM(COALESCE(ma.orders_in_month, 0)) OVER w        AS cum_orders,
    ROUND(SUM(COALESCE(ma.revenue_in_month, 0)) OVER w, 2) AS cum_net_revenue,
    MAX(ma.last_order_in_month) OVER w                 AS last_order_date
  FROM customer_months cm
  LEFT JOIN monthly_activity ma USING (user_id, month_start)
  WINDOW w AS (PARTITION BY cm.user_id ORDER BY cm.month_start
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
),

-- The VIP line moves as the business grows, so it's recalculated each month
-- rather than fixed once. VIP means top 10% of spend among customers who had
-- ordered by then.
vip_threshold AS (
  SELECT
    month_start,
    APPROX_QUANTILES(cum_net_revenue, 10)[OFFSET(9)]   AS vip_cutoff
  FROM running_state
  WHERE cum_net_revenue > 0
  GROUP BY month_start
),

-- The segment rule. Thresholds are the ones agreed with the CRM team and are
-- documented in docs/business_context.md, so the same definition is used
-- everywhere rather than reinvented per query.
segmented AS (
  SELECT
    rs.*,
    DATE_DIFF(rs.month_end, rs.last_order_date, DAY)   AS days_since_last_order,
    CASE
      WHEN rs.cum_orders = 0 THEN 'Prospect'
      WHEN DATE_DIFF(rs.month_end, rs.last_order_date, DAY) <= 90
           AND rs.cum_net_revenue >= vt.vip_cutoff     THEN 'VIP'
      WHEN rs.cum_orders = 1
           AND DATE_DIFF(rs.month_end, rs.last_order_date, DAY) <= 90 THEN 'New'
      WHEN DATE_DIFF(rs.month_end, rs.last_order_date, DAY) <= 90  THEN 'Active'
      WHEN DATE_DIFF(rs.month_end, rs.last_order_date, DAY) <= 180 THEN 'Cooling'
      WHEN DATE_DIFF(rs.month_end, rs.last_order_date, DAY) <= 365 THEN 'At risk'
      ELSE 'Lapsed'
    END                                                AS segment
  FROM running_state rs
  LEFT JOIN vip_threshold vt USING (month_start)
),

-- Collapse runs: a customer who is Active for 14 months should be one row, not
-- 14. Comparing each month to the previous one marks where a spell starts, and
-- a running sum of those marks gives each spell an id to group by.
change_points AS (
  SELECT
    *,
    IF(segment = LAG(segment) OVER (PARTITION BY user_id ORDER BY month_start), 0, 1) AS is_new_spell
  FROM segmented
),
spells AS (
  SELECT
    *,
    SUM(is_new_spell) OVER (PARTITION BY user_id ORDER BY month_start
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS spell_id
  FROM change_points
),
collapsed AS (
  SELECT
    user_id,
    spell_id,
    ANY_VALUE(segment)                                 AS segment,
    MIN(month_start)                                   AS valid_from,
    MAX(month_end)                                     AS valid_to_actual,
    -- State at the end of the spell
    MAX_BY(cum_orders, month_start)                    AS orders_to_date,
    MAX_BY(cum_net_revenue, month_start)               AS net_revenue_to_date,
    MAX_BY(last_order_date, month_start)               AS last_order_date,
    MAX_BY(days_since_last_order, month_start)         AS days_since_last_order
  FROM spells
  GROUP BY user_id, spell_id
)

SELECT
  -- Surrogate key: one row per customer per spell, which is the grain.
  FARM_FINGERPRINT(CONCAT(CAST(c.user_id AS STRING), '|', CAST(c.spell_id AS STRING))) AS customer_sk,
  c.user_id,
  c.segment,
  c.valid_from,
  -- The current spell stays open, which is what makes "as at today" joins simple.
  IF(c.valid_to_actual >= (SELECT as_of_date FROM cfg), DATE '9999-12-31', c.valid_to_actual) AS valid_to,
  c.valid_to_actual >= (SELECT as_of_date FROM cfg)    AS is_current,
  DATE_DIFF(LEAST(c.valid_to_actual, (SELECT as_of_date FROM cfg)), c.valid_from, DAY) AS days_in_segment,
  -- Customer attributes, which don't change
  u.age,
  u.gender,
  u.country,
  u.market,
  u.region,
  u.city,
  u.state,
  u.latitude,
  u.longitude,
  u.signup_date,
  u.signup_cohort_month,
  u.signup_channel,
  u.signup_channel_is_paid,
  -- Behaviour as at the end of this spell
  c.orders_to_date,
  c.net_revenue_to_date,
  c.last_order_date,
  c.days_since_last_order,
  ROUND(SAFE_DIVIDE(c.net_revenue_to_date, NULLIF(c.orders_to_date, 0)), 2) AS avg_order_value_to_date
FROM collapsed c
JOIN `northloom_staging.stg_users` u USING (user_id);

-- ---------------------------------------------------------------------------
-- dim_customers_current: the everyday view. Most questions are about now, and
-- joining to the Type 2 table without a date filter silently multiplies rows,
-- which is the classic way a star schema gets misread.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW `northloom_marts.dim_customers_current` AS
SELECT * EXCEPT (valid_to, is_current)
FROM `northloom_marts.dim_customers`
WHERE is_current;
