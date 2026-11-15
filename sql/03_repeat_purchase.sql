-- 03_repeat_purchase.sql : (b) does a late FIRST delivery lower repeat purchase within 6 months?
-- Customer = customer_unique_id (customer_id is new on every order in Olist).

-- Data end = last day with >= 100 orders (the final weeks of the file are near-empty).
CREATE OR REPLACE VIEW data_end AS
SELECT MAX(d) AS data_end FROM (
    SELECT purchased_at::DATE d FROM order_facts GROUP BY 1 HAVING COUNT(*) >= 100
);

-- Every order per person, ranked. Canceled/unavailable orders do not count as a repeat.
CREATE OR REPLACE VIEW customer_orders AS
SELECT *,
       ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY purchased_at, order_id) AS order_seq,
       MIN(purchased_at) OVER (PARTITION BY customer_unique_id) AS first_purchase_at
FROM order_facts
WHERE order_status NOT IN ('canceled', 'unavailable');

-- Cohort: first orders that were delivered and have a full 180-day follow-up window.
CREATE OR REPLACE TABLE first_order_cohort AS
WITH first_o AS (
    SELECT * FROM customer_orders
    WHERE order_seq = 1 AND order_status = 'delivered' AND delivered_at IS NOT NULL
), nxt AS (
    -- next order on a LATER calendar day (same-day orders are a split basket, not a repeat)
    SELECT f.customer_unique_id,
           MIN(c.purchased_at)                                                AS next_purchase_at,
           MIN(CASE WHEN c.purchased_at > f.delivered_at THEN c.purchased_at END) AS next_after_delivery_at,
           SUM(CASE WHEN c.purchased_at::DATE <= f.purchased_at::DATE + 180 THEN c.order_value END) AS repeat_value_180d
    FROM first_o f
    JOIN customer_orders c
      ON c.customer_unique_id = f.customer_unique_id
     AND c.order_seq > 1
     AND c.purchased_at::DATE > f.purchased_at::DATE
    GROUP BY 1
)
SELECT f.customer_unique_id, f.order_id, f.customer_state, f.seller_id, f.product_category,
       f.purchase_month, f.purchased_at, f.delivered_at, f.is_late, f.days_late,
       f.review_score, f.order_value,
       (n.next_purchase_at IS NOT NULL
        AND n.next_purchase_at::DATE <= f.purchased_at::DATE + 180)              AS repeat_180d,
       (n.next_after_delivery_at IS NOT NULL
        AND n.next_after_delivery_at::DATE <= f.delivered_at::DATE + 180)        AS repeat_180d_after_delivery,
       COALESCE(n.repeat_value_180d, 0)                                          AS repeat_value_180d
FROM first_o f
LEFT JOIN nxt n USING (customer_unique_id)
CROSS JOIN data_end
WHERE f.purchased_at::DATE <= data_end.data_end - 180
  AND f.delivered_at::DATE <= data_end.data_end - 180;

-- name: repeat_late_vs_ontime
SELECT CASE WHEN is_late THEN 'late' ELSE 'on_time' END AS first_delivery,
       COUNT(*)                                          AS customers,
       SUM(repeat_180d::INT)                             AS repeaters,
       ROUND(AVG(repeat_180d::INT) * 100, 2)             AS repeat_rate_pct,
       ROUND(SQRT(AVG(repeat_180d::INT) * (1 - AVG(repeat_180d::INT)) / COUNT(*)) * 100, 2) AS se_pct,
       ROUND(AVG(repeat_180d_after_delivery::INT) * 100, 2) AS repeat_after_delivery_pct,
       ROUND(AVG(repeat_value_180d), 2)                  AS repeat_brl_per_customer,
       ROUND(SUM(repeat_value_180d) / NULLIF(SUM(repeat_180d::INT), 0), 2) AS brl_per_repeater
FROM first_order_cohort
GROUP BY 1 ORDER BY 1;

-- name: repeat_gap_with_ci
WITH g AS (
    SELECT is_late, AVG(repeat_180d::INT) p, COUNT(*) n,
           AVG(repeat_180d_after_delivery::INT) p2
    FROM first_order_cohort GROUP BY 1
)
SELECT (SELECT MIN(purchased_at)::DATE FROM first_order_cohort) AS cohort_from,
       (SELECT MAX(purchased_at)::DATE FROM first_order_cohort) AS cohort_to,
       ROUND((l.p - o.p) * 100, 2)                                                   AS gap_pp,
       ROUND((l.p - o.p - 1.96 * SQRT(l.p*(1-l.p)/l.n + o.p*(1-o.p)/o.n)) * 100, 2) AS ci95_low_pp,
       ROUND((l.p - o.p + 1.96 * SQRT(l.p*(1-l.p)/l.n + o.p*(1-o.p)/o.n)) * 100, 2) AS ci95_high_pp,
       ROUND((l.p - o.p) / SQRT(l.p*(1-l.p)/l.n + o.p*(1-o.p)/o.n), 2)              AS z_stat,
       ROUND((l.p2 - o.p2) * 100, 2)                                                 AS gap_after_delivery_pp,
       ROUND((l.p2 - o.p2 - 1.96 * SQRT(l.p2*(1-l.p2)/l.n + o.p2*(1-o.p2)/o.n)) * 100, 2) AS ci95_low_after_pp,
       ROUND((l.p2 - o.p2 + 1.96 * SQRT(l.p2*(1-l.p2)/l.n + o.p2*(1-o.p2)/o.n)) * 100, 2) AS ci95_high_after_pp
FROM g l, g o WHERE l.is_late AND NOT o.is_late;

-- name: repeat_dose_response
SELECT CASE WHEN days_late <= -8 THEN '1: 8+ days early'
            WHEN days_late <=  0 THEN '2: 0-7 days early'
            WHEN days_late <=  7 THEN '3: 1-7 days late'
            ELSE                      '4: 8+ days late' END AS lateness_bucket,
       COUNT(*) AS customers,
       SUM(repeat_180d::INT) AS repeaters,
       ROUND(AVG(repeat_180d::INT) * 100, 2) AS repeat_rate_pct
FROM first_order_cohort GROUP BY 1 ORDER BY 1;

-- Repeat is driven by the first experience, so look at review score as the "felt" outcome too.
-- name: repeat_by_first_review
SELECT COALESCE(review_score::VARCHAR, 'no review') AS first_review,
       COUNT(*) AS customers,
       ROUND(AVG(repeat_180d::INT) * 100, 2) AS repeat_rate_pct
FROM first_order_cohort GROUP BY 1 ORDER BY 1;

-- Stratified: compare within customer_state x purchase_month (geography + seasonality).
-- name: repeat_gap_stratified
WITH cells AS (
    SELECT customer_state, purchase_month,
           AVG(CASE WHEN is_late THEN repeat_180d::INT END)     AS p_late,
           AVG(CASE WHEN NOT is_late THEN repeat_180d::INT END) AS p_ontime,
           SUM(is_late::INT) AS n_late
    FROM first_order_cohort GROUP BY 1, 2
), cells_c AS (
    SELECT product_category, purchase_month,
           AVG(CASE WHEN is_late THEN repeat_180d::INT END)     AS p_late,
           AVG(CASE WHEN NOT is_late THEN repeat_180d::INT END) AS p_ontime,
           SUM(is_late::INT) AS n_late
    FROM first_order_cohort GROUP BY 1, 2
)
SELECT 'within state x month' AS strata, COUNT(*) AS cells, SUM(n_late) AS late_customers,
       ROUND(SUM((p_late - p_ontime) * n_late) / SUM(n_late) * 100, 2) AS weighted_gap_pp
FROM cells WHERE p_late IS NOT NULL AND p_ontime IS NOT NULL
UNION ALL
SELECT 'within category x month', COUNT(*), SUM(n_late),
       ROUND(SUM((p_late - p_ontime) * n_late) / SUM(n_late) * 100, 2)
FROM cells_c WHERE p_late IS NOT NULL AND p_ontime IS NOT NULL;

-- Power check: smallest drop in repeat rate this sample could detect (80% power, 5% two-sided).
-- name: repeat_power
WITH g AS (SELECT AVG(repeat_180d::INT) p,
                  COUNT(CASE WHEN is_late THEN 1 END) n_l,
                  COUNT(CASE WHEN NOT is_late THEN 1 END) n_o
           FROM first_order_cohort)
SELECT n_l AS late_first_orders, n_o AS ontime_first_orders, ROUND(p * 100, 2) AS base_repeat_pct,
       ROUND((1.96 + 0.84) * SQRT(p * (1 - p) * (1.0 / n_l + 1.0 / n_o)) * 100, 2) AS min_detectable_drop_pp,
       ROUND((1.96 + 0.84) * SQRT(p * (1 - p) * (1.0 / n_l + 1.0 / n_o)) / p * 100, 0) AS min_detectable_drop_relative_pct
FROM g;
