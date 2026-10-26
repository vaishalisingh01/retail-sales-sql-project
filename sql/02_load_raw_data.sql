-- =====================================================================
-- 02_load_raw_data.sql
-- Loads the CSV files into the RAW tables.
--
-- Run this from the project root folder using psql:
--     psql -d retail_db -f sql/02_load_raw_data.sql
--
-- (\copy reads the file from YOUR computer, so it works without
--  admin rights. If you use pgAdmin instead, right-click each raw
--  table -> Import/Export Data -> choose the CSV, Header = Yes.)
-- =====================================================================

TRUNCATE raw.customers, raw.products, raw.orders;

\copy raw.customers FROM 'data/customers.csv' WITH (FORMAT csv, HEADER true)
\copy raw.products  FROM 'data/products.csv'  WITH (FORMAT csv, HEADER true)
\copy raw.orders    FROM 'data/orders.csv'    WITH (FORMAT csv, HEADER true)

-- Quick check: how many rows landed in each table?
SELECT 'raw.customers' AS table_name, COUNT(*) AS row_count FROM raw.customers
UNION ALL
SELECT 'raw.products', COUNT(*) FROM raw.products
UNION ALL
SELECT 'raw.orders',   COUNT(*) FROM raw.orders;
