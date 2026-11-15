-- 05_opportunity.sql : size the opportunity for the worst segment.
-- Worst segment = customers in Rio de Janeiro (RJ): #1 on review stars lost to lateness
-- (04_segments), 12.1% late vs 4.5% in SP, and 13% of delivered orders.
--
-- ASSUMPTIONS (all explicit, change them in `params`):
--  A1  The late->outcome gaps measured in 02/03 are causal and the same in RJ as nationally.
--  A2  Cutting RJ's late rate by X points cuts the late rate of RJ first orders by X points.
--  A3  Volume = last 12 full months in the data (2017-09-01 .. 2018-08-31), held flat.
--  A4  Value of a repeat customer = average BRL of repeat orders in 180 days (from 03).
--  A5  Repeat effect: three cases. low = stratified estimate (-0.21 pp), mid = raw gap,
--      high = lower end of the raw gap's 95% CI. The raw gap is NOT statistically significant.
--  A6  No second-order effects (better ratings -> more conversion from new shoppers) are
--      counted. That channel is plausibly larger but is not measurable in this dataset.

CREATE OR REPLACE VIEW opp_params AS
SELECT 'RJ' AS segment_state, DATE '2017-09-01' AS win_start, DATE '2018-09-01' AS win_end;

CREATE OR REPLACE VIEW opp_inputs AS
WITH p AS (SELECT * FROM opp_params),
rv AS (  -- review gap, stratified within seller x month (02)
    SELECT SUM((late_avg - ontime_avg) * n_late) / SUM(n_late) AS review_gap
    FROM (SELECT seller_id, purchase_month,
                 AVG(CASE WHEN is_late THEN review_score END) late_avg,
                 AVG(CASE WHEN NOT is_late THEN review_score END) ontime_avg,
                 SUM(is_late::INT) n_late
          FROM delivered WHERE review_score IS NOT NULL GROUP BY 1, 2)
    WHERE late_avg IS NOT NULL AND ontime_avg IS NOT NULL
),
rp AS (  -- repeat gaps (03)
    SELECT AVG(CASE WHEN is_late THEN repeat_180d::INT END) - AVG(CASE WHEN NOT is_late THEN repeat_180d::INT END) AS raw_gap,
           AVG(CASE WHEN is_late THEN repeat_180d::INT END) p_l, COUNT(CASE WHEN is_late THEN 1 END) n_l,
           AVG(CASE WHEN NOT is_late THEN repeat_180d::INT END) p_o, COUNT(CASE WHEN NOT is_late THEN 1 END) n_o,
           SUM(repeat_value_180d) / SUM(repeat_180d::INT) AS brl_per_repeater
    FROM first_order_cohort
),
rs AS (
    SELECT SUM((p_late - p_ontime) * n_late) / SUM(n_late) AS strat_gap
    FROM (SELECT customer_state, purchase_month,
                 AVG(CASE WHEN is_late THEN repeat_180d::INT END) p_late,
                 AVG(CASE WHEN NOT is_late THEN repeat_180d::INT END) p_ontime,
                 SUM(is_late::INT) n_late
          FROM first_order_cohort GROUP BY 1, 2)
    WHERE p_late IS NOT NULL AND p_ontime IS NOT NULL
),
seg AS (
    SELECT COUNT(*) AS seg_orders_12m,
           AVG(is_late::INT) AS seg_late_rate,
           AVG(review_score) AS seg_avg_review,
           SUM(order_value) AS seg_gmv_12m
    FROM delivered, p
    WHERE customer_state = p.segment_state AND purchased_at >= p.win_start AND purchased_at < p.win_end
),
newc AS (  -- first-ever orders by people in the segment within the window
    SELECT COUNT(*) AS seg_new_customers_12m
    FROM customer_orders c, p
    WHERE order_seq = 1 AND customer_state = p.segment_state
      AND purchased_at >= p.win_start AND purchased_at < p.win_end
),
segrep AS (
    SELECT AVG(repeat_180d::INT) AS seg_repeat_rate FROM first_order_cohort, p WHERE customer_state = p.segment_state
),
nat AS (SELECT AVG(is_late::INT) AS sp_late_rate FROM delivered WHERE customer_state = 'SP')
SELECT * , (rp.p_l - rp.p_o - 1.96 * SQRT(rp.p_l*(1-rp.p_l)/rp.n_l + rp.p_o*(1-rp.p_o)/rp.n_o)) AS ci_low_gap
FROM rv, rp, rs, seg, newc, segrep, nat;

-- name: opportunity_inputs
SELECT (SELECT segment_state FROM opp_params) AS segment,
       seg_orders_12m, seg_new_customers_12m, ROUND(seg_gmv_12m, 0) AS seg_gmv_12m_brl,
       ROUND(seg_late_rate * 100, 1) AS seg_late_rate_pct, ROUND(sp_late_rate * 100, 1) AS sp_late_rate_pct,
       ROUND(seg_avg_review, 2) AS seg_avg_review, ROUND(seg_repeat_rate * 100, 2) AS seg_repeat_rate_pct,
       ROUND(review_gap, 3) AS review_gap_stratified,
       ROUND(strat_gap * 100, 2) AS repeat_gap_low_pp, ROUND(raw_gap * 100, 2) AS repeat_gap_mid_pp,
       ROUND(ci_low_gap * 100, 2) AS repeat_gap_high_pp,
       ROUND(brl_per_repeater, 2) AS brl_per_repeater_180d
FROM opp_inputs;

-- name: opportunity_scenarios
WITH x AS (
    SELECT * FROM (VALUES ('X = 3 pts', 3.0), ('X = 5 pts', 5.0)) v(scenario, pts)
    UNION ALL
    SELECT 'X = parity with SP', ROUND((seg_late_rate - sp_late_rate) * 100, 1) FROM opp_inputs
), e AS (
    SELECT * FROM (VALUES ('low', 1), ('mid', 2), ('high', 3)) v(effect_case, k)
)
SELECT x.scenario, x.pts AS late_pts_cut, e.effect_case,
       ROUND(seg_late_rate * 100 - x.pts, 1)                         AS new_late_rate_pct,
       ROUND(seg_orders_12m * x.pts / 100, 0)                        AS late_orders_avoided_12m,
       ROUND(seg_avg_review - review_gap * x.pts / 100, 3)           AS new_avg_review,   -- gap is negative
       ROUND(seg_repeat_rate * 100, 2)                               AS repeat_rate_now_pct,
       ROUND((seg_repeat_rate - CASE k WHEN 1 THEN strat_gap WHEN 2 THEN raw_gap ELSE ci_low_gap END * x.pts / 100) * 100, 3) AS repeat_rate_new_pct,
       ROUND(-seg_new_customers_12m * x.pts / 100 * CASE k WHEN 1 THEN strat_gap WHEN 2 THEN raw_gap ELSE ci_low_gap END, 1) AS extra_repeat_customers_12m,
       ROUND(-seg_new_customers_12m * x.pts / 100 * CASE k WHEN 1 THEN strat_gap WHEN 2 THEN raw_gap ELSE ci_low_gap END * brl_per_repeater, 0) AS extra_repeat_revenue_brl_12m,
       ROUND(-seg_new_customers_12m * x.pts / 100 * CASE k WHEN 1 THEN strat_gap WHEN 2 THEN raw_gap ELSE ci_low_gap END * brl_per_repeater / seg_gmv_12m * 100, 3) AS pct_of_segment_gmv
FROM x, e, opp_inputs
ORDER BY x.pts, e.k;

-- Alternative framing that IS well-measured: bad reviews avoided.
-- name: opportunity_bad_reviews
WITH b AS (
    SELECT AVG(CASE WHEN is_late THEN (review_score <= 2)::INT END) - AVG(CASE WHEN NOT is_late THEN (review_score <= 2)::INT END) AS bad_gap
    FROM delivered WHERE review_score IS NOT NULL
)
SELECT pts AS late_pts_cut,
       ROUND(seg_orders_12m * pts / 100, 0) AS late_orders_avoided_12m,
       ROUND(seg_orders_12m * pts / 100 * bad_gap, 0) AS one_two_star_reviews_avoided_12m,
       ROUND(bad_gap * 100, 1) AS bad_review_gap_pp
FROM opp_inputs, b,
     (SELECT 3.0 AS pts UNION ALL SELECT 5.0 UNION ALL
      SELECT ROUND((seg_late_rate - sp_late_rate) * 100, 1) FROM opp_inputs) v
ORDER BY pts;
