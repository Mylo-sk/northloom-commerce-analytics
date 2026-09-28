# Data Quality Report: `northloom_raw`

Run on 2026-09-17 with [sql/quality/01_data_quality_checks.sql](../sql/quality/01_data_quality_checks.sql): 36 checks covering referential integrity, key uniqueness, business rules, timestamp logic, money values, dimension consistency and missing values.

**Verdict: the data is fit for analysis, with three caveats that have to be stated whenever results are reported.** Every join in the star schema holds, every key is unique, and no money value is impossible. The problems are all in timestamps and dimension values.

## Summary

| Result | Checks |
| --- | --- |
| Passed with zero failures | 28 |
| Failed, handled in staging | 5 |
| Context to state as a caveat | 3 |

## Issues found

### 1. 35,699 items shipped before they were ordered — BLOCKER

Nearly one line item in five (19.7% of 180,858) has `shipped_at` earlier than `created_at`. That's physically impossible and it directly threatens the fulfillment question (NL-110), which is built on time from order to ship to delivery.

[sql/quality/02_ship_timing_investigation.sql](../sql/quality/02_ship_timing_investigation.sql) narrowed it down. Of 116,878 shipped items, 34,471 (29.5%) ship before they're ordered:

| What was tested | Result |
| --- | --- |
| How far out are they? | 453 rows by under an hour, 11,766 by up to a day, **22,252 by up to a week**. Too large to be clock drift |
| Confined to one warehouse? | No. Every one of the 10 DCs sits between 29.1% and 30.1% |
| Confined to one order status? | No. Complete 29.2%, Shipped 29.8%, Returned 29.4% |
| Getting better or worse? | Neither. Every year from 2019 to 2026 sits between 28.6% and 31.1% |
| Is the rest of the timeline sane? | Yes. On the bad rows, 18,270 of 18,271 delivered items still have delivery after shipping |

**Diagnosis:** the same share fails in every warehouse, every status and every year, so this isn't a warehouse or a process going wrong. The ship timestamp is being written by something that doesn't reference the order timestamp at all: a separate system, or a clock that isn't synchronised. Only the **order-to-ship leg** is affected. The **ship-to-delivery leg is intact**, even on the bad rows.

**Handling:**

1. Revenue and margin keep every row, since they don't use timestamps.
2. The fact table carries `has_valid_ship_timeline`, so the exclusion is visible rather than silent.
3. **Ship-to-delivery time becomes the primary measure of fulfillment performance** (NL-110, NL-112), because it's reliable on 99.99% of rows and it's the leg that matters for the question of whether to open an Asia-Pacific warehouse.
4. Order-to-ship is reported as a secondary measure on valid rows only, **with the bias stated**: dropping the bad rows removes exactly the shortest lags, so the true median is lower than the 33 hours the valid rows show. Reporting 33 hours as fact would be the mistake.

**Baseline on valid rows:** 33 hours from order to ship, 60 hours from ship to delivery.

**Recommendation to carry into the findings:** this is an upstream bug worth raising with engineering, not something to patch quietly in the warehouse. Roughly 30% of fulfillment data has been unusable for seven years, which means nobody has been measuring warehouse speed.

### 2. 46% of website visits can't be tied to a customer — caveat

1,125,459 of 2,425,353 events have no `user_id`, because the visitor wasn't signed in.

**Handling:** the conversion funnel (NL-109) is measured **per session**, not per customer, so anonymous traffic is included. Attribution (NL-105) can only follow customers who signed in, so it covers the signed-in half and says so. Reporting attribution as if it covered everyone would be the mistake here.

### 3. 1,211 rows dated in the future — fixed

`order_items` and `events` contain rows dated after 2026-09-17, because Google regenerates the public dataset on a schedule. `orders` has none, so those item rows have no parent order.

**Handling:** every staging view filters to `as_of_date = 2026-09-17`. This also makes results reproducible when the source dataset is refreshed.

### 4. 14,640 customers have a country name in the wrong language — fixed

`Brasil` (14,639 rows) sits next to `Brazil`, and `Deutschland` (1 row) next to `Germany`. Left alone, Brazil looks like two separate markets, and it would drop out of the top-three ranking in the market analysis (NL-112).

**Handling:** staging maps local spellings to English names. Three countries have fewer than 50 customers (Austria at 1, Deutschland at 1, Colombia at 12) and are grouped as "Other" in market reporting, since single-customer countries aren't markets.

### 5. 24 products have no category or brand, and 2 cost under a dollar — fixed

Twenty-four of 29,120 products (0.08%) are missing a category or brand, which would drop them out of category reporting. Two products have a retail price under $1, including the $0.02 item found in profiling.

**Handling:** missing values become `'Unknown'` rather than null, so the rows still appear and the gap is visible. The sub-dollar products are flagged, not deleted, since they're too few to affect totals.

## 6. Delivery timestamps don't encode distance — discovered during analysis

Found while answering NL-112, not by the checks above. Median ship-to-delivery time is **58–60 hours to every region on earth**: Asia Pacific 60, North America 60, Europe 58, Latin America 59, with the 90th percentile at 107–108 hours everywhere. A parcel cannot reach Shanghai from Memphis in the time it reaches Chicago.

**What it means:** delivery timestamps are usable for *whether* something arrived and for order-level sequencing, but they carry no geographic signal at all. Any question whose answer depends on distance — international service levels, the value of a local warehouse, carrier performance by lane — cannot be answered from this data.

**Handling:** fulfillment analysis is limited to within-region comparisons and to whether the timeline is internally consistent. The Asia-Pacific warehouse question (NL-112) is reported as unanswerable pending carrier data, rather than answered with numbers that don't describe reality.

**Why it wasn't caught earlier:** the quality checks tested timestamps for internal consistency (does delivery follow shipping?) and these rows pass. A value can be perfectly consistent and still be wrong. It took a business question with a known real-world expectation to expose it.

## Checks that passed

Worth stating in the README, because passing checks is what earns trust in the numbers:

- **Referential integrity:** no orphaned order items, no products without a distribution center. Every star-schema join holds.
- **Uniqueness:** no duplicate keys in any table, and no stock unit sold twice.
- **Order headers agree with their lines:** `num_of_item` matches the line count on every order, and no order's status contradicts all of its items.
- **Money is believable:** no zero or negative sale prices, no products costing more than they retail for, no item sold at more than double list price.
- **Returns are logged consistently:** every returned item has a return date, no return predates delivery, and nothing marked cancelled was shipped.
- **Product details agree** between `inventory_items` and `products`, so the copied columns are safe to ignore.
- **The funnel ties out:** purchase events exactly equal order item rows (180,858 each), so one purchase event is one item sold, not one order. The funnel must count sessions, not events, to avoid overstating conversions.
