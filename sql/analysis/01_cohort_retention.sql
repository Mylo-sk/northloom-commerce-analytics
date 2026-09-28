-- NL-101 | VP Growth / CRM
-- "Are the customers we acquire this year worse than last year's? Are they coming back?"
--
-- Technique: acquisition cohorts, DATE_DIFF month indexing, window functions for
-- cohort size and cumulative revenue.
-- Grain of the result: one row per acquisition cohort per month since acquisition.
--
-- Read it as a triangle: each cohort starts at 100% in month 0, and the columns to
-- the right show how much of it is still buying. Comparing cohorts down the rows
-- shows whether newer customers behave worse than older ones.
--
-- Cohorts are defined by FIRST PURCHASE, not signup, because acquisition spend is
-- judged on buyers. Cancelled orders are excluded, since they never became sales.

CREATE OR REPLACE VIEW `northloom_marts.vw_cohort_retention` AS
WITH cfg AS (SELECT * FROM `northloom_staging.analysis_config`),

first_purchase AS (
  SELECT
    user_id,
    DATE_TRUNC(MIN(order_date), MONTH)                  AS cohort_month
  FROM `northloom_marts.fact_order_items`
  WHERE is_net_sale
  GROUP BY user_id
),

-- One row per customer per month in which they bought something.
monthly_activity AS (
  SELECT
    f.user_id,
    DATE_TRUNC(f.order_date, MONTH)                     AS active_month,
    SUM(f.net_revenue)                                  AS net_revenue,
    COUNT(DISTINCT f.order_id)                          AS orders
  FROM `northloom_marts.fact_order_items` f
  WHERE f.is_net_sale
  GROUP BY f.user_id, active_month
),

cohort_activity AS (
  SELECT
    fp.cohort_month,
    DATE_DIFF(ma.active_month, fp.cohort_month, MONTH)  AS months_since_first_purchase,
    ma.user_id,
    ma.net_revenue,
    ma.orders
  FROM first_purchase fp
  JOIN monthly_activity ma USING (user_id)
),

cohort_size AS (
  SELECT cohort_month, COUNT(*) AS cohort_customers
  FROM first_purchase
  GROUP BY cohort_month
)

SELECT
  ca.cohort_month,
  EXTRACT(YEAR FROM ca.cohort_month)                    AS cohort_year,
  cs.cohort_customers,
  ca.months_since_first_purchase,
  COUNT(DISTINCT ca.user_id)                            AS active_customers,
  ROUND(100 * SAFE_DIVIDE(COUNT(DISTINCT ca.user_id), cs.cohort_customers), 1) AS retention_pct,
  ROUND(SUM(ca.net_revenue), 2)                         AS net_revenue,
  ROUND(SAFE_DIVIDE(SUM(ca.net_revenue), cs.cohort_customers), 2) AS revenue_per_cohort_customer,
  -- Cumulative revenue per acquired customer: what the cohort has returned so far.
  ROUND(SUM(SUM(ca.net_revenue)) OVER (
    PARTITION BY ca.cohort_month
    ORDER BY ca.months_since_first_purchase
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) / cs.cohort_customers, 2)                           AS cumulative_revenue_per_customer
FROM cohort_activity ca
JOIN cohort_size cs USING (cohort_month)
CROSS JOIN cfg
-- Part-finished months would look like a collapse, so trends stop at the last
-- complete month.
WHERE ca.cohort_month <= cfg.last_complete_month
  AND DATE_ADD(ca.cohort_month, INTERVAL ca.months_since_first_purchase MONTH) <= cfg.last_complete_month
GROUP BY ca.cohort_month, cs.cohort_customers, ca.months_since_first_purchase;

-- ---------------------------------------------------------------------------
-- The answer to the ticket: has retention changed as Northloom has grown?
--
-- The VP asked who orders again BY month 3, which is cumulative: anyone who came
-- back at any point in those three months. The view above answers a different
-- question, who bought IN month 3 exactly, and that number is far smaller. This
-- query answers the question that was actually asked.
--
-- Customers are only counted once their window has fully elapsed. Someone who
-- bought last week hasn't failed to return in 90 days, they simply haven't had
-- 90 days, and counting them would drag recent cohorts down.
-- ---------------------------------------------------------------------------
WITH cfg AS (SELECT * FROM `northloom_staging.analysis_config`),

customer_orders AS (
  SELECT user_id, order_id, MIN(order_date) AS order_date
  FROM `northloom_marts.fact_order_items`
  WHERE is_net_sale
  GROUP BY user_id, order_id
),

order_sequence AS (
  SELECT
    user_id,
    order_date,
    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY order_date, order_id) AS order_number
  FROM customer_orders
),

customer_timeline AS (
  SELECT
    f.user_id,
    f.order_date                                        AS first_order_date,
    DATE_TRUNC(f.order_date, MONTH)                     AS cohort_month,
    s.order_date                                        AS second_order_date,
    DATE_DIFF(s.order_date, f.order_date, DAY)          AS days_to_second_order
  FROM (SELECT * FROM order_sequence WHERE order_number = 1) f
  LEFT JOIN (SELECT * FROM order_sequence WHERE order_number = 2) s USING (user_id)
),

-- Value delivered inside the first year, for cohorts old enough to have one.
first_year_value AS (
  SELECT
    ct.user_id,
    SUM(IF(fo.order_date <= DATE_ADD(ct.first_order_date, INTERVAL 365 DAY), fo.net_revenue, 0)) AS revenue_first_12m
  FROM customer_timeline ct
  JOIN `northloom_marts.fact_order_items` fo USING (user_id)
  WHERE fo.is_net_sale
  GROUP BY ct.user_id
),

-- Whether each customer has had the full window yet. The numerator and the
-- denominator MUST use the same flag: counting fast repeat buyers whose window
-- hasn't elapsed against a denominator that excludes them produced a repeat rate
-- above 100% for the 2026 cohort, and quietly inflated 2024 and 2025 too.
windowed AS (
  SELECT
    ct.*,
    fyv.revenue_first_12m,
    DATE_ADD(ct.first_order_date, INTERVAL 90 DAY)  <= cfg.last_complete_month_end AS has_90d_window,
    DATE_ADD(ct.first_order_date, INTERVAL 180 DAY) <= cfg.last_complete_month_end AS has_180d_window,
    DATE_ADD(ct.first_order_date, INTERVAL 365 DAY) <= cfg.last_complete_month_end AS has_365d_window
  FROM customer_timeline ct
  JOIN first_year_value fyv USING (user_id)
  CROSS JOIN cfg
)

SELECT
  EXTRACT(YEAR FROM cohort_month)                       AS cohort_year,
  COUNT(*)                                              AS customers_acquired,
  COUNTIF(has_365d_window)                              AS customers_with_full_year,
  ROUND(100 * SAFE_DIVIDE(
    COUNTIF(has_90d_window  AND days_to_second_order <= 90),
    COUNTIF(has_90d_window)), 1)                        AS repeat_by_month_3_pct,
  ROUND(100 * SAFE_DIVIDE(
    COUNTIF(has_180d_window AND days_to_second_order <= 180),
    COUNTIF(has_180d_window)), 1)                       AS repeat_by_month_6_pct,
  ROUND(100 * SAFE_DIVIDE(
    COUNTIF(has_365d_window AND days_to_second_order <= 365),
    COUNTIF(has_365d_window)), 1)                       AS repeat_by_month_12_pct,
  ROUND(AVG(IF(has_365d_window, revenue_first_12m, NULL)), 2) AS revenue_per_customer_first_12m,
  -- Median, and only among customers who both repeated within a year and had a
  -- full year to do it. A plain average across all repeaters is meaningless here:
  -- old cohorts can show a 1,000-day gap, new ones physically cannot.
  APPROX_QUANTILES(
    IF(has_365d_window AND days_to_second_order <= 365, days_to_second_order, NULL), 100
  )[OFFSET(50)]                                         AS median_days_to_second_order
FROM windowed
GROUP BY cohort_year
ORDER BY cohort_year;
