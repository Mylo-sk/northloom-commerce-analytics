# Northloom: Commerce Analytics in BigQuery

**An analytics layer and thirteen stakeholder investigations for a fictional online fashion retailer, built in BigQuery with SQL.**

Northloom sells third-party apparel brands online, ships worldwide from ten US distribution centers, and turns over about $5.1M a year. Leadership believed growth was getting more expensive and less profitable, and wanted to know why. Thirteen requests came in from the CEO, CFO, CMO, COO and five other stakeholders.

This repository contains the warehouse that answered them, and the answers.

> Northloom is fictional. The data is Google's public `thelook_ecommerce` dataset. The company, the stakeholders, the metric definitions, the analysis and every conclusion here are my own work.

---

## The headline

**The three things leadership worried about were not the three things costing the money.**

| Problem | Annual cost | Was anyone managing it? |
| --- | --- | --- |
| Inventory holding cost | **~$2.2M** | No |
| Cancellations | ~$790K of margin | No |
| Returns | ~$543K of margin | Discussed constantly |
| Retention | 76% of customer value arrives on day one | No |

Northloom carries $8.8M of stock against $2.6M of annual gross margin — **3.5 years of supply in every single category**. At a standard 25% carrying rate, holding that inventory consumes roughly 85% of the margin the business earns. Nobody had asked.

---

## Five findings worth reading

**1. The buying budget and the dead stock are the same problem.**
Men's Jeans and Men's Outerwear are the two largest categories — and the two worst performers relative to the company, together shedding 2.63 points of revenue share since 2021. They are also the two largest piles of trapped stock, at $698,718 and $646,000. Northloom holds the most inventory in precisely the two categories it is losing customers in. Two tickets (NL-104, NL-107) turned out to answer each other.

**2. The cancellations are a system failure, not customer behaviour.**
$1.58M of revenue never collected. Measured across eleven cuts — market, year, warehouse, channel, department, basket size, region, day of week, price band, order position — the widest spread was 1.6 points around a 15.0% average. Every cancellation is a whole order; not one order had part cancelled and the rest shipped. A customer's first-ever order cancels at 14.9%, their tenth at 15.1%. Something fails after the customer commits, at a constant rate, and **the reason code is not collected anywhere**.

**3. Returns do not cause churn. They predict loyalty.**
Customers who returned an item from their first order came back within a year **45.1% of the time, against 37.6% for those who kept everything**. This reversed my own earlier conclusion, which had read a correlation backwards. The recommendation flipped with it: make returning easy, and do not fund a returns-reduction programme on churn grounds.

**4. Two systems disagree about 70% of revenue.**
The clickstream credits Email with 45% of revenue and Paid Search with 30%. The signup record says Paid Search 70%, Email 5%. Email cannot introduce a customer, because you need an address before you can email one — so the clickstream is tagging returning visits, not acquisition. First-touch and last-touch attribution agreed within 2.9% on every channel, because customers average 1.6 sessions before buying. The attribution debate was moot; the tagging was the problem.

**5. The retention problem is already fixing itself.**
Repeat purchase within a year has risen every year since 2019, from 8.5% to 22.7%. In the P&L, new-customer dependence has fallen from 74.3% of revenue to 55.6% in eleven quarters. Nobody at Northloom was tracking it.

Full write-ups, with the numbers and the recommendation for each stakeholder: **[docs/findings.md](docs/findings.md)**.

---

## Three questions I answered "you can't"

A portfolio full of neat answers is a portfolio that didn't check anything. Three tickets came back negative, and the negatives took more work than the answers.

- **NL-110, warehouse performance.** 29.5% of order rows ship before they are ordered, at an identical rate in every warehouse, every status and every year since 2019 — an upstream clock or system problem, not an operations one. Delivery times then turned out to be 58–60 hours to *every region on earth*, Shanghai and Chicago alike, so they carry no geographic signal. The ticket cannot be answered and was closed with the reasoning documented.
- **NL-112, the Asia-Pacific warehouse.** 43.6% of revenue comes from Asia Pacific and China has grown 364% since 2021, so the premise is sound. But with no measurable delivery gap, the business case cannot be built from this data. The answer is "get carrier data first", plus a warning that opening a second site under current buying habits would need 83,000 units where 5,900 would do.
- **NL-109, the conversion funnel.** My first query reported a drop-off of **minus 58.1%**, which is impossible. Path-integrity checks showed why: 100% of sessions view a product while only 63.2% view a department, so the steps do not nest. The usable funnel is product → cart → purchase, and a department-page drop-off must never be published, because 36.8% of shoppers never see that page and are not lost there.

Four analytical errors of my own were caught and corrected during the work, each documented where it happened rather than quietly fixed. The most instructive: a cancellation rate of **0.0% for new customers and 35.4% for returning ones**, which was entirely an artifact of building the customer-type label on top of cancellation status. A metric built on an outcome cannot explain that outcome.

---

## How it was built

```
raw → staging → data quality → marts (star schema) → analysis → dashboard
```

**`northloom_raw`** — the seven source tables, copied once, never edited.

**`northloom_staging`** — cleaned views applying every shared definition exactly once: net revenue, gross margin using the cost of the physical unit sold, return rate against items shipped, and a fixed analysis date so results reproduce. It also reconciles two systems that name marketing channels differently (Search/Display versus Adwords/YouTube), and drops personal data before it reaches the marts.

**`northloom_marts`** — a star schema: `dim_customers`, `dim_products`, `dim_date`, `dim_distribution_centers`, `fact_order_items`, `fact_sessions`, `fact_inventory_snapshot`.

`dim_customers` is a **Type 2 slowly changing dimension**. A customer's segment is not a fact about them, it is a fact about them at a point in time, so each row is one spell in one segment with `valid_from` / `valid_to` dates. The VIP threshold is recalculated monthly, because the top 10% of spend in 2019 is not the top 10% in 2026. It is built with running totals per customer and a gaps-and-islands collapse that turns 92 monthly rows into one row per spell.

That design earns its keep immediately: **7,957 customers have reached VIP and 6,519 of them are no longer VIP.** A dimension that overwrote the current segment would show today's 1,438 VIPs and no trace of the 6,519 lost.

**Validation.** 36 data quality checks over the raw layer ([docs/data_quality.md](docs/data_quality.md)) and a marts test suite proving grain, uniqueness, SCD integrity (no overlapping spells, no gaps, one current row per customer) and reconciliation back to staging to the cent.

### SQL techniques used

Window functions (`LAG`, `FIRST_VALUE`, `LAST_VALUE`, `NTILE`, `RANK`, `ROW_NUMBER`, running `SUM`/`AVG`), gaps-and-islands for the Type 2 dimension, `QUALIFY`, self-joins for market basket affinity, cohort triangles, `APPROX_QUANTILES`, `GENERATE_DATE_ARRAY` spines, `INFORMATION_SCHEMA` for schema verification, and BigQuery scripting with `EXECUTE IMMEDIATE`.

---

## Repository

```
sql/
  raw/         load the source tables, verify the schema, profile the data
  quality/     36 data quality checks and the ship-timing investigation
  staging/     cleaned views, where every shared definition lives
  warehouse/   star schema dimensions, facts and the test suite
  analysis/    thirteen stakeholder queries, one file per ticket
docs/
  business_context.md   the company, the stakeholders, the metric definitions
  schema.md             verified source schema and the modelling decisions
  data_quality.md       what was wrong with the data and how each issue was handled
  findings.md           the thirteen answers, written as replies to stakeholders
```

Every analysis file opens with the ticket, the stakeholder, the question in their words, the technique and the grain of the result.

## Reproducing it

Needs a Google Cloud project with BigQuery enabled. Everything fits inside the free tier; expect $0.

```
1. sql/raw/00_load_raw.sql            copy the public dataset in (~1 min)
2. sql/quality/01_data_quality_checks.sql
3. sql/staging/01_stg_views.sql       cleaned layer
4. sql/warehouse/01_dimensions.sql    then 02_facts.sql, then 03_marts_tests.sql
5. sql/analysis/*.sql                 any order, no dependencies between them
```

Dataset names are unqualified, so the scripts run against whichever project is selected. The analysis date is fixed in one place (`northloom_staging.analysis_config`), because the public dataset is regenerated on a schedule and contains future-dated rows.

## Dashboard

**[View the Looker Studio dashboard →](https://datastudio.google.com/reporting/6fcb94a1-9137-4e38-8e21-2ca512c61220)**

Built directly on the marts, so every figure on it agrees with this repository by construction. Four core elements: trading scorecards, new versus returning revenue by quarter, where the cash is trapped, and growth against the company. Plus a cohort retention triangle and the customer segments.

What is deliberately *not* on it — the funnel, delivery times, channel attribution, and weekly returns and cancellations — and why, is set out in [docs/dashboard_spec.md](docs/dashboard_spec.md).

---

**Stack:** Google BigQuery · SQL · Looker Studio
**Data:** `bigquery-public-data.thelook_ecommerce`
