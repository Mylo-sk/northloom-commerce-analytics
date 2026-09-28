-- Northloom: data quality checks over the raw layer
-- Run before trusting any analysis. Returns one tall result: check / severity /
-- failing_rows / note. Export as CSV; findings and their handling go in docs/data_quality.md.
--
-- severity: BLOCKER = fix before analysis, WATCH = state the caveat, INFO = context only.

WITH
-- 1. Referential integrity: do the joins in the star schema actually hold?
orphan_items_order AS (
  SELECT 'orphan: order_item without order' AS check_name, 'BLOCKER' AS severity,
         COUNT(*) AS failing_rows, 'order_items.order_id missing from orders' AS note
  FROM `northloom_raw.order_items` oi
  LEFT JOIN `northloom_raw.orders` o USING (order_id)
  WHERE o.order_id IS NULL
),
orphan_items_user AS (
  SELECT 'orphan: order_item without user', 'BLOCKER', COUNT(*), 'order_items.user_id missing from users'
  FROM `northloom_raw.order_items` oi
  LEFT JOIN `northloom_raw.users` u ON oi.user_id = u.id
  WHERE u.id IS NULL
),
orphan_items_product AS (
  SELECT 'orphan: order_item without product', 'BLOCKER', COUNT(*), 'order_items.product_id missing from products'
  FROM `northloom_raw.order_items` oi
  LEFT JOIN `northloom_raw.products` p ON oi.product_id = p.id
  WHERE p.id IS NULL
),
orphan_items_inventory AS (
  SELECT 'orphan: order_item without inventory unit', 'BLOCKER', COUNT(*), 'breaks true unit cost, so margin falls back to products.cost'
  FROM `northloom_raw.order_items` oi
  LEFT JOIN `northloom_raw.inventory_items` ii ON oi.inventory_item_id = ii.id
  WHERE ii.id IS NULL
),
orphan_product_dc AS (
  SELECT 'orphan: product without distribution center', 'WATCH', COUNT(*), 'products.distribution_center_id missing from distribution_centers'
  FROM `northloom_raw.products` p
  LEFT JOIN `northloom_raw.distribution_centers` dc ON p.distribution_center_id = dc.id
  WHERE dc.id IS NULL
),
orphan_event_user AS (
  SELECT 'events with no user_id (logged out)', 'INFO', COUNTIF(user_id IS NULL), 'anonymous sessions cannot be tied to a customer'
  FROM `northloom_raw.events`
),

-- 2. Uniqueness: are the keys really keys?
dup_keys AS (
  SELECT 'duplicate key: users.id' AS check_name, 'BLOCKER' AS severity,
         (SELECT COUNT(*) FROM (SELECT id FROM `northloom_raw.users` GROUP BY id HAVING COUNT(*) > 1)) AS failing_rows,
         'grain check' AS note
  UNION ALL SELECT 'duplicate key: orders.order_id', 'BLOCKER',
         (SELECT COUNT(*) FROM (SELECT order_id FROM `northloom_raw.orders` GROUP BY order_id HAVING COUNT(*) > 1)), 'grain check'
  UNION ALL SELECT 'duplicate key: order_items.id', 'BLOCKER',
         (SELECT COUNT(*) FROM (SELECT id FROM `northloom_raw.order_items` GROUP BY id HAVING COUNT(*) > 1)), 'fact table grain'
  UNION ALL SELECT 'duplicate key: products.id', 'BLOCKER',
         (SELECT COUNT(*) FROM (SELECT id FROM `northloom_raw.products` GROUP BY id HAVING COUNT(*) > 1)), 'grain check'
  UNION ALL SELECT 'duplicate key: inventory_items.id', 'BLOCKER',
         (SELECT COUNT(*) FROM (SELECT id FROM `northloom_raw.inventory_items` GROUP BY id HAVING COUNT(*) > 1)), 'grain check'
  UNION ALL SELECT 'inventory unit sold more than once', 'BLOCKER',
         (SELECT COUNT(*) FROM (SELECT inventory_item_id FROM `northloom_raw.order_items` GROUP BY inventory_item_id HAVING COUNT(*) > 1)), 'one physical unit should sell once'
),

-- 3. Business rules: does the order header agree with its lines?
header_vs_lines AS (
  SELECT 'order.num_of_item disagrees with line count' AS check_name, 'WATCH' AS severity,
         COUNT(*) AS failing_rows, 'header and lines out of step' AS note
  FROM (
    SELECT o.order_id, o.num_of_item, COUNT(oi.id) AS line_count
    FROM `northloom_raw.orders` o
    LEFT JOIN `northloom_raw.order_items` oi USING (order_id)
    GROUP BY o.order_id, o.num_of_item
  )
  WHERE num_of_item != line_count
),
status_mismatch AS (
  SELECT 'order status disagrees with all its line statuses', 'WATCH', COUNT(*), 'decides whether revenue uses header or line status'
  FROM (
    SELECT o.order_id
    FROM `northloom_raw.orders` o
    JOIN `northloom_raw.order_items` oi USING (order_id)
    GROUP BY o.order_id, o.status
    HAVING COUNTIF(oi.status = o.status) = 0
  )
),

-- 4. Timestamp logic: can the fulfillment timeline be trusted? (NL-110)
timestamp_logic AS (
  SELECT 'shipped before ordered' AS check_name, 'BLOCKER' AS severity,
         COUNTIF(shipped_at < created_at) AS failing_rows, 'breaks time-to-ship' AS note
  FROM `northloom_raw.order_items`
  UNION ALL SELECT 'delivered before shipped', 'BLOCKER',
         COUNTIF(delivered_at < shipped_at), 'breaks time-to-deliver'
  FROM `northloom_raw.order_items`
  UNION ALL SELECT 'returned before delivered', 'WATCH',
         COUNTIF(returned_at < delivered_at), 'return logged before arrival'
  FROM `northloom_raw.order_items`
  UNION ALL SELECT 'status Returned but no returned_at', 'WATCH',
         COUNTIF(status = 'Returned' AND returned_at IS NULL), 'return date needed for return-window analysis'
  FROM `northloom_raw.order_items`
  UNION ALL SELECT 'returned_at set but status is not Returned', 'WATCH',
         COUNTIF(returned_at IS NOT NULL AND status != 'Returned'), 'conflicting return signals'
  FROM `northloom_raw.order_items`
  UNION ALL SELECT 'status Cancelled but shipped anyway', 'WATCH',
         COUNTIF(status = 'Cancelled' AND shipped_at IS NOT NULL), 'cancelled goods that still left the warehouse'
  FROM `northloom_raw.order_items`
  UNION ALL SELECT 'stock unit sold before it arrived', 'WATCH',
         COUNTIF(sold_at < created_at), 'inventory_items.sold_at before created_at'
  FROM `northloom_raw.inventory_items`
),

-- 5. Future-dated rows: the public dataset seeds rows ahead of today (as_of_date = 2026-09-17)
future_dated AS (
  SELECT 'future-dated order_items' AS check_name, 'BLOCKER' AS severity,
         COUNTIF(created_at > TIMESTAMP('2026-09-17 23:59:59')) AS failing_rows,
         'excluded by the as_of_date filter' AS note
  FROM `northloom_raw.order_items`
  UNION ALL SELECT 'future-dated events', 'BLOCKER',
         COUNTIF(created_at > TIMESTAMP('2026-09-17 23:59:59')), 'excluded by the as_of_date filter'
  FROM `northloom_raw.events`
  UNION ALL SELECT 'future-dated order_items without a parent order', 'INFO',
         COUNT(*), 'orders has no future rows but order_items does, so these lines are parentless'
  FROM `northloom_raw.order_items` oi
  LEFT JOIN `northloom_raw.orders` o USING (order_id)
  WHERE oi.created_at > TIMESTAMP('2026-09-17 23:59:59') AND o.order_id IS NULL
),

-- 6. Money: are prices and costs believable? (margin work, NL-108)
money_checks AS (
  SELECT 'sale_price is zero or negative' AS check_name, 'BLOCKER' AS severity,
         COUNTIF(sale_price <= 0) AS failing_rows, 'would distort revenue' AS note
  FROM `northloom_raw.order_items`
  UNION ALL SELECT 'product retail_price under $1', 'WATCH',
         COUNTIF(retail_price < 1), 'the $0.02 low end found in profiling'
  FROM `northloom_raw.products`
  UNION ALL SELECT 'product cost above retail price', 'WATCH',
         COUNTIF(cost > retail_price), 'sold at a loss at list price'
  FROM `northloom_raw.products`
  UNION ALL SELECT 'product cost is null or zero', 'WATCH',
         COUNTIF(cost IS NULL OR cost = 0), 'no cost means no margin'
  FROM `northloom_raw.products`
  UNION ALL SELECT 'sale_price more than double retail price', 'WATCH',
         COUNT(*), 'sold well above list, which suggests a pricing error'
  FROM `northloom_raw.order_items` oi
  JOIN `northloom_raw.products` p ON oi.product_id = p.id
  WHERE oi.sale_price > 2 * p.retail_price
),

-- 7. Dimension consistency: the copied product details on inventory_items
dimension_drift AS (
  SELECT 'inventory_items product details disagree with products' AS check_name, 'WATCH' AS severity,
         COUNT(*) AS failing_rows, 'why products is the single source for the marts' AS note
  FROM `northloom_raw.inventory_items` ii
  JOIN `northloom_raw.products` p ON ii.product_id = p.id
  WHERE ii.product_category != p.category OR ii.product_brand != p.brand OR ii.product_department != p.department
),

-- 8. Dirty dimension values: country names arrive in more than one language (NL-112)
country_variants AS (
  SELECT 'country values needing cleanup' AS check_name, 'WATCH' AS severity,
         COUNTIF(country IN ('Brasil', 'Deutschland', 'España', 'Espana')) AS failing_rows,
         'local-language spellings sit next to English ones' AS note
  FROM `northloom_raw.users`
  UNION ALL SELECT 'countries with under 50 customers', 'INFO',
         (SELECT COUNT(*) FROM (SELECT country FROM `northloom_raw.users` GROUP BY country HAVING COUNT(*) < 50)),
         'tiny country counts are usually typos or test data'
),

-- 9. Missing dimension values
null_dims AS (
  SELECT 'products with null category or brand' AS check_name, 'WATCH' AS severity,
         COUNTIF(category IS NULL OR brand IS NULL) AS failing_rows, 'would drop out of category reporting' AS note
  FROM `northloom_raw.products`
  UNION ALL SELECT 'users with null country', 'WATCH', COUNTIF(country IS NULL), 'would drop out of market reporting'
  FROM `northloom_raw.users`
  UNION ALL SELECT 'events with null session_id', 'WATCH', COUNTIF(session_id IS NULL), 'breaks session-level funnel work'
  FROM `northloom_raw.events`
),

-- 10. Funnel sanity: purchase events should line up with order items (NL-109)
funnel_check AS (
  SELECT 'purchase events vs order_items rows' AS check_name, 'INFO' AS severity,
         (SELECT COUNTIF(event_type = 'purchase') FROM `northloom_raw.events`)
         - (SELECT COUNT(*) FROM `northloom_raw.order_items`) AS failing_rows,
         'difference between the two counts; 0 means one purchase event per item sold' AS note
)

SELECT * FROM orphan_items_order
UNION ALL SELECT * FROM orphan_items_user
UNION ALL SELECT * FROM orphan_items_product
UNION ALL SELECT * FROM orphan_items_inventory
UNION ALL SELECT * FROM orphan_product_dc
UNION ALL SELECT * FROM orphan_event_user
UNION ALL SELECT * FROM dup_keys
UNION ALL SELECT * FROM header_vs_lines
UNION ALL SELECT * FROM status_mismatch
UNION ALL SELECT * FROM timestamp_logic
UNION ALL SELECT * FROM future_dated
UNION ALL SELECT * FROM money_checks
UNION ALL SELECT * FROM dimension_drift
UNION ALL SELECT * FROM country_variants
UNION ALL SELECT * FROM null_dims
UNION ALL SELECT * FROM funnel_check
ORDER BY severity, failing_rows DESC;
