-- Generate continuous load against the workshop database
-- Pastable in pgAdmin query tool

-- 1. Bulk insert new customers
INSERT INTO customers (name, email, country)
SELECT
    'Customer ' || i,
    'customer' || i || '@loadtest.no',
    CASE (i % 5)
        WHEN 0 THEN 'Norway'
        WHEN 1 THEN 'Sweden'
        WHEN 2 THEN 'Denmark'
        WHEN 3 THEN 'Finland'
        WHEN 4 THEN 'Iceland'
    END
FROM generate_series(1000, 1999) AS s(i)
ON CONFLICT (email) DO NOTHING;

-- 2. Bulk insert new products
INSERT INTO products (product_name, category, price, stock_quantity)
SELECT
    'Product ' || i,
    CASE (i % 4)
        WHEN 0 THEN 'Electronics'
        WHEN 1 THEN 'Furniture'
        WHEN 2 THEN 'Clothing'
        WHEN 3 THEN 'Books'
    END,
    (RANDOM() * 5000 + 50)::DECIMAL(10,2),
    (RANDOM() * 500)::INTEGER
FROM generate_series(1000, 1499) AS s(i);

-- 3. Generate a large batch of orders
INSERT INTO orders (customer_id, total_amount, status)
SELECT
    (SELECT customer_id FROM customers ORDER BY RANDOM() LIMIT 1),
    (RANDOM() * 20000 + 100)::DECIMAL(10,2),
    (ARRAY['pending', 'completed', 'shipped', 'cancelled'])[floor(RANDOM() * 4 + 1)::int]
FROM generate_series(1, 5000);

-- 4. Generate order items for recent orders
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT
    o.order_id,
    (SELECT product_id FROM products ORDER BY RANDOM() LIMIT 1),
    (RANDOM() * 10 + 1)::INTEGER,
    (RANDOM() * 5000 + 50)::DECIMAL(10,2)
FROM orders o
    CROSS JOIN generate_series(1, 3) AS items
WHERE o.order_id NOT IN (SELECT DISTINCT order_id FROM order_items);

-- 5. Heavy read queries to simulate reporting load
SELECT c.country, COUNT(o.order_id) AS total_orders, SUM(o.total_amount) AS revenue
FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
GROUP BY c.country
ORDER BY revenue DESC;

SELECT p.category,
    COUNT(oi.order_item_id) AS items_sold,
    SUM(oi.quantity * oi.unit_price) AS total_sales,
    AVG(oi.unit_price) AS avg_price
FROM products p
    JOIN order_items oi ON p.product_id = oi.product_id
GROUP BY p.category
ORDER BY total_sales DESC;

-- 6. Update operations to generate write load
UPDATE orders
SET status = 'completed'
WHERE status = 'pending'
    AND order_date < NOW() - INTERVAL '1 minute'
    AND order_id IN (SELECT order_id FROM orders WHERE status = 'pending' LIMIT 500);

UPDATE products
SET stock_quantity = stock_quantity - 1
WHERE product_id IN (
    SELECT product_id FROM products WHERE stock_quantity > 0 ORDER BY RANDOM() LIMIT 200
);

-- 7. Aggregation query to stress the planner
SELECT
    date_trunc('hour', o.order_date) AS order_hour,
    c.country,
    COUNT(*) AS order_count,
    SUM(o.total_amount) AS hourly_revenue,
    AVG(o.total_amount) AS avg_order_value
FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
GROUP BY order_hour, c.country
ORDER BY order_hour DESC, hourly_revenue DESC
LIMIT 100;

-- Summary
SELECT 'Customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT 'Products', COUNT(*) FROM products
UNION ALL
SELECT 'Orders', COUNT(*) FROM orders
UNION ALL
SELECT 'Order Items', COUNT(*) FROM order_items;
