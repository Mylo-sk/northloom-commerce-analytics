-- NL-109 | Head of Ecommerce
-- "Where do we lose shoppers between landing and checkout, and does it differ by
--  channel or device?"
--
-- Technique: session-grain funnel from the clickstream fact, with step-to-step
-- drop-off, then the same funnel cut by channel and browser.
-- Grain of the result: one row per funnel step, then one per channel, one per
-- browser.
--
-- Three things to hold on to while reading it:
--   1. Counted per SESSION, never per event. A session that buys three items
--      fires three purchase events, so counting events would inflate conversion
--      by the basket size.
--   2. 46% of events have no customer attached, so this is the whole audience,
--      signed in or not. That is the right choice for a funnel and the wrong one
--      for attribution (NL-105).
--   3. The absolute rate is not believable. Northloom's sessions convert at 26%,
--      where real fashion retail runs at 2-3%. The clickstream is synthetic and
--      too generous. COMPARE the steps and the channels against each other;
--      never quote the headline number.

CREATE OR REPLACE VIEW `northloom_marts.vw_funnel_sessions` AS
SELECT
  s.session_id,
  s.session_date,
  s.session_month,
  s.channel,
  s.channel_is_paid,
  s.browser,
  s.is_signed_in,
  s.user_id,
  s.event_count,
  s.session_seconds,
  s.reached_home,
  s.reached_department,
  s.reached_product,
  s.reached_cart,
  s.reached_purchase,
  s.had_cancel_event,
  s.items_purchased,
  -- The deepest point the session got to, which is what makes drop-off countable.
  CASE
    WHEN s.reached_purchase   THEN 5
    WHEN s.reached_cart       THEN 4
    WHEN s.reached_product    THEN 3
    WHEN s.reached_department THEN 2
    ELSE                           1
  END                                                   AS deepest_step,
  CASE
    WHEN s.reached_purchase   THEN '5. Purchased'
    WHEN s.reached_cart       THEN '4. Abandoned at cart'
    WHEN s.reached_product    THEN '3. Left after viewing a product'
    WHEN s.reached_department THEN '2. Left after browsing a department'
    ELSE                           '1. Left from the landing page'
  END                                                   AS where_they_left
FROM `northloom_marts.fact_sessions` s;

-- ---------------------------------------------------------------------------
-- Result 1: how many sessions reach each step, and DOES THE FUNNEL NEST?
--
-- The first version of this query assumed the obvious thing: that a shopper goes
-- landing, department, product, cart, purchase, and that each step is a subset of
-- the one before. It reported a drop-off of MINUS 58.1% between department and
-- product, because 100% of sessions view a product while only 63% view a
-- department. A negative drop-off is impossible, and it means the assumption was
-- wrong, not the data.
--
-- So this version measures reach per step independently and then tests the
-- nesting directly. Any "impossible path" count above zero means a conventional
-- funnel chart of this data would be fiction, and the step-to-step conversion
-- rates everyone wants would be meaningless.
-- ---------------------------------------------------------------------------
WITH s AS (SELECT * FROM `northloom_marts.vw_funnel_sessions`),
reach AS (
  SELECT '1. Sessions'             AS measure, COUNT(*)                     AS sessions FROM s
  UNION ALL SELECT '2. Viewed a department', COUNTIF(reached_department)     FROM s
  UNION ALL SELECT '3. Viewed a product',    COUNTIF(reached_product)        FROM s
  UNION ALL SELECT '4. Added to cart',       COUNTIF(reached_cart)           FROM s
  UNION ALL SELECT '5. Purchased',           COUNTIF(reached_purchase)       FROM s
),
path_integrity AS (
  SELECT 'CHECK: product viewed without a department first' AS measure,
         COUNTIF(reached_product AND NOT reached_department) FROM s
  UNION ALL SELECT 'CHECK: cart without ever viewing a product',
         COUNTIF(reached_cart AND NOT reached_product) FROM s
  UNION ALL SELECT 'CHECK: purchase without ever adding to cart',
         COUNTIF(reached_purchase AND NOT reached_cart) FROM s
  UNION ALL SELECT 'CHECK: purchase without viewing a department',
         COUNTIF(reached_purchase AND NOT reached_department) FROM s
  UNION ALL SELECT 'CHECK: sessions longer than 8 hours (not real sessions)',
         COUNTIF(session_seconds > 8 * 3600) FROM s
)
SELECT
  measure,
  sessions,
  ROUND(100 * SAFE_DIVIDE(sessions, (SELECT COUNT(*) FROM s)), 1) AS pct_of_all_sessions
FROM (SELECT * FROM reach UNION ALL SELECT * FROM path_integrity)
ORDER BY measure;

-- ---------------------------------------------------------------------------
-- Result 2: does the funnel behave differently by channel?
--
-- A channel that fills the top of the funnel but converts badly is buying the
-- wrong traffic. Set against NL-105: channels all produce customers worth about
-- $120, so a conversion gap here is the only quality difference that exists.
-- ---------------------------------------------------------------------------
SELECT
  channel,
  channel_is_paid,
  COUNT(*)                                              AS sessions,
  ROUND(100 * SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()), 1) AS pct_of_traffic,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(reached_product), COUNT(*)), 1)  AS pct_reaching_product,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(reached_cart), COUNT(*)), 1)     AS pct_reaching_cart,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(reached_purchase), COUNT(*)), 1) AS conversion_pct,
  -- Cart to purchase is where checkout problems show up, as opposed to traffic
  -- quality problems, which show up higher in the funnel.
  ROUND(100 * SAFE_DIVIDE(COUNTIF(reached_purchase), NULLIF(COUNTIF(reached_cart), 0)), 1) AS cart_to_purchase_pct,
  ROUND(AVG(event_count), 1)                            AS avg_pages_viewed,
  ROUND(AVG(session_seconds) / 60, 1)                   AS avg_minutes_on_site,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(is_signed_in), COUNT(*)), 1) AS pct_signed_in,
  -- Distance from the site average, so a real difference is obvious.
  ROUND(100 * SAFE_DIVIDE(COUNTIF(reached_purchase), COUNT(*))
        - 100 * SAFE_DIVIDE(SUM(COUNTIF(reached_purchase)) OVER (), SUM(COUNT(*)) OVER ()), 1) AS conversion_vs_site_avg_pts
FROM `northloom_marts.vw_funnel_sessions`
GROUP BY channel, channel_is_paid
ORDER BY sessions DESC;

-- ---------------------------------------------------------------------------
-- Result 3: by browser, which is the closest thing to a device signal here, and
-- where they gave up.
--
-- A browser converting well below the rest is usually a broken checkout on that
-- platform, and it is the cheapest fix in this entire project if it exists.
-- ---------------------------------------------------------------------------
SELECT
  browser,
  COUNT(*)                                              AS sessions,
  ROUND(100 * SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()), 1) AS pct_of_traffic,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(reached_purchase), COUNT(*)), 1) AS conversion_pct,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(reached_purchase), NULLIF(COUNTIF(reached_cart), 0)), 1) AS cart_to_purchase_pct,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(reached_purchase), COUNT(*))
        - 100 * SAFE_DIVIDE(SUM(COUNTIF(reached_purchase)) OVER (), SUM(COUNT(*)) OVER ()), 1) AS conversion_vs_site_avg_pts,
  -- Where the sessions that didn't buy gave up, as a share of that browser.
  ROUND(100 * SAFE_DIVIDE(COUNTIF(where_they_left = '1. Left from the landing page'), COUNT(*)), 1) AS pct_left_at_landing,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(where_they_left = '4. Abandoned at cart'), COUNT(*)), 1) AS pct_abandoned_at_cart
FROM `northloom_marts.vw_funnel_sessions`
GROUP BY browser
ORDER BY sessions DESC;
