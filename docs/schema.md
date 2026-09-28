# Verified Schema: `northloom_raw`

Confirmed on 2026-09-17 against the copied tables via `INFORMATION_SCHEMA.COLUMNS` ([sql/raw/01_verify_schema.sql](../sql/raw/01_verify_schema.sql)). Every column is nullable, so the staging layer must handle nulls rather than assume them away. Source: one-time copy of `bigquery-public-data.thelook_ecommerce`.

## Differences from the brief's expected schema

The actual tables carry five columns the brief didn't list. None of them break the plan, and two are useful:

| Table | Extra column | Use |
| --- | --- | --- |
| `distribution_centers` | `distribution_center_geom` (GEOGRAPHY) | Map the fulfillment network in the dashboard |
| `users` | `street_address`, `postal_code`, `latitude`, `longitude`, `user_geom` | Customer location on a map; the street address is synthetic but treated as personal data anyway, so it's excluded from the marts |
| `inventory_items` | `product_sku` | Join inventory to products by SKU as a cross-check |

## users — one row per registered customer

| Column | Type | Meaning |
| --- | --- | --- |
| `id` | INT64 | Customer key. Referenced by `orders.user_id`, `order_items.user_id`, `events.user_id` |
| `first_name`, `last_name`, `email` | STRING | Personal details. Excluded from the marts; only a hashed id is carried through |
| `age` | INT64 | Age in years, used for demographic cuts |
| `gender` | STRING | Customer gender, which mirrors the Men's/Women's department split |
| `state`, `street_address`, `postal_code`, `city`, `country` | STRING | Delivery location. `country` drives the domestic-vs-international cut |
| `latitude`, `longitude` | FLOAT64 | Coordinates for mapping |
| `traffic_source` | STRING | The channel that brought the customer in at signup. Distinct from the per-event channel in `events` |
| `created_at` | TIMESTAMP | Signup time. Defines the signup cohort (NL-101) |
| `user_geom` | GEOGRAPHY | Location as a geography point |

## orders — one row per order (the order header)

| Column | Type | Meaning |
| --- | --- | --- |
| `order_id` | INT64 | Order key |
| `user_id` | INT64 | The customer who placed it |
| `status` | STRING | Order state (Complete, Shipped, Processing, Cancelled, Returned). Drives the net-revenue rule |
| `gender` | STRING | Copied from the customer; redundant, so the marts take gender from `users` |
| `created_at` | TIMESTAMP | Order placed. The date every trend is measured on |
| `shipped_at`, `delivered_at` | TIMESTAMP | Fulfillment milestones, for the delivery-speed analysis (NL-110) |
| `returned_at` | TIMESTAMP | When the order came back. Null if it wasn't returned |
| `num_of_item` | INT64 | Item count on the order. Cross-check against the line count in `order_items` |

## order_items — one row per item on an order (the grain of the fact table)

| Column | Type | Meaning |
| --- | --- | --- |
| `id` | INT64 | Line item key |
| `order_id` | INT64 | Parent order |
| `user_id` | INT64 | Customer, repeated from the order |
| `product_id` | INT64 | Product sold |
| `inventory_item_id` | INT64 | The physical unit sold, which links to cost and distribution center |
| `status` | STRING | Line-level state. Can differ from the order status when part of an order is returned |
| `created_at`, `shipped_at`, `delivered_at`, `returned_at` | TIMESTAMP | Line-level milestones |
| `sale_price` | FLOAT64 | What the customer paid for this item. The revenue measure. Margin is this minus the item's cost |

## products — one row per product sold

| Column | Type | Meaning |
| --- | --- | --- |
| `id` | INT64 | Product key |
| `cost` | FLOAT64 | Wholesale cost to Northloom. The basis of gross margin |
| `category` | STRING | Product category (Jeans, Tops & Tees, Outerwear, and so on). The buying team's unit of analysis |
| `name` | STRING | Product name |
| `brand` | STRING | The brand Northloom buys from |
| `retail_price` | FLOAT64 | List price. Compared with `sale_price` this reveals discounting |
| `department` | STRING | Men or Women |
| `sku` | STRING | Stock keeping unit |
| `distribution_center_id` | INT64 | The DC that stocks this product |

## inventory_items — one row per physical unit of stock

| Column | Type | Meaning |
| --- | --- | --- |
| `id` | INT64 | Inventory unit key, referenced by `order_items.inventory_item_id` |
| `product_id` | INT64 | Which product this unit is |
| `created_at` | TIMESTAMP | When the unit entered stock |
| `sold_at` | TIMESTAMP | When it sold. Null means it's still on hand, which is how stock on hand is counted (NL-104) |
| `cost` | FLOAT64 | Cost of this specific unit, which can differ from `products.cost` |
| `product_category`, `product_name`, `product_brand`, `product_retail_price`, `product_department`, `product_sku` | | Product details copied onto the row. The marts take these from `products` instead, and any disagreement is a data quality check |
| `product_distribution_center_id` | INT64 | Where the unit is held |

## distribution_centers — one row per warehouse

| Column | Type | Meaning |
| --- | --- | --- |
| `id` | INT64 | DC key |
| `name` | STRING | DC name, usually its city |
| `latitude`, `longitude` | FLOAT64 | Coordinates |
| `distribution_center_geom` | GEOGRAPHY | Location as a geography point, for the map |

## events — one row per page view (clickstream)

| Column | Type | Meaning |
| --- | --- | --- |
| `id` | INT64 | Event key |
| `user_id` | INT64 | Customer, null for visitors who aren't logged in |
| `sequence_number` | INT64 | Position of the event within its session. Orders the funnel steps |
| `session_id` | STRING | Session key, the unit for measuring conversion |
| `created_at` | TIMESTAMP | When the event happened |
| `ip_address` | STRING | Visitor IP. Personal data, excluded from the marts |
| `city`, `state`, `postal_code` | STRING | Visitor location |
| `browser` | STRING | Browser used, a rough stand-in for device type (NL-109) |
| `traffic_source` | STRING | Channel for this visit. The basis of first-touch and last-touch attribution (NL-105) |
| `uri` | STRING | Page visited |
| `event_type` | STRING | What happened (home, department, product, cart, purchase). The funnel steps |

## Notes for the staging layer

- **Two sources of channel.** `users.traffic_source` is fixed at signup, while `events.traffic_source` varies per visit. Attribution uses `events`; customer acquisition reporting uses `users`. Keep them clearly named apart.
- **Two sources of product detail.** `products` and the copied columns on `inventory_items`. The marts use `products` as the single source, with a quality check for disagreements.
- **Two sources of cost.** `products.cost` and `inventory_items.cost`. Margin uses `inventory_items.cost` where a line item links to a unit, because that's the cost actually incurred, and falls back to `products.cost` otherwise.
- **Status lives at two levels.** Use the `order_items` status for revenue and returns, since part of an order can come back while the rest is kept.
- **Personal data.** `email`, `street_address` and `ip_address` stay out of the marts, since a public portfolio repo shouldn't model customer personal data carelessly.
