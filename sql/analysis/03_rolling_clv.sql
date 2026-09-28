-- NL-103 | CFO
-- "What is a customer worth over their first 12 months? I need it to set how much
--  we can spend to acquire one."
--
-- Technique: SUM() OVER (PARTITION BY user_id ORDER BY month) for running value
-- per customer, then averaged across customers at each month of tenure.
-- Grain of the result: one row per customer per month of their first 24 months.
--
-- Two decisions that change the answer:
--   1. Value is measured as GROSS MARGIN, not revenue. The CFO can only spend
--      what the customer actually contributes, and Northloom keeps about half of
--      each sale. Revenue would overstate the affordable acquisition cost by 2x.
--   2. Only cohorts old enough to have completed the window are included at each
--      month. Without that, recent customers with 2 months of history would drag
--      the 12-month average down and make acquisition look worse than it is.

CREATE OR REPLACE VIEW `northloom_marts.vw_customer_value_curve` AS
WITH cfg AS (SELECT * FROM `northloom_staging.analysis_config`),

first_purchase AS (
  SELECT
    user_id,
    DATE_TRUNC(MIN(order_date), MONTH)                  AS cohort_month
  FROM `northloom_marts.fact_order_items`
  WHERE is_net_sale
  GROUP BY user_id
),

-- Every month of each customer's first 24, including the quiet ones. Missing
-- months would make the running total jump straight from month 1 to month 9.
customer_month_spine AS (
  SELECT
    fp.user_id,
    fp.cohort_month,
    month_index,
    DATE_ADD(fp.cohort_month, INTERVAL month_index MONTH) AS tenure_month
  FROM first_purchase fp
  CROSS JOIN UNNEST(GENERATE_ARRAY(0, 23)) AS month_index
),

monthly_value AS (
  SELECT
    user_id,
    DATE_TRUNC(order_date, MONTH)                       AS tenure_month,
    SUM(net_revenue)                                    AS net_revenue,
    SUM(gross_margin)                                   AS gross_margin,
    COUNT(DISTINCT order_id)                            AS orders
  FROM `northloom_marts.fact_order_items`
  WHERE is_net_sale
  GROUP BY user_id, tenure_month
)

SELECT
  s.user_id,
  s.cohort_month,
  EXTRACT(YEAR FROM s.cohort_month)                     AS cohort_year,
  s.month_index,
  s.tenure_month,
  COALESCE(mv.orders, 0)                                AS orders_in_month,
  ROUND(COALESCE(mv.net_revenue, 0), 2)                 AS net_revenue_in_month,
  ROUND(COALESCE(mv.gross_margin, 0), 2)                AS gross_margin_in_month,
  ROUND(SUM(COALESCE(mv.net_revenue, 0)) OVER w, 2)     AS cumulative_net_revenue,
  ROUND(SUM(COALESCE(mv.gross_margin, 0)) OVER w, 2)    AS cumulative_gross_margin,
  SUM(COALESCE(mv.orders, 0)) OVER w                    AS cumulative_orders,
  -- Has this customer been around long enough for this month to have happened?
  -- Everything downstream filters on it.
  DATE_ADD(s.cohort_month, INTERVAL s.month_index MONTH) <= cfg.last_complete_month AS is_observed
FROM customer_month_spine s
CROSS JOIN cfg
LEFT JOIN monthly_value mv USING (user_id, tenure_month)
WINDOW w AS (PARTITION BY s.user_id ORDER BY s.month_index
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW);

-- ---------------------------------------------------------------------------
-- The answer to the ticket: the value curve, and the acquisition budget it implies.
-- ---------------------------------------------------------------------------
WITH curve AS (
  SELECT
    month_index,
    COUNT(DISTINCT user_id)                             AS customers_observed,
    ROUND(AVG(cumulative_net_revenue), 2)               AS avg_cumulative_revenue,
    ROUND(AVG(cumulative_gross_margin), 2)              AS avg_cumulative_margin,
    ROUND(APPROX_QUANTILES(cumulative_gross_margin, 100)[OFFSET(50)], 2) AS median_cumulative_margin,
    ROUND(AVG(cumulative_orders), 2)                    AS avg_cumulative_orders,
    -- What share of 24-month value has arrived by now? If most of it lands in
    -- month 0, Northloom is effectively a single-purchase business.
    ROUND(100 * SAFE_DIVIDE(
      AVG(cumulative_gross_margin),
      MAX(AVG(cumulative_gross_margin)) OVER ()), 1)    AS pct_of_24_month_value
  FROM `northloom_marts.vw_customer_value_curve`
  WHERE is_observed
  GROUP BY month_index
)
SELECT
  month_index                                           AS months_since_first_purchase,
  customers_observed,
  avg_cumulative_revenue,
  avg_cumulative_margin,
  median_cumulative_margin,
  avg_cumulative_orders,
  pct_of_24_month_value,
  -- The number the CFO asked for: the most that can be spent to acquire a
  -- customer and still break even within the window, at a 70% margin-to-CAC
  -- rule (a 1.4x payback, the usual floor for a healthy retailer).
  ROUND(0.7 * avg_cumulative_margin, 2)                 AS max_affordable_cac
FROM curve
ORDER BY months_since_first_purchase;
