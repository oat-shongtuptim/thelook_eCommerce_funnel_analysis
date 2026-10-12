-- =====================================================================
-- theLook eCommerce dashboard (April 2026) - BigQuery
-- Builds the 6 tables behind the 2-slide dashboard. Run the statements top to bottom.
-- Needs: thelook_copy.events and thelook_copy.order_items (copies of bigquery-public-data.thelook_ecommerce)
-- Cohort: sessions whose FIRST event is in April 2026, with all of their events.
-- =====================================================================


-- 1. One row per April session (feeds the funnel and both channel charts)
CREATE OR REPLACE TABLE thelook_copy.sessions_april AS
SELECT
  session_id,
  MAX(user_id)                                       AS user_id,
  ANY_VALUE(traffic_source)                          AS traffic_source,
  MIN(created_at)                                    AS session_start,
  MIN(IF(event_type = 'purchase', created_at, NULL)) AS purchase_time,
  MAX(IF(event_type = 'cart',     1, 0))             AS cart,
  MAX(IF(event_type = 'purchase', 1, 0))             AS purchase
FROM thelook_copy.events
GROUP BY session_id
HAVING MIN(created_at) BETWEEN '2026-04-01' AND '2026-05-01';


-- 2. Link each purchase session to its order item (same user, closest item within 1 hour)
CREATE OR REPLACE TABLE thelook_copy.purchase_links AS
SELECT
  s.session_id,
  s.traffic_source,
  oi.sale_price,
  oi.status
FROM thelook_copy.sessions_april AS s
JOIN thelook_copy.order_items AS oi
  ON oi.user_id = s.user_id
 AND oi.created_at BETWEEN TIMESTAMP_SUB(s.purchase_time, INTERVAL 1 HOUR)
                       AND TIMESTAMP_ADD(s.purchase_time, INTERVAL 1 HOUR)
WHERE s.purchase = 1
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY s.session_id
  ORDER BY ABS(TIMESTAMP_DIFF(oi.created_at, s.purchase_time, SECOND)), oi.id
) = 1;


-- 3. KPI cards (one row)
CREATE OR REPLACE TABLE thelook_copy.kpis AS
WITH s AS (
  SELECT COUNT(*) AS sessions, SUM(purchase) AS purchases
  FROM thelook_copy.sessions_april
),
rev AS (
  SELECT
    SUM(sale_price)                                                AS gross,
    SUM(IF(status IN ('Cancelled', 'Returned'), sale_price, 0))    AS cancelled_returned
  FROM thelook_copy.order_items
  WHERE created_at BETWEEN '2026-04-01' AND '2026-05-01'
)
SELECT
  sessions,
  purchases,
  ROUND(100 * purchases / sessions, 1)           AS conversion_pct,
  ROUND(gross, 2)                                AS gross_revenue,
  ROUND(cancelled_returned, 2)                   AS cancelled_returned,
  ROUND(100 * cancelled_returned / gross, 1)     AS cancelled_returned_pct,
  ROUND(gross - cancelled_returned, 2)           AS net_revenue
FROM s, rev;


-- 4. Daily gross revenue (line chart)
CREATE OR REPLACE TABLE thelook_copy.daily_revenue AS
SELECT
  DATE(created_at)          AS sales_date,
  ROUND(SUM(sale_price), 2) AS gross_revenue
FROM thelook_copy.order_items
WHERE created_at BETWEEN '2026-04-01' AND '2026-05-01'
GROUP BY sales_date
ORDER BY sales_date;


-- 5. Funnel: product view -> cart -> purchase
CREATE OR REPLACE TABLE thelook_copy.funnel AS
WITH stages AS (
  SELECT 1 AS stage_order, 'Product view' AS stage, COUNT(*)      AS sessions FROM thelook_copy.sessions_april
  UNION ALL
  SELECT 2, 'Cart',     SUM(cart)     FROM thelook_copy.sessions_april
  UNION ALL
  SELECT 3, 'Purchase', SUM(purchase) FROM thelook_copy.sessions_april
)
SELECT
  stage_order,
  stage,
  sessions,
  ROUND(100 * (1 - LEAD(sessions) OVER (ORDER BY stage_order) / sessions), 1) AS abandonment_pct
FROM stages
ORDER BY stage_order;


-- 6. Session conversion by channel with 95% range (dot = conversion_pct, bar = ci_low to ci_high)
CREATE OR REPLACE TABLE thelook_copy.channel_conversion AS
WITH c AS (
  SELECT
    traffic_source,
    COUNT(*)                    AS sessions,
    SUM(purchase)               AS purchases,
    SUM(purchase) / COUNT(*)    AS p
  FROM thelook_copy.sessions_april
  GROUP BY traffic_source
)
SELECT
  traffic_source,
  sessions,
  purchases,
  ROUND(100 * p, 1)                                          AS conversion_pct,
  ROUND(100 * (p - 1.96 * SQRT(p * (1 - p) / sessions)), 1)  AS ci_low,
  ROUND(100 * (p + 1.96 * SQRT(p * (1 - p) / sessions)), 1)  AS ci_high,
  ROUND(100 * SUM(purchases) OVER () / SUM(sessions) OVER (), 1) AS overall_pct
FROM c
ORDER BY sessions DESC;


-- 7. Revenue per session by channel (gross vs net)
CREATE OR REPLACE TABLE thelook_copy.channel_revenue AS
SELECT
  s.traffic_source,
  COUNT(DISTINCT s.session_id)                                                  AS sessions,
  ROUND(SUM(l.sale_price) / COUNT(DISTINCT s.session_id), 2)                    AS gross_per_session,
  ROUND(SUM(IF(l.status NOT IN ('Cancelled', 'Returned'), l.sale_price, 0))
        / COUNT(DISTINCT s.session_id), 2)                                      AS net_per_session
FROM thelook_copy.sessions_april AS s
LEFT JOIN thelook_copy.purchase_links AS l
  ON s.session_id = l.session_id
GROUP BY s.traffic_source
ORDER BY gross_per_session DESC;


-- =====================================================================
-- CHECKS (expected values for April 2026)
-- =====================================================================
SELECT * FROM thelook_copy.kpis;
-- 10,457 sessions | 5,207 purchases | 49.8% | $310,382.10 | $75,235.19 (24.2%) | $235,146.91

SELECT COUNT(*) AS linked_sessions FROM thelook_copy.purchase_links;
-- 5,207

SELECT ROUND(AVG(gross_revenue), 0) AS avg_daily_gross FROM thelook_copy.daily_revenue;
-- about 10,346

SELECT * FROM thelook_copy.funnel;
-- 10,457 -> 7,839 -> 5,207 | abandonment 25.0% and 33.6%

SELECT * FROM thelook_copy.channel_conversion;
-- overall 49.8% | Email 49.0 (47.6-50.4) | Adwords 50.6 | YouTube 49.9 | Facebook 51.3 | Organic 49.4

SELECT * FROM thelook_copy.channel_revenue;
-- gross per session $29.50-$31.39 | net $22.09-$24.12

SELECT
  ROUND(SUM(gross_per_session * sessions) / SUM(sessions), 2) AS avg_gross_per_session,  -- 29.78
  ROUND(SUM(net_per_session   * sessions) / SUM(sessions), 2) AS avg_net_per_session     -- 22.71
FROM thelook_copy.channel_revenue;
