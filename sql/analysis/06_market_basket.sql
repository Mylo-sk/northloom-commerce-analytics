-- NL-106 | Merchandising Lead
-- "What do customers buy together? We want to build bundles and 'complete the
--  look' recommendations."
--
-- Technique: self-join of the sales fact to itself on order_id to build every
-- category pair in a basket, then support, confidence and lift.
-- Grain of the result: basket composition, then one row per category pair.
--
-- Set expectations before reading it: Northloom averages 1.44 items per order and
-- half of all orders are a single item. Basket analysis needs baskets. The first
-- result establishes how much co-purchase exists at all, because if the answer is
-- "very little" then no amount of lift maths will produce a bundle worth building.
--
-- Pairs are built at CATEGORY level, not product level. With 29,120 products and
-- few multi-item orders, product pairs would each be seen once or twice and every
-- lift score would be noise.

CREATE OR REPLACE VIEW `northloom_marts.vw_basket_pairs` AS
WITH order_categories AS (
  -- One row per order per category. DISTINCT matters: two pairs of jeans in one
  -- order is not a Jeans-with-Jeans affinity.
  SELECT DISTINCT
    f.order_id,
    p.category
  FROM `northloom_marts.fact_order_items` f
  JOIN `northloom_marts.dim_products` p USING (product_id)
  WHERE f.is_net_sale
),
totals AS (
  SELECT COUNT(DISTINCT order_id) AS total_orders FROM order_categories
),
category_frequency AS (
  SELECT category, COUNT(DISTINCT order_id) AS orders_with_category
  FROM order_categories
  GROUP BY category
),
pairs AS (
  -- a.category < b.category gives each unordered pair once instead of twice.
  SELECT
    a.category                                          AS category_a,
    b.category                                          AS category_b,
    COUNT(DISTINCT a.order_id)                          AS orders_with_both
  FROM order_categories a
  JOIN order_categories b
    ON a.order_id = b.order_id
   AND a.category < b.category
  GROUP BY category_a, category_b
)
SELECT
  p.category_a,
  p.category_b,
  p.orders_with_both,
  fa.orders_with_category                               AS orders_with_a,
  fb.orders_with_category                               AS orders_with_b,
  t.total_orders,
  -- Support: how often this pair shows up at all. Tiny support means the pair is
  -- not worth a bundle however strong the association looks.
  ROUND(100 * SAFE_DIVIDE(p.orders_with_both, t.total_orders), 3) AS support_pct,
  -- Confidence: of the baskets containing A, how many also contain B.
  ROUND(100 * SAFE_DIVIDE(p.orders_with_both, fa.orders_with_category), 2) AS confidence_a_to_b_pct,
  -- How many pairings you'd expect if the two categories were bought completely
  -- independently of each other.
  ROUND(SAFE_DIVIDE(fa.orders_with_category * fb.orders_with_category, t.total_orders), 1) AS expected_if_unrelated,
  -- Lift: observed over expected. 1.0 is pure chance, above 1.2 is usually taken
  -- as a real affinity, below 0.8 means the two are bought together LESS than
  -- chance would predict.
  ROUND(SAFE_DIVIDE(
    SAFE_DIVIDE(p.orders_with_both, t.total_orders),
    SAFE_DIVIDE(fa.orders_with_category, t.total_orders) * SAFE_DIVIDE(fb.orders_with_category, t.total_orders)
  ), 2)                                                 AS lift
FROM pairs p
JOIN category_frequency fa ON fa.category = p.category_a
JOIN category_frequency fb ON fb.category = p.category_b
CROSS JOIN totals t;

-- ---------------------------------------------------------------------------
-- Result 1: is there a basket at all?
--
-- Read this before result 2. It decides whether the question is answerable.
-- ---------------------------------------------------------------------------
WITH order_size AS (
  SELECT
    order_id,
    COUNT(*)                                            AS items,
    COUNT(DISTINCT product_id)                          AS distinct_products,
    ROUND(SUM(net_revenue), 2)                          AS order_value
  FROM `northloom_marts.fact_order_items`
  WHERE is_net_sale
  GROUP BY order_id
)
SELECT
  CASE
    WHEN items = 1 THEN '1 item (no basket to analyse)'
    WHEN items = 2 THEN '2 items'
    WHEN items = 3 THEN '3 items'
    ELSE                '4 or more items'
  END                                                   AS basket_size,
  COUNT(*)                                              AS orders,
  ROUND(100 * SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()), 1) AS pct_of_orders,
  ROUND(AVG(order_value), 2)                            AS avg_order_value,
  ROUND(SUM(order_value), 0)                            AS net_revenue,
  ROUND(100 * SAFE_DIVIDE(SUM(order_value), SUM(SUM(order_value)) OVER ()), 1) AS pct_of_revenue
FROM order_size
GROUP BY basket_size
ORDER BY basket_size;

-- ---------------------------------------------------------------------------
-- Result 2: the pairs, strongest first.
--
-- Filtered to pairs seen at least 30 times, because a lift of 4.0 built on six
-- orders is a coincidence with a decimal point. The verdict column does the
-- interpreting so nobody reads noise as a recommendation.
-- ---------------------------------------------------------------------------
SELECT
  category_a,
  category_b,
  orders_with_both,
  expected_if_unrelated,
  support_pct,
  confidence_a_to_b_pct,
  lift,
  CASE
    WHEN lift >= 1.2 THEN 'Bought together more than chance — worth testing as a bundle'
    WHEN lift <= 0.8 THEN 'Bought together LESS than chance — these substitute for each other'
    ELSE                  'Indistinguishable from chance — no affinity'
  END                                                   AS verdict
FROM `northloom_marts.vw_basket_pairs`
WHERE orders_with_both >= 30
ORDER BY lift DESC, orders_with_both DESC
LIMIT 25;
