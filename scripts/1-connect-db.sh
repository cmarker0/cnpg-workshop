#!/bin/bash

CLUSTER_NAME=${1:-pg-cluster}
NAMESPACE=${2:-default}

# Hent database credentials
export PGPASSWORD=$(kubectl get secret ${CLUSTER_NAME}-app -n ${NAMESPACE} -o jsonpath='{.data.password}' | base64 -d)
export PGUSER=$(kubectl get secret ${CLUSTER_NAME}-app -n ${NAMESPACE} -o jsonpath='{.data.username}' | base64 -d)
export PGDATABASE=$(kubectl get secret ${CLUSTER_NAME}-app -n ${NAMESPACE} -o jsonpath='{.data.dbname}' | base64 -d)

# Finn primary pod
PRIMARY_POD=$(kubectl get pod -n ${NAMESPACE} -l cnpg.io/cluster=${CLUSTER_NAME},role=primary -o jsonpath='{.items[0].metadata.name}')

echo "Connecting to primary pod: ${PRIMARY_POD}"
echo "Database: ${PGDATABASE}, User: ${PGUSER}"
echo ""

kubectl exec -it ${PRIMARY_POD} -n ${NAMESPACE} -- psql