-- =====================================================================
-- theLook eCommerce: exploration behind the dashboard (April 2026) - BigQuery
-- Run dashboard.sql first (sections 1-2 create sessions_april and purchase_links;
-- section 4 creates daily_revenue). Then run ONE numbered query at a time.
-- Each part checks an assumption the dashboard depends on.
-- Dates: BETWEEN '2026-04-01' AND '2026-05-01'.
-- Unit: sessions (COUNT(DISTINCT session_id)), not raw events.
-- =====================================================================


-- =====================================================================
-- A. THE DATA AND THE APRIL COHORT
-- =====================================================================

-- A1. What does the events table hold?
-- Observed: 2019-01-02 to 2026-10-09 | 2,426,288 rows | 681,758 sessions (the full table, not April).
SELECT
  MIN(created_at)            AS first_event,
  MAX(created_at)            AS last_event,
  COUNT(*)                   AS total_rows,
  COUNT(DISTINCT session_id) AS total_sessions
FROM thelook_copy.events;

-- A2. Why the cohort is "sessions whose FIRST event is in April" and not "events dated in April".
-- Sessions can last days, so an event-date filter cuts them in half.
-- Earlier event-window checks found 188 sessions that started in March and bought in April, and 197
-- that started in April and bought after April 30. Expect counts close to those.
WITH s AS (
  SELECT
    session_id,
    MIN(created_at)                                    AS first_event,
    MIN(IF(event_type = 'purchase', created_at, NULL)) AS purchase_time
  FROM thelook_copy.events
  GROUP BY session_id
)
SELECT
  COUNTIF(first_event < '2026-04-01'
          AND purchase_time BETWEEN '2026-04-01' AND '2026-05-01') AS started_before_april_bought_in_april,
  COUNTIF(first_event BETWEEN '2026-04-01' AND '2026-05-01'
          AND purchase_time > '2026-05-01')                        AS started_in_april_bought_after
FROM s;

-- A3. Size of the cohort table.
-- Observed: 10,457 sessions | 7,839 carts | 5,207 purchases.
SELECT
  COUNT(*)      AS sessions,
  SUM(cart)     AS carts,
  SUM(purchase) AS purchases
FROM thelook_copy.sessions_april;

-- A4. Which event types exist in the cohort?
-- Observed (sessions): product 10,457 | cart 7,839 | department 7,830 | purchase 5,207 | home 2,567 | cancel 1,348.
-- Every session has a product view, so "Product view" = all sessions in the funnel.
SELECT
  event_type,
  COUNT(*)                   AS events,
  COUNT(DISTINCT session_id) AS sessions
FROM thelook_copy.events
WHERE session_id IN (SELECT session_id FROM thelook_copy.sessions_april)
GROUP BY event_type
ORDER BY sessions DESC;


-- =====================================================================
-- B. THE FUNNEL
-- =====================================================================

-- B1. Do the funnel steps happen in order? (first occurrence of each step)
-- Equal pairs mean the earlier step always came first.
-- Observed: product_and_cart = product_before_cart = 7,839 | cart_and_purchase = cart_before_purchase = 5,207.
WITH o AS (
  SELECT
    session_id,
    MIN(IF(event_type = 'product',  sequence_number, NULL)) AS product_seq,
    MIN(IF(event_type = 'cart',     sequence_number, NULL)) AS cart_seq,
    MIN(IF(event_type = 'purchase', sequence_number, NULL)) AS purchase_seq
  FROM thelook_copy.events
  WHERE session_id IN (SELECT session_id FROM thelook_copy.sessions_april)
  GROUP BY session_id
)
SELECT
  COUNTIF(product_seq IS NOT NULL AND cart_seq IS NOT NULL)     AS product_and_cart,
  COUNTIF(product_seq < cart_seq)                               AS product_before_cart,
  COUNTIF(cart_seq IS NOT NULL AND purchase_seq IS NOT NULL)    AS cart_and_purchase,
  COUNTIF(cart_seq < purchase_seq)                              AS cart_before_purchase
FROM o;

-- B2. Funnel and conversion rates (matches the dashboard funnel).
-- Observed: 10,457 -> 7,839 -> 5,207 | 75.0% | 66.4% | 49.8% overall.
SELECT
  COUNT(*)                                          AS product_sessions,
  SUM(cart)                                         AS cart_sessions,
  SUM(purchase)                                     AS purchase_sessions,
  ROUND(100 * SUM(cart) / COUNT(*), 1)              AS product_to_cart_pct,
  ROUND(100 * SUM(purchase) / SUM(cart), 1)         AS cart_to_purchase_pct,
  ROUND(100 * SUM(purchase) / COUNT(*), 1)          AS overall_conversion_pct
FROM thelook_copy.sessions_april;

-- B3. Full journeys: the exact page sequence of each session.
-- Observed: only 8 distinct journeys cover all 10,457 sessions, and every looping journey is the same
-- "department > product > cart" unit repeated 2-4 times. This is why the dashboard is labelled synthetic data.
WITH j AS (
  SELECT
    session_id,
    STRING_AGG(event_type, ' > ' ORDER BY sequence_number) AS journey
  FROM thelook_copy.events
  WHERE session_id IN (SELECT session_id FROM thelook_copy.sessions_april)
  GROUP BY session_id
)
SELECT
  journey,
  COUNT(*)                                         AS sessions,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_sessions
FROM j
GROUP BY journey
ORDER BY sessions DESC;

-- B4. How do cart sessions end, by number of cart visits?
-- Observed: 1 visit: 5,199 sessions, 49.4% purchased | 2, 3 and 4 visits: 100% purchased.
-- Every session that returned to the cart bought, another sign the data is generated.
WITH c AS (
  SELECT
    session_id,
    COUNTIF(event_type = 'cart')           AS cart_visits,
    MAX(IF(event_type = 'purchase', 1, 0)) AS purchased,
    MAX(IF(event_type = 'cancel',   1, 0)) AS cancelled
  FROM thelook_copy.events
  WHERE session_id IN (SELECT session_id FROM thelook_copy.sessions_april)
  GROUP BY session_id
  HAVING COUNTIF(event_type = 'cart') > 0
)
SELECT
  cart_visits,
  COUNT(*)                                          AS sessions,
  COUNTIF(purchased = 1)                            AS purchased,
  COUNTIF(cancelled = 1)                            AS cancelled,
  COUNTIF(purchased = 0 AND cancelled = 0)          AS abandoned,
  ROUND(100 * COUNTIF(purchased = 1) / COUNT(*), 1) AS purchase_rate_pct
FROM c
GROUP BY cart_visits
ORDER BY cart_visits;


-- =====================================================================
-- C. CONVERSION BY CHANNEL
-- =====================================================================

-- C1. Volume and conversion by channel (matches the dashboard chart).
-- Observed: Email 4,731 (49.0%) | Adwords 3,181 (50.6%) | YouTube 1,051 (49.9%) |
--           Facebook 984 (51.3%) | Organic 510 (49.4%) | overall 49.8%.
SELECT
  traffic_source,
  COUNT(*)                                         AS sessions,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_sessions,
  SUM(purchase)                                    AS purchases,
  ROUND(100 * SUM(purchase) / COUNT(*), 1)         AS conversion_pct
FROM thelook_copy.sessions_april
GROUP BY traffic_source
ORDER BY sessions DESC;

-- C2. Is any channel's conversion really different? Two-proportion z-test, each channel vs. all others.
-- Reading: |z| >= 1.96 is roughly significant at the 5% level. Five channels are tested at once,
-- so |z| >= 2.58 is a safer bar. A channel whose 95% range (dashboard chart) contains the overall
-- rate will normally show |z| below 1.96.
WITH c AS (
  SELECT traffic_source, COUNT(*) AS n, SUM(purchase) AS x
  FROM thelook_copy.sessions_april
  GROUP BY traffic_source
),
t AS (
  SELECT SUM(n) AS n, SUM(x) AS x FROM c
)
SELECT
  c.traffic_source,
  ROUND(100 * c.x / c.n, 1) AS conversion_pct,
  ROUND((c.x / c.n - (t.x - c.x) / (t.n - c.n))
        / SQRT((t.x / t.n) * (1 - t.x / t.n) * (1 / c.n + 1 / (t.n - c.n))), 2) AS z_score
FROM c
CROSS JOIN t
ORDER BY c.n DESC;


-- =====================================================================
-- D. REVENUE
-- =====================================================================

-- D1. Order items by status. Gross = all items; cancelled + returned are removed to get net.
-- Observed: 5,198 items, about $310.4K gross | Cancelled 760 (14.6%) + Returned 513 (9.9%).
-- 'Processing' items are not a final outcome, so net revenue is provisional.
SELECT
  status,
  COUNT(*)                                                       AS items,
  ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)               AS pct_of_items,
  ROUND(SUM(sale_price), 2)                                      AS revenue,
  ROUND(100 * SUM(sale_price) / SUM(SUM(sale_price)) OVER (), 1) AS pct_of_revenue
FROM thelook_copy.order_items
WHERE created_at BETWEEN '2026-04-01' AND '2026-05-01'
GROUP BY status
ORDER BY items DESC;

-- D2. Does a 'purchase' event equal an order, or an order item?
-- Observed: purchase_events 5,198 = order_items 5,198, while orders are fewer (3,612).
-- So a purchase event is one ORDER ITEM, which is why revenue per session uses items.
SELECT
  (SELECT COUNT(*) FROM thelook_copy.events
   WHERE event_type = 'purchase' AND created_at BETWEEN '2026-04-01' AND '2026-05-01') AS purchase_events,
  (SELECT COUNT(*) FROM thelook_copy.orders
   WHERE created_at BETWEEN '2026-04-01' AND '2026-05-01')                             AS orders,
  (SELECT COUNT(*) FROM thelook_copy.order_items
   WHERE created_at BETWEEN '2026-04-01' AND '2026-05-01')                             AS order_items;

-- D3. Can every purchase session be linked to an order item (same user, within 1 hour)?
-- Exact timestamp matching links only about half (the single-cart-visit sessions differ by minutes),
-- so purchase_links uses a 1-hour window and keeps the closest item.
-- Expect: no_item = 0. Observed earlier: every purchase has an item within 1 hour.
WITH n AS (
  SELECT s.session_id, COUNT(oi.id) AS items_within_1h
  FROM thelook_copy.sessions_april AS s
  LEFT JOIN thelook_copy.order_items AS oi
    ON oi.user_id = s.user_id
   AND oi.created_at BETWEEN TIMESTAMP_SUB(s.purchase_time, INTERVAL 1 HOUR)
                         AND TIMESTAMP_ADD(s.purchase_time, INTERVAL 1 HOUR)
  WHERE s.purchase = 1
  GROUP BY s.session_id
)
SELECT
  COUNT(*)                  AS purchase_sessions,
  COUNTIF(items_within_1h = 0) AS no_item,
  COUNTIF(items_within_1h = 1) AS one_item,
  COUNTIF(items_within_1h > 1) AS several_items
FROM n;

-- D4. Why revenue per session is $29.78 but the KPI card total implies $29.68.
-- The KPI cards use all April ITEMS (by item date); revenue per session uses the items linked
-- to the 5,207 purchase sessions. They differ slightly (about 0.3%).
-- Observed: linked $311,390.61 vs all April items $310,382.10.
SELECT
  (SELECT ROUND(SUM(sale_price), 2) FROM thelook_copy.purchase_links) AS linked_gross,
  (SELECT ROUND(SUM(sale_price), 2) FROM thelook_copy.order_items
   WHERE created_at BETWEEN '2026-04-01' AND '2026-05-01')            AS all_items_gross;

-- D5. Daily revenue: average, best and worst day (matches the line chart).
-- Observed: average about $10,346 | best Apr 29 $12,742.92 | worst Apr 20 $7,998.57.
SELECT
  ROUND(AVG(gross_revenue), 0)                                    AS avg_daily_gross,
  MAX(gross_revenue)                                              AS best_day_revenue,
  ARRAY_AGG(sales_date ORDER BY gross_revenue DESC LIMIT 1)[OFFSET(0)] AS best_day,
  MIN(gross_revenue)                                              AS worst_day_revenue,
  ARRAY_AGG(sales_date ORDER BY gross_revenue ASC LIMIT 1)[OFFSET(0)]  AS worst_day
FROM thelook_copy.daily_revenue;
