-- Northloom: star schema facts (step 4c)
-- Run after sql/warehouse/01_dimensions.sql.

-- ---------------------------------------------------------------------------
-- fact_order_items: one row per item sold. Everything that has to be true for
-- every revenue question is settled here, so no analysis query decides for
-- itself what counts as revenue.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `northloom_marts.fact_order_items`
PARTITION BY order_date
CLUSTER BY product_id, user_id AS
WITH order_sequence AS (
  -- Which order in the customer's life is this? Needed for new-versus-returning
  -- revenue, which the CEO's weekly review turns on (NL-111).
  SELECT
    user_id,
    order_id,
    MIN(order_date)                                    AS order_date,
    DENSE_RANK() OVER (PARTITION BY user_id ORDER BY MIN(order_date), order_id) AS order_seq
  FROM `northloom_staging.stg_order_items`
  WHERE NOT is_cancelled
  GROUP BY user_id, order_id
)
SELECT
  oi.order_item_id,
  oi.order_id,
  oi.user_id,
  oi.product_id,
  oi.inventory_item_id,
  oi.distribution_center_id,
  oi.order_date,
  oi.order_month,
  oi.order_ts,

  -- Order context. The sequence is built over orders that weren't cancelled,
  -- because a cancelled order never became a purchase (docs/business_context.md).
  -- That leaves cancelled items with no sequence number, so they get their own
  -- label rather than being lumped in with 'Returning'. Calling them Returning
  -- produced a spectacular false finding: a 35.4% cancellation rate for returning
  -- customers and 0.0% for new ones, which was purely this definition talking.
  oi.item_status,
  os.order_seq                                         AS customer_order_seq,
  os.order_seq = 1                                     AS is_first_order,
  CASE
    WHEN oi.is_cancelled  THEN 'Cancelled'
    WHEN os.order_seq = 1 THEN 'New'
    ELSE                       'Returning'
  END                                                  AS customer_type,

  -- Money, using the rules from docs/business_context.md
  oi.sale_price,
  oi.unit_cost,
  oi.gross_revenue,
  oi.net_revenue,
  oi.gross_margin,
  oi.discount_amount,
  oi.is_cancelled,
  oi.is_returned,
  oi.is_net_sale,
  -- Cancellations and returns cost different things: a cancellation loses the
  -- sale, a return loses the sale AND the cost of shipping it both ways.
  IF(oi.is_cancelled, oi.sale_price, 0)                AS revenue_lost_to_cancellation,
  IF(oi.is_returned,  oi.sale_price, 0)                AS revenue_lost_to_return,
  IF(oi.is_returned,  oi.sale_price - oi.unit_cost, 0) AS margin_lost_to_return,

  -- Fulfillment. hours_order_to_ship is null where the timestamp is impossible,
  -- so any average over it is automatically taken on valid rows only.
  oi.shipped_at,
  oi.delivered_at,
  oi.returned_at,
  oi.has_valid_ship_timeline,
  oi.hours_order_to_ship,
  oi.hours_ship_to_delivery,
  oi.hours_order_to_delivery,
  oi.days_delivered_to_return
FROM `northloom_staging.stg_order_items` oi
LEFT JOIN order_sequence os USING (user_id, order_id);

-- ---------------------------------------------------------------------------
-- fact_sessions: one row per website session.
--
-- Built at session grain on purpose. 46% of events have no user_id, so a
-- customer-level funnel would throw away half the traffic and overstate
-- conversion. Purchase events also match items, not orders, so a session that
-- buys three items fires three purchase events: counting events as conversions
-- would inflate the rate by the basket size.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `northloom_marts.fact_sessions`
PARTITION BY session_date
CLUSTER BY channel AS
SELECT
  e.session_id,
  DATE(MIN(e.event_ts))                                AS session_date,
  DATE_TRUNC(DATE(MIN(e.event_ts)), MONTH)             AS session_month,
  MIN(e.event_ts)                                      AS session_start_ts,
  MAX(e.event_ts)                                      AS session_end_ts,
  TIMESTAMP_DIFF(MAX(e.event_ts), MIN(e.event_ts), SECOND) AS session_seconds,

  -- A session belongs to the channel it arrived on, so the first event wins.
  MIN_BY(e.channel, e.sequence_number)                 AS channel,
  MIN_BY(e.channel_is_paid, e.sequence_number)         AS channel_is_paid,
  MIN_BY(e.browser, e.sequence_number)                 AS browser,
  MIN_BY(e.state, e.sequence_number)                   AS state,
  MIN_BY(e.city, e.sequence_number)                    AS city,

  -- Anonymous sessions still count in the funnel; they just can't be tied to a
  -- customer for attribution.
  MAX(e.user_id)                                       AS user_id,
  LOGICAL_OR(e.is_signed_in)                           AS is_signed_in,

  COUNT(*)                                             AS event_count,
  MAX(e.funnel_step)                                   AS max_funnel_step,
  LOGICAL_OR(e.event_type = 'home')                    AS reached_home,
  LOGICAL_OR(e.event_type = 'department')              AS reached_department,
  LOGICAL_OR(e.event_type = 'product')                 AS reached_product,
  LOGICAL_OR(e.event_type = 'cart')                    AS reached_cart,
  LOGICAL_OR(e.event_type = 'purchase')                AS reached_purchase,
  LOGICAL_OR(e.event_type = 'cancel')                  AS had_cancel_event,
  -- One conversion per session, however many items were bought.
  IF(LOGICAL_OR(e.event_type = 'purchase'), 1, 0)      AS converted,
  COUNTIF(e.event_type = 'purchase')                   AS items_purchased
FROM `northloom_staging.stg_events` e
GROUP BY e.session_id;

-- ---------------------------------------------------------------------------
-- fact_inventory_snapshot: stock position as at the analysis date, by product
-- and warehouse. The grain answers the supply chain question directly (NL-104):
-- what have we got, where is it, how long has it sat, and what is it costing us.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE `northloom_marts.fact_inventory_snapshot` AS
WITH cfg AS (SELECT * FROM `northloom_staging.analysis_config`),
-- Demand over the trailing 90 days is what turns stock into days of cover.
recent_demand AS (
  SELECT
    product_id,
    distribution_center_id,
    COUNT(*)                                           AS units_sold_90d,
    ROUND(SUM(net_revenue), 2)                         AS net_revenue_90d
  FROM `northloom_staging.stg_order_items`, cfg
  WHERE is_net_sale
    AND order_date > DATE_SUB(cfg.as_of_date, INTERVAL 90 DAY)
  GROUP BY product_id, distribution_center_id
),
stock AS (
  SELECT
    product_id,
    distribution_center_id,
    COUNTIF(is_on_hand)                                AS units_on_hand,
    ROUND(SUM(IF(is_on_hand, unit_cost, 0)), 2)        AS stock_value_at_cost,
    ROUND(AVG(IF(is_on_hand, days_in_stock, NULL)), 0) AS avg_days_in_stock,
    COUNTIF(NOT is_on_hand)                            AS units_sold_lifetime
  FROM `northloom_staging.stg_inventory_items`
  GROUP BY product_id, distribution_center_id
)
SELECT
  (SELECT as_of_date FROM cfg)                         AS snapshot_date,
  s.product_id,
  s.distribution_center_id,
  s.units_on_hand,
  s.stock_value_at_cost,
  s.avg_days_in_stock,
  s.units_sold_lifetime,
  COALESCE(d.units_sold_90d, 0)                        AS units_sold_90d,
  COALESCE(d.net_revenue_90d, 0)                       AS net_revenue_90d,
  ROUND(SAFE_DIVIDE(COALESCE(d.units_sold_90d, 0), 90), 3) AS avg_daily_demand,
  -- Days of cover: at the current rate of sale, how long until it runs out.
  -- Null means nothing sold in 90 days, which is its own problem: dead stock.
  ROUND(SAFE_DIVIDE(s.units_on_hand, SAFE_DIVIDE(NULLIF(d.units_sold_90d, 0), 90)), 1) AS days_of_cover,
  CASE
    WHEN s.units_on_hand = 0                           THEN 'Out of stock'
    WHEN d.units_sold_90d IS NULL                      THEN 'Dead stock'
    WHEN SAFE_DIVIDE(s.units_on_hand, SAFE_DIVIDE(d.units_sold_90d, 90)) < 14  THEN 'Stockout risk'
    WHEN SAFE_DIVIDE(s.units_on_hand, SAFE_DIVIDE(d.units_sold_90d, 90)) > 180 THEN 'Overstocked'
    ELSE 'Healthy'
  END                                                  AS stock_status
FROM stock s
LEFT JOIN recent_demand d USING (product_id, distribution_center_id);
