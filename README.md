# Customer Retention & Cohort Analysis (MySQL + Power BI)

How many customers come back after their first order, who drives the revenue, and when should a retailer act? This project answers those questions with **SQL** (MySQL) and a four-page **Power BI** dashboard, using two years of real transactions from a UK online retailer.

---

## Project at a glance

| | |
|---|---|
| **Data** | [Online Retail II](https://archive.ics.uci.edu/dataset/502/online+retail+ii) (UCI), 1,067,371 rows, 1 Dec 2009 to 9 Dec 2011, currency in £ |
| **Tools** | MySQL 8 (Workbench), Power BI Desktop |
| **SQL skills used** | CTEs, recursive CTE, window functions (`LAG`, `NTILE`, `ROW_NUMBER`), cohort and retention logic, views |
| **After cleaning** | about £17.07M revenue, 37K orders, 6K identified customers |

---

## Key findings

| # | Finding | Recommended action |
|---|---|---|
| 1 | **77% of new customers do not order again the following month** (Month 1 retention is 23.0%, or 21.0% excluding the first cohort). Retention then settles at around 22%. | Send an automated post-purchase offer within 14 days to drive a second order. |
| 2 | **The top 20% of customers (about 1,200) generate 77% of revenue.** The 1,580 "Champions" segment alone drives 70% (£11.9M) of sales. | Launch a VIP tier with volume rebates and priority stock for Champions and Loyal buyers. |
| 3 | **1,920 customers have gone quiet:** 290 formerly loyal customers (£1.0M historical spend) and 1,630 hibernating customers (£0.7M). | Run a win-back campaign after 60 days of inactivity, starting with the formerly loyal group. |
| 4 | **Revenue roughly doubles in Q4:** about £1.15M a month in October and November vs about £0.58M a month in the first half of the year. | Move inventory and acquisition spend forward to September. |

---

## How it works

```text
Raw CSVs (2 yearly sheets)
        |
        v
Staging tables (all text, so the import never fails)
        |
        v
online_retail_combined  -->  clean_sales  (business rules below)
        |
        v
Views:  v_orders_base > v_customer_cohort > v_orders
        v_cohort_retention   v_monthly_summary   v_rfm
        v_revenue_concentration   v_country_summary
        |
        v
Power BI dashboard (4 pages)
```

### Cleaning rules

| Removed | Why |
|---|---|
| Cancelled invoices (start with `C`) | Returns are not sales |
| Rows with no Customer ID | Guest checkouts cannot be tracked as customers |
| Non-product stock codes (postage, test, adjustments) | Not real products |
| Zero or negative quantity or price | Invalid for revenue |
| Exact duplicate rows | They would inflate revenue |

### Definitions

- **Cohort:** the calendar month of a customer's first order.
- **Month N retention:** share of a cohort that placed an order N months after their cohort month.
- **Retention grid:** only includes months that have actually happened for each cohort, so recent cohorts are not penalised.
- **RFM segments:** recency, frequency and monetary value, each scored 1 to 5 with `NTILE(5)`, then grouped into Champions, Loyal, At risk (was loyal), New / recent, Lost / hibernating and Needs attention.

---

## Dashboard

### 1. Revenue overview
![Revenue overview](customer-retention-cohort-analysis/docs%20images/01_revenue_overview.png)

### 2. Cohort retention
![Cohort retention](customer-retention-cohort-analysis/docs%20images/02_cohort_retention.png)

### 3. Customer segments
![Customer segments](customer-retention-cohort-analysis/docs%20images/03_customer_segments.png)

### 4. Key findings and recommendations
![Key findings](customer-retention-cohort-analysis/docs%20images/04_insights.png)

---

## Limitations

- **The first cohort (Dec 2009) is inflated.** It shows 35% Month 1 retention vs about 21% in 2010 to 2011, because it includes customers who had already bought before the data starts.
- **Guest orders are excluded** from cohort and RFM metrics.
- **One UK retailer, many of them wholesalers.** About 83% of revenue (£14.2M) is UK, so results may not carry over to other businesses.
- **Two years of history** limits what can be said about long-term churn.
- **Calendar-month cohorts:** an order on 31 Jan and one on 1 Feb count as "month 1", the same as an order 58 days later.
- **December 2011 is a partial month** (9 days of data).

---

## Repository structure

```text
customer-retention-cohort-analysis/
├── README.md
├── sql/
│   └── retention_cohort_analysis.sql
├── dashboard/
│   ├── Retail_cohort_analysis_Dashboard.pbix
└── docs/images/
```

## How to reproduce

1. Download `online_retail_II.xlsx` from the [UCI page](https://archive.ics.uci.edu/dataset/502/online+retail+ii) and save each sheet (2009-2010 and 2010-2011) as CSV.
2. In MySQL Workbench, run `sql/retention_cohort_analysis.sql` section by section. Import each CSV into its yearly staging table when the script reaches that step (Table Data Import Wizard).
3. Open the `.pbix` in Power BI Desktop and point the MySQL connection at your `retail_cohort` database, then refresh.

The raw dataset is not included in this repository. Download it from the source above.

---

## Data source and credit

Chen, D. (2012). *Online Retail II* [Dataset]. UCI Machine Learning Repository. https://doi.org/10.24432/C5CG6D. Licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

## Author

**Prudhvi Sai Mada**: [GitHub](https://github.com/prudhvi108) | [LinkedIn](https://linkedin.com/in/prudhvi-sai-62324a353)# customer_retention_cohort_analysis
