# Late-delivery roadmap (one page)

**Problem.** 6.8% of delivered Olist orders arrive after the promised date. Those orders score
**2.27 vs 4.29 stars** (-1.93 even within the same seller and month), and 62% of them get a 1-2 star
review vs 9% of on-time orders. The effect on 6-month repeat purchase is small and **not statistically
significant** (-0.38 pp, 95% CI -0.89 to +0.13), so this roadmap optimises for **review quality and
late-order volume**, and treats retention as a hypothesis to test, not a promised outcome.

**Where the late orders come from** (from `sql/04_segments.sql`)
- **Time:** 48% of all late orders were bought in 3 months (Nov-17, Feb-18, Mar-18) that hold 22% of orders. RJ hit 31% late in those months.
- **Carrier leg:** late orders spend 27.9 days with the carrier vs 7.9 for on-time ones; the seller missed its hand-off deadline in only 28% of late orders.
- **Geography:** cross-state deliveries to North/Northeast/Centre-West customers are 10.2% late vs 4.5% same-state in the South/Southeast. RJ loses the most stars (12,350 orders, 12.1% late vs SP 4.5%).
- **Sellers:** the 100 sellers with the most late orders (of 2,959) carry 50% of late orders but 42% of orders.

Scoring: Impact (H/M/L) on late orders and stars, Effort (person-weeks, rough), Confidence that the data supports the impact. Ranked by Impact x Confidence / Effort.

| # | Initiative | What ships | Impact | Effort | Confidence | Success metric |
|---|---|---|---|---|---|---|
| 1 | **Peak-season carrier capacity + promise buffer** | Before Black Friday and Feb-Mar, pre-book carrier capacity on SP->RJ/NE lanes and auto-add buffer days to the promised date when lane backlog is high | **High** - targets the months holding 48% of late orders | Medium (4-6 wks, ops + ETA config) | **Medium-High** - the spike pattern is large and repeats across states; cause (carrier capacity vs strikes/weather) needs ops confirmation | Peak-month late rate from 12-19% to <8%; RJ peak late rate from 31% |
| 2 | **Send the review survey after confirmed delivery, plus a proactive delay message** | Trigger the review email on the delivered event instead of the promised date; when a parcel will miss its date, notify the buyer with a new ETA | **Medium** - 74.5% of late-order reviews were written *before arrival* (avg 1.84 vs 3.53 after); protects seller ratings and search ranking from "where is my parcel" scores | **Low** (1-2 wks, messaging config) | **Medium** - the 1.84 vs 3.53 split is confounded (the latest parcels are both reviewed early and most annoying), so the true uplift needs an A/B test | Late-order avg review; % of reviews mentioning delivery; buyer contacts per late order |
| 3 | **Late-seller program for the top-100 offenders** | Weekly seller scorecard (hand-off vs deadline, late rate), dispatch-SLA nudges, then search demotion for repeat misses | **Medium** - 50% of late orders are in these sellers, but sellers caused only ~28% of late orders (missed hand-off) | Medium (3-4 wks) | **Medium** - concentration is measured; how much behaviour changes under a scorecard is not | Top-100 late rate; % orders handed off after deadline |
| 4 | **Lane-aware delivery estimates for cross-state N/NE and RJ** | Train ETA on lane x season history so the promise is honest, instead of one national buffer | Medium - turns some "late" into "slow but as promised" | **High** (6-10 wks, data science + checkout) | **Low-Medium** - longer promises may cut conversion; needs a checkout A/B test | Late rate on target lanes with no drop in checkout conversion |

**Not on the roadmap (yet):** a retention play (e.g. a voucher after a late delivery). The data can't
show late delivery reduces repeat purchase; only ~2% of customers ever reorder, and this sample can only
detect a drop of 0.79 pp or more. Run a randomised holdout on the voucher before building anything.

**Sizing for the worst segment (RJ)** is in `sql/05_opportunity.sql`: bringing RJ's 14.9% late rate
(last 12 months) to SP's 4.5% avoids ~972 late orders and ~517 one/two-star reviews a year and lifts
RJ's average review from 3.89 to ~4.09. Extra repeat revenue would be only R$325-1,364 a year
(<0.1% of RJ's R$1.55M GMV), which is why the case is built on reviews, not retention.
