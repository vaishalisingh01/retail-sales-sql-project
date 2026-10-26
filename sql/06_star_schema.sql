-- =====================================================================
-- 06_star_schema.sql
-- Builds a STAR SCHEMA (data warehouse layer) in the `dw` schema.
--
-- A star schema has:
--   * ONE fact table      -> the events/measurements (each sale)
--   * MANY dimension tables -> the "who, what, when" that describe a sale
--
--                 dim_date
--                     |
--   dim_customer -- fact_sales -- dim_product
--
-- Why? Analysts can answer almost any question with simple joins from the
-- fact table to the dimensions, and BI tools (Power BI, Tableau) expect it.
--
-- Key idea: SURROGATE KEYS
--   Dimensions use their own key (customer_key) instead of the business ID
--   (customer_id). This lets one customer have several historical versions
--   (see 07_scd_type2_customers.sql).
-- =====================================================================

DROP SCHEMA IF EXISTS dw CASCADE;
CREATE SCHEMA dw;


-- ---------------------------------------------------------------------
-- dim_date: one row per calendar day (built with generate_series)
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_date (
    date_key     INT PRIMARY KEY,          -- e.g. 20250315
    full_date    DATE NOT NULL UNIQUE,
    day          INT  NOT NULL,
    month        INT  NOT NULL,
    month_name   VARCHAR(10) NOT NULL,
    quarter      INT  NOT NULL,
    year         INT  NOT NULL,
    day_name     VARCHAR(10) NOT NULL,
    is_weekend   BOOLEAN NOT NULL
);

INSERT INTO dw.dim_date
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INT,
    d::DATE,
    EXTRACT(DAY FROM d)::INT,
    EXTRACT(MONTH FROM d)::INT,
    TRIM(TO_CHAR(d, 'Month')),
    EXTRACT(QUARTER FROM d)::INT,
    EXTRACT(YEAR FROM d)::INT,
    TRIM(TO_CHAR(d, 'Day')),
    EXTRACT(ISODOW FROM d) IN (6, 7)        -- 6 = Saturday, 7 = Sunday
FROM generate_series('2024-01-01'::DATE, '2026-12-31'::DATE, INTERVAL '1 day') AS d;


-- ---------------------------------------------------------------------
-- dim_product
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_product (
    product_key   SERIAL PRIMARY KEY,       -- surrogate key
    product_id    INT UNIQUE NOT NULL,      -- business key from source
    product_name  VARCHAR(100) NOT NULL,
    category      VARCHAR(50)  NOT NULL,
    unit_price    NUMERIC(10,2) NOT NULL
);

INSERT INTO dw.dim_product (product_id, product_name, category, unit_price)
SELECT product_id, product_name, category, unit_price
FROM clean.products
ORDER BY product_id;


-- ---------------------------------------------------------------------
-- dim_customer (SCD Type 2 ready: keeps history of changes)
--   effective_from / effective_to -> the period this version was true
--   is_current                    -> TRUE only for the latest version
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_customer (
    customer_key    SERIAL PRIMARY KEY,     -- surrogate key (one per version)
    customer_id     INT NOT NULL,           -- business key (same for all versions)
    customer_name   VARCHAR(100) NOT NULL,
    email           VARCHAR(150),
    city            VARCHAR(50) NOT NULL,
    region          VARCHAR(20) NOT NULL,
    effective_from  DATE NOT NULL,
    effective_to    DATE NOT NULL DEFAULT '9999-12-31',
    is_current      BOOLEAN NOT NULL DEFAULT TRUE
);

-- a customer can only have ONE current version
CREATE UNIQUE INDEX uq_dim_customer_current
    ON dw.dim_customer (customer_id) WHERE is_current;

-- First load: every customer gets version 1, valid "from the beginning"
INSERT INTO dw.dim_customer (customer_id, customer_name, email, city, region,
                             effective_from, effective_to, is_current)
SELECT customer_id, customer_name, email, city, region,
       '1900-01-01', '9999-12-31', TRUE
FROM clean.customers
ORDER BY customer_id;


-- ---------------------------------------------------------------------
-- fact_sales: one row per order (this is the "grain" of the table)
-- ---------------------------------------------------------------------
CREATE TABLE dw.fact_sales (
    order_id        INT PRIMARY KEY,        -- degenerate dimension (no own table)
    date_key        INT NOT NULL REFERENCES dw.dim_date(date_key),
    customer_key    INT NOT NULL REFERENCES dw.dim_customer(customer_key),
    product_key     INT NOT NULL REFERENCES dw.dim_product(product_key),
    quantity        INT NOT NULL,
    unit_price      NUMERIC(10,2) NOT NULL,
    discount_pct    NUMERIC(5,2)  NOT NULL,
    sales_amount    NUMERIC(12,2) NOT NULL,
    payment_method  VARCHAR(30) NOT NULL,
    order_status    VARCHAR(20) NOT NULL,
    loaded_at       TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_fact_date     ON dw.fact_sales(date_key);
CREATE INDEX idx_fact_customer ON dw.fact_sales(customer_key);
CREATE INDEX idx_fact_product  ON dw.fact_sales(product_key);

-- Initial load: swap business IDs for surrogate keys.
-- The customer join picks the version that was valid ON THE ORDER DATE.
INSERT INTO dw.fact_sales (order_id, date_key, customer_key, product_key, quantity,
                           unit_price, discount_pct, sales_amount, payment_method, order_status)
SELECT
    o.order_id,
    d.date_key,
    c.customer_key,
    p.product_key,
    o.quantity,
    p.unit_price,
    o.discount_pct,
    o.sales_amount,
    o.payment_method,
    o.order_status
FROM clean.orders o
JOIN dw.dim_date     d ON d.full_date   = o.order_date
JOIN dw.dim_product  p ON p.product_id  = o.product_id
JOIN dw.dim_customer c ON c.customer_id = o.customer_id
                      AND o.order_date BETWEEN c.effective_from AND c.effective_to;


-- ---------------------------------------------------------------------
-- Check: every clean order made it into the fact table
-- ---------------------------------------------------------------------
SELECT 'dim_date'     AS table_name, COUNT(*) AS row_count FROM dw.dim_date
UNION ALL SELECT 'dim_product',  COUNT(*) FROM dw.dim_product
UNION ALL SELECT 'dim_customer', COUNT(*) FROM dw.dim_customer
UNION ALL SELECT 'fact_sales',   COUNT(*) FROM dw.fact_sales
UNION ALL SELECT 'clean.orders (should match fact_sales)', COUNT(*) FROM clean.orders;
