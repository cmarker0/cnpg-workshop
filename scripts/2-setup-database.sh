#!/bin/bash

CLUSTER_NAME=${1:-pg-cluster}
NAMESPACE=${2:-default}

# Hent credentials
export PGPASSWORD=$(kubectl get secret ${CLUSTER_NAME}-app -n ${NAMESPACE} -o jsonpath='{.data.password}' | base64 -d)
PRIMARY_POD=$(kubectl get pod -n ${NAMESPACE} -l cnpg.io/cluster=${CLUSTER_NAME},role=primary -o jsonpath='{.items[0].metadata.name}')

echo "🚀 Setting up workshop database on ${PRIMARY_POD}..."

kubectl exec -i ${PRIMARY_POD} -n ${NAMESPACE} -- psql << 'EOF'
-- Create workshop schema
CREATE SCHEMA IF NOT EXISTS workshop;

-- Customers table
CREATE TABLE IF NOT EXISTS workshop.customers (
    customer_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    country VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Products table
CREATE TABLE IF NOT EXISTS workshop.products (
    product_id SERIAL PRIMARY KEY,
    product_name VARCHAR(100) NOT NULL,
    category VARCHAR(50),
    price DECIMAL(10, 2) NOT NULL,
    stock_quantity INTEGER DEFAULT 0
);

-- Orders table
CREATE TABLE IF NOT EXISTS workshop.orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES workshop.customers(customer_id),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10, 2),
    status VARCHAR(20) DEFAULT 'pending'
);

-- Order items table
CREATE TABLE IF NOT EXISTS workshop.order_items (
    order_item_id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES workshop.orders(order_id),
    product_id INTEGER REFERENCES workshop.products(product_id),
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10, 2) NOT NULL
);

-- Insert sample customers
INSERT INTO workshop.customers (name, email, country) VALUES
    ('Ole Hansen', 'ole.hansen@example.no', 'Norway'),
    ('Kari Nordmann', 'kari.nordmann@example.no', 'Norway'),
    ('Erik Svendsen', 'erik.svendsen@example.no', 'Norway'),
    ('Ingrid Berg', 'ingrid.berg@example.no', 'Norway'),
    ('Lars Johansen', 'lars.johansen@example.no', 'Norway')
ON CONFLICT (email) DO NOTHING;

-- Insert sample products
INSERT INTO workshop.products (product_name, category, price, stock_quantity) VALUES
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
    SELECT customer_id FROM workshop.customers LIMIT 3
),
product_ids AS (
    SELECT product_id FROM workshop.products LIMIT 5
)
INSERT INTO workshop.orders (customer_id, total_amount, status)
SELECT 
    (SELECT customer_id FROM customer_ids ORDER BY RANDOM() LIMIT 1),
    (RANDOM() * 10000 + 1000)::DECIMAL(10,2),
    CASE WHEN RANDOM() > 0.5 THEN 'completed' ELSE 'pending' END
FROM generate_series(1, 10);

\echo 'Database setup complete!'
\echo ''
\echo 'Available tables:'
\dt workshop.*

\echo ''
\echo 'Sample data counts:'
SELECT 'Customers' as table_name, COUNT(*) as row_count FROM workshop.customers
UNION ALL
SELECT 'Products', COUNT(*) FROM workshop.products
UNION ALL
SELECT 'Orders', COUNT(*) FROM workshop.orders;
EOF

echo ""
echo "✅ Database setup completed successfully!"