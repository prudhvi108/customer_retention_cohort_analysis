/* ====================================================================
   Customer Retention & Cohort Analysis  |  MySQL 8.0+ (MySQL Workbench)
   Dataset : Online Retail II (UCI), exported to CSV
   Columns : Invoice, StockCode, Description, Quantity, InvoiceDate,
             Price, Customer ID, Country
   Run the sections in order. Every number you put on your resume must
   come from YOUR run of these queries.
   ==================================================================== */

CREATE DATABASE IF NOT EXISTS retail_cohort;
USE retail_cohort;

DROP TABLE IF EXISTS online_retail_ii_year_2010_2011;
/* --------------------------------------------------------------------
   STEP 1. STAGING TABLE (everything as text so the import never fails)
   -------------------------------------------------------------------- */
DROP TABLE IF EXISTS online_retail_II_YEAR_2010_2011;

CREATE TABLE online_retail_II_YEAR_2009_2010 (
  invoice      VARCHAR(20),
  stock_code   VARCHAR(30),
  description  VARCHAR(255),
  quantity     VARCHAR(20),
  invoice_date VARCHAR(30),
  price        VARCHAR(20),
  customer_id  VARCHAR(20),
  country      VARCHAR(60)
);

CREATE TABLE online_retail_II_YEAR_2010_2011 (
  invoice      VARCHAR(20),
  stock_code   VARCHAR(30),
  description  VARCHAR(255),
  quantity     VARCHAR(20),
  invoice_date VARCHAR(30),
  price        VARCHAR(20),
  customer_id  VARCHAR(20),
  country      VARCHAR(60)
);

CREATE TABLE online_retail_combined AS
SELECT * FROM online_retail_ii_year_2009_2010
UNION ALL
SELECT * FROM online_retail_ii_year_2010_2011;

-- Load option A (easiest): Workbench > right-click the table > Table Data
--   Import Wizard > choose your CSV > import into the existing table.
-- Load option B (needs SET GLOBAL local_infile = 1 and local infile enabled
--   in the connection settings):
-- LOAD DATA LOCAL INFILE 'C:/path/online_retail_II.csv'
-- INTO TABLE stg_online_retail
-- FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
-- LINES TERMINATED BY '\n' IGNORE 1 ROWS;

SELECT * FROM online_retail_combined;

-- Sanity checks after loading
SELECT COUNT(*) AS rows_loaded FROM online_retail_combined;
SELECT * FROM online_retail_combined LIMIT 10;
SELECT invoice_date FROM online_retail_combined LIMIT 5;   -- check the date format
SET SESSION MAX_EXECUTION_TIME = 0; -- 0 means no limit

/* --------------------------------------------------------------------
   STEP 2. DATA QUALITY PROFILE (record these numbers in your README)
   The categories overlap, so they do not add up to the total.
   -------------------------------------------------------------------- */
SELECT 
    COUNT(*) AS total_rows,
    SUM(CASE WHEN invoice LIKE 'C%' THEN 1 ELSE 0 END) AS cancellation_invoices,
    SUM(CASE WHEN customer_id IS NULL OR TRIM(customer_id) = '' THEN 1 ELSE 0 END) AS missing_customer_id,
    SUM(CASE WHEN CAST(quantity AS SIGNED) <= 0 THEN 1 ELSE 0 END) AS invalid_quantity,
    SUM(CASE WHEN CAST(price AS DECIMAL(12,2)) <= 0 THEN 1 ELSE 0 END) AS invalid_price,
    SUM(CASE WHEN stock_code NOT REGEXP '^[0-9]{5}' THEN 1 ELSE 0 END) AS non_product_stock_codes
FROM online_retail_combined;

/* --------------------------------------------------------------------
   STEP 3. CLEAN TABLE
   Keeps only real sales made by identified customers:
   no cancellations, no guest checkouts, no non-product codes,
   no zero or negative price/quantity, no exact duplicates.
   If your date shows up as NULL, change the format string in STR_TO_DATE.
   -------------------------------------------------------------------- */
   
SET SESSION internal_tmp_mem_storage_engine = TempTable;
   
DROP TABLE IF EXISTS clean_sales;
CREATE TABLE clean_sales AS
SELECT invoice, stock_code, description, quantity, invoice_ts, unit_price,
       customer_id, country, ROUND(quantity * unit_price, 2) AS line_revenue
FROM (
  SELECT
    invoice,
    stock_code,
    TRIM(description)                                         AS description,
    CAST(quantity AS SIGNED)                                  AS quantity,
    STR_TO_DATE(invoice_date, '%c/%e/%Y %H:%i')            AS invoice_ts,
    CAST(price AS DECIMAL(12,2))                              AS unit_price,
    CAST(CAST(customer_id AS DECIMAL(12,0)) AS UNSIGNED)      AS customer_id,
    TRIM(country)                                             AS country,
    ROW_NUMBER() OVER (
      PARTITION BY invoice, stock_code, quantity, invoice_date, price, customer_id
      ORDER BY invoice)                                       AS rn
  FROM online_retail_combined
  WHERE invoice NOT LIKE 'C%'
    AND customer_id IS NOT NULL AND TRIM(customer_id) <> ''
    AND stock_code REGEXP '^[0-9]{5}'
) t
WHERE rn = 1 AND quantity > 0 AND unit_price > 0 AND invoice_ts IS NOT NULL;

ALTER TABLE clean_sales
  ADD INDEX idx_customer (customer_id),
  ADD INDEX idx_invoice (invoice),
  ADD INDEX idx_ts (invoice_ts);

-- Reconciliation: what is left after cleaning
SELECT COUNT(*)                      AS rows_kept,
       COUNT(DISTINCT invoice)       AS orders,
       COUNT(DISTINCT customer_id)   AS customers,
       ROUND(SUM(line_revenue), 2)   AS revenue,
       MIN(invoice_ts)               AS first_order,
       MAX(invoice_ts)               AS last_order
FROM clean_sales;

/* --------------------------------------------------------------------
   STEP 4. ANALYSIS VIEWS (Power BI will connect to these)
   -------------------------------------------------------------------- */

-- 4.1 One row per order (invoice)
CREATE OR REPLACE VIEW v_orders_base AS
SELECT invoice,
       customer_id,
       MIN(country)                                             AS country,
       MIN(invoice_ts)                                          AS order_ts,
       DATE(MIN(invoice_ts))                                    AS order_date,
       CAST(DATE_FORMAT(MIN(invoice_ts), '%Y-%m-01') AS DATE)   AS order_month,
       SUM(line_revenue)                                        AS order_revenue,
       SUM(quantity)                                            AS units
FROM clean_sales
GROUP BY invoice, customer_id;

-- 4.2 Each customer's cohort = the calendar month of their first order
CREATE OR REPLACE VIEW v_customer_cohort AS
SELECT customer_id,
       MIN(order_month) AS cohort_month,
       MIN(order_date)  AS first_order_date
FROM v_orders_base
GROUP BY customer_id;

-- 4.3 Orders enriched with cohort, month number and New/Returning flag
CREATE OR REPLACE VIEW v_orders AS
SELECT b.*,
       c.cohort_month,
       TIMESTAMPDIFF(MONTH, c.cohort_month, b.order_month) AS month_number,
       CASE WHEN b.order_month = c.cohort_month THEN 'New' ELSE 'Returning' END
                                                           AS customer_type
FROM v_orders_base b
JOIN v_customer_cohort c ON c.customer_id = b.customer_id;

-- 4.4 Cohort retention grid (one row per cohort x month number).
--     The grid only includes months that have actually happened for that
--     cohort, so recent cohorts are not penalised for months not yet reached.
CREATE OR REPLACE VIEW v_cohort_retention AS
WITH RECURSIVE nums AS (
  SELECT 0 AS n UNION ALL SELECT n + 1 FROM nums WHERE n < 24
),
last_month AS (
  SELECT MAX(order_month) AS m FROM v_orders
),
cohorts AS (
  SELECT cohort_month, COUNT(*) AS cohort_customers
  FROM v_customer_cohort
  GROUP BY cohort_month
),
grid AS (
  SELECT c.cohort_month, c.cohort_customers, nums.n AS month_number
  FROM cohorts c
  CROSS JOIN nums
  CROSS JOIN last_month l
  WHERE TIMESTAMPDIFF(MONTH, c.cohort_month, l.m) >= nums.n
),
active AS (
  SELECT cohort_month, month_number, COUNT(DISTINCT customer_id) AS active_customers
  FROM v_orders
  GROUP BY cohort_month, month_number
)
SELECT g.cohort_month,
       g.month_number,
       g.cohort_customers,
       COALESCE(a.active_customers, 0) AS active_customers,
       ROUND(100 * COALESCE(a.active_customers, 0) / g.cohort_customers, 1) AS retention_pct
FROM grid g
LEFT JOIN active a
       ON a.cohort_month = g.cohort_month AND a.month_number = g.month_number;

-- 4.5 Monthly summary with month-over-month growth, new vs returning
CREATE OR REPLACE VIEW v_monthly_summary AS
WITH monthly AS (
  SELECT order_month,
         SUM(order_revenue)                                              AS revenue,
         COUNT(*)                                                        AS orders,
         COUNT(DISTINCT customer_id)                                     AS customers,
         COUNT(DISTINCT CASE WHEN customer_type = 'New' THEN customer_id END)
                                                                         AS new_customers,
         COUNT(DISTINCT CASE WHEN customer_type = 'Returning' THEN customer_id END)
                                                                         AS returning_customers,
         SUM(CASE WHEN customer_type = 'New' THEN order_revenue ELSE 0 END)
                                                                         AS new_revenue,
         SUM(CASE WHEN customer_type = 'Returning' THEN order_revenue ELSE 0 END)
                                                                         AS returning_revenue
  FROM v_orders
  GROUP BY order_month
)
SELECT m.*,
       LAG(revenue) OVER (ORDER BY order_month) AS prev_revenue,
       ROUND(100 * (revenue - LAG(revenue) OVER (ORDER BY order_month))
             / NULLIF(LAG(revenue) OVER (ORDER BY order_month), 0), 1) AS mom_growth_pct
FROM monthly m;

-- 4.6 RFM segmentation (snapshot = day after the last order in the data)
CREATE OR REPLACE VIEW v_rfm AS
WITH snap AS (
  SELECT DATE_ADD(MAX(order_date), INTERVAL 1 DAY) AS snapshot_date FROM v_orders
),
rfm AS (
  SELECT o.customer_id,
         DATEDIFF(s.snapshot_date, MAX(o.order_date)) AS recency_days,
         COUNT(*)                                     AS frequency,
         ROUND(SUM(o.order_revenue), 2)               AS monetary
  FROM v_orders o
  CROSS JOIN snap s
  GROUP BY o.customer_id, s.snapshot_date
),
scored AS (
  SELECT rfm.*,
         NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,   -- 5 = most recent
         NTILE(5) OVER (ORDER BY frequency)         AS f_score,
         NTILE(5) OVER (ORDER BY monetary)          AS m_score
  FROM rfm
)
SELECT scored.*,
       CASE
         WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions'
         WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal'
         WHEN r_score <= 2 AND f_score >= 4 THEN 'At risk (was loyal)'
         WHEN r_score >= 4 AND f_score <= 2 THEN 'New / recent'
         WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost / hibernating'
         ELSE 'Needs attention'
       END AS segment
FROM scored;

-- 4.7 Revenue concentration: how much of revenue comes from the top 20% of customers
CREATE OR REPLACE VIEW v_revenue_concentration AS
WITH cust AS (
  SELECT customer_id, SUM(order_revenue) AS revenue FROM v_orders GROUP BY customer_id
),
ranked AS (
  SELECT customer_id, revenue, NTILE(5) OVER (ORDER BY revenue DESC) AS customer_quintile
  FROM cust
)
SELECT customer_quintile,
       COUNT(*)                                                 AS customers,
       ROUND(SUM(revenue), 2)                                   AS revenue,
       ROUND(100 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1) AS revenue_share_pct
FROM ranked
GROUP BY customer_quintile;

-- 4.8 Country summary
CREATE OR REPLACE VIEW v_country_summary AS
SELECT country,
       COUNT(DISTINCT customer_id) AS customers,
       COUNT(*)                    AS orders,
       ROUND(SUM(order_revenue), 2) AS revenue
FROM v_orders
GROUP BY country;

/* --------------------------------------------------------------------
   STEP 5. HEADLINE NUMBERS 
   -------------------------------------------------------------------- */

-- Total revenue, customers, orders, average order value
SELECT ROUND(SUM(order_revenue), 2)           AS total_revenue,
       COUNT(DISTINCT customer_id)            AS customers,
       COUNT(*)                               AS orders,
       ROUND(SUM(order_revenue) / COUNT(*), 2) AS avg_order_value
FROM v_orders;

-- Month 1 retention across all cohorts that have reached month 1
SELECT ROUND(100 * SUM(active_customers) / SUM(cohort_customers), 1) AS month1_retention_pct
FROM v_cohort_retention
WHERE month_number = 1;

-- Same, but excluding the first cohort (see the left-censoring note in the guide)
SELECT ROUND(100 * SUM(active_customers) / SUM(cohort_customers), 1) AS month1_retention_excl_first_cohort
FROM v_cohort_retention
WHERE month_number = 1
  AND cohort_month > (SELECT MIN(cohort_month) FROM v_customer_cohort);

-- Average retention curve by month number
SELECT month_number,
       ROUND(100 * SUM(active_customers) / SUM(cohort_customers), 1) AS retention_pct
FROM v_cohort_retention
GROUP BY month_number
ORDER BY month_number;

-- Repeat customers: share who ordered at least twice
SELECT ROUND(100 * SUM(CASE WHEN n_orders >= 2 THEN 1 ELSE 0 END) / COUNT(*), 1) AS repeat_customer_pct
FROM (SELECT customer_id, COUNT(*) AS n_orders FROM v_orders GROUP BY customer_id) t;

-- Month-over-month range and peak month
SELECT MIN(mom_growth_pct) AS worst_mom_pct,
       MAX(mom_growth_pct) AS best_mom_pct,
       MAX(revenue)        AS peak_month_revenue
FROM v_monthly_summary;

SELECT order_month, revenue, mom_growth_pct FROM v_monthly_summary ORDER BY order_month;
SELECT * FROM v_revenue_concentration ORDER BY customer_quintile;

SELECT segment, COUNT(*) AS customers, ROUND(SUM(monetary), 2) AS revenue
FROM v_rfm GROUP BY segment ORDER BY revenue DESC;

/* --------------------------------------------------------------------
   STEP 6. VALIDATION CHECKS (all should pass before you build the dashboard)
   -------------------------------------------------------------------- */

-- 1) Order-level revenue equals line-level revenue (difference should be 0)
SELECT ROUND((SELECT SUM(order_revenue) FROM v_orders)
           - (SELECT SUM(line_revenue)  FROM clean_sales), 2) AS revenue_difference;

-- 2) Every customer is in exactly one cohort (the two numbers must match)
SELECT (SELECT COUNT(*) FROM v_customer_cohort)            AS customers_in_cohorts,
       (SELECT COUNT(DISTINCT customer_id) FROM clean_sales) AS customers_in_sales;

-- 3) Month 0 retention must be 100% for every cohort (should return no rows)
SELECT * FROM v_cohort_retention WHERE month_number = 0 AND retention_pct <> 100;

-- 4) Cohort sizes add up to total customers
SELECT SUM(cohort_customers) AS total_in_month0
FROM v_cohort_retention WHERE month_number = 0;

-- 5) No order should be missing its date or customer (should return 0)
SELECT COUNT(*) AS bad_orders FROM v_orders WHERE order_month IS NULL OR customer_id IS NULL;