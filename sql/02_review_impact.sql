-- 02_review_impact.sql : (a) how much does a late delivery lower the review score?

-- name: review_late_vs_ontime
SELECT
    CASE WHEN is_late THEN 'late' ELSE 'on_time' END             AS delivery,
    COUNT(*)                                                      AS orders_with_review,
    ROUND(AVG(review_score), 3)                                   AS avg_review,
    ROUND(STDDEV_SAMP(review_score) / SQRT(COUNT(*)), 4)          AS se_avg_review,
    ROUND(AVG((review_score <= 2)::INT) * 100, 1)                 AS pct_1_2_star,
    ROUND(AVG((review_score = 5)::INT) * 100, 1)                  AS pct_5_star
FROM delivered
WHERE review_score IS NOT NULL
GROUP BY 1 ORDER BY 1;

-- name: review_gap_with_ci
WITH g AS (
    SELECT is_late, AVG(review_score) m, VAR_SAMP(review_score) v, COUNT(*) n
    FROM delivered WHERE review_score IS NOT NULL GROUP BY 1
)
SELECT ROUND(l.m - o.m, 3)                                         AS gap_late_minus_ontime,
       ROUND(l.m - o.m - 1.96 * SQRT(l.v / l.n + o.v / o.n), 3)    AS ci95_low,
       ROUND(l.m - o.m + 1.96 * SQRT(l.v / l.n + o.v / o.n), 3)    AS ci95_high,
       ROUND((l.m - o.m) / SQRT(l.v / l.n + o.v / o.n), 1)         AS z_stat
FROM g l, g o WHERE l.is_late AND NOT o.is_late;

-- Dose-response: if lateness drives the drop, the score should fall steadily with days late.
-- name: review_dose_response
SELECT
    CASE
        WHEN days_late <= -15 THEN '01: 15+ days early'
        WHEN days_late <=  -8 THEN '02: 8-14 days early'
        WHEN days_late <=  -1 THEN '03: 1-7 days early'
        WHEN days_late  =   0 THEN '04: on promised day'
        WHEN days_late <=   3 THEN '05: 1-3 days late'
        WHEN days_late <=   7 THEN '06: 4-7 days late'
        WHEN days_late <=  14 THEN '07: 8-14 days late'
        ELSE                       '08: 15+ days late'
    END                                                AS lateness_bucket,
    COUNT(*)                                           AS orders,
    ROUND(AVG(review_score), 3)                        AS avg_review,
    ROUND(AVG((review_score <= 2)::INT) * 100, 1)      AS pct_1_2_star
FROM delivered
WHERE review_score IS NOT NULL
GROUP BY 1 ORDER BY 1;

-- Stratified ("matched") estimate: compare late vs on-time orders only WITHIN the same
-- seller x purchase-month cell, then average the cell gaps weighted by late orders (ATT).
-- This removes confounding by seller quality and seasonality (e.g. Black Friday 2017).
-- name: review_gap_stratified
WITH cells AS (
    SELECT seller_id, purchase_month,
           AVG(CASE WHEN is_late THEN review_score END)     AS late_avg,
           AVG(CASE WHEN NOT is_late THEN review_score END) AS ontime_avg,
           SUM(is_late::INT)                                AS n_late,
           SUM((NOT is_late)::INT)                          AS n_ontime
    FROM delivered WHERE review_score IS NOT NULL
    GROUP BY 1, 2
), cells2 AS (
    SELECT customer_state, product_category, purchase_month,
           AVG(CASE WHEN is_late THEN review_score END)     AS late_avg,
           AVG(CASE WHEN NOT is_late THEN review_score END) AS ontime_avg,
           SUM(is_late::INT)                                AS n_late
    FROM delivered WHERE review_score IS NOT NULL
    GROUP BY 1, 2, 3
)
SELECT 'within seller x month' AS strata,
       COUNT(*) AS cells_with_both, SUM(n_late) AS late_orders_matched,
       ROUND(SUM((late_avg - ontime_avg) * n_late) / SUM(n_late), 3) AS weighted_gap
FROM cells WHERE n_late > 0 AND n_ontime > 0
UNION ALL
SELECT 'within state x category x month',
       COUNT(*), SUM(n_late),
       ROUND(SUM((late_avg - ontime_avg) * n_late) / SUM(n_late), 3)
FROM cells2 WHERE late_avg IS NOT NULL AND ontime_avg IS NOT NULL;

-- Mechanism check: Olist emails the review survey around the promised date, so many
-- late customers rate BEFORE the parcel arrives.
-- name: review_written_before_delivery
SELECT CASE WHEN is_late THEN 'late' ELSE 'on_time' END AS delivery,
       COUNT(*) AS orders_with_review,
       ROUND(AVG((review_creation_date::DATE < delivered_at::DATE)::INT) * 100, 1) AS pct_review_before_delivery,
       ROUND(AVG(CASE WHEN review_creation_date::DATE <  delivered_at::DATE THEN review_score END), 2) AS avg_if_before,
       ROUND(AVG(CASE WHEN review_creation_date::DATE >= delivered_at::DATE THEN review_score END), 2) AS avg_if_after
FROM delivered WHERE review_score IS NOT NULL
GROUP BY 1 ORDER BY 1;

-- How padded is the promise? Average days early/late by group.
-- name: promise_padding
SELECT CASE WHEN is_late THEN 'late' ELSE 'on_time' END AS delivery,
       COUNT(*) AS orders,
       ROUND(AVG(days_late), 1) AS avg_days_vs_promise,
       MEDIAN(days_late) AS median_days_vs_promise
FROM delivered GROUP BY 1 ORDER BY 1;
