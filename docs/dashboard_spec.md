# Dashboard Specification (Looker Studio)

Build order for the Northloom dashboard. One page, seven elements, built in the Looker Studio UI on top of views that already exist in `northloom_marts`.

**Design rule: one page.** A recruiter or an executive gives a dashboard one screen and about twenty seconds. Everything here fits above the fold on a laptop, and the story reads left to right, top to bottom: how big, how healthy, is it improving, where is the money stuck.

**Build in two passes.** The four core elements tell the whole story on their own; the three extras are worth adding only if the page still breathes.

| Element | Tier | Why |
| --- | --- | --- |
| 1. Scorecard row | **Core** | Cheap to build, answers "how big is this business" |
| 3. New vs returning revenue | **Core** | The single best trend in the business |
| 6. Where the cash is trapped | **Core** | The largest cost, and half of the sharpest finding |
| 7. Growth against the company | **Core** | The other half — these two must sit side by side |
| 4. Cohort retention triangle | Extra | The chart interviewers recognise; add it second |
| 5. Customer segments | Extra | Most directly actionable, add it third |
| 2. Weekly revenue trend | Extra | Lowest value: element 3 already shows growth |

Four charts and a tile row is a finished dashboard. Seven is a busy one.

**Nothing computes a metric in the chart.** Every figure comes from a view, so the dashboard cannot disagree with `docs/findings.md`. If a number needs changing, it changes in SQL and every chart follows.

---

## Connecting

1. Open Looker Studio → **Create → Report → BigQuery connector**.
2. Choose the project, dataset `northloom_marts`, and the view named in each chart below.
3. Select **the view, not a custom query**. Custom queries in a dashboard are where definitions go to drift.
4. Set the report's default date range to **last 12 weeks**, and add one date range control at the top so a viewer can widen it.

---

## Element 1 — Scorecard row (four tiles, across the top)

**Source:** `vw_weekly_business_review`

| Tile | Metric | Setting |
| --- | --- | --- |
| Net revenue | `net_revenue` | SUM, currency, comparison to previous period |
| Gross margin | calculated field `Margin %` | see below |
| Orders | `orders` | SUM, comparison to previous period |
| **Revenue from returning customers** | calculated field `Returning share` | see below |

Two calculated fields, added once on the data source (**Resource → Manage added data sources → Edit → Add a field**):

| Field name | Formula | Type |
| --- | --- | --- |
| `Margin %` | `SUM(gross_margin) / SUM(net_revenue)` | Percent |
| `Returning share` | `SUM(revenue_from_returning_customers) / SUM(net_revenue)` | Percent |

**Why calculated, not averaged.** The view already has `margin_pct` and `pct_revenue_from_new_customers`, but averaging weekly percentages weights a quiet week the same as a busy one, so the tile would drift from the true figure as the date range widens. Ratio of sums is correct over any range.

The fourth tile is the one that matters. Returning share is currently about 44%, up from about 26% in 2023. A rising number reads as good news, which is why it is framed as returning rather than new.

---

## Element 2 — Weekly revenue trend (time series, full width under the tiles)

**Source:** `vw_weekly_business_review`
**Dimension:** `week_start` · **Metrics:** `net_revenue`, `revenue_4_week_avg`

Two lines: actual weekly revenue, and the four-week average as a smoother reference. Style the average as a thicker line and the weekly as thin.

*Shows:* uninterrupted growth, every quarter up, accelerating. It is the context for everything else on the page.

---

## Element 3 — New versus returning revenue (stacked 100% column)

**Source:** `vw_weekly_business_review`
**Dimension:** `week_start` (set to quarter granularity) · **Metrics:** `revenue_from_new_customers`, `revenue_from_returning_customers`

*Shows:* the single best trend in the business — the returning band growing from roughly a quarter of revenue to nearly half. Pair it with a text box: *"New-customer dependence fell from 74% to 56% in eleven quarters."*

---

## Element 4 — Cohort retention triangle (pivot table with heatmap)

**Source:** `vw_cohort_retention`
**Row dimension:** `cohort_month` · **Column dimension:** `months_since_first_purchase` · **Metric:** `retention_pct` (AVG)

Apply conditional formatting as a colour scale. Filter columns to 0–12 so the triangle stays readable.

*Shows:* the classic cohort triangle, and the improvement down the rows — newer cohorts holding better than older ones. This is the chart most likely to be recognised by an interviewer, so it earns its place even though the trend also appears in element 3.

---

## Element 5 — Customer segments (horizontal bar, sorted by revenue)

**Source:** `vw_rfm_segments`
**Dimension:** `rfm_segment` · **Metrics:** `monetary_value` (SUM), `user_id` (COUNT)

Sort descending by revenue. Add `campaign_action` as a tooltip or a second table column if space allows.

*Shows:* Champions at 13.7% of customers and 28.1% of revenue, and "Cannot lose them" — 3,746 customers worth as much each as Champions whose last order was three years ago. The most directly actionable chart on the page.

---

## Element 6 — Where the cash is trapped (table with bars)

**Source:** `vw_stock_position`
**Dimension:** `category` · **Metrics:** `stock_value_at_cost` (SUM), `annual_holding_cost` (SUM), `units_sold_90d` (SUM)

Sort by stock value descending, limit to 10 rows, and turn on bar rendering in the stock value column.

*Shows:* $8.8M of stock, led by Men's Jeans and Men's Outerwear. Put it directly beside element 7, because together they make the sharpest point in the project.

---

## Element 7 — Growth against the company (bar chart, diverging)

**Source:** `vw_category_growth`
**Dimension:** `category` · **Metric:** `growth_vs_company_pts`

Sort ascending so the losers appear at the top. Colour negative bars red and positive green if the chart type allows.

*Shows:* Men's Jeans at −91.6 points and Men's Outerwear at −55.5 — the two biggest categories losing ground fastest. Sitting next to element 6, the viewer sees unaided that **the most stock is held in the two worst-performing categories**. Add a text box between them: *"The two largest categories are the two biggest share losers — and hold $1.34M of stock between them."*

---

## Deliberately not on the dashboard

Worth saying in an interview, because knowing what not to publish is the harder judgement:

- **No conversion funnel.** The steps do not nest (36.8% of sessions reach a product without a department page), so a funnel chart would invent a drop-off that does not exist.
- **No delivery-time or warehouse-performance chart.** Delivery times are 58–60 hours to every region on earth; they carry no geographic signal.
- **No channel attribution chart.** Two systems disagree about 70% of revenue, and publishing either one would settle a budget argument with a number that cannot be trusted.
- **No weekly returns or cancellations chart.** Both have been flat for eleven quarters. A chart of a constant invites people to react to noise. They belong in a quarterly exception report with a threshold.

---

## Finishing touches

- Title the report **"Northloom — Commerce Analytics"** with a one-line subtitle: *fictional retailer, real public data*.
- Add a footer text box crediting the source dataset and linking to the GitHub repository.
- **File → Share → set link access to "Anyone with the link can view"**, otherwise the link in the README opens a permission screen for everyone who clicks it.
- Paste the share URL into the Dashboard section of `README.md`.
