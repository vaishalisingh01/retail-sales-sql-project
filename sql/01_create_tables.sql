-- =====================================================================
-- 01_create_tables.sql
-- Creates the first layers of tables:
--   1. RAW tables     -> store the CSV data exactly as it arrives (all text)
--   2. CLEAN tables   -> correct data types, keys and constraints
--   3. STAGING tables -> temporary landing area for NEW batches of data
--                        that arrive later (used by the incremental load)
--
-- Why separate layers? In real data engineering you never edit the source
-- data directly. You load it as-is, then build clean tables from it.
-- If something goes wrong, you can always rebuild from raw.
-- (The star schema / warehouse layer is created later in 06_star_schema.sql)
-- =====================================================================

DROP SCHEMA IF EXISTS raw CASCADE;
DROP SCHEMA IF EXISTS clean CASCADE;
DROP SCHEMA IF EXISTS staging CASCADE;

CREATE SCHEMA raw;
CREATE SCHEMA clean;
CREATE SCHEMA staging;

-- ---------------------------------------------------------------------
-- STAGING layer: new batches land here first, then get merged
-- ---------------------------------------------------------------------
CREATE TABLE staging.customer_updates (
    customer_id    TEXT,
    customer_name  TEXT,
    email          TEXT,
    city           TEXT,
    region         TEXT,
    signup_date    TEXT,
    updated_at     TEXT
);

CREATE TABLE staging.new_orders (
    order_id       TEXT,
    customer_id    TEXT,
    product_id     TEXT,
    order_date     TEXT,
    quantity       TEXT,
    discount_pct   TEXT,
    payment_method TEXT,
    order_status   TEXT
);

-- ---------------------------------------------------------------------
-- RAW layer: everything is TEXT so that bad values never fail the load
-- ---------------------------------------------------------------------
CREATE TABLE raw.customers (
    customer_id    TEXT,
    customer_name  TEXT,
    email          TEXT,
    city           TEXT,
    region         TEXT,
    signup_date    TEXT
);

CREATE TABLE raw.products (
    product_id     TEXT,
    product_name   TEXT,
    category       TEXT,
    unit_price     TEXT
);

CREATE TABLE raw.orders (
    order_id       TEXT,
    customer_id    TEXT,
    product_id     TEXT,
    order_date     TEXT,
    quantity       TEXT,
    discount_pct   TEXT,
    payment_method TEXT,
    order_status   TEXT
);

-- ---------------------------------------------------------------------
-- CLEAN layer: proper types, primary keys and foreign keys
-- ---------------------------------------------------------------------
CREATE TABLE clean.customers (
    customer_id    INT PRIMARY KEY,
    customer_name  VARCHAR(100) NOT NULL,
    email          VARCHAR(150),
    city           VARCHAR(50)  NOT NULL,
    region         VARCHAR(20)  NOT NULL,
    signup_date    DATE         NOT NULL
);

CREATE TABLE clean.products (
    product_id     INT PRIMARY KEY,
    product_name   VARCHAR(100)  NOT NULL,
    category       VARCHAR(50)   NOT NULL,
    unit_price     NUMERIC(10,2) NOT NULL CHECK (unit_price > 0)
);

CREATE TABLE clean.orders (
    order_id       INT PRIMARY KEY,
    customer_id    INT  NOT NULL REFERENCES clean.customers(customer_id),
    product_id     INT  NOT NULL REFERENCES clean.products(product_id),
    order_date     DATE NOT NULL,
    quantity       INT  NOT NULL CHECK (quantity > 0),
    discount_pct   NUMERIC(5,2) NOT NULL DEFAULT 0,
    payment_method VARCHAR(30)  NOT NULL,
    order_status   VARCHAR(20)  NOT NULL,
    -- calculated column: final amount after discount
    sales_amount   NUMERIC(12,2)
);

-- Indexes on columns we filter / join on a lot
CREATE INDEX idx_orders_customer ON clean.orders(customer_id);
CREATE INDEX idx_orders_product  ON clean.orders(product_id);
CREATE INDEX idx_orders_date     ON clean.orders(order_date);
