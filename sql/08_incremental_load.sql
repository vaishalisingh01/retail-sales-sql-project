-- =====================================================================
-- 08_incremental_load.sql
-- A new batch of orders arrives (January 2026).
--
-- FULL LOAD vs INCREMENTAL LOAD
--   Full load        -> delete everything and reload all data every day.
--                       Simple, but slow and expensive as data grows.
--   Incremental load -> only process what is NEW or CHANGED.
--                       This is what real pipelines do.
--
-- The new batch contains:
--   * brand-new orders                      -> must be INSERTED
--   * old orders whose status changed       -> must be UPDATED
--     (e.g. Delivered -> Returned)
--   * a few duplicate rows                  -> must be ignored
--
-- MERGE (also called UPSERT) does insert + update in a single statement.
-- Running this script twice gives the SAME result (it is "idempotent"),
-- so a failed pipeline can simply be re-run safely.
-- =====================================================================


-- ---------------------------------------------------------------------
-- STEP 1: land the new file in staging and clean it
-- ---------------------------------------------------------------------
TRUNCATE staging.new_orders;
\copy staging.new_orders FROM 'data/new_orders.csv' WITH (FORMAT csv, HEADER true)

DROP TABLE IF EXISTS stg_orders;
CREATE TEMP TABLE stg_orders AS
SELECT DISTINCT ON (o.order_id::INT)
    o.order_id::INT                                   AS order_id,
    o.customer_id::INT                                AS customer_id,
    o.product_id::INT                                 AS product_id,
    o.order_date::DATE                                AS order_date,
    o.quantity::INT                                   AS quantity,
    o.discount_pct::NUMERIC                           AS discount_pct,
    COALESCE(NULLIF(TRIM(o.payment_method), ''), 'Unknown') AS payment_method,
    TRIM(o.order_status)                              AS order_status,
    ROUND(p.unit_price * o.quantity::INT
          * (1 - o.discount_pct::NUMERIC / 100), 2)   AS sales_amount
FROM staging.new_orders o
JOIN clean.products p ON p.product_id = o.product_id::INT
WHERE o.quantity::INT > 0
ORDER BY o.order_id::INT;

-- What is in this batch?
SELECT
    COUNT(*)                                                      AS rows_in_batch,
    SUM(CASE WHEN c.order_id IS NULL THEN 1 ELSE 0 END)           AS new_orders,
    SUM(CASE WHEN c.order_status <> s.order_status THEN 1 ELSE 0 END) AS status_changes,
    SUM(CASE WHEN c.order_status = s.order_status THEN 1 ELSE 0 END)  AS unchanged
FROM stg_orders s
LEFT JOIN clean.orders c ON c.order_id = s.order_id;


-- ---------------------------------------------------------------------
-- STEP 2: MERGE into clean.orders
-- ---------------------------------------------------------------------
MERGE INTO clean.orders AS t
USING stg_orders AS s
    ON t.order_id = s.order_id
WHEN MATCHED AND t.order_status <> s.order_status THEN
    UPDATE SET order_status = s.order_status
WHEN NOT MATCHED THEN
    INSERT (order_id, customer_id, product_id, order_date, quantity,
            discount_pct, payment_method, order_status, sales_amount)
    VALUES (s.order_id, s.customer_id, s.product_id, s.order_date, s.quantity,
            s.discount_pct, s.payment_method, s.order_status, s.sales_amount);


-- ---------------------------------------------------------------------
-- STEP 3: MERGE into the fact table (dw.fact_sales)
--   Look up surrogate keys. The customer version is the one that was
--   valid ON THE ORDER DATE, so January 2026 orders from customers who
--   moved get their NEW city, while their older orders keep the OLD one.
-- ---------------------------------------------------------------------
MERGE INTO dw.fact_sales AS f
USING (
    SELECT
        s.order_id,
        d.date_key,
        c.customer_key,
        p.product_key,
        s.quantity,
        p.unit_price,
        s.discount_pct,
        s.sales_amount,
        s.payment_method,
        s.order_status
    FROM stg_orders s
    JOIN dw.dim_date     d ON d.full_date   = s.order_date
    JOIN dw.dim_product  p ON p.product_id  = s.product_id
    JOIN dw.dim_customer c ON c.customer_id = s.customer_id
                          AND s.order_date BETWEEN c.effective_from AND c.effective_to
) AS src
    ON f.order_id = src.order_id
WHEN MATCHED AND f.order_status <> src.order_status THEN
    UPDATE SET order_status = src.order_status,
               loaded_at    = NOW()
WHEN NOT MATCHED THEN
    INSERT (order_id, date_key, customer_key, product_key, quantity,
            unit_price, discount_pct, sales_amount, payment_method, order_status)
    VALUES (src.order_id, src.date_key, src.customer_key, src.product_key, src.quantity,
            src.unit_price, src.discount_pct, src.sales_amount, src.payment_method,
            src.order_status);


-- ---------------------------------------------------------------------
-- STEP 4: data quality checks for the warehouse (all should PASS)
-- ---------------------------------------------------------------------
SELECT 'Fact table row count matches clean.orders' AS check_name,
       CASE WHEN (SELECT COUNT(*) FROM dw.fact_sales) = (SELECT COUNT(*) FROM clean.orders)
            THEN 'PASS' ELSE 'FAIL' END AS result

UNION ALL
SELECT 'Fact revenue matches clean.orders revenue',
       CASE WHEN (SELECT SUM(sales_amount) FROM dw.fact_sales)
               = (SELECT SUM(sales_amount) FROM clean.orders)
            THEN 'PASS' ELSE 'FAIL' END

UNION ALL
SELECT 'Order statuses match between clean and fact',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM clean.orders o
JOIN dw.fact_sales f ON f.order_id = o.order_id
WHERE f.order_status <> o.order_status

UNION ALL
SELECT 'Every customer has exactly one current version',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (
    SELECT customer_id
    FROM dw.dim_customer
    GROUP BY customer_id
    HAVING SUM(CASE WHEN is_current THEN 1 ELSE 0 END) <> 1
) x

UNION ALL
SELECT 'No overlapping customer versions',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM dw.dim_customer a
JOIN dw.dim_customer b
  ON a.customer_id = b.customer_id
 AND a.customer_key < b.customer_key
 AND a.effective_from <= b.effective_to
 AND b.effective_from <= a.effective_to;
