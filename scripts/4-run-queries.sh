#!/bin/bash

CLUSTER_NAME=${1:-pg-cluster}
NAMESPACE=${2:-default}

export PGPASSWORD=$(kubectl get secret ${CLUSTER_NAME}-app -n ${NAMESPACE} -o jsonpath='{.data.password}' | base64 -d)
PRIMARY_POD=$(kubectl get pod -n ${NAMESPACE} -l cnpg.io/cluster=${CLUSTER_NAME},role=primary -o jsonpath='{.items[0].metadata.name}')

echo "Running sample queries..."

kubectl exec -i ${PRIMARY_POD} -n ${NAMESPACE} -- psql << 'EOF'
\echo '=== Top 5 customers by order count ==='
SELECT 
    c.name,
    c.email,
    COUNT(o.order_id) as order_count,
    SUM(o.total_amount) as total_spent
FROM workshop.customers c
LEFT JOIN workshop.orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.name, c.email
ORDER BY order_count DESC
LIMIT 5;

\echo ''
\echo '=== Product inventory status ==='
SELECT 
    product_name,
    category,
    price,
    stock_quantity,
    CASE 
        WHEN stock_quantity < 25 THEN 'Low Stock'
        WHEN stock_quantity < 100 THEN 'Medium Stock'
        ELSE 'Well Stocked'
    END as stock_status
FROM workshop.products
ORDER BY stock_quantity;

\echo ''
\echo '=== Recent orders summary ==='
SELECT 
    DATE(order_date) as order_day,
    COUNT(*) as order_count,
    SUM(total_amount) as daily_revenue,
    AVG(total_amount) as avg_order_value
FROM workshop.orders
WHERE order_date >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY DATE(order_date)
ORDER BY order_day DESC;

\echo ''
\echo '=== Replication lag (if replicas exist) ==='
SELECT 
    application_name,
    client_addr,
    state,
    sync_state,
    pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) as send_lag_bytes,
    pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) as replay_lag_bytes
FROM pg_stat_replication;
EOF