-- =====================================================================
-- 04_data_quality_checks.sql
-- Tests that the clean data is trustworthy.
-- Every check should return  result = 'PASS'.
-- =====================================================================

SELECT 'No duplicate order IDs' AS check_name,
       CASE WHEN COUNT(*) = COUNT(DISTINCT order_id) THEN 'PASS' ELSE 'FAIL' END AS result
FROM clean.orders

UNION ALL
SELECT 'No duplicate customer IDs',
       CASE WHEN COUNT(*) = COUNT(DISTINCT customer_id) THEN 'PASS' ELSE 'FAIL' END
FROM clean.customers

UNION ALL
SELECT 'All quantities are positive',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM clean.orders WHERE quantity <= 0

UNION ALL
SELECT 'No orders without a valid customer',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM clean.orders o
LEFT JOIN clean.customers c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL

UNION ALL
SELECT 'No names with extra spaces',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM clean.customers WHERE customer_name <> TRIM(customer_name)

UNION ALL
SELECT 'Sales amount is never negative',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM clean.orders WHERE sales_amount < 0

UNION ALL
SELECT 'No missing payment methods',
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM clean.orders WHERE payment_method IS NULL OR payment_method = '';
