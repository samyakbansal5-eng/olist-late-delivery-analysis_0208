# Resume bullets and interview prep

## Resume bullets
- Analysed 96K Olist e-commerce orders in SQL/DuckDB (CTEs, window functions, cohorts): late deliveries (6.8% of orders) cut review scores by 1.9 stars (4.29 -> 2.27, robust within seller x month); found 48% of late orders came from 3 peak months and 74.5% of late-order reviews were written before the parcel arrived.
- Sized the worst segment (Rio de Janeiro, 14.9% late vs 4.5% in São Paulo): reaching parity avoids ~970 late orders and ~520 one/two-star reviews a year (+0.2 stars), while showing the retention upside was under R$1.4K/yr (repeat effect not significant); turned this into a 4-item ICE-ranked roadmap and a Streamlit dashboard.

## 8 tough interview questions

**1. How do you know late delivery caused the review drop?**
I don't know it for certain; it's observational. Three things make causation the most likely reading. First, the gap barely moves when I compare late and on-time orders from the same seller in the same month (-1.93 vs -2.02 raw), so seller quality and seasonality aren't driving it. Second, there's a dose-response: 4.03 stars on the promised day, 3.29 at 1-3 days late, 2.10 at 4-7, 1.67 at 8-14. Third, there's a mechanism: 74.5% of late-order reviews were written before the parcel arrived. To prove it I'd run a regression discontinuity around the promised date (1 day early vs 1 day late) or randomise the promised date buffer.

**2. Your repeat-purchase effect isn't significant. Isn't the project a failure?**
No, it changed the recommendation. The gap is -0.38 pp with a CI of -0.89 to +0.13, and the sample could only detect drops of 0.79 pp or more. Only 2% of customers ever reorder, so even a real effect is worth under R$1.4K a year in RJ. That told me not to sell this as a retention play, and to build the case on review quality instead.

**3. Why customer_unique_id and not customer_id?**
Olist creates a new customer_id for every order, so customer_id gives 0% repeat. customer_unique_id is the person. It turns 99,441 customer_ids into 96,096 people.

**4. How did you avoid right-censoring in the 6-month window?**
I set the data end as the last day with 100+ orders (2018-08-29; the file has a near-empty tail) and only kept first orders purchased and delivered at least 180 days before it. That leaves first orders from Sep 2016 to Feb 2018, 51,035 customers.

**5. Why is RJ the "worst" segment when AL has a 21% late rate?**
AL has 397 orders. I ranked by stars lost (late reviewed orders x review gap), which combines rate and volume. RJ has 12,350 orders at 12.1% late, so it loses the most stars (3,391) and is where a fix moves the platform average. AL is worst per order, RJ is worst in total.

**6. What's your biggest data-quality risk?**
The "estimated delivery date" is Olist's promise, and it's padded: on-time orders arrive 13.5 days early on average (late ones are 10.6 days late, median 7). So "late" means "broke a generous promise", which is often a carrier failure. Also, a multi-seller order is attributed to the seller of its most expensive item, and ~550 orders have multiple reviews (I kept the latest).

**7. If you had to pick one roadmap item, which and why?**
Peak-season carrier capacity. 48% of late orders came from three months holding 22% of orders, and late orders spend 27.9 days with the carrier vs 7.9 on time, while sellers missed their hand-off in only 28% of late orders. It's the biggest, best-evidenced pool. Moving the review survey to after delivery is the quick win to ship alongside it, but it's partly a measurement fix, so it needs an A/B test.

**8. How would you measure success after launch?**
Primary: late rate on target lanes in peak months, and average review on late orders. Guardrails: checkout conversion (if promises get longer) and cost per order. Retention as a secondary metric through a randomised holdout, because the historical data can't settle it.
