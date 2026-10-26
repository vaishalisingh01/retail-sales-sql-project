-- =====================================================================
-- 03_data_cleaning.sql
-- Step 1: PROFILE the raw data (find the problems)
-- Step 2: CLEAN it and insert into the clean tables
-- =====================================================================


-- ---------------------------------------------------------------------
-- STEP 1: DATA PROFILING - what is wrong with the raw data?
-- ---------------------------------------------------------------------

-- 1a. Duplicate customers (same customer_id appears more than once)
SELECT customer_id, COUNT(*) AS times_found
FROM raw.customers
GROUP BY customer_id
HAVING COUNT(*) > 1
ORDER BY customer_id;

-- 1b. Duplicate orders
SELECT COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_order_rows
FROM raw.orders;

-- 1c. Names / cities with extra spaces or wrong case
SELECT customer_name, city
FROM raw.customers
WHERE customer_name <> TRIM(customer_name)
   OR city <> INITCAP(TRIM(city))
LIMIT 10;

-- 1d. Missing values
SELECT
    SUM(CASE WHEN email IS NULL OR TRIM(email) = '' THEN 1 ELSE 0 END) AS missing_emails
FROM raw.customers;

SELECT
    SUM(CASE WHEN payment_method IS NULL OR TRIM(payment_method) = '' THEN 1 ELSE 0 END) AS missing_payment
FROM raw.orders;

-- 1e. Invalid quantities (zero or negative)
SELECT order_id, quantity
FROM raw.orders
WHERE quantity::INT <= 0;


-- ---------------------------------------------------------------------
-- STEP 2: CLEAN AND LOAD
-- ---------------------------------------------------------------------
TRUNCATE clean.orders, clean.customers, clean.products;

-- 2a. Customers
--   - remove duplicates (DISTINCT ON keeps one row per customer_id)
--   - trim spaces and fix capitalisation
--   - turn empty emails into NULL
INSERT INTO clean.customers (customer_id, customer_name, email, city, region, signup_date)
SELECT DISTINCT ON (customer_id::INT)
    customer_id::INT,
    INITCAP(TRIM(customer_name)),
    NULLIF(LOWER(TRIM(email)), ''),
    INITCAP(TRIM(city)),
    TRIM(region),
    signup_date::DATE
FROM raw.customers
ORDER BY customer_id::INT;

-- 2b. Products (already clean, just cast the types)
INSERT INTO clean.products (product_id, product_name, category, unit_price)
SELECT
    product_id::INT,
    TRIM(product_name),
    TRIM(category),
    unit_price::NUMERIC
FROM raw.products;

-- 2c. Orders
--   - remove duplicate rows
--   - drop rows with zero / negative quantity
--   - fill missing payment method with 'Unknown'
--   - calculate sales_amount = price * quantity * (1 - discount)
INSERT INTO clean.orders (order_id, customer_id, product_id, order_date, quantity,
                          discount_pct, payment_method, order_status, sales_amount)
SELECT DISTINCT ON (o.order_id::INT)
    o.order_id::INT,
    o.customer_id::INT,
    o.product_id::INT,
    o.order_date::DATE,
    o.quantity::INT,
    o.discount_pct::NUMERIC,
    COALESCE(NULLIF(TRIM(o.payment_method), ''), 'Unknown'),
    TRIM(o.order_status),
    ROUND(p.unit_price * o.quantity::INT * (1 - o.discount_pct::NUMERIC / 100), 2)
FROM raw.orders o
JOIN clean.products p ON p.product_id = o.product_id::INT
WHERE o.quantity::INT > 0
ORDER BY o.order_id::INT;


-- ---------------------------------------------------------------------
-- STEP 3: BEFORE vs AFTER row counts
-- ---------------------------------------------------------------------
SELECT 'customers' AS table_name,
       (SELECT COUNT(*) FROM raw.customers)   AS raw_rows,
       (SELECT COUNT(*) FROM clean.customers) AS clean_rows
UNION ALL
SELECT 'orders',
       (SELECT COUNT(*) FROM raw.orders),
       (SELECT COUNT(*) FROM clean.orders);
