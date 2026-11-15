"""Build web/index.html, a static (no-server) version of the dashboard, from results/*.csv.
Deployable as-is to Vercel, Netlify or GitHub Pages.  Usage: python scripts/build_web.py"""
import json, pathlib
import pandas as pd
ROOT = pathlib.Path(__file__).resolve().parent.parent
R = lambda n: pd.read_csv(ROOT / "results" / f"{n}.csv")
data = {k: json.loads(R(k).to_json(orient="records")) for k in [
    "population_summary", "review_late_vs_ontime", "review_gap_with_ci", "review_gap_stratified",
    "review_dose_response", "review_written_before_delivery", "repeat_late_vs_ontime", "repeat_gap_with_ci",
    "repeat_dose_response", "repeat_gap_stratified", "repeat_power", "segment_states", "late_rate_by_month",
    "seller_concentration", "late_seller_vs_carrier", "peak_share_of_late", "opportunity_inputs",
    "opportunity_scenarios", "opportunity_bad_reviews", "segment_categories"]}
tpl = (ROOT / "web" / "template.html").read_text()
frag = tpl.replace("/*__DATA__*/null", json.dumps(data))
(ROOT / "web" / "fragment.html").write_text(frag)   # body-only, used for the claude.ai artifact
(ROOT / "web" / "index.html").write_text(
    '<!doctype html>\n<html lang="en"><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">'
    '<style>body{margin:0;font:14px system-ui,sans-serif}</style></head><body>\n' + frag + '\n</body></html>\n')
print("wrote web/index.html")
