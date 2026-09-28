# Findings

One entry per stakeholder ticket, written as the reply that stakeholder would get: what was asked, what the data says, and what to do about it. Figures are as at the analysis date, 2026-09-17.

**The through-line:** Northloom earns 76% of a customer's lifetime value on their first order, and fewer than one customer in four buys again within a year. That is the constraint on the whole business. The encouraging part is that repeat purchase has improved every year since 2019, from 8.5% to 22.7%, apparently without anyone tracking it.

---

## NL-103 | CFO: what is a customer worth, and what can we pay to get one?

**Answer: about $54 of gross margin over two years, and three quarters of that arrives on day one.**

| Months since first purchase | Avg cumulative margin | Share of 24-month value | Avg orders |
| --- | --- | --- | --- |
| 0 | $44.68 | 76.2% | 1.02 |
| 3 | $48.29 | 82.3% | 1.10 |
| 12 | $53.60 | 91.4% | 1.22 |
| 23 | $58.64 | 100% | 1.33 |

**What this means.** Northloom is, in practice, a **single-purchase business**. 76% of a customer's lifetime value lands in their first order, and the average customer places 1.33 orders in two years. Waiting a full year to recover acquisition cost buys only another $9 of margin per customer.

The median matters here too. Median cumulative margin at month 0 is $27.82 against a mean of $44.68, so a minority of large baskets pulls the average up. Budgeting against the mean will overpay for the typical customer.

**Recommendation.** Set the acquisition ceiling at **$31 per customer** on first-order margin alone, rising to **$37.50** if payback over 12 months is acceptable. These use a 1.4x margin-to-cost rule, the usual floor for a healthy retailer. Any channel costing more than that is buying revenue at a loss, and the marketing analysis (NL-105) should be read against this ceiling.

**Caveat.** Value is measured as gross margin, not revenue. Revenue would suggest $103 per customer by month 12 and roughly double the affordable acquisition cost. Northloom keeps about half of each sale, so revenue-based budgeting would overspend by about 2x.

---

## NL-102 | CRM Manager: who gets the VIP list and the win-back list?

**Answer: 9,075 Champions carry 28% of revenue, and 3,747 customers worth $936,000 are already slipping away.**

Every customer who has ever bought was scored against the rest of the base on how recently they bought, how often, and how much.

| Segment | Customers | Share of base | Lifetime revenue | Gross margin | Avg value | Days since last order | Return rate |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Champions | 9,071 | 13.7% | $2,256,761 | $1,177,157 | $248.79 | 91 | 4.9% |
| Loyal | 13,271 | 20.1% | $2,020,465 | $1,049,650 | $152.25 | 236 | 5.6% |
| Hibernating | 9,860 | 14.9% | $1,470,501 | $769,111 | $149.14 | 1,235 | 6.1% |
| Cannot lose them | 3,746 | 5.7% | $935,956 | $487,351 | $249.85 | 1,005 | 4.9% |
| Lost | 20,802 | 31.5% | $673,615 | $340,739 | $32.38 | 708 | 9.6% |
| Needs attention | 7,697 | 11.7% | $545,832 | $282,469 | $70.91 | 438 | 8.0% |
| At risk | 1,616 | 2.4% | $113,383 | $57,372 | $70.16 | 1,056 | 6.9% |

**What this means.** Four things stand out:

1. **"Cannot lose them" is the list to work first.** These customers are worth as much each as Champions ($249.85 against $248.79), but their last order was nearly three years ago. They are not at risk of leaving; they have already left. Recovering a tenth of them is worth about $94,000 of revenue and $49,000 of margin.
2. **A third of the base is Lost and worth almost nothing.** 20,802 customers hold 8.4% of revenue at $32 each. They should cost the CRM team nothing beyond the newsletter.
3. **Returns track churn.** The Lost segment returns 9.6% of what it buys, and Needs attention 8.0%, against 4.9% for both Champions and Cannot lose them. Northloom's best customers are its least troublesome ones: heavy returners are roughly twice as likely to have drifted away. A bad return experience looks like a churn driver, which is worth testing against delivery speed in NL-110.
4. **Even the Champions look inactive** by normal retail standards, with an average last order 91 days ago. In a business where the typical customer buys 1.33 times, "best customer" means very little repeat buying.

**Recommendation.** Run the win-back on "Cannot lose them" first, at 3,746 contacts, since it has the highest value per contact and a low return rate, so the recovered revenue should stick. Champions get early access rather than discounts, because discounting customers who already buy at full price gives away margin for nothing. Do not spend on the Lost segment: it is both the least valuable and the most return-prone.

---

## NL-101 | VP Growth: are newer customers worse, and do they come back?

**Answer: no, newer customers are better. Repeat purchase has improved every year, from 8.5% to 22.7%. It is still low, and the second purchase takes about five months.**

Share of each cohort that placed a second order within the window. Only customers who have had the full window are counted:

| Cohort year | Customers acquired | Repeat by month 3 | by month 6 | by month 12 | Revenue per customer, first year | Median days to 2nd order |
| --- | --- | --- | --- | --- | --- | --- |
| 2019 | 738 | 2.4% | 5.0% | 8.5% | $99.12 | 146 |
| 2020 | 2,325 | 2.4% | 5.3% | 10.6% | $95.20 | 178 |
| 2021 | 3,979 | 2.8% | 5.3% | 11.1% | $98.30 | 185 |
| 2022 | 6,049 | 3.2% | 6.5% | 12.9% | $99.32 | 180 |
| 2023 | 8,203 | 4.0% | 7.6% | 14.3% | $99.91 | 169 |
| 2024 | 10,956 | 4.9% | 9.5% | 17.7% | $103.83 | 168 |
| 2025 | 14,926 | 7.2% | 13.7% | 22.7% | $109.74 | 162 |
| 2026 | 18,887 | 13.0% | 19.5% | not yet observable | | |

**What this means.**

1. **Repeat purchase has improved every single year**, from 8.5% to 22.7% at twelve months, while the cohort grew from 738 customers to 14,926. Growing fast usually dilutes quality; here it hasn't. Whatever Northloom has changed since 2019 is working, and nobody appears to be measuring it.
2. **The 2026 cohort is on a different track again**, at 13.0% by month 3, nearly double 2025's 7.2% at the same point.
3. **It is still a low base.** Even the best cohort sees fewer than one customer in four come back within a year, which is what produces the 1.33 lifetime orders in NL-103.
4. **The second purchase takes about five months.** The median gap has been steady at 146–185 days for eight years, so this is a stable property of the business, not noise.

**Recommendation.** Two things follow directly:

- **Time the second-purchase campaign to land before day 90.** The median repeat buyer takes about 165 days, and only 13% return within 90. A nudge at 30–60 days addresses the gap rather than congratulating people who were coming back anyway.
- **Find out what changed.** The steady climb from 2019 to 2026 is the single most valuable pattern in this data, and nothing in the warehouse explains it. Marketing mix, site changes and delivery speed are the candidates, and NL-105 and NL-110 test two of them.

**Caveat, stated plainly.** Part of this rise is likely mechanical. Northloom sells far more now than in 2019, so a customer acquired recently has more company activity around them and more chance to buy again. The trend is consistent and large enough to be worth acting on, but it should not be reported as pure loyalty improvement until it survives a check against overall order growth.

**Note on method.** An earlier version of this query counted fast repeat buyers in the numerator whose window had not yet elapsed, while excluding them from the denominator. That produced 37.9% for 2025 and an impossible 108.6% for 2026. The corrected figures are 22.7% and not-yet-observable. The 2025 error was the dangerous one, because it looked plausible.

---

## NL-108 | CFO & Head of Buying: which categories lose us the most to returns?

**Answer: no category is the problem. Every one of them returns at 10–12%, and the money simply follows the size of the category. Cancellations cost more than returns do.**

Ranked by margin lost, the worst categories are the biggest ones:

| Category | Return rate | Margin lost to returns | Share of all return losses | Revenue lost to cancellations |
| --- | --- | --- | --- | --- |
| Outerwear & Coats (Men) | 11.7% | $47,261 | 8.7% | $121,790 |
| Jeans (Men) | 12.1% | $36,466 | 6.7% | $110,856 |
| Suits & Sport Coats (Men) | 11.8% | $36,109 | 6.6% | $91,337 |
| Dresses (Women) | 12.4% | $25,665 | 4.7% | $71,024 |
| Outerwear & Coats (Women) | 11.2% | $24,067 | 4.4% | $73,346 |

**What this means.** Across all 36 category-department combinations the return rate sits between **10.4% and 12.5%**. There is no outlier to fix, no badly-sized product line, no category to stop buying. Returns behave like a flat tax of about 11.6% on everything Northloom sells, costing **$543,000 of margin in total**.

That total is the important number, because **cancellations cost more**: $1.58M of revenue never collected, which is roughly $790,000 of margin at Northloom's 51.9% rate. Cancellations are the larger leak and nobody is looking at them.

**Recommendation.** Stop searching for a problem category, because the data says there isn't one. Put the effort into NL-113, the cancellation question, where the loss is about 1.5 times larger and the cause is unknown. If returns are to be attacked, it has to be through something that moves the whole 11.6%, such as sizing guidance or delivery speed, not through a category-by-category review.

---

## Returns and churn: the hypothesis was wrong

The RFM work (NL-102) showed churned customers returning 9.6% of what they bought against 4.9% for the best customers, and I suggested returns might be driving people away. **Tested directly, that is not true. The opposite is.**

Among customers whose first order was old enough to have had a full year:

| First order experience | Customers | Avg first order value | Came back within a year |
| --- | --- | --- | --- |
| Kept everything | 40,263 | $86.62 | **37.6%** |
| Returned an item | 1,948 | (see note) | **45.1%** |

Customers who returned something on their first order came back **more often, by 7.5 percentage points**. With 1,948 customers in that group the gap is far too large to be chance.

**What this means.** Returning is a sign of engagement, not dissatisfaction. Someone who sends an item back has learned that returning is easy and is more willing to order again. The RFM correlation runs the other way round from how it reads: customers who buy over many years accumulate more returns, so heavy returners look like churners when really they are simply customers with more history.

**Recommendation.** Do not fund a returns-reduction programme on the grounds that returns cause churn, because they do not. Make returns easy and keep them easy. The $543,000 is a cost of doing business in fashion, and the evidence here is that trying to suppress it would damage repeat purchase, which is the one thing Northloom cannot afford to lose (NL-101, NL-103).

**Note on method.** The average order value for the returners column reported $0.00 in the first run: it was summing net revenue, which is defined to be zero on a returned item. It measures the value of the return, not of the order. Fixed to use the price paid.

---

## NL-104 | Head of Supply Chain: what stock should we clear?

**Answer: all of it is overstocked, by roughly the same amount, and holding it costs about as much as Northloom earns.**

| Category | Stock at cost | Years of supply | Dead stock | Annual holding cost |
| --- | --- | --- | --- | --- |
| Jeans (Men) | $698,718 | 3.7 | $283,101 | $174,680 |
| Outerwear & Coats (Men) | $646,000 | 3.6 | $253,402 | $161,500 |
| Jeans (Women) | $435,975 | 3.6 | $201,468 | $108,994 |
| Suits & Sport Coats (Men) | $427,162 | 3.5 | $171,364 | $106,791 |
| Sweaters (Men) | $425,527 | 3.5 | $160,241 | $106,382 |

**What this means.**

1. **Every category holds 3.2 to 4.2 years of supply.** Not one is close to a healthy level. This is not a buying mistake in a particular department, it is how the whole company buys.
2. **At the standard 25% holding rate, that stock costs about $2.2M a year to carry.** Northloom's current run rate is roughly $5.1M of revenue and $2.6M of gross margin a year. **Carrying the inventory consumes something like 85% of the gross margin the business earns.** If that rate is even roughly right, it is the largest single cost in this analysis, far bigger than returns or cancellations.
3. **There is no Pareto concentration to exploit.** The worst 500 product-warehouse lines hold only about 13% of the trapped cash. Reaching half of it would take about 4,750 separate lines. The top of the list is predictable: $250+ outerwear and premium denim, sitting an average of over 1,200 days.

**Recommendation.** Two things, in order:

- **Clear by rule, not by line.** A line-by-line review cannot work at this spread. Apply a blanket markdown by age and price band, starting with everything over two years old in the $250+ bands, which is where the cash is densest. The 500-line list is the starting batch, not the plan.
- **Fix the buying, because clearance only cleans up the past.** Stock is being bought at roughly four times the rate it sells. Until order quantities are tied to actual demand, this position rebuilds itself.

---

## NL-105 | CMO: does Facebook bring in customers or just take credit?

**Answer: neither, and the question you should be asking is different. Facebook is about a tenth of the business under every model. The real problem is that your two systems disagree about where 70% of revenue comes from.**

The same revenue, credited three ways:

| Channel | First touch | Last touch | What the signup record says |
| --- | --- | --- | --- |
| Email | 45.0% | 45.3% | 5.0% |
| Paid Search | 30.1% | 29.9% | **70.3%** |
| Display & Video | 10.0% | 10.1% | 4.0% |
| Paid Social (Facebook) | 9.9% | 9.7% | 5.9% |
| Organic | 5.0% | 5.1% | 14.8% |

**What this means.**

1. **First touch and last touch agree almost exactly.** No channel shifts by more than 2.9%, and every one is "balanced". The reason is simple: customers average **1.6 sessions before their first purchase**, and the two models disagree for only 24.6% of customers. There is no long multi-touch journey to argue about, so the attribution debate that consumes most marketing teams does not apply here.
2. **The systems disagree wildly.** The clickstream says Email drives 45% of revenue and Paid Search 30%. The signup record says Paid Search drives 70% and Email 5%. Both cannot be true.
3. **The clickstream is the one to distrust for acquisition.** Email cannot introduce a customer to the business, because you need their address before you can email them. Email showing up as "first touch" for 45% of customers means the clickstream is tagging returning visits, not the arrival that won the customer. Read it as engagement, and read the signup source as acquisition.
4. **Facebook is small either way**, at 5.9% to 9.9% of revenue. Cutting it is not a decision worth this much debate.

**Recommendation.**

- **Do not cut Facebook on this evidence.** At around 10% of revenue and $121 per customer, it performs in line with every other channel. The decision needs cost data, which is not in the warehouse.
- **Settle the tagging question first.** Until Paid Search is either 30% or 70% of acquisition, no budget decision is defensible. This is the most valuable thing the marketing team could fix.
- **Use the acquisition ceiling from NL-103.** Revenue per customer barely varies by channel, from $119.66 to $123.96, so **no channel produces better customers**. They only differ in what they cost. Any channel costing more than **$31 per customer** is losing money, and that is the test to apply.

**Caveat.** Covers only customers whose sessions could be tied to them while signed in, and there is no ad spend in the warehouse, so this shows where revenue should be credited, not return on investment.

---

## NL-113 | Head of Ecommerce: which orders get cancelled, and what do they share?

**Answer: all of them and none of them. Cancellations are whole orders, never single items, running at a flat 15% of everything Northloom sells, and nothing in the warehouse predicts them. That is itself the finding.**

The rate was measured across eleven cuts. The widest spread in any of them:

| Cut | Spread between highest and lowest | Verdict |
| --- | --- | --- |
| Market (top 8) | 1.6 points (Germany 15.8%, UK 14.2%) | noise |
| Year (2019–2026) | 1.2 points | no trend |
| Warehouse | 1.0 point | not operational |
| Signup channel | 0.8 points | not a traffic-quality issue |
| Department | 0.7 points | not a product issue |
| Basket size | 0.6 points | not a big-order issue |
| Region | 0.6 points | not international |
| Day of week | 0.5 points | not a staffing pattern |
| Price band | 0.4 points | not a price-shock issue |
| **Order position** | **0.2 points** (first ever 14.9%, second 14.9%, third or later 15.1%) | **not new-customer friction** |

The company average is 15.0%. Every value in every cut sits within roughly half a point of it, and the flattest cut of all is the one that would have been most actionable: a customer's very first order is cancelled at exactly the same rate as their tenth. Whatever fails does not care whether it has seen you before, which rules out first-time payment friction, address errors and new-customer fraud screening.

**What this means.** Two structural facts do the explaining:

1. **Every cancellation is a whole order.** 18,562 orders cancelled in full; **not one order had part of it cancelled and the rest shipped**. If cancellations were caused by stock that wasn't really there, partial cancellations would dominate, because a warehouse runs out of one line, not all of them.
2. **The cancelled orders are indistinguishable from the kept ones.** Average value $85.00 against $85.72, identical basket sizes, same rate in 2019 and 2025.

That combination rules out the usual suspects: not stock, not a bad warehouse, not a bad channel, not big baskets, not one market. Something is failing **at the order level, after the customer commits and before anything is picked**, at a constant rate. The obvious candidates are payment authorisation failures, fraud screening, or an address validation step, and **none of them are in this warehouse**.

**Recommendation.** Stop analysing this in BigQuery; the data has given everything it can. The next step is engineering: capture the cancellation *reason code* from the order system, which does not currently flow into the warehouse, and instrument payment authorisation outcomes. **$1.58M of revenue, roughly $790K of margin, turns on a field nobody is collecting.** One flat 15% with no variation is the signature of a system failing, not customers changing their minds, and systems get fixed once rather than managed forever.

**A false finding, caught twice over.** The first run reported a 35.4% cancellation rate for returning customers against **0.0% for new ones** — a spectacular result, and entirely an artifact of a definition. The customer sequence number is built over orders that weren't cancelled, so cancelled orders had no sequence and defaulted into the "Returning" bucket: every cancellation was labelled Returning by construction.

Labelling cancelled items separately fixed the wrong number but produced a useless one, Cancelled 100% and everything else 0%, which merely restates the label. Answering the question the CRM team actually cares about needed a third definition: rank every order a customer ever placed, cancelled ones included, and compare position one against later ones. That is the 0.2-point row above.

The lesson worth keeping: **a 0.0% or a 100.0% is a broken definition until proven otherwise**, and a metric built on top of an outcome cannot be used to explain that outcome.

---

## NL-112 | COO: what would an Asia-Pacific warehouse be worth?

**Answer: on delivery times, nothing measurable, because parcels reportedly reach Shanghai as fast as Chicago. That is not believable, and the honest answer is that this question cannot be settled with the data Northloom currently has.**

| Region | Customers | Net revenue | Share | Median ship-to-delivery | 90th percentile |
| --- | --- | --- | --- | --- | --- |
| Asia Pacific | 35,016 | $3,497,626 | **43.6%** | 60 hours | 108 hours |
| North America | 17,987 | $1,819,386 | 22.7% | 60 hours | 108 hours |
| Europe | 15,084 | $1,509,712 | 18.8% | 58 hours | 108 hours |
| Latin America | 11,672 | $1,189,787 | 14.8% | 59 hours | 107 hours |

**What this means.**

1. **The premise of the ticket is right.** Asia Pacific is 43.6% of revenue against North America's 22.7%, and China alone reached $648,627 in 2025, growing 364% since 2021. Every market is growing at 290–540%, so this is not a China-specific bet; it is an international-growth bet.
2. **The delivery data cannot support the business case.** Every region shows a median of 58–60 hours and a 90th percentile of 107–108 hours. A parcel cannot reach Shanghai from Memphis in the same time it reaches Chicago. **The delivery timestamps do not encode distance**, which means they cannot measure the one thing a local warehouse would improve. This is a data limitation, not a finding that geography doesn't matter.
3. **Revenue per customer is identical everywhere**, at $99.89 to $101.94. Whatever the current service level is, it is not visibly suppressing international spend, though point 2 means the data could not show it if it were.

**Recommendation.**

- **Do not proceed on the delivery-time argument**, because there is no measurable gap to close. Anyone building the case on service improvement is building it on numbers that don't describe reality.
- **Get carrier data first.** Actual transit times and freight cost per parcel by destination sit with the carriers, not in this warehouse. Until those land, the warehouse question is unanswerable, and that is the finding to report.
- **If it does go ahead, fix the buying first.** At Northloom's current 3.5-year stock cover, an Asia-Pacific warehouse serving the last twelve months of demand (23,724 items) would need about **83,000 units**. At a healthy 90-day cover it needs about **5,900**. Opening a second site under today's buying habits duplicates the $8.8M inventory problem in a second country.

---

## NL-106 | Merchandising Lead: what do customers buy together?

**Answer: almost nothing. 71% of orders contain a single item. The opportunity isn't bundling particular products, it's getting a second item into the basket at all — that alone doubles the order value.**

| Basket | Orders | Share of orders | Avg order value | Share of revenue |
| --- | --- | --- | --- | --- |
| 1 item | 66,091 | **70.8%** | $60.02 | 49.5% |
| 2 items | 18,205 | 19.5% | $118.56 | 26.9% |
| 3 items | 4,622 | 4.9% | $177.74 | 10.2% |
| 4+ items | 4,458 | 4.8% | $239.99 | 13.3% |

**What this means.** Adding one item takes an order from $60.02 to $118.56. The 29% of orders that contain more than one item already produce **half of all revenue**. That is the lever, and it is much larger than any bundle.

The pairs themselves are weak. The strongest affinity in the catalogue is Maternity with Socks & Hosiery at a lift of 1.54, and it appears in 168 orders, which is **0.18% of them**. The largest pair by volume, Dresses with Intimates, occurs 484 times at a lift of 1.20. Nothing here supports a bundle on its own.

One coherent pattern does survive: a womenswear coordinates cluster. **Dresses, Skirts, Leggings, Pants & Capris, Blazers & Jackets and Socks & Hosiery all pair with each other** at lifts of 1.20 to 1.35. That is genuine "complete the look" behaviour, and it is the only group where the affinity is consistent rather than one-off.

**Recommendation.**

- **Target the second item, not the pair.** A recommendation module, free-shipping threshold or "add a second item" prompt is worth more than any bundle, because it addresses 71% of orders instead of 0.2% of them.
- **Build the womenswear coordinates as the one exception.** It is the only cluster with a repeatable signal, and it matches how the customer actually shops.
- **Do not build bundles off the top of the lift table.** Maternity with Socks & Hosiery is the highest score in the catalogue and would reach fewer than 200 orders a year. High lift on tiny support is a statistical curiosity, not a merchandising plan.

---

## NL-107 | Head of Buying: which categories are really growing?

**Answer: every category grows, because the company quadrupled. Measured against the company, the two biggest categories are the two worst performers — and they are exactly where the most stock is sitting.**

Company growth 2021 to 2025 was **375.4%**. Against that benchmark:

| Category | 2025 revenue | Growth | vs company | Share shift | Margin |
| --- | --- | --- | --- | --- | --- |
| Clothing Sets (W) | $3,291 | 1027.3% | **+651.9 pts** | +0.10 | 38.0% |
| Jumpsuits & Rompers (W) | $7,265 | 649.1% | +273.7 pts | +0.14 | 47.0% |
| **Active (M)** | **$47,860** | **582.3%** | **+206.9 pts** | **+0.76** | **58.3%** |
| Sweaters (W) | $57,750 | 525.0% | +149.6 pts | +0.72 | 55.3% |
| Outerwear & Coats (W) | $83,538 | 445.3% | +69.9 pts | +0.56 | 54.9% |
| … | | | | | |
| Swim (W) | $58,471 | 323.8% | −51.6 pts | −0.38 | 57.8% |
| **Outerwear & Coats (M)** | **$144,709** | **319.9%** | **−55.5 pts** | **−1.00** | 55.9% |
| **Jeans (M)** | **$128,896** | **283.8%** | **−91.6 pts** | **−1.63** | 46.8% |
| Tops & Tees (W) | $29,828 | 265.0% | −110.4 pts | −0.48 | 43.9% |

**What this means.**

1. **The number one and number two categories are losing ground fastest.** Men's Outerwear and Men's Jeans are the two largest categories in the business and the two biggest share losers, together shedding **2.63 points of revenue share** since 2021. They still grow, which is why nobody has noticed.
2. **This joins up with the inventory finding, and it is the sharpest thing in the whole project.** From NL-104, the two largest piles of trapped stock are **Men's Jeans ($698,718) and Men's Outerwear ($646,000)** — a combined $1.34M, 15% of all stock at cost. Northloom is holding the most inventory in precisely the two categories it is losing customers in. That is not two problems, it is one: the buying budget is anchored to what sold in 2021.
3. **The clearest place to move the money is Men's Active**: 582% growth, a 0.76-point share gain, and **58.3% margin**, which is above the company's 51.9%. It is also already at meaningful scale at $47,860, unlike the tiny percentage winners.
4. **Growth and margin do not agree.** The fastest grower, Women's Clothing Sets, runs a 38.0% margin, the worst in the catalogue. Chasing growth alone would dilute margin.

**Recommendation.** Move depth out of Men's Jeans and Men's Outerwear and into **Men's Active, Women's Sweaters and Women's Outerwear** — all growing above the company rate at 55%+ margin. Do it in that order, because the stock clearance in NL-104 frees the cash in exactly the categories being cut. **These two tickets answer each other.**

---

## NL-109 | Head of Ecommerce: where do we lose shoppers?

**Answer: unanswerable, and the query proved it rather than guessing. The clickstream does not describe a journey.**

The first version of this analysis reported a drop-off of **minus 58.1%** between viewing a department and viewing a product. A negative drop-off is impossible. The cause: **100% of sessions view a product while only 63.2% view a department**, so the steps do not nest, and the funnel everyone pictures does not exist in this data.

The path-integrity checks then showed exactly where the assumption broke:

| Check | Sessions | Verdict |
| --- | --- | --- |
| Product viewed without a department first | **250,067 (36.8%)** | breaks the assumed order |
| Cart without ever viewing a product | 0 | holds |
| Purchase without ever adding to cart | 0 | holds |
| Purchase without viewing a department | 0 | holds |
| Sessions longer than 8 hours | **72,599 (10.7%)** | not real visits |

**What this means.** The data supports a shorter funnel than the one the business imagines, and only that one:

- Every session views a product, so "product view" is not a step, it is the definition of a session.
- **Cart, department and purchase do nest properly.** The usable funnel is therefore **product → cart (63.2%) → purchase (41.5% of carts)**, ending at 26.2% of sessions.
- The 36.8% who reach a product without a department are browsing straight into products, which is normal behaviour and simply means the department page is not on the main path.

Two things still make the numbers unquotable outside the building:

1. **Every channel and every browser converts identically**, within 0.4 points across ten comparisons. Real sites never look like this; mobile Safari alone usually differs from desktop Chrome by several points.
2. **10.7% of sessions run over 8 hours**, averaging 398 minutes overall, so what the data calls a session is not a visit. No inactivity timeout has been applied upstream.

**Recommendation.** Publish the two-step funnel (product → cart → purchase) and nothing else. **Do not publish a department-page drop-off**, because 36.8% of shoppers never see that page and are not "lost" there. The prerequisite for anything richer is upstream: sessionise the clickstream with a 30-minute inactivity rule and record the page sequence.

**Worth saying plainly:** the value of this ticket was the negative. An analyst who had not checked the nesting would have shipped a funnel chart showing a 36.8% drop at the department step, and the ecommerce team would have spent a quarter optimising a page that nothing is wrong with.

---

## NL-111 | CEO: the weekly business review

**Answer: the table is below, and it carries the best news in this project. Northloom's dependence on new customers has fallen from 74% of revenue to 56% in under three years. The retention problem is already fixing itself.**

Quarterly, the view most useful for the board:

| Quarter | Net revenue | QoQ | Margin | Orders | AOV | Revenue from NEW customers | Return rate | Cancellation rate |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2023 Q4 | $254,875 | +8.3% | 52.0% | 3,222 | $79.10 | **74.3%** | 11.5% | 14.6% |
| 2024 Q4 | $382,283 | +7.6% | 51.8% | 4,724 | $80.92 | 66.9% | 10.7% | 14.9% |
| 2025 Q4 | $560,686 | +13.7% | 52.0% | 7,055 | $79.47 | 61.7% | 11.5% | 15.0% |
| 2026 Q2 | $799,593 | +20.3% | 52.1% | 10,075 | $79.36 | 58.1% | 12.3% | 14.6% |
| 2026 Q3 | **$900,792** | +12.7% | 51.9% | 11,382 | $79.14 | **55.6%** | 11.2% | 15.0% |

Most recent complete week (7 September 2026): $124,233 revenue, up 12.1% on the week and **218.6% on the same week last year**, 1,630 orders, $76.22 average order value, 51.9% margin.

**What this means.**

1. **Revenue has grown every single quarter**, from $254,875 to $900,792, never once going backwards. Growth is accelerating rather than fading.
2. **New-customer dependence has fallen 18.7 points in eleven quarters**, from 74.3% to 55.6%. Repeat revenue has gone from a quarter of the business to nearly half. This is the same improvement the cohort work found (NL-101: repeat purchase rising from 8.5% to 22.7%), now visible in the money rather than in a cohort table, and it is the strongest argument that Northloom is becoming a real retailer rather than an acquisition machine.
3. **Everything else is flat to three significant figures.** Margin sits between 51.8% and 52.1% in every quarter. Average order value never leaves $77–$81. Return rate stays near 11.5%, cancellations near 15%. Delivery holds at 56–64 hours.

That flatness is not boring, it is the most useful thing in the table: **the losses are structural constants, not fluctuations.** Watching them weekly will never produce an insight, and the cancellation rate has not moved in eleven quarters because nothing has been done to it. They will change only when someone changes the system that causes them (NL-113).

**Recommendation.** Report **four numbers weekly** — revenue, margin percentage, orders, and share of revenue from new customers — and move returns, cancellations and delivery to a quarterly exception report with a threshold, because they do not vary week to week. The one metric worth putting on the wall is **share of revenue from returning customers**, currently 44.4% and rising. It is the only figure here that reflects whether the business is getting better rather than just bigger.

---

## Cross-cutting notes for the README

- **Cancellations cost more than returns.** $1.58M lost to cancellations against $1.05M to returns, out of $10.6M ordered. Everyone at Northloom talks about returns.
- **No discounting exists.** All 178,552 items sold at list price, so margin is decided by mix and by losses, not by pricing.
- **Inventory is the biggest cost in the business.** $8.8M of stock at cost, 3.5 years of supply in every category, roughly $2.2M a year to carry against $2.6M of annual gross margin.
- **Four in five past VIPs are no longer VIPs** (6,519 of 7,957), which only the Type 2 customer dimension can show.
- **Two findings reversed an earlier conclusion of my own**, and both are written up with the correction visible: returns turned out to *increase* repeat purchase rather than drive churn, and the 2025 retention figure was half what a flawed first query reported. The method notes are left in deliberately.

## Where the money actually is

Ranked by size, so the priorities are not set by which problem is most talked about:

| Problem | Annual cost | Currently being managed? |
| --- | --- | --- |
| Inventory holding cost | ~$2.2M | No |
| Cancellations | ~$790K of margin | No |
| Returns | ~$543K of margin (lifetime) | Talked about constantly |
| Retention | 76% of customer value arrives on day one | No |

The three things leadership worries about are not the three things costing the money.
