-- NL-107 | Head of Buying
-- "Which categories are really growing, and which are flat? We're setting next
--  season's buying budget."
--
-- Technique: LAG() partitioned by category to compare each period with the one
-- before, plus share-of-revenue shift, which is what separates real growth from
-- being carried along by the company.
-- Grain of the result: one row per category per year, then per month.
--
-- The important column is not growth. Every category grows, because Northloom
-- grows: revenue roughly quadrupled between 2021 and 2025. The column that earns
-- its place is growth RELATIVE to the company, because a category growing at half
-- the company rate is losing ground while its chart points upwards.
--
-- Everything stops at the last complete month so a part-finished month can't read
-- as a collapse.

CREATE OR REPLACE VIEW `northloom_marts.vw_category_performance` AS
WITH cfg AS (SELECT * FROM `northloom_staging.analysis_config`),
monthly AS (
  SELECT
    p.category,
    p.department,
    f.order_month,
    EXTRACT(YEAR FROM f.order_month)                    AS order_year,
    ROUND(SUM(f.net_revenue), 2)                        AS net_revenue,
    ROUND(SUM(f.gross_margin), 2)                       AS gross_margin,
    COUNT(*)                                            AS items_sold,
    COUNT(DISTINCT f.user_id)                           AS customers
  FROM `northloom_marts.fact_order_items` f
  JOIN `northloom_marts.dim_products` p USING (product_id)
  CROSS JOIN cfg
  WHERE f.is_net_sale
    AND f.order_month <= cfg.last_complete_month
  GROUP BY p.category, p.department, f.order_month, order_year
)
SELECT
  *,
  -- Same month last year: the only honest comparison in a seasonal business,
  -- where Outerwear in November tells you nothing about Outerwear in July.
  LAG(net_revenue, 12) OVER (PARTITION BY category, department ORDER BY order_month) AS net_revenue_same_month_last_year,
  LAG(net_revenue, 1)  OVER (PARTITION BY category, department ORDER BY order_month) AS net_revenue_previous_month,
  -- Three-month average smooths the noise out of a category doing $30K a month.
  ROUND(AVG(net_revenue) OVER (
    PARTITION BY category, department ORDER BY order_month
    ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2)       AS revenue_3_month_avg,
  -- Share of the whole company that month, which is how you see a category
  -- quietly losing ground while still growing.
  ROUND(100 * SAFE_DIVIDE(net_revenue, SUM(net_revenue) OVER (PARTITION BY order_month)), 2) AS pct_of_company_revenue
FROM monthly;

-- ---------------------------------------------------------------------------
-- Result 1: the buying table. Where the budget should move.
--
-- Published as a view as well as a result, because the dashboard binds to it
-- (docs/dashboard_spec.md) and a chart should never re-implement a definition.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW `northloom_marts.vw_category_growth` AS
WITH yearly AS (
  SELECT
    category,
    department,
    SUM(IF(order_year = 2021, net_revenue, 0))          AS revenue_2021,
    SUM(IF(order_year = 2023, net_revenue, 0))          AS revenue_2023,
    SUM(IF(order_year = 2025, net_revenue, 0))          AS revenue_2025,
    SUM(IF(order_year = 2025, gross_margin, 0))         AS margin_2025,
    SUM(IF(order_year = 2025, items_sold, 0))           AS items_2025
  FROM `northloom_marts.vw_category_performance`
  GROUP BY category, department
),
with_growth AS (
  SELECT
    *,
    ROUND(100 * SAFE_DIVIDE(revenue_2025 - revenue_2021, NULLIF(revenue_2021, 0)), 1) AS growth_pct,
    ROUND(100 * SAFE_DIVIDE(revenue_2025, SUM(revenue_2025) OVER ()), 2) AS share_2025_pct,
    ROUND(100 * SAFE_DIVIDE(revenue_2021, SUM(revenue_2021) OVER ()), 2) AS share_2021_pct,
    ROUND(100 * SAFE_DIVIDE(SUM(revenue_2025) OVER () - SUM(revenue_2021) OVER (),
                            NULLIF(SUM(revenue_2021) OVER (), 0)), 1)    AS company_growth_pct,
    ROUND(100 * SAFE_DIVIDE(margin_2025, NULLIF(revenue_2025, 0)), 1)    AS margin_pct_2025
  FROM yearly
)
SELECT
  category,
  department,
  ROUND(revenue_2021, 0)                                AS revenue_2021,
  ROUND(revenue_2023, 0)                                AS revenue_2023,
  ROUND(revenue_2025, 0)                                AS revenue_2025,
  growth_pct,
  company_growth_pct,
  -- The number the buying team should act on. Positive means the category is
  -- outrunning the company; negative means it is being carried.
  ROUND(growth_pct - company_growth_pct, 1)             AS growth_vs_company_pts,
  share_2021_pct,
  share_2025_pct,
  ROUND(share_2025_pct - share_2021_pct, 2)             AS share_shift_pts,
  margin_pct_2025,
  RANK() OVER (ORDER BY revenue_2025 DESC)              AS rank_by_size,
  CASE
    WHEN growth_pct - company_growth_pct >= 50  THEN '1. Buy deeper — outrunning the company'
    WHEN growth_pct - company_growth_pct >= 0   THEN '2. Hold — keeping pace'
    WHEN growth_pct - company_growth_pct >= -50 THEN '3. Watch — slipping behind'
    ELSE                                             '4. Cut back — losing ground badly'
  END                                                   AS buying_recommendation
FROM with_growth
WHERE revenue_2021 > 0;

-- The buying table itself.
SELECT *
FROM `northloom_marts.vw_category_growth`
ORDER BY growth_vs_company_pts DESC;

-- ---------------------------------------------------------------------------
-- Result 2: momentum in the last 12 complete months, for the ten biggest
-- categories. Year-on-year by month, so seasonality can't fake a trend.
-- ---------------------------------------------------------------------------
WITH cfg AS (SELECT * FROM `northloom_staging.analysis_config`),
top_categories AS (
  SELECT category, department
  FROM `northloom_marts.vw_category_performance`
  GROUP BY category, department
  ORDER BY SUM(net_revenue) DESC
  LIMIT 10
)
SELECT
  v.order_month,
  v.category,
  v.department,
  ROUND(v.net_revenue, 0)                               AS net_revenue,
  ROUND(v.net_revenue_same_month_last_year, 0)          AS same_month_last_year,
  ROUND(100 * SAFE_DIVIDE(v.net_revenue - v.net_revenue_same_month_last_year,
                          NULLIF(v.net_revenue_same_month_last_year, 0)), 1) AS yoy_growth_pct,
  ROUND(v.revenue_3_month_avg, 0)                       AS revenue_3_month_avg,
  v.pct_of_company_revenue,
  v.items_sold
FROM `northloom_marts.vw_category_performance` v
JOIN top_categories t USING (category, department)
CROSS JOIN cfg
WHERE v.order_month > DATE_SUB(cfg.last_complete_month, INTERVAL 11 MONTH)
ORDER BY v.category, v.department, v.order_month;
