# E-commerce Analytics SQL Portfolio Project

## What this is

A portfolio project to demonstrate strong, intermediate-to-advanced **SQL and data analysis** skills using **Google BigQuery**. It's modeled on the relational shape real e-commerce companies run on (Shopify-style merchant systems: customers, orders, line items, products, inventory), built on top of Google's own public `thelook_ecommerce` dataset — a synthetic e-commerce dataset the Looker team built specifically for this kind of practice, and one that shows up constantly in real analyst interview case studies.

**Who this is for:** the project owner is a **data analyst**, not a data engineer. They have a Google Data Analytics Certificate, are comfortable with intermediate SQL (joins, aggregations, subqueries), and understand ETL/ELT and warehousing concepts conceptually — but the point of this project is to showcase analysis and SQL fluency, not to build or operate a production database. Keep that in mind when making implementation choices: prefer the simplest path that still produces genuinely impressive SQL, and don't add infrastructure for its own sake.

## Business framing update (2026-09-17): read `docs/business_context.md` first

The owner wants this project to simulate a real business, not a generic exercise. Where this brief conflicts with `docs/business_context.md`, the business context file wins:

- **Company:** **Northloom**, a fictional US-based online multi-brand fashion retailer that runs its own distribution centers. This replaces the "Shopify-style store" framing, because the data (thousands of brands, ~10 company-run DCs, wholesale cost, heavy returns) matches that kind of retailer much better.
- **Project name:** *Northloom: Commerce Analytics in BigQuery* (repo name `northloom-commerce-analytics`).
- **Queries:** 11 stakeholder tickets instead of 7. The original seven stay, and four are added: returns and margin leakage, conversion funnel, fulfillment SLA, and a weekly business review.
- **Layers:** raw → staging → data quality checks → marts → analysis. All of it stays inside BigQuery, and the no-OLTP / no-pipeline decision below still applies.
- **Extra docs:** `docs/business_context.md`, `docs/data_quality.md`, and `docs/findings.md` written as replies to stakeholders.
- **README:** a case study about Northloom. Situation: growth is getting more expensive. Action: built the analytics layer and answered the tickets. Result: specific findings plus recommendations.

## Decision already made — read this before doing anything else

Skip building or operating a custom operational (OLTP) database. **No Neon, no Supabase, no live pipeline for this project.** Everything happens inside BigQuery / Google Cloud Console:

1. Copy the public `bigquery-public-data.thelook_ecommerce` tables into a BigQuery dataset the owner controls.
2. Verify the real schema of what got copied (don't assume — check it).
3. Model a star schema from the copied tables.
4. Write a set of analytical SQL queries that demonstrate window functions, CTEs, and BigQuery-specific SQL.
5. Put a Looker Studio dashboard on top of the results.
6. Package it as a clean, presentable GitHub repo with a case-study README.

A Neon-hosted OLTP layer plus a real ETL/CDC pipeline was considered and explicitly deferred — it's an **optional stretch goal for a later iteration**, not part of this build. Don't build it unless the owner asks for it later.

## Cost and account prerequisites (owner handles these manually — verify, don't assume)

- A Google Cloud project with the BigQuery API enabled. New accounts get $300 in trial credit (90 days); beyond that, BigQuery's always-free tier is 10 GiB storage + 1 TiB of query processing per month, which comfortably covers this entire project — expect **$0 cost** in normal use.
- `gcloud` and `bq` CLI installed and authenticated locally (`gcloud auth login`, `gcloud config set project <PROJECT_ID>`), or access via the BigQuery Console UI as a fallback.
- Optional, only if we automate anything: Python 3.10+ with `google-cloud-bigquery` installed (`pip install google-cloud-bigquery`).

If any of these aren't set up yet, stop and ask the owner to complete them before running `bq`/`gcloud` commands — don't try to provision a GCP project or billing yourself.

## Step-by-step build plan

### 1. Create the working dataset

```bash
bq mk --dataset --location=US <PROJECT_ID>:ecommerce_analytics
```

### 2. Copy the public dataset's tables in

The public dataset has 7 tables: `users`, `orders`, `order_items`, `products`, `inventory_items`, `distribution_centers`, `events`. Copy each with a `CREATE TABLE ... AS SELECT`, e.g.:

```sql
CREATE TABLE `ecommerce_analytics.orders` AS
SELECT * FROM `bigquery-public-data.thelook_ecommerce.orders`;
```

Repeat for all 7 tables. This is a one-time copy, not a live sync — no pipeline, no ongoing cost.

### 3. Verify the real schema before writing analysis queries — do not skip this

The column list below is the well-documented public schema, but **confirm it against the actual copied tables** before relying on it, since public datasets occasionally change:

```sql
SELECT table_name, column_name, data_type
FROM `ecommerce_analytics.INFORMATION_SCHEMA.COLUMNS`
ORDER BY table_name, ordinal_position;
```

Write the confirmed schema to `docs/schema.md` (table name, column, type, one-line meaning) before moving on. Expected shape, to check against:

- `users`: id, first_name, last_name, email, age, gender, state, city, country, traffic_source, created_at
- `orders`: order_id, user_id, status, gender, created_at, returned_at, shipped_at, delivered_at, num_of_item
- `order_items`: id, order_id, user_id, product_id, inventory_item_id, status, created_at, shipped_at, delivered_at, returned_at, sale_price
- `products`: id, cost, category, name, brand, retail_price, department, sku, distribution_center_id
- `inventory_items`: id, product_id, created_at, sold_at, cost, product_category, product_name, product_brand, product_retail_price, product_department, product_distribution_center_id
- `distribution_centers`: id, name, latitude, longitude
- `events`: id, user_id, sequence_number, session_id, created_at, ip_address, city, state, postal_code, browser, traffic_source, uri, event_type

`events.traffic_source` is what makes the marketing-attribution query possible — it's the closest thing this dataset has to a marketing channel dimension.

### 4. Build the star schema

In the same `ecommerce_analytics` dataset, create:

- `dim_customers` — one row per user, enriched with signup cohort (`DATE_TRUNC(created_at, MONTH)`) and total lifetime order count/value. If time allows, make this a **Type 2 slowly changing dimension** (track segment changes over time with `valid_from`/`valid_to`) — a good technique to call out explicitly in the README as deliberate, not accidental.
- `dim_products`, `dim_date` — standard dimension tables.
- `fact_order_items` — one row per order line item, foreign keys to every dimension above, plus quantity/price measures from `order_items` joined to `products`.

Write each as its own `.sql` file under `sql/warehouse/`.

### 5. Write the seven signature analysis queries

Each goes in its own file under `sql/analysis/`, with a one-line comment at the top stating the business question. Use real window functions and CTEs — this is the actual point of the project:

| File | Technique | Business question |
| --- | --- | --- |
| `01_cohort_retention.sql` | `DATE_TRUNC`, window function partitioned by signup cohort | What % of customers who ordered in month 0 order again by month 3? |
| `02_rfm_segmentation.sql` | `NTILE()` across recency/frequency/monetary | Who are the top 10% highest-value customers right now? |
| `03_rolling_clv.sql` | `SUM() OVER (PARTITION BY user_id ORDER BY created_at)` | How does customer lifetime value accumulate over their first 12 months? |
| `04_inventory_turnover.sql` | CTE + ratio math over `inventory_items` | Which products are at stockout risk? |
| `05_marketing_attribution.sql` | `FIRST_VALUE()`/`LAST_VALUE()` over `events` partitioned by user, using `traffic_source` | Which channel gets credit for a sale — first touch or last touch — and does the answer change? |
| `06_market_basket.sql` | self-join `order_items` to itself on `order_id` | Which products are most often bought together? |
| `07_growth_by_category.sql` | `LAG()` partitioned by category | Which product categories are actually growing vs. flat, month over month? |

Each query file should be runnable standalone against `ecommerce_analytics` and include a short comment block: business question, technique used, and one sentence on what the result showed once you've run it.

### 6. Dashboard

Connect Looker Studio (free) directly to the `ecommerce_analytics` dataset. Build 3–4 visuals: cohort retention curve, RFM segment breakdown, channel attribution comparison, inventory risk list. This step is manual in the Looker Studio UI — Claude Code can prepare the underlying views/queries but not build the dashboard itself.

### 7. Package as a portfolio repo

```
/sql
  /warehouse      -- star schema DDL (step 4)
  /analysis       -- the seven signature queries (step 5)
/docs
  schema.md       -- verified schema from step 3
  findings.md     -- one paragraph per query: what you found, stated as a business insight
README.md         -- case study framing, not a file listing (see below)
```

`README.md` should read as a case study: situation (modeled a Shopify-style retailer's data), action (built the star schema and wrote these queries), result (a specific, stated finding — e.g. "first-touch attribution credited paid social with 40% of revenue while last-touch credited email"). Link to the dashboard. Do not describe this as "just querying a public dataset" — the framing is that the schema, the star-schema modeling, and the analysis are the owner's own work product built on top of real data.

## Definition of done

- [ ] All 7 source tables copied into `ecommerce_analytics`
- [ ] Verified schema documented in `docs/schema.md`
- [ ] Star schema (`dim_customers`, `dim_products`, `dim_date`, `fact_order_items`) built and queryable
- [ ] All 7 analysis queries written, run successfully, and commented
- [ ] `docs/findings.md` has one real insight per query
- [ ] Looker Studio dashboard built and linked from the README
- [ ] `README.md` reads as a case study, not a file listing

## Explicitly out of scope for this iteration

- Any Neon/Supabase-hosted OLTP database
- Any scheduled ETL/CDC pipeline (Datastream, Airbyte, cron jobs)
- Synthetic data generation — this project uses the public dataset as-is, copied once

If the owner later wants to add the pipeline-building stretch goal, that's a separate follow-up project, not a modification of this one.
