-- 01_order_facts.sql : one row per order with delivery outcome, review, value,
-- customer (customer_unique_id = the real person), state, main seller and category.

-- Latest review per order (98,673 orders have >=1 review, ~550 have several).
CREATE OR REPLACE VIEW order_review AS
SELECT order_id, review_score, review_creation_date, review_comment_message
FROM (
    SELECT r.*,
           ROW_NUMBER() OVER (PARTITION BY order_id
                              ORDER BY review_answer_timestamp DESC, review_creation_date DESC) AS rn
    FROM reviews r
) WHERE rn = 1;

-- Order value = sum of payments (includes freight).
CREATE OR REPLACE VIEW order_value AS
SELECT order_id, SUM(payment_value) AS order_value
FROM payments GROUP BY order_id;

-- "Main" item per order = the most expensive line, used to attribute seller/category.
CREATE OR REPLACE VIEW order_main_item AS
SELECT order_id, seller_id, product_category,
       n_items, n_sellers
FROM (
    SELECT oi.order_id, oi.seller_id,
           COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS product_category,
           COUNT(*)                  OVER (PARTITION BY oi.order_id) AS n_items,
           COUNT(DISTINCT oi.seller_id) OVER (PARTITION BY oi.order_id) AS n_sellers,
           ROW_NUMBER() OVER (PARTITION BY oi.order_id ORDER BY oi.price DESC, oi.order_item_id) AS rn
    FROM order_items oi
    LEFT JOIN products p USING (product_id)
    LEFT JOIN category_translation t USING (product_category_name)
) WHERE rn = 1;

-- Core fact table. Late = delivered on a calendar day after the promised (estimated) date.
CREATE OR REPLACE TABLE order_facts AS
SELECT
    o.order_id,
    c.customer_unique_id,
    c.customer_state,
    o.order_status,
    o.order_purchase_timestamp                       AS purchased_at,
    o.order_delivered_customer_date                  AS delivered_at,
    o.order_estimated_delivery_date                  AS promised_at,
    DATE_TRUNC('month', o.order_purchase_timestamp)  AS purchase_month,
    DATE_DIFF('day', o.order_estimated_delivery_date::DATE,
                     o.order_delivered_customer_date::DATE)     AS days_late,      -- >0 late, <=0 on time/early
    DATE_DIFF('day', o.order_purchase_timestamp::DATE,
                     o.order_estimated_delivery_date::DATE)     AS promised_lead_days,
    (o.order_delivered_customer_date::DATE > o.order_estimated_delivery_date::DATE) AS is_late,
    r.review_score,
    r.review_creation_date,
    v.order_value,
    mi.seller_id,
    s.seller_state,
    mi.product_category,
    mi.n_items,
    mi.n_sellers
FROM orders o
JOIN customers c        USING (customer_id)
LEFT JOIN order_review r USING (order_id)
LEFT JOIN order_value  v USING (order_id)
LEFT JOIN order_main_item mi USING (order_id)
LEFT JOIN sellers s     ON s.seller_id = mi.seller_id;

-- Analysis population: delivered orders with a delivery date.
CREATE OR REPLACE VIEW delivered AS
SELECT * FROM order_facts
WHERE order_status = 'delivered' AND delivered_at IS NOT NULL AND promised_at IS NOT NULL;

-- name: population_summary
SELECT
    (SELECT COUNT(*) FROM orders)                                   AS all_orders,
    COUNT(*)                                                        AS delivered_orders,
    SUM(is_late::INT)                                               AS late_orders,
    ROUND(AVG(is_late::INT) * 100, 2)                               AS late_rate_pct,
    COUNT(review_score)                                             AS delivered_with_review,
    COUNT(DISTINCT customer_unique_id)                              AS unique_customers,
    ROUND(SUM(order_value), 0)                                      AS gmv_brl,
    MIN(purchased_at)::DATE                                         AS first_purchase,
    MAX(purchased_at)::DATE                                         AS last_purchase
FROM delivered;
