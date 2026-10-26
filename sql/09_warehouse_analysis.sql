-- =====================================================================
-- 09_warehouse_analysis.sql
-- Business questions answered from the STAR SCHEMA.
-- Notice how every query is just: fact_sales + JOIN the dimensions you need.
-- =====================================================================


-- Q1. Revenue by year and quarter (using dim_date instead of date functions)
SELECT
    d.year,
    d.quarter,
    COUNT(*)            AS orders,
    SUM(f.sales_amount) AS revenue
FROM dw.fact_sales f
JOIN dw.dim_date d ON d.date_key = f.date_key
WHERE f.order_status = 'Delivered'
GROUP BY d.year, d.quarter
ORDER BY d.year, d.quarter;


-- Q2. Weekday vs weekend sales
SELECT
    CASE WHEN d.is_weekend THEN 'Weekend' ELSE 'Weekday' END AS day_type,
    COUNT(*)                         AS orders,
    SUM(f.sales_amount)              AS revenue,
    ROUND(AVG(f.sales_amount), 2)    AS avg_order_value
FROM dw.fact_sales f
JOIN dw.dim_date d ON d.date_key = f.date_key
WHERE f.order_status = 'Delivered'
GROUP BY day_type;


-- Q3. Best day of the week for sales
SELECT
    d.day_name,
    COUNT(*)            AS orders,
    SUM(f.sales_amount) AS revenue
FROM dw.fact_sales f
JOIN dw.dim_date d ON d.date_key = f.date_key
WHERE f.order_status = 'Delivered'
GROUP BY d.day_name, EXTRACT(ISODOW FROM d.full_date)
ORDER BY EXTRACT(ISODOW FROM d.full_date);


-- Q4. Category revenue by year (pivot with CASE)
SELECT
    p.category,
    SUM(CASE WHEN d.year = 2024 THEN f.sales_amount ELSE 0 END) AS revenue_2024,
    SUM(CASE WHEN d.year = 2025 THEN f.sales_amount ELSE 0 END) AS revenue_2025,
    SUM(CASE WHEN d.year = 2026 THEN f.sales_amount ELSE 0 END) AS revenue_2026_ytd
FROM dw.fact_sales f
JOIN dw.dim_date    d ON d.date_key    = f.date_key
JOIN dw.dim_product p ON p.product_key = f.product_key
WHERE f.order_status = 'Delivered'
GROUP BY p.category
ORDER BY revenue_2025 DESC;


-- Q5. Why SCD Type 2 matters: revenue by region
--   historical_region -> the region the customer lived in WHEN they bought
--   current_region    -> where the customer lives TODAY
--   With SCD Type 1 we could only get the second (wrong for history).
SELECT
    c.region                 AS historical_region,
    SUM(f.sales_amount)      AS revenue_at_time_of_sale,
    (SELECT SUM(f2.sales_amount)
       FROM dw.fact_sales f2
       JOIN dw.dim_customer c2 ON c2.customer_key = f2.customer_key
       JOIN dw.dim_customer cur ON cur.customer_id = c2.customer_id AND cur.is_current
      WHERE f2.order_status = 'Delivered'
        AND cur.region = c.region)  AS revenue_if_using_current_region
FROM dw.fact_sales f
JOIN dw.dim_customer c ON c.customer_key = f.customer_key
WHERE f.order_status = 'Delivered'
GROUP BY c.region
ORDER BY c.region;


-- Q6. Orders of customers who moved: old orders link to old city,
--     new orders link to new city
SELECT
    c.customer_id,
    c.city,
    c.is_current,
    COUNT(f.order_id)     AS orders,
    MIN(d.full_date)      AS first_order,
    MAX(d.full_date)      AS last_order
FROM dw.dim_customer c
JOIN dw.fact_sales   f ON f.customer_key = c.customer_key
JOIN dw.dim_date     d ON d.date_key     = f.date_key
WHERE c.customer_id IN (
    SELECT customer_id FROM dw.dim_customer GROUP BY customer_id HAVING COUNT(*) > 1
)
GROUP BY c.customer_id, c.city, c.is_current, c.effective_from
ORDER BY c.customer_id, c.effective_from
LIMIT 12;


-- Q7. January 2026 (the incremental batch): top categories
SELECT
    p.category,
    COUNT(*)            AS orders,
    SUM(f.sales_amount) AS revenue
FROM dw.fact_sales f
JOIN dw.dim_date    d ON d.date_key    = f.date_key
JOIN dw.dim_product p ON p.product_key = f.product_key
WHERE d.year = 2026 AND d.month = 1
  AND f.order_status = 'Delivered'
GROUP BY p.category
ORDER BY revenue DESC;


-- Q8. New customers from the latest batch and what they bought
SELECT
    c.customer_id,
    c.customer_name,
    c.city,
    COUNT(f.order_id)              AS orders,
    COALESCE(SUM(f.sales_amount), 0) AS total_spent
FROM dw.dim_customer c
LEFT JOIN dw.fact_sales f ON f.customer_key = c.customer_key
WHERE c.effective_from = '2026-01-01'
  AND c.customer_id NOT IN (
      SELECT customer_id FROM dw.dim_customer WHERE effective_from < '2026-01-01'
  )
GROUP BY c.customer_id, c.customer_name, c.city
ORDER BY total_spent DESC;
