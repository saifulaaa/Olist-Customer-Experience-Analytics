use olist_ecommerce;


SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_KEY
FROM INFORMATION_SCHEMA.COLUMNS 
WHERE TABLE_SCHEMA = 'olist_ecommerce';

-- Fix the column types;
ALTER TABLE orders
	MODIFY order_id VARCHAR(50),
    MODIFY customer_id VARCHAR(50),
    MODIFY order_status VARCHAR(20);

ALTER TABLE customers
	MODIFY customer_id VARCHAR(50),
    MODIFY customer_unique_id VARCHAR(50),
	MODIFY customer_city VARCHAR(100),
	MODIFY customer_state CHAR(2);

ALTER TABLE sellers
	MODIFY seller_id VARCHAR(50),
	MODIFY seller_city VARCHAR(100),
	MODIFY seller_state CHAR(2);

ALTER TABLE order_items
  MODIFY order_id VARCHAR(50),
  MODIFY product_id VARCHAR(50),
  MODIFY seller_id VARCHAR(50);
  
ALTER TABLE payments
  MODIFY order_id VARCHAR(50),
  MODIFY payment_type VARCHAR(30);

ALTER TABLE reviews
  MODIFY review_id VARCHAR(50),
  MODIFY order_id VARCHAR(50);
  
ALTER TABLE products
  MODIFY product_id VARCHAR(50),
  MODIFY product_category VARCHAR(100);
-- select * from product_category_name_translation;
-- ALTER TABLE product_category_name_translation                               this to is used to rename the column name
-- 	RENAME COLUMN ï»¿product_category_name TO product_category_name;

ALTER TABLE product_category_name_translation
  MODIFY product_category_name VARCHAR(100),
  MODIFY product_category_name_english VARCHAR(100);
  
ALTER TABLE geolocation
  MODIFY geolocation_city VARCHAR(100),
  MODIFY geolocation_state CHAR(2);
  
-- Check the number of rows in each table
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT 'geolocation', COUNT(*) FROM geolocation
UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL
SELECT 'orders', COUNT(*) FROM orders
UNION ALL
SELECT 'payments', COUNT(*) FROM payments
UNION ALL
SELECT 'product_category_name_translation', count(*) FROM product_category_name_translation
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'reviews', COUNT(*) FROM reviews
UNION ALL
SELECT 'sellers', COUNT(*) FROM sellers;

-- add indexes so the joins run fast:

CREATE INDEX idx_orders_oid ON orders(order_id);
CREATE INDEX idx_orders_cid ON orders(customer_id);
CREATE INDEX idx_customers_cid ON customers(customer_id);
CREATE INDEX idx_items_oid ON order_items(order_id);
CREATE INDEX idx_items_sid ON order_items(seller_id);
CREATE INDEX idx_items_pid ON order_items(product_id);
CREATE INDEX idx_pay_oid ON payments(order_id);
CREATE INDEX idx_rev_oid ON reviews(order_id);
CREATE INDEX idx_sellers_sid ON sellers(seller_id);
CREATE INDEX idx_products_pid ON products(product_id);
CREATE INDEX idx_geo_zip ON geolocation(geolocation_zip_code_prefix);

-- Explore the data quality

-- 5a. Order status mix: which orders actually have a delivery date?

SELECT order_status, COUNT(*) AS no_of_orders,
	   ROUND(100 * count(*) / SUM(COUNT(*)) OVER(), 2) AS pct
FROM orders
GROUP BY order_status
ORDER BY no_of_orders DESC;

-- 5b. Missing values in the orders table

SELECT 
	sum(order_approved_at IS NULL) AS missing_approved,
    SUM(order_delivered_carrier_date IS NULL) AS missing_carrier,
    SUM(order_delivered_customer_date IS NULL) AS missing_delivered
FROM orders;

-- 5c. Orders with more than one review (join-multiplication risk)

SELECT COUNT(*) AS orders_with_multiple_reviews
FROM (SELECT order_id FROM reviews GROUP BY order_id HAVING count(*) > 1) a;

-- 5d. Duplicate review_ids

SELECT COUNT(*) - COUNT(DISTINCT review_id) as duplicate_review_ids
FROM reviews;

-- 5e. Orders with more than one seller

SELECT count(*) as multi_seller_orders
FROM (SELECT order_id FROM order_items GROUP BY order_id HAVING count(DISTINCT seller_id) > 1) a;

-- 5f. Orders in the orders table with no review
SELECT count(*) AS orders_without_review
FROM orders o LEFT JOIN reviews r ON o.order_id = r.order_id
WHERE r.order_id IS NULL;

-- 5g. Products with no category

SELECT sum(product_category IS NULL) as no_category
FROM products;

-- 5h. Geolocation: rows vs unique zip prefixes

SELECT count(*) as total_rows,
	   count(DISTINCT geolocation_zip_code_prefix) as unique_zip_prefix
        FROM geolocation;

-- 5i. Time coverage

SELECT MIN(order_purchase_timestamp), MAX(order_purchase_timestamp) FROM orders;

CREATE OR REPLACE VIEW order_master AS 
-- One row per order; multi-item orders get summed
WITH items AS(
SELECT order_id,
	   COUNT(*)                     AS n_items,
       COUNT(DISTINCT seller_id)    AS n_sellers,
       COUNT(DISTINCT product_id)   AS n_products,
       SUM(price)                   AS items_price,
       SUM(freight_value)           AS freight_total,
       MIN(seller_id)               AS seller_id,
       MIN(product_id)              AS product_id,
       MIN(shipping_limit_date)     AS shipping_limit_date
FROM order_items
GROUP BY order_id
),

pay AS (
	    -- Keep only the most recent review per order
	SELECT order_id,
		   SUM(payment_value)            AS total_paid,
           MAX(payment_installments)     AS max_installments,
           COUNT(DISTINCT payment_type)  AS n_payment_type
	FROM payments
    GROUP BY order_id
),
rev AS (

	SELECT order_id, review_score, review_comment_title,
		   review_comment_message, review_creation_date
	FROM (
		SELECT r.*, 
				ROW_NUMBER() OVER(PARTITION BY order_id ORDER BY review_answer_timestamp DESC) AS rn
		FROM reviews r
        ) t
	WHERE rn = 1 
)
SELECT
    o.order_id,
    c.customer_unique_id,
    c.customer_state,
    c.customer_city,
    c.customer_zip_code_prefix,
    s.seller_id,
    s.seller_state,
    s.seller_zip_code_prefix,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    -- delivery metrics (calendar days)
	DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) AS delivery_days,
    DATEDIFF(o.order_estimated_delivery_date, o.order_purchase_timestamp) AS estimated_days,
    DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) AS days_late,
    CASE WHEN DATEDIFF(o.order_delivered_customer_date,
                       o.order_estimated_delivery_date) > 0 THEN 1 ELSE 0 END AS is_late,
	DATEDIFF(o.order_delivered_carrier_date, o.order_approved_at)         AS seller_handoff_days,
    CASE WHEN c.customer_state = s.seller_state THEN 1 ELSE 0 END         AS same_state,
     i.n_items, i.n_sellers, i.n_products,
     i.items_price, i.freight_total,
     ROUND(i.freight_total / NULLIF(i.items_price, 0), 3)                   AS freight_ratio,
     p.product_category, 
	 t.product_category_name_english                                        AS category,
     p.product_weight_g, p.product_photos_qty,
     pay.total_paid, pay.max_installments,
     rev.review_score,
     rev.review_comment_message,
     rev.review_creation_date,
	 CASE WHEN rev.review_score <= 2 THEN 1 ELSE 0 END                      AS low_review
FROM orders o
JOIN customers c                 ON c.customer_id = o.customer_id 
LEFT JOIN items i                ON i.order_id = o.order_id
LEFT JOIN sellers s               ON s.seller_id = i.seller_id
LEFT JOIN products p             ON p.product_id = i.product_id
LEFT JOIN product_category_name_translation t ON t.product_category_name = p.product_category
LEFT JOIN pay                    ON pay.order_id = o.order_id
LEFT JOIN rev                    ON rev.order_id = o.order_id;

SELECT COUNT(*) AS rows_in_view, COUNT(DISTINCT order_id) AS distinct_orders FROM order_master;

-- Q1. Late rate and average review score: on-time vs late (delivered orders only)

SELECT is_late,
	   COUNT(*) AS orders,
       ROUND(AVG(review_score),2) AS avg_score,
       ROUND(100 * AVG(low_review),2) AS pct_low_review
FROM order_master
	WHERE order_status = 'delivered'
     AND order_delivered_customer_date IS NOT NULL
  AND review_score IS NOT NULL
GROUP BY is_late;

-- Q2. Review score by how late the order was (dose-response)

SELECT CASE WHEN days_late <= 0 THEN '1. On Time or Early'
			WHEN days_late <= 3 THEN '2. 1-3 Days Late'
            WHEN days_late <= 7 THEN '3. 4-7 Days Late'
            ELSE                     '4. 8+ Days Late' END AS delay_buket,
	    COUNT(*) AS orders,
        ROUND(AVG(review_score)) AS avg_review_score,
        ROUND(100*AVG(low_review), 1) AS pct_low_review
FROM order_master
WHERE order_status = 'delivered' AND review_score IS NULL 
	  AND order_delivered_customer_date IS NULL 
GROUP BY delay_buket
ORDER BY delay_buket;

-- Q3. Customer states ranked by late rate (min 500 orders to avoid noise)
SELECT customer_state,
       COUNT(*) AS orders,
       ROUND(100*AVG(is_late), 1) AS late_pct,
       ROUND(AVG(review_score), 2) AS avg_score,
       RANK() OVER (ORDER BY AVG(is_late) DESC) AS late_rank
FROM order_master
WHERE order_status = 'delivered' AND review_score IS NOT NULL
GROUP BY customer_state
HAVING COUNT(*) >= 500;

Q4. Monthly trend with 3-month rolling average of review score
WITH monthly AS (
  SELECT DATE_FORMAT(order_purchase_timestamp, '%Y-%m-01') AS month,
         COUNT(*) AS orders,
         AVG(review_score) AS avg_score,
         AVG(is_late) AS late_rate
  FROM order_master
  WHERE order_status = 'delivered' AND review_score IS NOT NULL
    AND order_purchase_timestamp >= '2017-01-01'
  GROUP BY month
)
SELECT month, orders,
       ROUND(avg_score, 2) AS avg_score,
       ROUND(AVG(avg_score) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS rolling_3m,
       ROUND(100*late_rate, 1) AS late_pct,
       ROUND(avg_score - LAG(avg_score) OVER (ORDER BY month), 3) AS change_vs_prev_month
FROM monthly;

-- Q5. Ten worst categories by low-review rate (min 300 orders)
SELECT category, COUNT(*) AS orders,
       ROUND(100*AVG(low_review), 1) AS pct_low_review,
       ROUND(100*AVG(is_late), 1) AS late_pct
FROM order_master
WHERE order_status = 'delivered' AND review_score IS NOT NULL
GROUP BY category
HAVING COUNT(*) >= 300
ORDER BY pct_low_review DESC
LIMIT 10;

-- Q6. Worst sellers: low-review rate, and how much of it is lateness
SELECT seller_id, seller_state, COUNT(*) AS orders,
       ROUND(AVG(review_score), 2) AS avg_score,
       ROUND(100*AVG(is_late), 1) AS late_pct,
       ROUND(AVG(seller_handoff_days), 1) AS avg_handoff_days
FROM order_master
WHERE order_status = 'delivered' AND review_score IS NOT NULL
GROUP BY seller_id, seller_state
HAVING COUNT(*) >= 50
ORDER BY avg_score ASC
LIMIT 10;

-- Q7. Same-state vs cross-state: does distance hurt?
SELECT same_state, COUNT(*) AS orders,
       ROUND(AVG(delivery_days), 1) AS avg_delivery_days,
       ROUND(100*AVG(is_late), 1) AS late_pct,
       ROUND(AVG(review_score), 2) AS avg_score
FROM order_master
WHERE order_status = 'delivered' AND review_score IS NOT NULL
GROUP BY same_state;

-- Q8. Is the seller's share of late deliveries concentrated? (Pareto check)
WITH seller_late AS (
  SELECT seller_id, SUM(is_late) AS late_orders
  FROM order_master WHERE order_status = 'delivered'
  GROUP BY seller_id
),
ranked AS (
  SELECT seller_id, late_orders,
         SUM(late_orders) OVER (ORDER BY late_orders DESC) AS cum_late,
         SUM(late_orders) OVER () AS total_late,
         ROW_NUMBER() OVER (ORDER BY late_orders DESC) AS rnk,
         COUNT(*) OVER () AS n_sellers
  FROM seller_late
)
SELECT rnk, ROUND(100*rnk/n_sellers, 1) AS pct_of_sellers,
       ROUND(100*cum_late/total_late, 1) AS pct_of_late_orders
FROM ranked
WHERE rnk IN (10, 30, 100, 300);
