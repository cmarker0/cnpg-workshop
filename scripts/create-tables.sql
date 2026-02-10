-- Setup workshop database and tables for the CNPG workshop.
-- Customers table
CREATE TABLE
	IF NOT EXISTS customers (
		customer_id SERIAL PRIMARY KEY,
		name VARCHAR(100) NOT NULL,
		email VARCHAR(100) UNIQUE NOT NULL,
		country VARCHAR(50),
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);

-- Products table
CREATE TABLE
	IF NOT EXISTS products (
		product_id SERIAL PRIMARY KEY,
		product_name VARCHAR(100) NOT NULL,
		category VARCHAR(50),
		price DECIMAL(10, 2) NOT NULL,
		stock_quantity INTEGER DEFAULT 0
	);

-- Orders table
CREATE TABLE
	IF NOT EXISTS orders (
		order_id SERIAL PRIMARY KEY,
		customer_id INTEGER REFERENCES customers (customer_id),
		order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		total_amount DECIMAL(10, 2),
		status VARCHAR(20) DEFAULT 'pending'
	);

-- Order items table
CREATE TABLE
	IF NOT EXISTS order_items (
		order_item_id SERIAL PRIMARY KEY,
		order_id INTEGER REFERENCES orders (order_id),
		product_id INTEGER REFERENCES products (product_id),
		quantity INTEGER NOT NULL,
		unit_price DECIMAL(10, 2) NOT NULL
	);