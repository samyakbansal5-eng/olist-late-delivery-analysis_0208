-- 04_segments.sql : (c) which states, sellers and categories are hit worst?
-- "Hit worst" = most review stars lost to lateness:
--   stars_lost = late_orders_with_review x (on-time avg - late avg) within the segment.
-- Also ranked by late rate. Minimum volume filters avoid tiny-sample noise.

-- name: segment_states
WITH s AS (
    SELECT customer_state AS state,
           COUNT(*) AS orders,
           SUM(is_late::INT) AS late_orders,
           AVG(is_late::INT) AS late_rate,
           AVG(CASE WHEN is_late THEN review_score END)     AS late_avg,
           AVG(CASE WHEN NOT is_late THEN review_score END) AS ontime_avg,
           COUNT(CASE WHEN is_late THEN review_score END)   AS late_reviewed,
           AVG(DATE_DIFF('day', purchased_at::DATE, delivered_at::DATE)) AS avg_days_to_deliver,
           SUM(order_value) AS gmv
    FROM delivered GROUP BY 1
)
SELECT state, orders, late_orders,
       ROUND(late_rate * 100, 1)               AS late_rate_pct,
       ROUND(avg_days_to_deliver, 1)           AS avg_days_to_deliver,
       ROUND(ontime_avg, 2) AS ontime_review, ROUND(late_avg, 2) AS late_review,
       ROUND(late_reviewed * (ontime_avg - late_avg), 0) AS stars_lost,
       ROUND(gmv, 0) AS gmv_brl,
       RANK() OVER (ORDER BY late_rate DESC)   AS rank_late_rate,
       RANK() OVER (ORDER BY late_reviewed * (ontime_avg - late_avg) DESC) AS rank_stars_lost
FROM s WHERE orders >= 300
ORDER BY late_rate DESC;

-- name: segment_categories
WITH s AS (
    SELECT product_category AS category,
           COUNT(*) AS orders, SUM(is_late::INT) AS late_orders, AVG(is_late::INT) AS late_rate,
           AVG(CASE WHEN is_late THEN review_score END)     AS late_avg,
           AVG(CASE WHEN NOT is_late THEN review_score END) AS ontime_avg,
           COUNT(CASE WHEN is_late THEN review_score END)   AS late_reviewed,
           SUM(order_value) AS gmv
    FROM delivered GROUP BY 1
)
SELECT category, orders, late_orders, ROUND(late_rate * 100, 1) AS late_rate_pct,
       ROUND(ontime_avg, 2) AS ontime_review, ROUND(late_avg, 2) AS late_review,
       ROUND(late_reviewed * (ontime_avg - late_avg), 0) AS stars_lost,
       ROUND(gmv, 0) AS gmv_brl
FROM s WHERE orders >= 500
ORDER BY late_rate DESC;

-- Sellers: >= 100 delivered orders. Also show what share of all late orders the
-- worst 20 sellers (by late count) account for -> concentration = where to act first.
-- name: segment_sellers
WITH s AS (
    SELECT seller_id, ANY_VALUE(seller_state) AS seller_state,
           COUNT(*) AS orders, SUM(is_late::INT) AS late_orders, AVG(is_late::INT) AS late_rate,
           AVG(review_score) AS avg_review,
           AVG(DATE_DIFF('day', purchased_at::DATE, delivered_at::DATE)) AS avg_days_to_deliver
    FROM delivered GROUP BY 1
)
SELECT LEFT(seller_id, 8) AS seller, seller_state, orders, late_orders,
       ROUND(late_rate * 100, 1) AS late_rate_pct, ROUND(avg_review, 2) AS avg_review,
       ROUND(avg_days_to_deliver, 1) AS avg_days_to_deliver
FROM s WHERE orders >= 100
ORDER BY late_rate DESC
LIMIT 25;

-- name: seller_concentration
WITH s AS (
    SELECT seller_id, COUNT(*) orders, SUM(is_late::INT) late_orders
    FROM delivered GROUP BY 1
), r AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY late_orders DESC) rk,
           SUM(late_orders) OVER () total_late, COUNT(*) OVER () total_sellers,
           SUM(orders) OVER () total_orders
    FROM s
)
SELECT top_n,
       SUM(late_orders) AS late_orders,
       ROUND(SUM(late_orders) * 100.0 / ANY_VALUE(total_late), 1)  AS pct_of_all_late,
       ROUND(SUM(orders) * 100.0 / ANY_VALUE(total_orders), 1)     AS pct_of_all_orders,
       ANY_VALUE(total_sellers) AS total_sellers
FROM (SELECT 10 AS top_n UNION ALL SELECT 50 UNION ALL SELECT 100 UNION ALL SELECT 300) n
JOIN r ON r.rk <= n.top_n
GROUP BY top_n ORDER BY top_n;

-- Interaction: is the "worst" state bad for every seller, or just long-haul routes?
-- name: route_late_rate
SELECT CASE WHEN seller_state = customer_state THEN 'same state' ELSE 'cross state' END AS route,
       CASE WHEN customer_state IN ('SP','RJ','MG','PR','SC','RS','ES') THEN 'South/Southeast customer'
            ELSE 'North/Northeast/Centre-West customer' END AS customer_region,
       COUNT(*) AS orders,
       ROUND(AVG(is_late::INT) * 100, 1) AS late_rate_pct,
       ROUND(AVG(promised_lead_days), 1) AS avg_promised_days,
       ROUND(AVG(DATE_DIFF('day', purchased_at::DATE, delivered_at::DATE)), 1) AS avg_actual_days
FROM delivered GROUP BY 1, 2 ORDER BY 1, 2;

-- Trend: late rate by month (Black Friday 2017 and Feb-Mar 2018 spikes).
-- name: late_rate_by_month
SELECT purchase_month::DATE AS month, COUNT(*) AS orders,
       ROUND(AVG(is_late::INT) * 100, 1) AS late_rate_pct,
       ROUND(AVG(review_score), 2) AS avg_review
FROM delivered
WHERE purchase_month >= '2017-01-01'
GROUP BY 1 ORDER BY 1;

-- Why is RJ bad? Split by seller location and by period (the Feb-Mar 2018 spike).
-- name: rj_breakdown
SELECT CASE WHEN customer_state = 'RJ' THEN 'RJ' WHEN customer_state = 'SP' THEN 'SP' ELSE 'other' END AS customer_grp,
       CASE WHEN purchase_month IN ('2017-11-01', '2018-02-01', '2018-03-01') THEN 'peak months (Nov-17, Feb-18, Mar-18)'
            ELSE 'other months' END AS period,
       COUNT(*) AS orders,
       ROUND(AVG(is_late::INT) * 100, 1) AS late_rate_pct,
       ROUND(AVG((seller_state = 'SP')::INT) * 100, 0) AS pct_shipped_from_sp,
       ROUND(AVG(promised_lead_days), 1) AS avg_promised_days
FROM delivered GROUP BY 1, 2 ORDER BY 1, 2;

-- Share of all late orders that fall in the 3 peak months.
-- name: peak_share_of_late
SELECT ROUND(SUM(CASE WHEN purchase_month IN ('2017-11-01','2018-02-01','2018-03-01') THEN is_late::INT END) * 100.0
             / SUM(is_late::INT), 1) AS pct_of_late_in_peak_months,
       ROUND(SUM(CASE WHEN purchase_month IN ('2017-11-01','2018-02-01','2018-03-01') THEN 1 END) * 100.0
             / COUNT(*), 1) AS pct_of_orders_in_peak_months
FROM delivered;

-- Who is late: seller or carrier? Seller missed the shipping_limit_date if it handed the
-- parcel to the carrier after that deadline (order_items.shipping_limit_date).
-- name: late_seller_vs_carrier
WITH lim AS (SELECT order_id, MAX(shipping_limit_date) AS ship_limit FROM order_items GROUP BY 1)
SELECT CASE WHEN d.is_late THEN 'late' ELSE 'on_time' END AS delivery,
       COUNT(*) AS orders,
       ROUND(AVG((o.order_delivered_carrier_date > lim.ship_limit)::INT) * 100, 1) AS pct_seller_missed_handoff,
       ROUND(AVG(DATE_DIFF('day', o.order_purchase_timestamp::DATE, o.order_delivered_carrier_date::DATE)), 1) AS avg_days_to_carrier,
       ROUND(AVG(DATE_DIFF('day', o.order_delivered_carrier_date::DATE, o.order_delivered_customer_date::DATE)), 1) AS avg_carrier_transit_days
FROM delivered d
JOIN orders o USING (order_id)
JOIN lim USING (order_id)
WHERE o.order_delivered_carrier_date IS NOT NULL
GROUP BY 1 ORDER BY 1;
