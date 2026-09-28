# Business Context: Northloom

> Northloom is a **fictional** company. The data comes from Google's public `thelook_ecommerce` dataset. Everything in this file sets the business scene that the analysis works in.

## Why not "a Shopify store"

A typical Shopify merchant is one brand with a small catalog, shipping from one warehouse or a 3PL. The data in `thelook_ecommerce` doesn't look like that:

| What the data contains (check it in step 3) | What that means in real life |
| --- | --- |
| Thousands of brands across ~26 apparel categories (Jeans, Outerwear, Intimates, Swim, Active…) | A **multi-brand fashion retailer** that buys stock from many brands, like ASOS, Zalando, Nordstrom.com or Revolve |
| Men's and Women's departments | Buying and merchandising teams split by department |
| ~10 company-run distribution centers across the US (Memphis, Chicago, Houston, LA, NY/NJ…) | The retailer runs **its own fulfillment network**, which Shopify merchants rarely do |
| Unit cost and retail price on every item | Wholesale buying with real **gross margin** decisions |
| Order statuses include `Returned` and `Cancelled` | **Returns** are the biggest profit problem in online fashion (industry return rates of 20–30%+) |
| Customers in many countries, with traffic sources (Search, Organic, Facebook, Email, Display) | Multi-country demand and a paid-marketing budget to defend |
| Clickstream `events` (home → department → product → cart → purchase) | A real site with a **conversion funnel** to analyse |

**Decision:** the data is best framed as a **US-headquartered online multi-brand fashion retailer that runs its own distribution centers**. That lets the project cover the problems these companies really face: returns eating into margin, marketing budget allocation, stock risk, and delivery speed.

## What the profiled data actually shows (measured 2026-09-17)

Numbers from [sql/raw/04_profile_raw.sql](../sql/raw/04_profile_raw.sql). These set the scale of the business and shaped the decisions below.

| Measure | Value | What it means for Northloom |
| --- | --- | --- |
| Customers | 100,000 | A mid-sized retailer, not a startup |
| Orders / order items | 124,581 / 180,858 | About 1.45 items per order, so basket-building has room to grow (NL-106) |
| Products / brands / categories | 29,120 / 2,756 / 26 | A wide third-party catalog, so the buying team needs category-level guidance |
| Stock units | 488,014 | Roughly 17 units per product across 10 DCs |
| Clickstream events | 2,425,353 | Enough to build a real funnel |
| History | Jan 2019 – Sep 2026 | Almost 8 years, enough for year-over-year cohorts |
| Cancelled orders | 14.9% | Unusually high, and worth a ticket of its own |
| Returned orders | 10.0% | Low for fashion, but the margin cost is still large |
| Gross margin at list price | 51.9% | Typical apparel retail, so discounting and returns decide real profit |
| Retail price range | $0.02 – $999 | The $0.02 end is almost certainly a data problem, not a product |

**The market mix is the biggest surprise.** Customers are mostly outside the US:

| Market | Customers |
| --- | --- |
| China | 34,148 |
| United States | 22,589 |
| Brazil | 14,639 |
| South Korea | 5,387 |
| France, UK, Germany, Spain | ~17,000 combined |

Yet all 10 distribution centers are in the US (Memphis, Chicago, Houston, Los Angeles, New Orleans, NY/NJ, Philadelphia, Mobile, Charleston, Savannah). **Northloom's largest market is served from warehouses on the other side of the world.** That is a real and common situation for a retailer that grew internationally through its website before its supply chain caught up, and it drives a new ticket, NL-112.

## The company

**Northloom** sells third-party apparel brands online. It's headquartered in the US and ships worldwide from its own US distribution centers. It buys stock wholesale and ships direct to customers.

The business is growing, but leadership thinks growth is getting **more expensive and less profitable**. Marketing spend keeps rising, returns seem to be climbing in some categories, nobody agrees on which channel is really bringing in customers who come back, and almost one order in seven is cancelled before it ships.

You are the **data analyst** who has just joined the new Analytics team. Your first job is to build a clean analytics layer in BigQuery, then answer the leadership team's open questions.

## Stakeholders and their requests

Each analysis query answers a request from a named stakeholder. Write the result the way you'd report back to them.

| Ticket | Stakeholder | Request | Query |
| --- | --- | --- | --- |
| NL-101 | VP Growth / CRM | "Are the customers we acquire this year worse than last year's? Are they coming back?" | `01_cohort_retention.sql` |
| NL-102 | CRM Manager | "I need a VIP list and an at-risk list for next month's email campaigns." | `02_rfm_segmentation.sql` |
| NL-103 | CFO | "What is a customer worth over their first 12 months? I need it to set how much we can spend to acquire one." | `03_rolling_clv.sql` |
| NL-104 | Head of Supply Chain | "Which stock is sitting in the warehouse tying up cash, and what should we clear?" | `04_inventory_turnover.sql` |
| NL-105 | CMO | "Finance wants to cut Facebook spend. Does Facebook bring in customers, or just take credit for them?" | `05_marketing_attribution.sql` |
| NL-106 | Merchandising Lead | "What do customers buy together? We want to build bundles and 'complete the look' recommendations." | `06_market_basket.sql` |
| NL-107 | Head of Buying | "Which categories are really growing, and which are flat? We're setting next season's buying budget." | `07_growth_by_category.sql` |
| NL-108 | CFO / Head of Buying | "Returns are killing us. Which categories and brands have the worst return rates, and how much margin are we losing?" | `08_returns_margin_leakage.sql` |
| NL-109 | Head of Ecommerce | "Where in the site do we lose shoppers between landing and checkout, and does it differ by channel or device?" | `09_conversion_funnel.sql` |
| NL-110 | Head of Operations | "Which distribution centers are slowest from order to delivery, and does slow delivery lead to more returns?" | `10_fulfillment_sla.sql` |
| NL-111 | CEO | "Give me one weekly business review table: revenue, orders, AOV, margin, return rate and new vs. returning customers." | `11_weekly_business_review.sql` |
| NL-112 | COO | "China is our biggest market but every parcel ships from the US. What would an Asia-Pacific distribution center be worth?" | `12_international_fulfillment.sql` |
| NL-113 | Head of Ecommerce | "Nearly 15% of orders are cancelled. Which ones, and what do they have in common?" | `13_cancellation_analysis.sql` |

Tickets NL-108 to NL-111 were added to the original seven queries. Returns, the conversion funnel, fulfillment and a weekly KPI review are the first questions a real fashion retailer's leadership would ask. NL-112 and NL-113 came out of profiling the data: the market-versus-warehouse mismatch and the 14.9% cancellation rate are the two things a real analyst would raise unprompted after a first look.

## Metric definitions (agree on these before writing queries)

Real analytics teams write these down first so every query reports the same numbers.

- **Gross revenue:** `SUM(sale_price)` for order items not `Cancelled`.
- **Net revenue:** gross revenue minus items with status `Returned`.
- **Gross margin:** net revenue minus `SUM(product cost)` for the items kept (not returned).
- **Return rate:** returned items ÷ shipped items (units), also reported by value.
- **AOV (average order value):** net revenue ÷ number of orders that weren't cancelled.
- **Active customer:** placed at least one order that wasn't cancelled in the last 12 months.
- **New vs. returning:** an order is "new" if it's the customer's first order that wasn't cancelled.
- **Analysis date:** the raw data runs to 2026-09-21, ahead of the day it was profiled, because the public dataset is regenerated on a schedule. Every query uses a fixed **`as_of_date` of 2026-09-17**, and monthly trends stop at the last complete month, **August 2026**. This keeps results reproducible and stops a part-finished month looking like a crash in sales. The date is defined once in `northloom_staging.analysis_config` so it can be changed in one place.

### Marketing channel: the two systems don't agree

Signup records and clickstream records use different channel names, which is exactly what happens when a website analytics tool and a CRM are set up by different teams:

| `users.traffic_source` (at signup) | `events.traffic_source` (per visit) |
| --- | --- |
| Search (70,012) | Adwords (723,908) |
| Organic (14,977) | Organic (120,402) |
| Facebook (5,957) | Facebook (244,490) |
| Email (5,028) | Email (1,094,256) |
| Display (4,026) | YouTube (242,297) |

Neither list can be reported next to the other as-is. The staging layer maps both to one shared set of channel names, and that mapping is the single agreed definition:

| Shared channel | From signup | From events |
| --- | --- | --- |
| Paid Search | Search | Adwords |
| Organic | Organic | Organic |
| Paid Social | Facebook | Facebook |
| Email | Email | Email |
| Display & Video | Display | YouTube |

The gap is itself a finding for the CMO (NL-105): attribution is currently impossible to do consistently because the two systems don't share a vocabulary.

## What the warehouse build settled (2026-09-18)

Three findings from validating the star schema ([sql/warehouse/03_marts_tests.sql](../sql/warehouse/03_marts_tests.sql)) that change what can and can't be asked:

1. **Northloom never discounts.** All 178,552 items sold at exactly list price. There is no discount analysis to do, so the margin questions (NL-108) rest entirely on returns, cancellations and product mix. Saying so plainly is better than implying a pricing analysis the data can't support.
2. **The inventory problem is the opposite of the one NL-104 assumed.** Not a single product-warehouse combination is at risk of running out. Instead, 14,051 rows are dead stock ($3.77M at cost) and 14,791 are overstocked ($5.07M at cost). Northloom holds **$8.8M of stock against $9.06M of lifetime revenue**, which is years of cover. NL-104 is rewritten to ask what to clear, not what will run out.
3. **The website data over-converts.** Sessions convert at 26.2%, where real fashion e-commerce runs at 2–3%. The clickstream is synthetic and too generous. Funnel work must therefore compare channels and steps **against each other**, never quote the absolute rate as if it were real.

Two numbers worth carrying into the analysis, both of which point at retention:

- **68% of net revenue comes from first-time buyers** ($5.45M of $8.02M). Northloom is buying growth rather than keeping it.
- **Of 7,957 customers who ever reached VIP, 6,519 are no longer VIP.** Four in five of the best customers were lost. This is exactly the question a Type 1 dimension could never answer.

## How the work is done (analytics-team realism, no extra infrastructure)

Everything stays inside BigQuery. The realism comes from *how* the work is organised, not from extra tools:

GCP project: `northloom-analytics`. Scripts reference datasets unqualified, so they run against whichever project is selected in the Console. Each layer gets its own BigQuery dataset (all in the `US` location): `northloom_raw`, `northloom_staging`, `northloom_marts`.

1. **Raw layer (`northloom_raw`):** tables copied once from the public dataset. Never edit these.
2. **Staging layer (`northloom_staging`):** `stg_*` views that rename columns, cast types, and apply the metric definitions above.
3. **Data quality checks:** queries that flag problems such as orphaned order items, negative prices, delivery dates before ship dates, duplicate IDs and future-dated rows. Log what you find and how you handled it in `docs/data_quality.md`, because real data is never clean.
4. **Marts (star schema):** `dim_customers` (Type 2 SCD on RFM segment), `dim_products`, `dim_date`, `dim_distribution_centers`, `fact_order_items`, `fact_events`.
5. **Analysis:** the 11 ticket queries, each run against the marts.
6. **Communication:** `docs/findings.md` is written as replies to stakeholders, with an insight, the number behind it, and a recommendation. The Looker Studio dashboard is the executive view.
