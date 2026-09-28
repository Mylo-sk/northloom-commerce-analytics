-- NL-105 | CMO
-- "Finance wants to cut Facebook spend. Does Facebook bring in customers, or just
--  take credit for them?"
--
-- Technique: FIRST_VALUE() and LAST_VALUE() over each customer's session history,
-- partitioned by customer and ordered by time, to build first-touch and last-touch
-- attribution from the same data and compare them.
-- Grain of the result: one row per customer, then one per channel per model.
--
-- Three caveats that have to travel with this answer:
--   1. Only 26.5% of sessions are signed in, so attribution can only follow
--      customers who were logged in at some point. It covers the signed-in half
--      of the business and must not be reported as if it covered everyone.
--   2. There is no ad spend in the warehouse, so this shows where revenue should
--      be CREDITED, not return on investment. Cost per channel has to come from
--      the ad platforms before anyone cuts a budget.
--   3. Signup records and clickstream use different channel names, mapped to a
--      shared vocabulary in staging. That mapping is itself a finding: the two
--      systems could not previously be compared at all.

CREATE OR REPLACE VIEW `northloom_marts.vw_attribution_by_customer` AS
WITH first_purchase AS (
  SELECT
    user_id,
    MIN(order_date)                                     AS first_order_date,
    SUM(net_revenue)                                    AS lifetime_net_revenue,
    SUM(gross_margin)                                   AS lifetime_gross_margin,
    COUNT(DISTINCT order_id)                            AS lifetime_orders
  FROM `northloom_marts.fact_order_items`
  WHERE is_net_sale
  GROUP BY user_id
),

-- Every session a customer had on or before the day they first bought. Sessions
-- after the first purchase belong to retention, not acquisition.
acquisition_sessions AS (
  SELECT
    s.user_id,
    s.session_id,
    s.session_start_ts,
    s.channel,
    s.channel_is_paid,
    s.reached_purchase,
    fp.first_order_date
  FROM `northloom_marts.fact_sessions` s
  JOIN first_purchase fp USING (user_id)
  WHERE s.user_id IS NOT NULL
    AND s.session_date <= fp.first_order_date
),

touches AS (
  SELECT
    user_id,
    first_order_date,
    -- The channel that introduced the customer to Northloom.
    FIRST_VALUE(channel) OVER w                         AS first_touch_channel,
    -- The channel they came through immediately before buying.
    LAST_VALUE(channel) OVER w                          AS last_touch_channel,
    COUNT(*) OVER (PARTITION BY user_id)                AS sessions_before_purchase,
    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY session_start_ts) AS rn
  FROM acquisition_sessions
  WINDOW w AS (PARTITION BY user_id ORDER BY session_start_ts
               ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
)

SELECT
  t.user_id,
  t.first_order_date,
  t.first_touch_channel,
  t.last_touch_channel,
  t.first_touch_channel != t.last_touch_channel         AS models_disagree,
  t.sessions_before_purchase,
  fp.lifetime_net_revenue,
  fp.lifetime_gross_margin,
  fp.lifetime_orders,
  -- The CRM system's own answer, recorded at signup. A third opinion, and it
  -- agrees with neither model most of the time.
  c.signup_channel
FROM touches t
JOIN first_purchase fp USING (user_id)
LEFT JOIN `northloom_marts.dim_customers_current` c USING (user_id)
WHERE t.rn = 1;

-- ---------------------------------------------------------------------------
-- Result 1: the same revenue, credited three ways.
--
-- If the models agree, the channel mix is robust and the CMO can act on it. Where
-- they disagree, the disagreement IS the answer: a channel that looks strong on
-- last touch but weak on first touch is harvesting demand someone else created.
-- ---------------------------------------------------------------------------
WITH first_touch AS (
  SELECT 'First touch (who introduced them)' AS model, first_touch_channel AS channel,
         COUNT(*) AS customers_credited,
         ROUND(SUM(lifetime_net_revenue), 0) AS revenue_credited,
         ROUND(SUM(lifetime_gross_margin), 0) AS margin_credited
  FROM `northloom_marts.vw_attribution_by_customer`
  GROUP BY channel
),
last_touch AS (
  SELECT 'Last touch (who closed them)', last_touch_channel,
         COUNT(*), ROUND(SUM(lifetime_net_revenue), 0), ROUND(SUM(lifetime_gross_margin), 0)
  FROM `northloom_marts.vw_attribution_by_customer`
  GROUP BY last_touch_channel
),
signup AS (
  SELECT 'Signup record (what the CRM says)', signup_channel,
         COUNT(*), ROUND(SUM(lifetime_net_revenue), 0), ROUND(SUM(lifetime_gross_margin), 0)
  FROM `northloom_marts.vw_attribution_by_customer`
  GROUP BY signup_channel
),
combined AS (
  SELECT * FROM first_touch
  UNION ALL SELECT * FROM last_touch
  UNION ALL SELECT * FROM signup
)
SELECT
  model,
  channel,
  customers_credited,
  revenue_credited,
  margin_credited,
  ROUND(100 * SAFE_DIVIDE(revenue_credited, SUM(revenue_credited) OVER (PARTITION BY model)), 1) AS pct_of_revenue,
  ROUND(SAFE_DIVIDE(revenue_credited, NULLIF(customers_credited, 0)), 2) AS revenue_per_customer
FROM combined
ORDER BY model, revenue_credited DESC;

-- ---------------------------------------------------------------------------
-- Result 2: how often the two models disagree, and which channels gain or lose.
--
-- This is the number that settles the Facebook argument. A channel whose
-- last-touch credit far exceeds its first-touch credit is being paid for
-- finishing journeys that another channel started.
-- ---------------------------------------------------------------------------
WITH per_channel AS (
  SELECT
    channel,
    SUM(IF(model = 'First touch (who introduced them)', revenue, 0)) AS first_touch_revenue,
    SUM(IF(model = 'Last touch (who closed them)', revenue, 0))      AS last_touch_revenue
  FROM (
    SELECT 'First touch (who introduced them)' AS model, first_touch_channel AS channel, lifetime_net_revenue AS revenue
    FROM `northloom_marts.vw_attribution_by_customer`
    UNION ALL
    SELECT 'Last touch (who closed them)', last_touch_channel, lifetime_net_revenue
    FROM `northloom_marts.vw_attribution_by_customer`
  )
  GROUP BY channel
)
SELECT
  channel,
  ROUND(first_touch_revenue, 0)                         AS first_touch_revenue,
  ROUND(last_touch_revenue, 0)                          AS last_touch_revenue,
  ROUND(last_touch_revenue - first_touch_revenue, 0)    AS credit_gained_by_last_touch,
  ROUND(100 * SAFE_DIVIDE(last_touch_revenue - first_touch_revenue, NULLIF(first_touch_revenue, 0)), 1) AS pct_difference,
  CASE
    WHEN SAFE_DIVIDE(last_touch_revenue, NULLIF(first_touch_revenue, 0)) > 1.15 THEN 'Closer: harvests demand others created'
    WHEN SAFE_DIVIDE(last_touch_revenue, NULLIF(first_touch_revenue, 0)) < 0.85 THEN 'Introducer: undervalued by last-touch reporting'
    ELSE 'Balanced: does both jobs'
  END                                                   AS channel_role,
  (SELECT ROUND(100 * SAFE_DIVIDE(COUNTIF(models_disagree), COUNT(*)), 1)
   FROM `northloom_marts.vw_attribution_by_customer`)   AS pct_of_customers_where_models_disagree,
  (SELECT ROUND(AVG(sessions_before_purchase), 1)
   FROM `northloom_marts.vw_attribution_by_customer`)   AS avg_sessions_before_first_purchase
FROM per_channel
ORDER BY credit_gained_by_last_touch DESC;
