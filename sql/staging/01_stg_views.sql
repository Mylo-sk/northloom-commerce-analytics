-- Northloom: staging layer (step 4a) -- VIEW build, needs billing enabled
--
-- The BigQuery sandbox rejects views in a dataset with the mandatory 60-day
-- expiry, so use 01_stg_tables.sql until billing is linked. This version is the
-- one to run afterwards if you'd rather staging stay in step with raw automatically.
--
-- Views, not tables, so they stay in step with raw and cost nothing to store.
-- Everything agreed in docs/business_context.md and docs/data_quality.md is applied
-- here, once, so no analysis query re-invents a definition.
--
-- Run as one script in the BigQuery Console.

-- ---------------------------------------------------------------------------
-- analysis_config: the fixed analysis date, defined once
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW `northloom_staging.analysis_config` AS
SELECT
  DATE '2026-09-17'                    AS as_of_date,
  TIMESTAMP '2026-09-17 23:59:59'      AS as_of_ts,
  -- Monthly trends stop at the last complete month so a part-finished month
  -- doesn't look like a collapse in sales.
  DATE '2026-08-31'                    AS last_complete_month_end,
  DATE '2026-08-01'                    AS last_complete_month;

-- ---------------------------------------------------------------------------
-- stg_channel_map: one vocabulary for two systems that disagree
-- Signup records say Search/Display; clickstream says Adwords/YouTube.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW `northloom_staging.stg_channel_map` AS
SELECT * FROM UNNEST([
  STRUCT('Search'   AS source_value, 'users'  AS source_system, 'Paid Search'      AS channel, TRUE  AS is_paid),
  STRUCT('Adwords',  'events', 'Paid Search',     TRUE),
  STRUCT('Organic',  'users',  'Organic',         FALSE),
  STRUCT('Organic',  'events', 'Organic',         FALSE),
  STRUCT('Facebook', 'users',  'Paid Social',     TRUE),
  STRUCT('Facebook', 'events', 'Paid Social',     TRUE),
  STRUCT('Email',    'users',  'Email',           FALSE),
  STRUCT('Email',    'events', 'Email',           FALSE),
  STRUCT('Display',  'users',  'Display & Video', TRUE),
  STRUCT('YouTube',  'events', 'Display & Video', TRUE)
]);

-- ---------------------------------------------------------------------------
-- stg_users: customers, cleaned. Personal details are dropped here and never
-- reach the marts (email, street address).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW `northloom_staging.stg_users` AS
WITH cleaned AS (
  SELECT
    u.id                                    AS user_id,
    u.age,
    COALESCE(NULLIF(TRIM(u.gender), ''), 'Unknown') AS gender,
    -- Local-language spellings arrive alongside English ones (14,640 rows).
    CASE TRIM(u.country)
      WHEN 'Brasil'      THEN 'Brazil'
      WHEN 'Deutschland' THEN 'Germany'
      WHEN 'España'      THEN 'Spain'
      WHEN 'Espana'      THEN 'Spain'
      ELSE COALESCE(NULLIF(TRIM(u.country), ''), 'Unknown')
    END                                     AS country,
    u.state,
    u.city,
    u.postal_code,
    u.latitude,
    u.longitude,
    u.traffic_source                        AS signup_traffic_source_raw,
    u.created_at                            AS signup_ts,
    DATE(u.created_at)                      AS signup_date,
    DATE_TRUNC(DATE(u.created_at), MONTH)   AS signup_cohort_month
  FROM `northloom_raw.users` u
  CROSS JOIN `northloom_staging.analysis_config` cfg
  WHERE u.created_at <= cfg.as_of_ts
),
-- Countries with almost no customers are noise, not markets (Austria has 1).
country_size AS (
  SELECT country, COUNT(*) AS customer_count
  FROM cleaned GROUP BY country
)
SELECT
  c.* EXCEPT (signup_traffic_source_raw),
  COALESCE(m.channel, 'Unknown')            AS signup_channel,
  COALESCE(m.is_paid, FALSE)                AS signup_channel_is_paid,
  CASE WHEN s.customer_count < 50 THEN 'Other' ELSE c.country END AS market,
  CASE
    WHEN c.country = 'United States' THEN 'North America'
    WHEN c.country IN ('China', 'South Korea', 'Japan', 'Australia') THEN 'Asia Pacific'
    WHEN c.country IN ('Brazil', 'Colombia') THEN 'Latin America'
    WHEN c.country IN ('United Kingdom', 'France', 'Germany', 'Spain', 'Belgium', 'Poland', 'Austria') THEN 'Europe'
    ELSE 'Other'
  END                                       AS region
FROM cleaned c
JOIN country_size s USING (country)
LEFT JOIN `northloom_staging.stg_channel_map` m
  ON m.source_system = 'users' AND m.source_value = c.signup_traffic_source_raw;

-- ---------------------------------------------------------------------------
-- stg_products: catalog, with missing values made visible rather than null
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW `northloom_staging.stg_products` AS
SELECT
  p.id                                      AS product_id,
  COALESCE(NULLIF(TRIM(p.name), ''), 'Unknown')       AS product_name,
  COALESCE(NULLIF(TRIM(p.category), ''), 'Unknown')   AS category,
  COALESCE(NULLIF(TRIM(p.brand), ''), 'Unknown')      AS brand,
  COALESCE(NULLIF(TRIM(p.department), ''), 'Unknown') AS department,
  p.sku,
  p.cost                                    AS list_cost,
  p.retail_price,
  ROUND(p.retail_price - p.cost, 2)         AS list_margin_amount,
  ROUND(100 * SAFE_DIVIDE(p.retail_price - p.cost, p.retail_price), 1) AS list_margin_pct,
  p.distribution_center_id,
  -- Two products retail under $1; flagged, not deleted.
  p.retail_price < 1                        AS is_price_suspect,
  p.category IS NULL OR p.brand IS NULL     AS has_missing_attributes
FROM `northloom_raw.products` p;

-- ---------------------------------------------------------------------------
-- stg_distribution_centers: warehouse network, with the city and state split out
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW `northloom_staging.stg_distribution_centers` AS
SELECT
  dc.id                                     AS distribution_center_id,
  dc.name                                   AS distribution_center_name,
  -- Names look like 'Memphis TN', so the trailing token is the state.
  REGEXP_EXTRACT(dc.name, r'^(.*)\s+\S+$')  AS dc_city,
  REGEXP_EXTRACT(dc.name, r'(\S+)$')        AS dc_state,
  dc.latitude,
  dc.longitude,
  dc.distribution_center_geom               AS dc_geom
FROM `northloom_raw.distribution_centers` dc;

-- ---------------------------------------------------------------------------
-- stg_inventory_items: stock units, with the true cost of each unit
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW `northloom_staging.stg_inventory_items` AS
SELECT
  ii.id                                     AS inventory_item_id,
  ii.product_id,
  ii.created_at                             AS stocked_ts,
  DATE(ii.created_at)                       AS stocked_date,
  ii.sold_at                                AS sold_ts,
  DATE(ii.sold_at)                          AS sold_date,
  ii.cost                                   AS unit_cost,
  ii.product_distribution_center_id         AS distribution_center_id,
  -- On hand as at the analysis date, which is how stock cover is counted (NL-104).
  ii.sold_at IS NULL OR ii.sold_at > cfg.as_of_ts AS is_on_hand,
  DATE_DIFF(cfg.as_of_date, DATE(ii.created_at), DAY) AS days_in_stock
FROM `northloom_raw.inventory_items` ii
CROSS JOIN `northloom_staging.analysis_config` cfg
WHERE ii.created_at <= cfg.as_of_ts;

-- ---------------------------------------------------------------------------
-- stg_orders: order headers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW `northloom_staging.stg_orders` AS
SELECT
  o.order_id,
  o.user_id,
  o.status                                  AS order_status,
  o.created_at                              AS order_ts,
  DATE(o.created_at)                        AS order_date,
  DATE_TRUNC(DATE(o.created_at), MONTH)     AS order_month,
  o.shipped_at,
  o.delivered_at,
  o.returned_at,
  o.num_of_item                             AS header_item_count,
  o.status = 'Cancelled'                    AS is_cancelled,
  o.status = 'Returned'                     AS is_returned
FROM `northloom_raw.orders` o
CROSS JOIN `northloom_staging.analysis_config` cfg
WHERE o.created_at <= cfg.as_of_ts;

-- ---------------------------------------------------------------------------
-- stg_order_items: the heart of the layer. One row per item sold, with the
-- agreed revenue, margin and fulfillment rules already applied.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW `northloom_staging.stg_order_items` AS
SELECT
  oi.id                                     AS order_item_id,
  oi.order_id,
  oi.user_id,
  oi.product_id,
  oi.inventory_item_id,
  ii.distribution_center_id,
  oi.status                                 AS item_status,
  oi.created_at                             AS order_ts,
  DATE(oi.created_at)                       AS order_date,
  DATE_TRUNC(DATE(oi.created_at), MONTH)    AS order_month,
  oi.shipped_at,
  oi.delivered_at,
  oi.returned_at,

  -- Money. Cancelled items never earned anything; returned items earned it and
  -- gave it back. Cost comes from the physical unit sold, not the list price.
  oi.sale_price,
  COALESCE(ii.unit_cost, p.list_cost)       AS unit_cost,
  oi.status = 'Cancelled'                   AS is_cancelled,
  oi.status = 'Returned'                    AS is_returned,
  oi.status NOT IN ('Cancelled', 'Returned') AS is_net_sale,
  IF(oi.status = 'Cancelled', 0, oi.sale_price)                                   AS gross_revenue,
  IF(oi.status IN ('Cancelled', 'Returned'), 0, oi.sale_price)                    AS net_revenue,
  IF(oi.status IN ('Cancelled', 'Returned'), 0,
     ROUND(oi.sale_price - COALESCE(ii.unit_cost, p.list_cost), 2))               AS gross_margin,
  -- What the customer paid against list price, which exposes discounting.
  ROUND(p.retail_price - oi.sale_price, 2)  AS discount_amount,

  -- Fulfillment. 29.5% of rows ship before they're ordered, so the order-to-ship
  -- leg is only trustworthy where the flag is true. Ship-to-delivery is sound
  -- either way, which is why it's the primary fulfillment measure.
  oi.shipped_at IS NULL OR oi.shipped_at >= oi.created_at AS has_valid_ship_timeline,
  IF(oi.shipped_at >= oi.created_at,
     TIMESTAMP_DIFF(oi.shipped_at, oi.created_at, HOUR), NULL)                    AS hours_order_to_ship,
  IF(oi.delivered_at >= oi.shipped_at,
     TIMESTAMP_DIFF(oi.delivered_at, oi.shipped_at, HOUR), NULL)                  AS hours_ship_to_delivery,
  IF(oi.delivered_at >= oi.created_at AND oi.shipped_at >= oi.created_at,
     TIMESTAMP_DIFF(oi.delivered_at, oi.created_at, HOUR), NULL)                  AS hours_order_to_delivery,
  IF(oi.returned_at IS NOT NULL AND oi.delivered_at IS NOT NULL,
     TIMESTAMP_DIFF(oi.returned_at, oi.delivered_at, DAY), NULL)                  AS days_delivered_to_return
FROM `northloom_raw.order_items` oi
CROSS JOIN `northloom_staging.analysis_config` cfg
LEFT JOIN `northloom_staging.stg_inventory_items` ii
  ON oi.inventory_item_id = ii.inventory_item_id
LEFT JOIN `northloom_staging.stg_products` p
  ON oi.product_id = p.product_id
-- Drops the 1,211 future-dated rows, which have no parent order.
WHERE oi.created_at <= cfg.as_of_ts;

-- ---------------------------------------------------------------------------
-- stg_events: clickstream, with the funnel step numbered and IP dropped
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW `northloom_staging.stg_events` AS
SELECT
  e.id                                      AS event_id,
  e.user_id,
  e.session_id,
  e.sequence_number,
  e.created_at                              AS event_ts,
  DATE(e.created_at)                        AS event_date,
  DATE_TRUNC(DATE(e.created_at), MONTH)     AS event_month,
  e.event_type,
  -- The funnel in order, so steps can be compared without hardcoding names again.
  CASE e.event_type
    WHEN 'home'       THEN 1
    WHEN 'department' THEN 2
    WHEN 'product'    THEN 3
    WHEN 'cart'       THEN 4
    WHEN 'purchase'   THEN 5
    WHEN 'cancel'     THEN 6
    ELSE NULL
  END                                       AS funnel_step,
  COALESCE(m.channel, 'Unknown')            AS channel,
  COALESCE(m.is_paid, FALSE)                AS channel_is_paid,
  e.browser,
  e.city,
  e.state,
  e.postal_code,
  e.uri,
  -- 46% of events have no user_id, so the funnel is counted per session.
  e.user_id IS NOT NULL                     AS is_signed_in
FROM `northloom_raw.events` e
CROSS JOIN `northloom_staging.analysis_config` cfg
LEFT JOIN `northloom_staging.stg_channel_map` m
  ON m.source_system = 'events' AND m.source_value = e.traffic_source
WHERE e.created_at <= cfg.as_of_ts;
