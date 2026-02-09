-- Setup workshop database schema and sample data

-- Customers table
CREATE TABLE IF NOT EXISTS customers (
    customer_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    country VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Products table
CREATE TABLE IF NOT EXISTS products (
    product_id SERIAL PRIMARY KEY,
    product_name VARCHAR(100) NOT NULL,
    category VARCHAR(50),
    price DECIMAL(10, 2) NOT NULL,
    stock_quantity INTEGER DEFAULT 0
);

-- Orders table
CREATE TABLE IF NOT EXISTS orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES customers(customer_id),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10, 2),
    status VARCHAR(20) DEFAULT 'pending'
);

-- Order items table
CREATE TABLE IF NOT EXISTS order_items (
    order_item_id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES orders(order_id),
    product_id INTEGER REFERENCES products(product_id),
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10, 2) NOT NULL
);

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
