#!/bin/bash

CLUSTER_NAME=${1:-pg-cluster}
NAMESPACE=${2:-default}

export PGPASSWORD=$(kubectl get secret ${CLUSTER_NAME}-app -n ${NAMESPACE} -o jsonpath='{.data.password}' | base64 -d)
PRIMARY_POD=$(kubectl get pod -n ${NAMESPACE} -l cnpg.io/cluster=${CLUSTER_NAME},role=primary -o jsonpath='{.items[0].metadata.name}')

echo "Cleaning up workshop database..."

kubectl exec -i ${PRIMARY_POD} -n ${NAMESPACE} -- psql << 'EOF'
DROP SCHEMA IF EXISTS workshop CASCADE;
\echo 'Workshop schema and all tables dropped!'
EOF

echo "✅ Cleanup completed!"