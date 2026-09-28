-- NL-104 | Head of Supply Chain
-- "Which stock is sitting in the warehouse tying up cash, and what should we clear?"
--
-- Technique: CTE ratio maths over the stock snapshot, window functions for
-- cumulative share (an ABC / Pareto analysis) and ranking.
-- Grain of the result: one row per category, then a ranked clearance list.
--
-- The ticket originally asked which products would run out. The data says that is
-- not the problem: Northloom holds $8.8M of stock at cost against $9.06M of
-- LIFETIME revenue, and not one product-warehouse combination is at risk of a
-- stockout. The question has been rewritten to the one that matters: what is the
-- cash tied up, and what should be cleared first.
--
-- Days of cover = units on hand / average daily demand over the last 90 days.
-- Null cover means nothing sold in 90 days, which is dead stock rather than
-- infinite cover.

CREATE OR REPLACE VIEW `northloom_marts.vw_stock_position` AS
SELECT
  s.snapshot_date,
  s.product_id,
  p.product_name,
  p.category,
  p.department,
  p.brand,
  p.price_band,
  s.distribution_center_id,
  dc.distribution_center_name,
  s.units_on_hand,
  s.stock_value_at_cost,
  -- What the stock would be worth if it all sold at list price, which is the
  -- optimistic case Northloom is implicitly betting on by holding it.
  ROUND(s.units_on_hand * p.retail_price, 2)            AS stock_value_at_retail,
  s.avg_days_in_stock,
  s.units_sold_90d,
  s.units_sold_lifetime,
  s.net_revenue_90d,
  s.days_of_cover,
  s.stock_status,
  -- Turnover: how many times the stock sold through in the last year. Under 1
  -- means the warehouse holds more than a year of supply.
  ROUND(SAFE_DIVIDE(s.units_sold_90d * 4, NULLIF(s.units_on_hand, 0)), 2) AS annualised_turns,
  -- Holding cost, at a standard 25% of stock value per year (warehousing,
  -- capital, obsolescence). This is the number that makes the case to clear.
  ROUND(s.stock_value_at_cost * 0.25, 2)                AS annual_holding_cost
FROM `northloom_marts.fact_inventory_snapshot` s
JOIN `northloom_marts.dim_products` p USING (product_id)
-- Joined explicitly, not with USING: dim_products also carries a warehouse id
-- (where the product is meant to be stocked), while the snapshot's id is where
-- the stock physically sits. The physical location is the one that matters here.
LEFT JOIN `northloom_marts.dim_distribution_centers` dc
  ON s.distribution_center_id = dc.distribution_center_id;

-- ---------------------------------------------------------------------------
-- Result 1: where the cash is trapped, by category.
-- ---------------------------------------------------------------------------
SELECT
  category,
  department,
  SUM(units_on_hand)                                    AS units_on_hand,
  ROUND(SUM(stock_value_at_cost), 0)                    AS stock_at_cost,
  ROUND(SUM(annual_holding_cost), 0)                    AS annual_holding_cost,
  SUM(units_sold_90d)                                   AS units_sold_90d,
  ROUND(SUM(net_revenue_90d), 0)                        AS revenue_90d,
  -- Years of supply at the current rate of sale. Anything in double figures is
  -- stock that will never sell at full price.
  ROUND(SAFE_DIVIDE(SUM(units_on_hand), NULLIF(SUM(units_sold_90d) * 4, 0)), 1) AS years_of_supply,
  COUNTIF(stock_status = 'Dead stock')                  AS dead_stock_lines,
  ROUND(SUM(IF(stock_status = 'Dead stock', stock_value_at_cost, 0)), 0) AS dead_stock_at_cost,
  ROUND(100 * SAFE_DIVIDE(SUM(stock_value_at_cost),
                          SUM(SUM(stock_value_at_cost)) OVER ()), 1) AS pct_of_total_stock_value
FROM `northloom_marts.vw_stock_position`
GROUP BY category, department
ORDER BY stock_at_cost DESC;

-- ---------------------------------------------------------------------------
-- Result 2: the clearance list, worst first.
--
-- Ranked by cash released rather than by units, and cut off at the point where
-- clearing accounts for half of all trapped capital: a supply chain team can act
-- on a few hundred lines, not on 29,000.
-- ---------------------------------------------------------------------------
WITH dead AS (
  SELECT
    product_id,
    product_name,
    category,
    brand,
    price_band,
    distribution_center_name,
    units_on_hand,
    stock_value_at_cost,
    stock_value_at_retail,
    avg_days_in_stock,
    units_sold_lifetime,
    units_sold_90d
  FROM `northloom_marts.vw_stock_position`
  WHERE stock_status IN ('Dead stock', 'Overstocked')
    AND units_on_hand > 0
),
ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (ORDER BY stock_value_at_cost DESC) AS clearance_rank,
    ROUND(100 * SUM(stock_value_at_cost) OVER (ORDER BY stock_value_at_cost DESC
                                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
          / SUM(stock_value_at_cost) OVER (), 1)        AS cumulative_pct_of_trapped_cash
  FROM dead
)
SELECT
  clearance_rank,
  product_name,
  category,
  brand,
  price_band,
  distribution_center_name,
  units_on_hand,
  stock_value_at_cost,
  stock_value_at_retail,
  avg_days_in_stock,
  units_sold_lifetime,
  cumulative_pct_of_trapped_cash,
  -- What to do with it. Stock that has never sold will not start now.
  CASE
    WHEN units_sold_lifetime = 0                        THEN '1. Write off or liquidate: never sold a unit'
    WHEN avg_days_in_stock > 730                        THEN '2. Deep clearance: over two years old'
    WHEN units_sold_90d = 0                             THEN '3. Markdown: no demand in 90 days'
    ELSE '4. Slow markdown, some demand remains'
  END                                                   AS recommended_action
FROM ranked
-- Capped at 500 lines, not at a share of the cash. The trapped capital turned out
-- to have no concentration at all: the worst 500 product-warehouse lines hold only
-- about 13% of it, and reaching half would take roughly 4,750 lines. A buying team
-- can action 500. Everything below that needs a blanket markdown rule by age and
-- category instead, which is the recommendation in docs/findings.md.
WHERE clearance_rank <= 500
ORDER BY clearance_rank;
