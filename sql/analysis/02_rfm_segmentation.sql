-- NL-102 | CRM Manager
-- "I need a VIP list and an at-risk list for next month's email campaigns."
--
-- Technique: NTILE(5) over recency, frequency and monetary value, combined into
-- the standard RFM grid and translated into segments the CRM team can act on.
-- Grain of the result: one row per customer who has ever bought.
--
-- Scores are relative, not absolute: NTILE ranks each customer against the rest
-- of the base, so the lists stay the right size as the business grows. Recency is
-- reversed, because a low number of days since the last order is a good thing.

CREATE OR REPLACE VIEW `northloom_marts.vw_rfm_segments` AS
WITH cfg AS (SELECT * FROM `northloom_staging.analysis_config`),

customer_rfm AS (
  SELECT
    f.user_id,
    DATE_DIFF(cfg.as_of_date, MAX(IF(f.is_net_sale, f.order_date, NULL)), DAY) AS recency_days,
    COUNT(DISTINCT IF(f.is_net_sale, f.order_id, NULL)) AS frequency_orders,
    ROUND(SUM(f.net_revenue), 2)                        AS monetary_value,
    ROUND(SAFE_DIVIDE(SUM(f.net_revenue),
                      COUNT(DISTINCT IF(f.is_net_sale, f.order_id, NULL))), 2) AS avg_order_value,
    MIN(IF(f.is_net_sale, f.order_date, NULL))          AS first_order_date,
    MAX(IF(f.is_net_sale, f.order_date, NULL))          AS last_order_date,
    -- Returns and cancellations have to be counted OUTSIDE the is_net_sale
    -- filter: that filter exists precisely to remove them, so counting them
    -- within it always returns zero.
    COUNTIF(f.is_returned)                              AS items_returned,
    COUNTIF(f.is_cancelled)                             AS items_cancelled,
    COUNTIF(f.is_net_sale)                              AS items_kept,
    COUNTIF(NOT f.is_cancelled)                         AS items_shipped,
    ROUND(SUM(f.gross_margin), 2)                       AS gross_margin
  FROM `northloom_marts.fact_order_items` f
  CROSS JOIN cfg
  GROUP BY f.user_id, cfg.as_of_date
  -- Customers whose every order was cancelled have no purchase history to score.
  HAVING frequency_orders > 0
),

scored AS (
  SELECT
    *,
    -- 5 is always the best score on every axis.
    NTILE(5) OVER (ORDER BY recency_days DESC)          AS r_score,
    NTILE(5) OVER (ORDER BY frequency_orders ASC, last_order_date ASC) AS f_score,
    NTILE(5) OVER (ORDER BY monetary_value ASC)         AS m_score
  FROM customer_rfm
),

labelled AS (
  SELECT
    s.*,
    CONCAT(CAST(r_score AS STRING), CAST(f_score AS STRING), CAST(m_score AS STRING)) AS rfm_cell,
    r_score + f_score + m_score                         AS rfm_total,
    -- Segment names the CRM team already uses, so campaigns can be briefed
    -- straight from this column without translation.
    CASE
      WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
      WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN 'Loyal'
      WHEN r_score >= 4 AND f_score <= 2                  THEN 'Promising newcomers'
      WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 4 THEN 'Cannot lose them'
      WHEN r_score <= 2 AND f_score >= 3                  THEN 'At risk'
      WHEN r_score = 3                                    THEN 'Needs attention'
      WHEN r_score <= 2 AND m_score >= 3                  THEN 'Hibernating'
      ELSE 'Lost'
    END                                                 AS rfm_segment,
    -- Return rate against items shipped, since a cancelled item was never sent
    -- and can't be returned. Heavy returners cost more than their spend suggests,
    -- so the CRM team should see this before paying to win someone back.
    ROUND(100 * SAFE_DIVIDE(items_returned, NULLIF(items_shipped, 0)), 1) AS return_rate_pct
  FROM scored s
)
SELECT
  l.*,
  -- The action follows the segment, so every segment has exactly one owner and
  -- nothing valuable falls into the newsletter by accident.
  CASE l.rfm_segment
    WHEN 'Cannot lose them'    THEN '1. Win-back call or offer (highest value at risk)'
    WHEN 'Champions'           THEN '2. VIP early access, no discount needed'
    WHEN 'At risk'             THEN '3. Reactivation series'
    WHEN 'Loyal'               THEN '4. Loyalty rewards, protect the relationship'
    WHEN 'Promising newcomers' THEN '5. Second-purchase nudge'
    WHEN 'Needs attention'     THEN '6. Re-engagement offer'
    WHEN 'Hibernating'         THEN '7. Low-cost reactivation email'
    ELSE '8. Newsletter only, no spend'
  END                                                   AS campaign_action
FROM labelled l;

-- ---------------------------------------------------------------------------
-- The answer to the ticket: how big is each list, what is it worth, and who
-- should be contacted first?
-- ---------------------------------------------------------------------------
SELECT
  rfm_segment,
  campaign_action,
  COUNT(*)                                              AS customers,
  ROUND(100 * SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()), 1) AS pct_of_base,
  ROUND(SUM(monetary_value), 0)                         AS lifetime_net_revenue,
  ROUND(100 * SAFE_DIVIDE(SUM(monetary_value), SUM(SUM(monetary_value)) OVER ()), 1) AS pct_of_revenue,
  ROUND(AVG(monetary_value), 2)                         AS avg_customer_value,
  ROUND(AVG(recency_days), 0)                           AS avg_days_since_last_order,
  ROUND(AVG(frequency_orders), 2)                       AS avg_orders,
  -- Weighted, not an average of percentages: a customer who bought 1 item and
  -- returned it shouldn't count as much as one who bought 20 and returned 5.
  ROUND(100 * SAFE_DIVIDE(SUM(items_returned), SUM(items_shipped)), 1) AS return_rate_pct,
  ROUND(SUM(gross_margin), 0)                           AS lifetime_gross_margin
FROM `northloom_marts.vw_rfm_segments`
GROUP BY rfm_segment, campaign_action
ORDER BY lifetime_net_revenue DESC;
