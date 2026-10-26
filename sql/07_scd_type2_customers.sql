-- =====================================================================
-- 07_scd_type2_customers.sql
-- A new batch of customer data arrives: some customers MOVED CITY and
-- some are BRAND NEW.
--
-- SCD = Slowly Changing Dimension. How should the warehouse handle it?
--
--   SCD Type 1 -> overwrite the old value. History is LOST.
--                 (Old sales would now show the customer's NEW city.)
--   SCD Type 2 -> keep the old row, close it, and add a NEW row.
--                 History is KEPT. Old sales stay linked to the old city.
--
-- Example for customer 17 who moved from Mumbai to Kolkata:
--
--   customer_key | customer_id | city    | effective_from | effective_to | is_current
--   -------------+-------------+---------+----------------+--------------+-----------
--             17 |          17 | Mumbai  | 1900-01-01     | 2025-12-31   | false
--            301 |          17 | Kolkata | 2026-01-01     | 9999-12-31   | true
--
-- This script does:
--   Step 1: land the file in staging and clean it
--   Step 2: UPSERT clean.customers (current state only, like SCD Type 1)
--   Step 3: SCD Type 2 on dw.dim_customer (full history)
--
-- It is safe to run more than once: if nothing changed, nothing happens.
-- =====================================================================


-- ---------------------------------------------------------------------
-- STEP 1: load the new file into staging, then clean it
-- ---------------------------------------------------------------------
TRUNCATE staging.customer_updates;
\copy staging.customer_updates FROM 'data/customer_updates.csv' WITH (FORMAT csv, HEADER true)

-- A temporary table lives only for this session. Same cleaning rules as file 03.
DROP TABLE IF EXISTS stg_customers;
CREATE TEMP TABLE stg_customers AS
SELECT DISTINCT ON (customer_id::INT)
    customer_id::INT                AS customer_id,
    INITCAP(TRIM(customer_name))    AS customer_name,
    NULLIF(LOWER(TRIM(email)), '')  AS email,
    INITCAP(TRIM(city))             AS city,
    TRIM(region)                    AS region,
    signup_date::DATE               AS signup_date,
    updated_at::DATE                AS updated_at
FROM staging.customer_updates
ORDER BY customer_id::INT, updated_at::DATE DESC;   -- keep the latest record

SELECT COUNT(*) AS customer_records_in_batch FROM stg_customers;


-- ---------------------------------------------------------------------
-- STEP 2: UPSERT into clean.customers with MERGE
--   - customer exists and something changed -> UPDATE it
--   - customer does not exist               -> INSERT it
-- ---------------------------------------------------------------------
MERGE INTO clean.customers AS t
USING stg_customers AS s
    ON t.customer_id = s.customer_id
WHEN MATCHED AND (
        t.customer_name IS DISTINCT FROM s.customer_name
     OR t.email         IS DISTINCT FROM s.email
     OR t.city          IS DISTINCT FROM s.city
     OR t.region        IS DISTINCT FROM s.region
    ) THEN
    UPDATE SET customer_name = s.customer_name,
               email         = s.email,
               city          = s.city,
               region        = s.region
WHEN NOT MATCHED THEN
    INSERT (customer_id, customer_name, email, city, region, signup_date)
    VALUES (s.customer_id, s.customer_name, s.email, s.city, s.region, s.signup_date);

-- (IS DISTINCT FROM is like <> but also handles NULLs correctly:
--  NULL <> 'a' gives NULL, while NULL IS DISTINCT FROM 'a' gives TRUE)


-- ---------------------------------------------------------------------
-- STEP 3: SCD Type 2 on dw.dim_customer
-- ---------------------------------------------------------------------

-- 3a. CLOSE the current version of every customer whose details changed
UPDATE dw.dim_customer AS d
SET effective_to = s.updated_at - 1,        -- valid until the day before the change
    is_current   = FALSE
FROM stg_customers AS s
WHERE d.customer_id = s.customer_id
  AND d.is_current
  AND (   d.customer_name IS DISTINCT FROM s.customer_name
       OR d.email         IS DISTINCT FROM s.email
       OR d.city          IS DISTINCT FROM s.city
       OR d.region        IS DISTINCT FROM s.region);

-- 3b. INSERT a new current version for:
--     - customers we just closed in 3a (they have no current row now)
--     - brand-new customers (they never had a row)
INSERT INTO dw.dim_customer (customer_id, customer_name, email, city, region,
                             effective_from, effective_to, is_current)
SELECT s.customer_id, s.customer_name, s.email, s.city, s.region,
       s.updated_at, '9999-12-31', TRUE
FROM stg_customers AS s
WHERE NOT EXISTS (
    SELECT 1
    FROM dw.dim_customer AS d
    WHERE d.customer_id = s.customer_id
      AND d.is_current
);


-- ---------------------------------------------------------------------
-- RESULTS
-- ---------------------------------------------------------------------

-- Customers that now have more than one version (their history)
SELECT customer_id, customer_key, customer_name, city, region,
       effective_from, effective_to, is_current
FROM dw.dim_customer
WHERE customer_id IN (
    SELECT customer_id FROM dw.dim_customer GROUP BY customer_id HAVING COUNT(*) > 1
)
ORDER BY customer_id, effective_from
LIMIT 10;

SELECT
    COUNT(DISTINCT customer_id)                 AS unique_customers,
    COUNT(*)                                    AS total_versions,
    SUM(CASE WHEN is_current THEN 1 ELSE 0 END) AS current_versions
FROM dw.dim_customer;
