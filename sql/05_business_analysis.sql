-- =====================================================================
-- 05_business_analysis.sql
-- Business questions answered with SQL, from EASY to ADVANCED.
-- Only 'Delivered' orders count as real revenue.
-- =====================================================================


-- =====================================================================
-- LEVEL 1: BASICS (SELECT, WHERE, GROUP BY, ORDER BY)
-- =====================================================================

-- Q1. What is the total revenue and number of delivered orders?
SELECT
    COUNT(*)                 AS total_orders,
    SUM(sales_amount)        AS total_revenue,
    ROUND(AVG(sales_amount), 2) AS avg_order_value
FROM clean.orders
WHERE order_status = 'Delivered';

-- Q2. Revenue by year
SELECT
    EXTRACT(YEAR FROM order_date) AS order_year,
    SUM(sales_amount)             AS revenue
FROM clean.orders
WHERE order_status = 'Delivered'
GROUP BY order_year
ORDER BY order_year;

-- Q3. How many orders were Delivered, Cancelled and Returned?
SELECT
    order_status,
    COUNT(*) AS order_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_orders
FROM clean.orders
GROUP BY order_status
ORDER BY order_count DESC;

-- Q4. Most popular payment methods
SELECT payment_method, COUNT(*) AS orders
FROM clean.orders
GROUP BY payment_method
ORDER BY orders DESC;


-- =====================================================================
-- LEVEL 2: JOINS
-- =====================================================================

-- Q5. Revenue by product category
SELECT
    p.category,
    SUM(o.sales_amount) AS revenue,
    SUM(o.quantity)     AS units_sold
FROM clean.orders o
JOIN clean.products p ON p.product_id = o.product_id
WHERE o.order_status = 'Delivered'
GROUP BY p.category
ORDER BY revenue DESC;

-- Q6. Top 10 best-selling products by revenue
SELECT
    p.product_name,
    p.category,
    SUM(o.sales_amount) AS revenue
FROM clean.orders o
JOIN clean.products p ON p.product_id = o.product_id
WHERE o.order_status = 'Delivered'
GROUP BY p.product_name, p.category
ORDER BY revenue DESC
LIMIT 10;

-- Q7. Revenue by region and city
SELECT
    c.region,
    c.city,
    SUM(o.sales_amount) AS revenue
FROM clean.orders o
JOIN clean.customers c ON c.customer_id = o.customer_id
WHERE o.order_status = 'Delivered'
GROUP BY c.region, c.city
ORDER BY c.region, revenue DESC;

-- Q8. Top 10 customers by total spend
SELECT
    c.customer_id,
    c.customer_name,
    c.city,
    COUNT(o.order_id)   AS orders,
    SUM(o.sales_amount) AS total_spent
FROM clean.customers c
JOIN clean.orders o ON o.customer_id = c.customer_id
WHERE o.order_status = 'Delivered'
GROUP BY c.customer_id, c.customer_name, c.city
ORDER BY total_spent DESC
LIMIT 10;

-- Q9. Customers who signed up but NEVER placed an order (LEFT JOIN)
SELECT c.customer_id, c.customer_name, c.signup_date
FROM clean.customers c
LEFT JOIN clean.orders o ON o.customer_id = c.customer_id
WHERE o.order_id IS NULL;


-- =====================================================================
-- LEVEL 3: SUBQUERIES & CTEs
-- =====================================================================

-- Q10. Which products have a return rate above the overall average?
WITH product_returns AS (
    SELECT
        p.product_name,
        COUNT(*) AS total_orders,
        SUM(CASE WHEN o.order_status = 'Returned' THEN 1 ELSE 0 END) AS returned_orders
    FROM clean.orders o
    JOIN clean.products p ON p.product_id = o.product_id
    GROUP BY p.product_name
)
SELECT
    product_name,
    total_orders,
    returned_orders,
    ROUND(100.0 * returned_orders / total_orders, 1) AS return_rate_pct
FROM product_returns
WHERE 1.0 * returned_orders / total_orders >
      (SELECT 1.0 * SUM(CASE WHEN order_status = 'Returned' THEN 1 ELSE 0 END) / COUNT(*)
       FROM clean.orders)
ORDER BY return_rate_pct DESC;

-- Q11. Customer segments based on total spend
WITH customer_spend AS (
    SELECT customer_id, SUM(sales_amount) AS total_spent
    FROM clean.orders
    WHERE order_status = 'Delivered'
    GROUP BY customer_id
)
SELECT
    CASE
        WHEN total_spent >= 30000 THEN 'High Value'
        WHEN total_spent >= 15000 THEN 'Medium Value'
        ELSE 'Low Value'
    END AS segment,
    COUNT(*)                   AS customers,
    ROUND(AVG(total_spent), 2) AS avg_spend
FROM customer_spend
GROUP BY segment
ORDER BY avg_spend DESC;


-- =====================================================================
-- LEVEL 4: WINDOW FUNCTIONS (very common in interviews!)
-- =====================================================================

-- Q12. Monthly revenue with month-over-month growth % (LAG)
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', order_date)::DATE AS month,
        SUM(sales_amount) AS revenue
    FROM clean.orders
    WHERE order_status = 'Delivered'
    GROUP BY 1
)
SELECT
    month,
    revenue,
    LAG(revenue) OVER (ORDER BY month) AS prev_month_revenue,
    ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
          / LAG(revenue) OVER (ORDER BY month), 1) AS mom_growth_pct
FROM monthly
ORDER BY month;

-- Q13. Running total of revenue through each year
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', order_date)::DATE AS month,
        SUM(sales_amount) AS revenue
    FROM clean.orders
    WHERE order_status = 'Delivered'
    GROUP BY 1
)
SELECT
    month,
    revenue,
    SUM(revenue) OVER (
        PARTITION BY EXTRACT(YEAR FROM month)
        ORDER BY month
    ) AS running_total_ytd
FROM monthly
ORDER BY month;

-- Q14. Top 3 products in EACH category (RANK + PARTITION BY)
WITH product_revenue AS (
    SELECT
        p.category,
        p.product_name,
        SUM(o.sales_amount) AS revenue
    FROM clean.orders o
    JOIN clean.products p ON p.product_id = o.product_id
    WHERE o.order_status = 'Delivered'
    GROUP BY p.category, p.product_name
),
ranked AS (
    SELECT *,
           RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS rank_in_category
    FROM product_revenue
)
SELECT category, product_name, revenue, rank_in_category
FROM ranked
WHERE rank_in_category <= 3
ORDER BY category, rank_in_category;

-- Q15. Each customer's first and most recent order, and days between them
SELECT
    customer_id,
    MIN(order_date)                   AS first_order,
    MAX(order_date)                   AS last_order,
    MAX(order_date) - MIN(order_date) AS days_active,
    COUNT(*)                          AS total_orders
FROM clean.orders
GROUP BY customer_id
ORDER BY total_orders DESC
LIMIT 10;

-- Q16. Repeat customers: what % of customers ordered more than once?
WITH order_counts AS (
    SELECT customer_id, COUNT(*) AS orders
    FROM clean.orders
    WHERE order_status = 'Delivered'
    GROUP BY customer_id
)
SELECT
    COUNT(*) AS customers_with_orders,
    SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END) AS repeat_customers,
    ROUND(100.0 * SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS repeat_rate_pct
FROM order_counts;

-- Q17. 3-month moving average of revenue (smooths out spikes)
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', order_date)::DATE AS month,
        SUM(sales_amount) AS revenue
    FROM clean.orders
    WHERE order_status = 'Delivered'
    GROUP BY 1
)
SELECT
    month,
    revenue,
    ROUND(AVG(revenue) OVER (
        ORDER BY month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2) AS moving_avg_3m
FROM monthly
ORDER BY month;

-- Q18. Each customer's latest order (ROW_NUMBER - classic interview question)
WITH numbered AS (
    SELECT
        o.*,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date DESC, order_id DESC) AS rn
    FROM clean.orders o
)
SELECT customer_id, order_id, order_date, sales_amount, order_status
FROM numbered
WHERE rn = 1
ORDER BY customer_id
LIMIT 20;


-- =====================================================================
-- BONUS: a reusable VIEW for dashboards (Power BI / Tableau / Excel)
-- =====================================================================
CREATE OR REPLACE VIEW clean.vw_sales_summary AS
SELECT
    o.order_id,
    o.order_date,
    DATE_TRUNC('month', o.order_date)::DATE AS order_month,
    c.customer_name,
    c.city,
    c.region,
    p.product_name,
    p.category,
    o.quantity,
    o.discount_pct,
    o.sales_amount,
    o.payment_method,
    o.order_status
FROM clean.orders o
JOIN clean.customers c ON c.customer_id = o.customer_id
JOIN clean.products  p ON p.product_id  = o.product_id;

SELECT * FROM clean.vw_sales_summary LIMIT 5;
