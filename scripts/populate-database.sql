-- Add sample data to the database tables created in the previous step.

-- Insert sample customers
INSERT INTO customers (name, email, country) VALUES
    ('Ole Hansen', 'ole.hansen@example.no', 'Norway'),
    ('Kari Nordmann', 'kari.nordmann@example.no', 'Norway'),
    ('Erik Svendsen', 'erik.svendsen@example.no', 'Norway'),
    ('Ingrid Berg', 'ingrid.berg@example.no', 'Norway'),
    ('Lars Johansen', 'lars.johansen@example.no', 'Norway')
ON CONFLICT (email) DO NOTHING;

-- Insert sample products
INSERT INTO products (product_name, category, price, stock_quantity) VALUES
    ('Laptop', 'Electronics', 12999.00, 50),
    ('Mouse', 'Electronics', 299.00, 200),
    ('Keyboard', 'Electronics', 899.00, 150),
    ('Monitor', 'Electronics', 3499.00, 75),
    ('Headphones', 'Electronics', 1299.00, 100),
    ('Desk Chair', 'Furniture', 2499.00, 30),
    ('Standing Desk', 'Furniture', 4999.00, 20)
ON CONFLICT DO NOTHING;

-- Create some sample orders
WITH customer_ids AS (
    SELECT customer_id FROM customers LIMIT 3
),
product_ids AS (
    SELECT product_id FROM products LIMIT 5
)
INSERT INTO orders (customer_id, total_amount, status)
SELECT
    (SELECT customer_id FROM customer_ids ORDER BY RANDOM() LIMIT 1),
    (RANDOM() * 10000 + 1000)::DECIMAL(10,2),
    CASE WHEN RANDOM() > 0.5 THEN 'completed' ELSE 'pending' END
FROM generate_series(1, 10);

-- Show results
SELECT 'Customers' as table_name, COUNT(*) as row_count FROM customers
UNION ALL
SELECT 'Products', COUNT(*) FROM products
UNION ALL
SELECT 'Orders', COUNT(*) FROM orders;
