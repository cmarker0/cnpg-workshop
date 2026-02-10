# CNPG Workshop

CloudNativePG workshop setup with a PostgreSQL cluster, connection pooling, automated backups, and monitoring.

## Kubernetes Resource Structure

```mermaid
graph TD
    NS[Namespace<br/><b>workshop-pg-cluster</b>]

    subgraph Secrets
        SEC_ADMIN[Secret<br/><b>admin-user</b><br/><i>postgres superuser</i>]
        SEC_APP[Secret<br/><b>app-user</b><br/><i>app db user</i>]
    end

    subgraph Cluster
        CL[Cluster<br/><b>workshop-pg-cluster</b><br/><i>3 instances, PG 18.1</i>]
    end

    subgraph Backup & Restore
        SB[ScheduledBackup<br/><b>workshop-scheduled-backup</b><br/><i>3x daily</i>]
        BOS[ObjectStore<br/><b>workshop-backup-azure-object-store</b><br/><i>Azure Blob Storage</i>]
        ROS[ObjectStore<br/><b>workshop-restore-azure-object-store</b><br/><i>Azure Blob Storage</i>]
    end

    subgraph Connection Pooling
        RW[Pooler<br/><b>workshop-pg-pooler-rw</b><br/><i>3 instances, read-write</i>]
        RO[Pooler<br/><b>workshop-pg-pooler-ro</b><br/><i>3 instances, read-only</i>]
    end

    %% Namespace contains everything
    NS --> SEC_ADMIN
    NS --> SEC_APP
    NS --> CL
    NS --> SB
    NS --> BOS
    NS --> ROS
    NS --> RW
    NS --> RO

    %% Cluster references secrets
    SEC_ADMIN -- "superuserSecret" --> CL
    SEC_APP -- "bootstrap.initdb.secret" --> CL

    %% Cluster references backup object store
    CL -- "barmanObjectName" --> BOS

    %% Cluster recovery (commented out)
    ROS -. "recovery<br/>(commented out)" .-> CL

    %% ScheduledBackup targets the cluster
    SB -- "cluster.name" --> CL

    %% Poolers reference the cluster
    RW -- "spec.cluster" --> CL
    RO -- "spec.cluster" --> CL
```

## Directory Layout

```
development/
├── database/
│   ├── kustomization.yaml        # Kustomize composition
│   ├── namespace.yaml            # Namespace
│   ├── cluster.yaml              # CNPG Cluster (3 replicas, PG 18.1)
│   ├── db-admin.secret.yaml      # Superuser credentials
│   ├── db-user.secret.yaml       # App user credentials
│   ├── backup.yaml               # ScheduledBackup (08:00, 12:00, 18:00 UTC)
│   ├── backup.objectstore.yaml   # Backup target (Azure Blob)
│   ├── restore.objectstore.yaml  # Restore source (Azure Blob)
│   ├── rw.pooler.yaml            # Read-write connection pooler
│   ├── ro.pooler.yaml            # Read-only connection pooler
│   └── podmonitor.yaml           # Prometheus PodMonitor
└── pgadmin/
    └── .gitkeep
```

*The storage account in this workshop is using LRS redundancy option.*

When setting up storage account in production for backups:

use at least ZRS (Zone-Redundant Storage) to protect against zone failures. GRS (Geo-Redundant Storage) is recommended for cross-region durability.

![storage account example](images/storage-account.png)

![redundancy options](images/redundancy.png)
