-- NL-108 | CFO / Head of Buying
-- "Returns are killing us. Which categories and brands have the worst return
--  rates, and how much margin are we losing?"
--
-- Technique: CTEs with conditional aggregation, window functions for share of
-- total and ranking, plus a cohort-style check on what a return does to the
-- customer relationship.
-- Grain of the result: one row per category, then one per return experience.
--
-- Return rate is measured against items SHIPPED, not items ordered: a cancelled
-- item never left the warehouse and cannot be returned, so including cancellations
-- in the denominator would flatter every category equally.
--
-- Northloom does not discount (all items sell at list price), so margin is decided
-- by product mix, cancellations and returns alone. That makes this the main lever
-- the CFO actually has.

CREATE OR REPLACE VIEW `northloom_marts.vw_returns_by_product` AS
SELECT
  p.category,
  p.department,
  p.brand,
  p.price_band,
  f.product_id,
  p.product_name,
  COUNTIF(NOT f.is_cancelled)                           AS items_shipped,
  COUNTIF(f.is_returned)                                AS items_returned,
  COUNTIF(f.is_cancelled)                               AS items_cancelled,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(f.is_returned), NULLIF(COUNTIF(NOT f.is_cancelled), 0)), 1) AS return_rate_pct,
  ROUND(SUM(f.net_revenue), 2)                          AS net_revenue,
  ROUND(SUM(f.gross_margin), 2)                         AS gross_margin,
  ROUND(SUM(f.revenue_lost_to_return), 2)               AS revenue_lost_to_return,
  ROUND(SUM(f.margin_lost_to_return), 2)                AS margin_lost_to_return,
  ROUND(SUM(f.revenue_lost_to_cancellation), 2)         AS revenue_lost_to_cancellation,
  ROUND(AVG(f.days_delivered_to_return), 1)             AS avg_days_to_return
FROM `northloom_marts.fact_order_items` f
JOIN `northloom_marts.dim_products` p USING (product_id)
GROUP BY p.category, p.department, p.brand, p.price_band, f.product_id, p.product_name;

-- ---------------------------------------------------------------------------
-- Result 1: where the money actually leaks, by category.
--
-- Ranked by margin lost, not by return rate. A 20% return rate on a category
-- selling $3,000 a year is a rounding error; a 9% rate on the biggest category
-- is the real problem. Rate tells you where the customer experience is worst,
-- lost margin tells you where to spend management attention.
-- ---------------------------------------------------------------------------
SELECT
  category,
  department,
  SUM(items_shipped)                                    AS items_shipped,
  SUM(items_returned)                                   AS items_returned,
  ROUND(100 * SAFE_DIVIDE(SUM(items_returned), NULLIF(SUM(items_shipped), 0)), 1) AS return_rate_pct,
  ROUND(SUM(net_revenue), 0)                            AS net_revenue,
  ROUND(SUM(gross_margin), 0)                           AS gross_margin,
  ROUND(SUM(margin_lost_to_return), 0)                  AS margin_lost_to_return,
  ROUND(SUM(revenue_lost_to_cancellation), 0)           AS revenue_lost_to_cancellation,
  -- What share of this category's potential margin never lands?
  ROUND(100 * SAFE_DIVIDE(SUM(margin_lost_to_return),
                          NULLIF(SUM(gross_margin) + SUM(margin_lost_to_return), 0)), 1) AS pct_of_margin_lost,
  -- Share of the company's total return losses, so the CFO can size the prize.
  ROUND(100 * SAFE_DIVIDE(SUM(margin_lost_to_return),
                          SUM(SUM(margin_lost_to_return)) OVER ()), 1) AS pct_of_all_return_losses,
  RANK() OVER (ORDER BY SUM(margin_lost_to_return) DESC) AS leakage_rank
FROM `northloom_marts.vw_returns_by_product`
GROUP BY category, department
ORDER BY margin_lost_to_return DESC;

-- ---------------------------------------------------------------------------
-- Result 2: what a return does to the customer relationship.
--
-- The RFM work (NL-102) showed churned customers return 9.6% of what they buy
-- against 4.9% for the best customers. That is a correlation with the direction
-- unknown: do returns drive people away, or do disengaged people return more?
--
-- This tests the causal direction the business can act on: among customers whose
-- FIRST order is old enough to have had a year, did returning an item from that
-- first order change whether they came back?
-- ---------------------------------------------------------------------------
WITH cfg AS (SELECT * FROM `northloom_staging.analysis_config`),

first_orders AS (
  SELECT
    user_id,
    order_id,
    MIN(order_date)                                     AS first_order_date,
    -- The experience they had on that first order
    LOGICAL_OR(is_returned)                             AS returned_something,
    -- What they paid at the till. net_revenue zeroes out returned items, so using
    -- it here reported $0.00 as the average order value of every customer who
    -- returned something, which is the price of the return, not of the order.
    SUM(sale_price)                                     AS first_order_revenue,
    COUNT(*)                                            AS first_order_items
  FROM `northloom_marts.fact_order_items`
  WHERE NOT is_cancelled
  GROUP BY user_id, order_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY MIN(order_date), order_id) = 1
),

later_orders AS (
  SELECT
    fo.user_id,
    COUNTIF(f.order_date > fo.first_order_date
            AND f.order_date <= DATE_ADD(fo.first_order_date, INTERVAL 365 DAY)) > 0 AS came_back_within_a_year
  FROM first_orders fo
  JOIN `northloom_marts.fact_order_items` f USING (user_id)
  WHERE f.is_net_sale
  GROUP BY fo.user_id
)

SELECT
  IF(fo.returned_something, 'Returned an item on first order', 'Kept everything on first order') AS first_order_experience,
  COUNT(*)                                              AS customers,
  ROUND(AVG(fo.first_order_revenue), 2)                 AS avg_first_order_value,
  COUNTIF(lo.came_back_within_a_year)                   AS came_back_within_a_year,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(lo.came_back_within_a_year), COUNT(*)), 1) AS repeat_rate_pct
FROM first_orders fo
JOIN later_orders lo USING (user_id)
CROSS JOIN cfg
-- Only customers who have had a full year to come back.
WHERE DATE_ADD(fo.first_order_date, INTERVAL 365 DAY) <= cfg.last_complete_month_end
GROUP BY first_order_experience
ORDER BY first_order_experience;
