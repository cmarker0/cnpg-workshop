-- Generate continuous WAL-heavy write load for demonstrating WAL archiving and PITR
-- Pastable in pgAdmin query tool
-- Run this script multiple times or in stages to build up WAL segments over time

-- ============================================================================
-- PHASE 1: Checkpoint marker — record the start time for PITR reference
-- ============================================================================
CREATE TABLE IF NOT EXISTS wal_demo_log (
    id SERIAL PRIMARY KEY,
    phase TEXT NOT NULL,
    marker TEXT,
    recorded_at TIMESTAMP DEFAULT now()
);

INSERT INTO wal_demo_log (phase, marker)
VALUES ('phase_1', 'WAL load generation started');

SELECT '--- PHASE 1: Start marker recorded ---' AS status, now() AS pitr_safe_before;

-- ============================================================================
-- PHASE 2: High-frequency single-row inserts (each generates its own WAL record)
-- ============================================================================
DO $$
BEGIN
    FOR i IN 1..500 LOOP
        INSERT INTO customers (name, email, country)
        VALUES (
            'WAL-User-' || i,
            'wal-user-' || i || '@demo.no',
            (ARRAY['Norway','Sweden','Denmark','Finland','Iceland'])[1 + (i % 5)]
        )
        ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name;
    END LOOP;
END $$;

INSERT INTO wal_demo_log (phase, marker)
VALUES ('phase_2', '500 single-row customer inserts completed');

SELECT '--- PHASE 2: Single-row inserts done ---' AS status, now() AS pitr_safe_before;

-- ============================================================================
-- PHASE 3: Bulk inserts to generate larger WAL segments
-- ============================================================================
INSERT INTO products (product_name, category, price, stock_quantity)
SELECT
    'WAL-Product-' || i,
    (ARRAY['Electronics','Furniture','Clothing','Books'])[1 + (i % 4)],
    (random() * 9000 + 100)::DECIMAL(10,2),
    (random() * 1000)::INTEGER
FROM generate_series(2000, 3999) AS s(i)
ON CONFLICT DO NOTHING;

INSERT INTO orders (customer_id, total_amount, status)
SELECT
    (SELECT customer_id FROM customers ORDER BY random() LIMIT 1),
    (random() * 50000 + 500)::DECIMAL(10,2),
    (ARRAY['pending','completed','shipped','cancelled'])[1 + floor(random() * 4)::int]
FROM generate_series(1, 10000);

INSERT INTO wal_demo_log (phase, marker)
VALUES ('phase_3', 'Bulk inserts: 2000 products + 10000 orders');

SELECT '--- PHASE 3: Bulk inserts done ---' AS status, now() AS pitr_safe_before;

-- ============================================================================
-- PHASE 4: Heavy UPDATE pass (updates generate more WAL than inserts due to MVCC)
-- ============================================================================
UPDATE orders
SET total_amount = total_amount * 1.1,
    status = CASE
        WHEN random() < 0.3 THEN 'completed'
        WHEN random() < 0.5 THEN 'shipped'
        ELSE status
    END
WHERE order_id IN (
    SELECT order_id FROM orders ORDER BY random() LIMIT 5000
);

UPDATE products
SET price = price * (0.9 + random() * 0.2),
    stock_quantity = (random() * 500)::INTEGER
WHERE product_id IN (
    SELECT product_id FROM products ORDER BY random() LIMIT 1000
);

INSERT INTO wal_demo_log (phase, marker)
VALUES ('phase_4', 'Heavy updates: 5000 orders + 1000 products');

SELECT '--- PHASE 4: Heavy updates done ---' AS status, now() AS pitr_safe_before;

-- ============================================================================
-- PHASE 5: DELETE + re-INSERT churn (DELETEs are WAL-expensive)
-- ============================================================================
DELETE FROM order_items
WHERE order_item_id IN (
    SELECT order_item_id FROM order_items ORDER BY random() LIMIT 2000
);

INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT
    (SELECT order_id FROM orders ORDER BY random() LIMIT 1),
    (SELECT product_id FROM products ORDER BY random() LIMIT 1),
    (random() * 20 + 1)::INTEGER,
    (random() * 5000 + 50)::DECIMAL(10,2)
FROM generate_series(1, 3000);

INSERT INTO wal_demo_log (phase, marker)
VALUES ('phase_5', 'Churn: deleted 2000 + inserted 3000 order_items');

SELECT '--- PHASE 5: Delete/insert churn done ---' AS status, now() AS pitr_safe_before;

-- ============================================================================
-- PHASE 6: Large-object and TOAST-generating writes (long text forces WAL TOAST entries)
-- ============================================================================
CREATE TABLE IF NOT EXISTS wal_demo_blobs (
    id SERIAL PRIMARY KEY,
    payload TEXT,
    created_at TIMESTAMP DEFAULT now()
);

INSERT INTO wal_demo_blobs (payload)
SELECT repeat('WAL-demo-payload-' || i || '-', 500)
FROM generate_series(1, 200) AS s(i);

INSERT INTO wal_demo_log (phase, marker)
VALUES ('phase_6', '200 large TOAST rows inserted');

SELECT '--- PHASE 6: TOAST writes done ---' AS status, now() AS pitr_safe_before;

-- ============================================================================
-- PHASE 7: Rapid DDL changes (each DDL statement generates WAL)
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_wal_orders_status ON orders (status);
CREATE INDEX IF NOT EXISTS idx_wal_orders_date ON orders (order_date DESC);
CREATE INDEX IF NOT EXISTS idx_wal_products_cat ON products (category);
CREATE INDEX IF NOT EXISTS idx_wal_customers_country ON customers (country);

-- Analyze to update statistics (also generates WAL)
ANALYZE customers;
ANALYZE products;
ANALYZE orders;
ANALYZE order_items;

INSERT INTO wal_demo_log (phase, marker)
VALUES ('phase_7', 'DDL: 4 indexes created + ANALYZE');

SELECT '--- PHASE 7: DDL operations done ---' AS status, now() AS pitr_safe_before;

-- ============================================================================
-- SUMMARY: Show all phase timestamps for PITR targeting
-- ============================================================================
SELECT '=== WAL DEMO LOG ===' AS info;
SELECT phase, marker, recorded_at FROM wal_demo_log ORDER BY id;

SELECT '=== TABLE SIZES ===' AS info;
SELECT 'Customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'Products', COUNT(*) FROM products
UNION ALL SELECT 'Orders', COUNT(*) FROM orders
UNION ALL SELECT 'Order Items', COUNT(*) FROM order_items
UNION ALL SELECT 'WAL Demo Blobs', COUNT(*) FROM wal_demo_blobs;
