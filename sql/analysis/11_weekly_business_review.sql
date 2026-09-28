-- NL-111 | CEO
-- "Give me one weekly business review table: revenue, orders, AOV, margin,
--  return rate and new vs returning customers."
--
-- Also absorbs what survives of NL-110 (Head of Operations, fulfillment speed).
-- That ticket asked which warehouses are slowest and whether slow delivery drives
-- returns. It cannot be answered: the order-to-ship leg is corrupt on 29.5% of
-- rows, and delivery times turned out to carry no geographic signal at all, with
-- Shanghai and Chicago both at 60 hours (docs/data_quality.md). What remains
-- trustworthy is the median ship-to-delivery time as a stability check, so it
-- rides along here instead of getting a ticket of its own.
--
-- Technique: weekly aggregation against the date dimension, LAG() for week on
-- week movement, and a rolling 4-week average so one odd week doesn't start a
-- panic in the Monday meeting.
-- Grain of the result: one row per complete week.
--
-- Every definition comes from the staging layer, so this table agrees with every
-- other number in the project by construction. That is the entire point of a
-- business review: one set of figures nobody argues about.

CREATE OR REPLACE VIEW `northloom_marts.vw_weekly_business_review` AS
WITH cfg AS (SELECT * FROM `northloom_staging.analysis_config`),
weekly AS (
  SELECT
    d.week_start,
    -- Trade
    ROUND(SUM(f.net_revenue), 2)                        AS net_revenue,
    ROUND(SUM(f.gross_margin), 2)                       AS gross_margin,
    COUNT(DISTINCT IF(f.is_net_sale, f.order_id, NULL)) AS orders,
    COUNT(DISTINCT IF(f.is_net_sale, f.user_id, NULL))  AS active_customers,
    COUNTIF(f.is_net_sale)                              AS items_sold,
    -- Losses
    ROUND(SUM(f.revenue_lost_to_cancellation), 2)       AS revenue_lost_to_cancellation,
    ROUND(SUM(f.revenue_lost_to_return), 2)             AS revenue_lost_to_return,
    COUNTIF(f.is_cancelled)                             AS items_cancelled,
    COUNTIF(f.is_returned)                              AS items_returned,
    COUNTIF(NOT f.is_cancelled)                         AS items_shipped,
    COUNT(*)                                            AS items_ordered,
    -- New versus returning, the split that says whether growth is being bought
    -- or earned. Cancelled items carry their own label and are excluded here.
    ROUND(SUM(IF(f.customer_type = 'New', f.net_revenue, 0)), 2)       AS revenue_from_new_customers,
    ROUND(SUM(IF(f.customer_type = 'Returning', f.net_revenue, 0)), 2) AS revenue_from_returning_customers,
    COUNT(DISTINCT IF(f.customer_type = 'New' AND f.is_net_sale, f.user_id, NULL)) AS new_customers,
    -- Fulfillment: the one leg that survived the data quality work.
    APPROX_QUANTILES(f.hours_ship_to_delivery, 100)[OFFSET(50)] AS median_hours_ship_to_delivery
  FROM `northloom_marts.fact_order_items` f
  JOIN `northloom_marts.dim_date` d ON f.order_date = d.date_key
  CROSS JOIN cfg
  -- Only complete weeks. A week still in progress always looks like a disaster.
  WHERE d.week_start <= DATE_SUB(cfg.as_of_date, INTERVAL 7 DAY)
  GROUP BY d.week_start
)
SELECT
  week_start,
  net_revenue,
  gross_margin,
  ROUND(100 * SAFE_DIVIDE(gross_margin, NULLIF(net_revenue, 0)), 1) AS margin_pct,
  orders,
  active_customers,
  items_sold,
  ROUND(SAFE_DIVIDE(net_revenue, NULLIF(orders, 0)), 2) AS avg_order_value,
  ROUND(SAFE_DIVIDE(items_sold, NULLIF(orders, 0)), 2)  AS items_per_order,
  ROUND(100 * SAFE_DIVIDE(items_returned, NULLIF(items_shipped, 0)), 1) AS return_rate_pct,
  ROUND(100 * SAFE_DIVIDE(items_cancelled, NULLIF(items_ordered, 0)), 1) AS cancellation_rate_pct,
  revenue_lost_to_cancellation,
  revenue_lost_to_return,
  new_customers,
  -- Exposed as amounts, not just as a percentage, so the dashboard can compute
  -- the share over any date range as SUM / SUM. Averaging weekly percentages
  -- would weight a quiet week the same as a busy one.
  revenue_from_new_customers,
  revenue_from_returning_customers,
  ROUND(100 * SAFE_DIVIDE(revenue_from_new_customers, NULLIF(net_revenue, 0)), 1) AS pct_revenue_from_new_customers,
  median_hours_ship_to_delivery,
  -- Week on week, the number everyone looks at first.
  LAG(net_revenue) OVER (ORDER BY week_start)           AS net_revenue_last_week,
  ROUND(100 * SAFE_DIVIDE(net_revenue - LAG(net_revenue) OVER (ORDER BY week_start),
                          NULLIF(LAG(net_revenue) OVER (ORDER BY week_start), 0)), 1) AS revenue_wow_pct,
  -- Same week last year, which is the only fair comparison in a seasonal
  -- business, and a four-week average to damp the noise.
  LAG(net_revenue, 52) OVER (ORDER BY week_start)       AS net_revenue_same_week_last_year,
  ROUND(100 * SAFE_DIVIDE(net_revenue - LAG(net_revenue, 52) OVER (ORDER BY week_start),
                          NULLIF(LAG(net_revenue, 52) OVER (ORDER BY week_start), 0)), 1) AS revenue_yoy_pct,
  ROUND(AVG(net_revenue) OVER (ORDER BY week_start ROWS BETWEEN 3 PRECEDING AND CURRENT ROW), 2) AS revenue_4_week_avg
FROM weekly;

-- ---------------------------------------------------------------------------
-- The review itself: the last 13 complete weeks, most recent first.
-- One screen, no scrolling, nothing the CEO has to ask a follow-up about.
-- ---------------------------------------------------------------------------
WITH cfg AS (SELECT * FROM `northloom_staging.analysis_config`)
SELECT
  v.week_start,
  v.net_revenue,
  v.revenue_wow_pct,
  v.revenue_yoy_pct,
  v.revenue_4_week_avg,
  v.gross_margin,
  v.margin_pct,
  v.orders,
  v.avg_order_value,
  v.items_per_order,
  v.active_customers,
  v.new_customers,
  v.pct_revenue_from_new_customers,
  v.return_rate_pct,
  v.cancellation_rate_pct,
  v.revenue_lost_to_cancellation,
  v.median_hours_ship_to_delivery
FROM `northloom_marts.vw_weekly_business_review` v
CROSS JOIN cfg
WHERE v.week_start > DATE_SUB(cfg.as_of_date, INTERVAL 91 DAY)
ORDER BY v.week_start DESC;

-- ---------------------------------------------------------------------------
-- The same figures by quarter, for the board pack. Weekly is for running the
-- business; quarterly is for seeing whether anything is actually changing.
-- ---------------------------------------------------------------------------
-- Aggregated first, then the window applied on top. A window's ORDER BY can't
-- reference week_start once the rows have been grouped into quarters, and it
-- can't see the quarter_start alias from the same SELECT either.
WITH quarterly AS (
  SELECT
    DATE_TRUNC(week_start, QUARTER)                     AS quarter_start,
    ROUND(SUM(net_revenue), 0)                          AS net_revenue,
    ROUND(SUM(gross_margin), 0)                         AS gross_margin,
    ROUND(100 * SAFE_DIVIDE(SUM(gross_margin), NULLIF(SUM(net_revenue), 0)), 1) AS margin_pct,
    SUM(orders)                                         AS orders,
    ROUND(SAFE_DIVIDE(SUM(net_revenue), NULLIF(SUM(orders), 0)), 2) AS avg_order_value,
    SUM(new_customers)                                  AS new_customers,
    ROUND(AVG(pct_revenue_from_new_customers), 1)       AS avg_pct_revenue_from_new_customers,
    ROUND(AVG(return_rate_pct), 1)                      AS avg_return_rate_pct,
    ROUND(AVG(cancellation_rate_pct), 1)                AS avg_cancellation_rate_pct,
    ROUND(SUM(revenue_lost_to_cancellation), 0)         AS revenue_lost_to_cancellation,
    ROUND(SUM(revenue_lost_to_return), 0)               AS revenue_lost_to_return
  FROM `northloom_marts.vw_weekly_business_review`
  GROUP BY quarter_start
)
SELECT
  *,
  -- Quarter on quarter, so a trend is visible without reading 13 weekly rows.
  ROUND(100 * SAFE_DIVIDE(
    net_revenue - LAG(net_revenue) OVER (ORDER BY quarter_start),
    NULLIF(LAG(net_revenue) OVER (ORDER BY quarter_start), 0)), 1) AS revenue_qoq_pct
FROM quarterly
ORDER BY quarter_start DESC
LIMIT 12;
