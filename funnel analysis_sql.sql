##import dataset
CREATE SCHEMA IF NOT EXISTS thelook_copy
OPTIONS (location = 'US');

CREATE OR REPLACE TABLE thelook_copy.distribution_centers AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.distribution_centers`;

CREATE OR REPLACE TABLE thelook_copy.products AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.products`;

CREATE OR REPLACE TABLE thelook_copy.users AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.users`;

CREATE OR REPLACE TABLE thelook_copy.inventory_items AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.inventory_items`;

CREATE OR REPLACE TABLE thelook_copy.orders AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.orders`;

CREATE OR REPLACE TABLE thelook_copy.order_items AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.order_items`;

CREATE OR REPLACE TABLE thelook_copy.events AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.events`;


##events
SELECT * FROM thelook_copy.events 
WHERE created_at BETWEEN '2026-04-01' AND '2026-05-01'
LIMIT 10;

SELECT event_type, COUNT(*) AS n
FROM thelook_copy.events
GROUP BY event_type;

#month filter
SELECT session_id, MIN(created_at) AS session_start
FROM thelook_copy.events
GROUP BY session_id
HAVING MIN(created_at) BETWEEN '2026-04-01' AND '2026-05-01' #HAVING to keep all the events in a session 
LIMIT 10;

CREATE OR REPLACE TABLE thelook_copy.sessions_april AS
SELECT
  session_id,
  MAX(user_id) AS user_id,
  ANY_VALUE(traffic_source) AS traffic_source,
  MAX(IF(event_type = 'cart', 1, 0)) AS cart, #1 == session reaches cart
  MAX(IF(event_type = 'purchase', 1, 0)) AS purchase, #1 == session reaches purchase
  MIN(IF(event_type = 'purchase', created_at, NULL)) AS purchase_time
FROM thelook_copy.events
GROUP BY session_id
HAVING MIN(created_at) BETWEEN '2026-04-01' AND '2026-05-01';

#total sessions
SELECT COUNT(*) AS total_sessions
FROM thelook_copy.sessions_april;

#total cart
SELECT SUM(cart) AS cart_sessions
FROM thelook_copy.sessions_april;

#total purchase
SELECT SUM(purchase) AS purchase_sessions
FROM thelook_copy.sessions_april;

#conversion rate
SELECT ROUND(SUM(purchase)/COUNT(*)*100,1) AS conversion_pct
FROM thelook_copy.sessions_april;

#customer journey
SELECT 
  event_type, 
  COUNT(*) AS events,
  COUNT(DISTINCT session_id) AS sessions
FROM thelook_copy.events
WHERE session_id IN (SELECT session_id FROM thelook_copy.sessions_april)
GROUP BY event_type
ORDER BY sessions DESC;

WITH j AS (
  SELECT
    session_id,
    STRING_AGG(event_type, ' > ' ORDER BY sequence_number) AS journey
  FROM thelook_copy.events
  WHERE session_id IN (SELECT session_id FROM thelook_copy.sessions_april)
  GROUP BY session_id
)
SELECT journey, COUNT(*) AS sessions
FROM j
GROUP BY journey
ORDER BY sessions DESC;

#funnel table
SELECT 1 AS stage_order, 'Product view' AS stage, COUNT(*) AS sessions
FROM thelook_copy.sessions_april
UNION ALL
SELECT 2, 'Cart', SUM(cart)
FROM thelook_copy.sessions_april
UNION ALL
SELECT 3, 'Purchase', SUM(purchase)
FROM thelook_copy.sessions_april;

CREATE OR REPLACE TABLE thelook_copy.funnel AS
WITH stages AS (
  SELECT 1 AS stage_order, 'Product view' AS stage, COUNT(*) AS sessions
  FROM thelook_copy.sessions_april
  UNION ALL
  SELECT 2, 'Cart', SUM(cart)
  FROM thelook_copy.sessions_april
  UNION ALL
  SELECT 3, 'Purchase', SUM(purchase)
  FROM thelook_copy.sessions_april
)
SELECT
  stage_order,
  stage,
  sessions,
  ROUND(100 * (1 - LEAD(sessions) OVER (ORDER BY stage_order) / sessions), 1) AS dropoff_pct
FROM stages
ORDER BY stage_order;


##revenue
SELECT * FROM thelook_copy.order_items
WHERE created_at BETWEEN '2026-04-01' AND '2026-05-01'
LIMIT 10;

#revenue by order status
SELECT status, COUNT(*) AS items, ROUND(SUM(sale_price), 2) AS revenue
FROM thelook_copy.order_items
WHERE created_at BETWEEN '2026-04-01' AND '2026-05-01'
GROUP BY status;

#daily gross revenue
CREATE OR REPLACE TABLE thelook_copy.daily_revenue AS
SELECT
  DATE(created_at) AS sales_date,
  ROUND(SUM(sale_price), 2) AS gross_revenue
FROM thelook_copy.order_items
WHERE created_at BETWEEN '2026-04-01' AND '2026-05-01'
GROUP BY sales_date
ORDER BY sales_date;

#revenue KPIs
CREATE OR REPLACE TABLE thelook_copy.kpis AS
WITH s AS (
  SELECT COUNT(*) AS sessions, SUM(purchase) AS purchases
  FROM thelook_copy.sessions_april
),
r AS (
  SELECT
    SUM(sale_price) AS gross,
    SUM(IF(status IN ('Cancelled', 'Returned'), sale_price, 0)) AS cancelled_returned
  FROM thelook_copy.order_items
  WHERE created_at BETWEEN '2026-04-01' AND '2026-05-01'
)
SELECT
  sessions,
  purchases,
  ROUND(100 * purchases / sessions, 1) AS conversion_pct,
  ROUND(gross, 2) AS gross_revenue,
  ROUND(cancelled_returned, 2) AS cancelled_returned,
  ROUND(100 * cancelled_returned / gross, 1) AS cancelled_returned_pct,
  ROUND(gross - cancelled_returned, 2) AS net_revenue
FROM s, r;


##channels
SELECT traffic_source, COUNT(*) AS sessions
FROM thelook_copy.sessions_april
GROUP BY traffic_source
ORDER BY sessions DESC;

#conversion by channel
SELECT
  traffic_source,
  COUNT(*) AS sessions,
  SUM(purchase) AS purchases,
  ROUND(100 * SUM(purchase) / COUNT(*), 1) AS conversion_pct
FROM thelook_copy.sessions_april
GROUP BY traffic_source
ORDER BY sessions DESC;

CREATE OR REPLACE TABLE thelook_copy.channel_conversion AS
WITH c AS (
  SELECT
    traffic_source,
    COUNT(*) AS sessions,
    SUM(purchase) AS purchases,
    SUM(purchase) / COUNT(*) AS p
  FROM thelook_copy.sessions_april
  GROUP BY traffic_source
)
SELECT
  traffic_source,
  sessions,
  purchases,
  ROUND(100 * p, 1) AS conversion_pct,
  ROUND(100 * (p - 1.96 * SQRT(p * (1 - p) / sessions)), 1) AS ci_low,
  ROUND(100 * (p + 1.96 * SQRT(p * (1 - p) / sessions)), 1) AS ci_high,
  ROUND(100 * SUM(purchases) OVER () / SUM(sessions) OVER (), 1) AS overall_pct
FROM c
ORDER BY sessions DESC;

#revenue by channel
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

SELECT COUNT(*) AS links, COUNT(DISTINCT session_id) AS sessions
FROM thelook_copy.purchase_links;

#gross vs net
CREATE OR REPLACE TABLE thelook_copy.channel_revenue AS
SELECT
  s.traffic_source,
  COUNT(DISTINCT s.session_id) AS sessions,
  ROUND(SUM(l.sale_price) / COUNT(DISTINCT s.session_id), 2) AS gross_per_session,
  ROUND(SUM(IF(l.status NOT IN ('Cancelled', 'Returned'), l.sale_price, 0))
        / COUNT(DISTINCT s.session_id), 2) AS net_per_session
FROM thelook_copy.sessions_april AS s
LEFT JOIN thelook_copy.purchase_links AS l
  ON s.session_id = l.session_id
GROUP BY s.traffic_source
ORDER BY gross_per_session DESC;

#overall revenue per session
SELECT
  ROUND(SUM(l.sale_price) / COUNT(DISTINCT s.session_id), 2) AS gross_per_session,
  ROUND(SUM(IF(l.status NOT IN ('Cancelled', 'Returned'), l.sale_price, 0))
        / COUNT(DISTINCT s.session_id), 2) AS net_per_session
FROM thelook_copy.sessions_april AS s
LEFT JOIN thelook_copy.purchase_links AS l
  ON s.session_id = l.session_id;