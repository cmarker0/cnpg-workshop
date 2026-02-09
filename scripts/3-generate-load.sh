#!/bin/bash

CLUSTER_NAME=${1:-pg-cluster}
NAMESPACE=${2:-default}
ITERATIONS=${3:-100}

export PGPASSWORD=$(kubectl get secret ${CLUSTER_NAME}-app -n ${NAMESPACE} -o jsonpath='{.data.password}' | base64 -d)
PRIMARY_POD=$(kubectl get pod -n ${NAMESPACE} -l cnpg.io/cluster=${CLUSTER_NAME},role=primary -o jsonpath='{.items[0].metadata.name}')

echo "Generating load with ${ITERATIONS} iterations on ${PRIMARY_POD}..."

kubectl exec -i ${PRIMARY_POD} -n ${NAMESPACE} -- psql << EOF
DO \$\$
DECLARE
    i INTEGER;
    customer_id INTEGER;
    product_id INTEGER;
    order_id INTEGER;
BEGIN
    FOR i IN 1..${ITERATIONS} LOOP
        -- Insert random customer
        INSERT INTO workshop.customers (name, email, country)
        VALUES (
            'Customer ' || i || '-' || floor(random() * 1000),
            'customer' || i || '-' || floor(random() * 1000) || '@example.no',
            'Norway'
        ) RETURNING customer_id INTO customer_id;
        
        -- Create an order
        INSERT INTO workshop.orders (customer_id, total_amount, status)
        VALUES (
            customer_id,
            (random() * 5000 + 500)::DECIMAL(10,2),
            CASE WHEN random() > 0.3 THEN 'completed' ELSE 'pending' END
        ) RETURNING order_id INTO order_id;
        
        -- Add 1-3 order items
        FOR j IN 1..(1 + floor(random() * 3)) LOOP
            SELECT product_id INTO product_id 
            FROM workshop.products 
            ORDER BY RANDOM() 
            LIMIT 1;
            
            INSERT INTO workshop.order_items (order_id, product_id, quantity, unit_price)
            VALUES (
                order_id,
                product_id,
                (1 + floor(random() * 5))::INTEGER,
                (random() * 1000 + 100)::DECIMAL(10,2)
            );
        END LOOP;
        
        IF i % 10 = 0 THEN
            RAISE NOTICE 'Processed % iterations', i;
        END IF;
    END LOOP;
END \$\$;

\echo ''
\echo 'Load generation complete!'
SELECT 'Total customers' as metric, COUNT(*) as value FROM workshop.customers
UNION ALL
SELECT 'Total orders', COUNT(*) FROM workshop.orders
UNION ALL
SELECT 'Total order items', COUNT(*) FROM workshop.order_items;
EOF

echo "✅ Load generation completed!"