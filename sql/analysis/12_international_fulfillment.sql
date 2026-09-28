-- NL-112 | COO
-- "China is our biggest market but every parcel ships from the US. What would an
--  Asia-Pacific distribution center be worth?"
--
-- Technique: regional cohort comparison against the fulfillment fact, using the
-- ship-to-delivery leg only (the order-to-ship leg is unusable, see
-- docs/data_quality.md), plus a sizing of the prize.
-- Grain of the result: one row per region, then one per market per year, then the
-- business case inputs.
--
-- Northloom has 43,932 Asia Pacific customers and 22,520 in North America, and
-- ships all of it from 10 warehouses in the United States.

CREATE OR REPLACE VIEW `northloom_marts.vw_fulfillment_by_market` AS
SELECT
  c.region,
  c.market,
  c.country,
  f.order_date,
  EXTRACT(YEAR FROM f.order_date)                       AS order_year,
  f.order_item_id,
  f.user_id,
  f.sale_price,
  f.net_revenue,
  f.gross_margin,
  f.is_cancelled,
  f.is_returned,
  f.is_net_sale,
  f.hours_ship_to_delivery,
  f.hours_order_to_delivery,
  f.has_valid_ship_timeline,
  dc.distribution_center_name,
  dc.dc_state
FROM `northloom_marts.fact_order_items` f
JOIN `northloom_marts.dim_customers_current` c USING (user_id)
LEFT JOIN `northloom_marts.dim_distribution_centers` dc USING (distribution_center_id);

-- ---------------------------------------------------------------------------
-- Result 1: what each region is worth, and what it currently gets.
--
-- If delivery times to Asia Pacific are materially worse than to North America,
-- that gap is the thing a local warehouse would close, and its size sets the
-- ceiling on the benefit. If the times are the same, the case has to rest on
-- freight cost instead, which is not in this warehouse.
-- ---------------------------------------------------------------------------
SELECT
  region,
  COUNT(DISTINCT user_id)                               AS customers,
  COUNT(DISTINCT IF(is_net_sale, order_item_id, NULL))  AS items_sold,
  ROUND(SUM(net_revenue), 0)                            AS net_revenue,
  ROUND(SUM(gross_margin), 0)                           AS gross_margin,
  ROUND(100 * SAFE_DIVIDE(SUM(net_revenue), SUM(SUM(net_revenue)) OVER ()), 1) AS pct_of_revenue,
  ROUND(SAFE_DIVIDE(SUM(net_revenue), COUNT(DISTINCT user_id)), 2) AS revenue_per_customer,
  -- The measure that matters: the leg a local warehouse would shorten.
  APPROX_QUANTILES(hours_ship_to_delivery, 100)[OFFSET(50)] AS median_hours_ship_to_delivery,
  APPROX_QUANTILES(hours_ship_to_delivery, 100)[OFFSET(90)] AS p90_hours_ship_to_delivery,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(is_returned), NULLIF(COUNTIF(NOT is_cancelled), 0)), 1) AS return_rate_pct,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(is_cancelled), COUNT(*)), 1) AS cancellation_rate_pct
FROM `northloom_marts.vw_fulfillment_by_market`
GROUP BY region
ORDER BY net_revenue DESC;

-- ---------------------------------------------------------------------------
-- Result 2: which markets are growing, because a warehouse is a ten-year bet.
--
-- Built on the last complete month so the current part-year doesn't read as a
-- collapse, and shown as a share of each year so growth is comparable.
-- ---------------------------------------------------------------------------
WITH cfg AS (SELECT * FROM `northloom_staging.analysis_config`),
yearly AS (
  SELECT
    m.market,
    ANY_VALUE(m.region)                                 AS region,
    m.order_year,
    ROUND(SUM(m.net_revenue), 0)                        AS net_revenue,
    COUNT(DISTINCT m.user_id)                           AS active_customers
  FROM `northloom_marts.vw_fulfillment_by_market` m
  CROSS JOIN cfg
  WHERE m.order_date <= cfg.last_complete_month_end
  GROUP BY m.market, m.order_year
)
SELECT
  market,
  region,
  SUM(IF(order_year = 2021, net_revenue, 0))            AS revenue_2021,
  SUM(IF(order_year = 2023, net_revenue, 0))            AS revenue_2023,
  SUM(IF(order_year = 2025, net_revenue, 0))            AS revenue_2025,
  -- Four-year growth, the number that justifies or kills a capital project.
  ROUND(100 * SAFE_DIVIDE(
    SUM(IF(order_year = 2025, net_revenue, 0)) - SUM(IF(order_year = 2021, net_revenue, 0)),
    NULLIF(SUM(IF(order_year = 2021, net_revenue, 0)), 0)), 1) AS growth_2021_to_2025_pct,
  SUM(IF(order_year = 2025, active_customers, 0))       AS active_customers_2025,
  RANK() OVER (ORDER BY SUM(IF(order_year = 2025, net_revenue, 0)) DESC) AS rank_by_2025_revenue
FROM yearly
GROUP BY market, region
ORDER BY revenue_2025 DESC
LIMIT 15;

-- ---------------------------------------------------------------------------
-- Result 3: the business case inputs, for the region a warehouse would serve.
--
-- Deliberately stops short of a recommendation. The warehouse decision needs
-- freight rates, lease costs and duty, none of which are in the warehouse. What
-- the data CAN give the COO is the size of the demand it would serve, the stock
-- it would have to hold, and the delivery gap it would close.
-- ---------------------------------------------------------------------------
WITH cfg AS (SELECT * FROM `northloom_staging.analysis_config`),
apac AS (
  SELECT *
  FROM `northloom_marts.vw_fulfillment_by_market`
  WHERE region = 'Asia Pacific'
),
trailing_year AS (
  SELECT
    COUNT(DISTINCT IF(is_net_sale, order_item_id, NULL)) AS items_last_12m,
    ROUND(SUM(net_revenue), 0)                          AS revenue_last_12m,
    ROUND(SUM(gross_margin), 0)                         AS margin_last_12m,
    COUNT(DISTINCT user_id)                             AS customers_last_12m
  FROM apac, cfg
  WHERE order_date > DATE_SUB(cfg.as_of_date, INTERVAL 365 DAY)
),
delivery_gap AS (
  SELECT
    APPROX_QUANTILES(IF(region = 'Asia Pacific', hours_ship_to_delivery, NULL), 100)[OFFSET(50)] AS apac_median_hours,
    APPROX_QUANTILES(IF(region = 'North America', hours_ship_to_delivery, NULL), 100)[OFFSET(50)] AS us_median_hours
  FROM `northloom_marts.vw_fulfillment_by_market`
)
SELECT
  'Asia Pacific'                                        AS region,
  t.customers_last_12m,
  t.items_last_12m,
  t.revenue_last_12m,
  t.margin_last_12m,
  -- Stock a local warehouse would need, at the company's current (excessive)
  -- cover level and at a healthy one. The gap between these two is itself an
  -- argument: opening a warehouse at today's buying habits ties up 3.5 years of
  -- stock in a second location.
  ROUND(t.items_last_12m * 3.5, 0)                      AS units_at_current_cover,
  ROUND(t.items_last_12m * 0.25, 0)                     AS units_at_90_day_cover,
  d.apac_median_hours,
  d.us_median_hours,
  d.apac_median_hours - d.us_median_hours               AS delivery_gap_hours,
  ROUND((d.apac_median_hours - d.us_median_hours) / 24.0, 1) AS delivery_gap_days
FROM trailing_year t
CROSS JOIN delivery_gap d;
