"""Streamlit dashboard: does late delivery hurt Olist reviews and repeat purchase?

Run:  python scripts/run_sql.py && streamlit run app.py
Every number on this page is read from results/*.csv, written by the SQL in sql/.
"""
import pathlib
import pandas as pd
import plotly.express as px
import streamlit as st

ROOT = pathlib.Path(__file__).parent
RES = ROOT / "results"
ONTIME, LATE = "#2a78d6", "#eb6834"   # categorical slots 1 and 2 (validated palette)

st.set_page_config(page_title="Olist late deliveries", layout="wide")


@st.cache_data
def r(name: str) -> pd.DataFrame:
    return pd.read_csv(RES / f"{name}.csv")


if not (RES / "population_summary.csv").exists():
    st.error("No results yet. Run `python scripts/run_sql.py` first.")
    st.stop()

pop = r("population_summary").iloc[0]
rv = r("review_late_vs_ontime").set_index("delivery")
gap = r("review_gap_with_ci").iloc[0]
strat = r("review_gap_stratified")
rp = r("repeat_late_vs_ontime").set_index("first_delivery")
rgap = r("repeat_gap_with_ci").iloc[0]
power = r("repeat_power").iloc[0]


def style(fig, h=340):
    fig.update_layout(height=h, margin=dict(l=10, r=10, t=40, b=10), legend_title_text="",
                      plot_bgcolor="rgba(0,0,0,0)", paper_bgcolor="rgba(0,0,0,0)")
    fig.update_xaxes(showgrid=False)
    fig.update_yaxes(gridcolor="rgba(128,128,128,0.2)")
    return fig


st.title("Late deliveries at Olist: what they cost, and where")
st.caption(f"{int(pop.delivered_orders):,} delivered orders, {pop.first_purchase} to {pop.last_purchase}. "
           "Late = delivered on a day after the promised date. All figures come from the SQL in /sql.")

c = st.columns(4)
c[0].metric("Late rate", f"{pop.late_rate_pct:.1f}%", help=f"{int(pop.late_orders):,} late orders")
c[1].metric("Review, late vs on time", f"{rv.loc['late','avg_review']:.2f} vs {rv.loc['on_time','avg_review']:.2f}",
            f"{gap.gap_late_minus_ontime:+.2f} stars")
c[2].metric("Gap within same seller and month", f"{strat.iloc[0].weighted_gap:+.2f} stars")
c[3].metric("6-month repeat, late vs on time", f"{rp.loc['late','repeat_rate_pct']:.2f}% vs {rp.loc['on_time','repeat_rate_pct']:.2f}%",
            f"{rgap.gap_pp:+.2f} pp (not significant)", delta_color="off")

tab1, tab2, tab3, tab4 = st.tabs(["(a) Reviews", "(b) Repeat purchase", "(c) Who is hit worst", "Opportunity sizing"])

with tab1:
    st.subheader(f"Late orders score {abs(gap.gap_late_minus_ontime):.2f} stars lower "
                 f"(95% CI {gap.ci95_low} to {gap.ci95_high})")
    dr = r("review_dose_response")
    dr["label"] = dr.lateness_bucket.str[4:]
    dr["status"] = ["late" if "late" in b else "on time / early" for b in dr.lateness_bucket]
    fig = px.bar(dr, x="label", y="avg_review", color="status", text="avg_review",
                 color_discrete_map={"late": LATE, "on time / early": ONTIME},
                 hover_data={"orders": ":,", "pct_1_2_star": True, "label": False},
                 labels={"label": "Delivered vs promised date", "avg_review": "Average review (1-5)"},
                 title="Dose-response: the more days late, the lower the score")
    fig.update_traces(texttemplate="%{text:.2f}", textposition="outside", marker_cornerradius=4)
    st.plotly_chart(style(fig, 380), width="stretch")
    b = r("review_written_before_delivery").set_index("delivery")
    st.info(f"**Mechanism:** {b.loc['late','pct_review_before_delivery']:.1f}% of late-order reviews were written "
            f"*before the parcel arrived* (Olist sends the survey around the promised date). Those average "
            f"{b.loc['late','avg_if_before']:.2f} stars; late orders reviewed after arrival average "
            f"{b.loc['late','avg_if_after']:.2f}.")
    st.markdown("**Robustness: compare like with like**")
    st.dataframe(strat, hide_index=True)
    st.dataframe(rv.reset_index(), hide_index=True)

with tab2:
    st.subheader(f"Repeat within 180 days: {rp.loc['late','repeat_rate_pct']:.2f}% after a late first order vs "
                 f"{rp.loc['on_time','repeat_rate_pct']:.2f}% after an on-time one")
    st.warning(f"The gap is {rgap.gap_pp:+.2f} pp (95% CI {rgap.ci95_low_pp} to {rgap.ci95_high_pp}), "
               f"not statistically significant. Only {int(rp.repeaters.sum()):,} of {int(rp.customers.sum()):,} cohort "
               f"customers came back. With this sample the smallest drop we could reliably detect is "
               f"{power.min_detectable_drop_pp} pp ({int(power.min_detectable_drop_relative_pct)}% relative). "
               "Treat this as 'directionally negative, unproven'.")
    rd = r("repeat_dose_response")
    rd["label"] = rd.lateness_bucket.str[3:]
    rd["status"] = ["late" if "late" in b else "on time / early" for b in rd.lateness_bucket]
    fig = px.bar(rd, x="label", y="repeat_rate_pct", color="status", text="repeat_rate_pct",
                 color_discrete_map={"late": LATE, "on time / early": ONTIME},
                 hover_data={"customers": ":,", "repeaters": True, "label": False},
                 labels={"label": "First order delivered vs promise", "repeat_rate_pct": "Repeat within 180 days (%)"},
                 title="Repeat rate by lateness of the first order")
    fig.update_traces(texttemplate="%{text:.2f}%", textposition="outside", marker_cornerradius=4)
    st.plotly_chart(style(fig), width="stretch")
    st.dataframe(r("repeat_gap_stratified"), hide_index=True)
    st.dataframe(r("repeat_by_first_review"), hide_index=True)

with tab3:
    seg = st.radio("Segment", ["States", "Categories", "Sellers"], horizontal=True)
    if seg == "States":
        s = r("segment_states").sort_values("late_rate_pct")
        fig = px.bar(s, y="state", x="late_rate_pct", orientation="h", color_discrete_sequence=[LATE],
                     hover_data={"orders": ":,", "late_orders": ":,", "stars_lost": ":,", "avg_days_to_deliver": True},
                     labels={"late_rate_pct": "Late rate (%)", "state": "Customer state"},
                     title="Late rate by customer state (states with 300+ orders)")
        fig.update_traces(marker_cornerradius=4)
        st.plotly_chart(style(fig, 620), width="stretch")
        st.markdown("RJ ranks 7th on late rate but **1st on review stars lost**, because it pairs a 12% late rate "
                    "with the second-largest volume.")
        st.dataframe(r("rj_breakdown"), hide_index=True)
        st.dataframe(r("route_late_rate"), hide_index=True)
        st.dataframe(r("segment_states"), hide_index=True)
    elif seg == "Categories":
        st.dataframe(r("segment_categories"), hide_index=True)
    else:
        st.dataframe(r("seller_concentration"), hide_index=True)
        st.dataframe(r("segment_sellers"), hide_index=True)
    m = r("late_rate_by_month")
    fig = px.line(m, x="month", y="late_rate_pct", markers=True, color_discrete_sequence=[LATE],
                  hover_data={"orders": ":,", "avg_review": True},
                  labels={"late_rate_pct": "Late rate (%)", "month": "Purchase month"},
                  title="Late rate by month: peaks in Nov 2017 and Feb-Mar 2018")
    fig.update_traces(line_width=2, marker_size=8)
    st.plotly_chart(style(fig), width="stretch")

with tab4:
    inp = r("opportunity_inputs").iloc[0]
    st.subheader(f"If RJ's late rate ({inp.seg_late_rate_pct}%, last 12 months) fell by X points")
    sc = r("opportunity_scenarios")
    case = st.select_slider("Repeat-effect assumption", ["low", "mid", "high"], value="mid",
                            help=f"low = stratified {inp.repeat_gap_low_pp} pp, mid = raw {inp.repeat_gap_mid_pp} pp, "
                                 f"high = CI bound {inp.repeat_gap_high_pp} pp per late first order")
    st.dataframe(sc[sc.effect_case == case].drop(columns=["effect_case", "repeat_rate_now_pct"]), hide_index=True)
    st.dataframe(r("opportunity_bad_reviews"), hide_index=True)
    st.markdown(
        f"**Read-out:** even at parity with SP, extra repeat revenue is tiny (well under 0.1% of RJ's "
        f"R$ {inp.seg_gmv_12m_brl:,.0f} 12-month GMV) because only ~2% of Olist customers ever come back. "
        "The defensible case for fixing late delivery is review quality (+0.2 stars in RJ, ~500 fewer "
        "1-2 star reviews a year), not retention revenue.")
    st.caption("Assumptions A1-A6 are listed at the top of sql/05_opportunity.sql and in the README.")
