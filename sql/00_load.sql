-- 00_load.sql : load all 9 Olist CSVs into DuckDB as typed tables.
-- Run from the project root:  duckdb data/olist.duckdb < sql/00_load.sql
CREATE OR REPLACE TABLE customers   AS SELECT * FROM read_csv_auto('data/raw/olist_customers_dataset.csv', header=true);
CREATE OR REPLACE TABLE geolocation AS SELECT * FROM read_csv_auto('data/raw/olist_geolocation_dataset.csv', header=true);
CREATE OR REPLACE TABLE order_items AS SELECT * FROM read_csv_auto('data/raw/olist_order_items_dataset.csv', header=true);
CREATE OR REPLACE TABLE payments    AS SELECT * FROM read_csv_auto('data/raw/olist_order_payments_dataset.csv', header=true);
CREATE OR REPLACE TABLE reviews     AS SELECT * FROM read_csv_auto('data/raw/olist_order_reviews_dataset.csv', header=true);
CREATE OR REPLACE TABLE orders      AS SELECT * FROM read_csv_auto('data/raw/olist_orders_dataset.csv', header=true);
CREATE OR REPLACE TABLE products    AS SELECT * FROM read_csv_auto('data/raw/olist_products_dataset.csv', header=true);
CREATE OR REPLACE TABLE sellers     AS SELECT * FROM read_csv_auto('data/raw/olist_sellers_dataset.csv', header=true);
CREATE OR REPLACE TABLE category_translation AS SELECT * FROM read_csv_auto('data/raw/product_category_name_translation.csv', header=true);

-- Row-count check (should match Kaggle: 99,441 orders, 112,650 items, 99,224 reviews)
-- name: row_counts
SELECT 'orders' AS tbl, count(*) AS n FROM orders UNION ALL
SELECT 'order_items', count(*) FROM order_items UNION ALL
SELECT 'reviews', count(*) FROM reviews UNION ALL
SELECT 'payments', count(*) FROM payments UNION ALL
SELECT 'customers', count(*) FROM customers UNION ALL
SELECT 'sellers', count(*) FROM sellers UNION ALL
SELECT 'products', count(*) FROM products UNION ALL
SELECT 'geolocation', count(*) FROM geolocation UNION ALL
SELECT 'category_translation', count(*) FROM category_translation;
