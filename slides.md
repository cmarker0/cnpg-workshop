---
marp: true
theme: default
paginate: true
backgroundColor: #1a1a2e
color: #e0e0e0
style: |
  section {
    font-family: 'Segoe UI', sans-serif;
  }
  section.lead h1 {
    color: #00d4ff;
  }
  section.lead {
    text-align: center;
  }
  h1 {
    color: #00d4ff;
  }
  h2, h3 {
    color: #7ec8e3;
  }
  a {
    color: #00d4ff;
  }
  blockquote {
    border-left: 4px solid #00d4ff;
    color: #b0b0b0;
    font-style: italic;
  }
  table {
    margin: 0 auto;
  }
  th {
    background-color: #2a2a4a;
  }
  code {
    background-color: #2a2a4a;
  }
  .columns {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 2rem;
  }
  .columns3 {
    display: grid;
    grid-template-columns: 1fr 1fr 1fr;
    gap: 1rem;
  }
  .box {
    border: 1px solid #444;
    border-radius: 8px;
    padding: 1rem;
  }
  .highlight {
    background-color: rgba(0, 120, 215, 0.15);
    border-radius: 8px;
    padding: 1rem;
    margin-top: 1rem;
  }
---

<!-- _class: lead -->

# CloudNativePG

## PostgreSQL på Kubernetes

[CNPG Docs](https://cloudnative-pg.io) | [Workshop Repo](https://github.com/cmarker0/cnpg-workshop)

<!--
Velkommen til denne presentasjonen om CloudNativePG. Vi skal se på hvordan vi kan kjøre PostgreSQL på Kubernetes.
-->

---

<!-- _class: lead -->

# Hvorfor CloudNativePG?

<!--
Vi starter med å se på hvorfor vi trenger CNPG.
-->

---

# Utfordringen / Løsningen

<div class="columns">
<div>

### Utfordringen

Å kjøre databaser på Kubernetes har tradisjonelt vært komplisert:

- Stateful workloads i en stateless-plattform
- Manuell konfigurasjon av replikering
- Failover krever eksterne verktøy
- Backup og restore er opp til deg selv
- TLS og sikkerhet er ekstraarbeid

</div>
<div>

### Løsningen: CNPG

CloudNativePG er en Kubernetes-operator bygd for PostgreSQL:

- Open source (Apache 2.0)
- Direkte integrasjon med Kubernetes API
- Ingen eksterne avhengigheter
- Deklarativ konfigurasjon
- Self healing cluster
- Innebygd backup og restore
- Connection pooling med PgBouncer

> *Utviklet av EDB, CNCF Sandbox-prosjekt*

</div>
</div>

<!--
CNPG er bygd fra grunnen av for Kubernetes. De bruker interne kubernetes systemer for HA funksjonaliteter.
-->

---

# Eksempel arkitekturoversikt 



<!--
Her ser vi arkitekturen. Primary håndterer writes, replicaene tar read. PgBouncer-poolere fordeler trafikken, og Barman tar seg av backup til Azure.
-->

---

# Høy tilgjengelighet

CNPG sørger for at databasen alltid er tilgjengelig

<div class="columns3">
<div class="box">

### Automatisk failover

Når primær instansen går ned, blir replicaen med mest oppdatert data promotet automatisk.

Ingen manuell arbeid kreves.

</div>
<div class="box">

### Self-healing

Feilede instanser blir automatisk gjenskapt. Clusteret reparerer seg selv.

Operatoren overvåker kontinuerlig.

</div>
<div class="box">

### Pod anti-affinity

Instanser blir spredt over ulike noder for å tåle nodefeil.

Konfigurerbart per sone eller host.

</div>
</div>

```yaml
spec:
  instances: 3
  affinity:
    enablePodAntiAffinity: true
    topologyKey: kubernetes.io/hostname
    podAntiAffinityType: required
```

<!--
HA er kjernen i CNPG. Operatoren snakker direkte med Kubernetes API-serveren - ingen behov eksterne verktøy.
-->

---

# Cluster-konfigurasjon

Deklarativt PostgreSQL-cluster med YAML

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: workshop-pg-cluster
spec:
  instances: 3
  enableSuperuserAccess: true
  superuserSecret:
    name: admin-user
  bootstrap:
    initdb:
      database: app
      owner: app
      secret:
        name: app-user
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: workshop-backup-azure-object-store
  imageName: ghcr.io/cloudnative-pg/postgresql:18.1-system-trixie
  resources:
    requests:
      memory: 100Mi
      cpu: 200m
    limits:
      memory: 300Mi
  storage:
    storageClass: kubevirt-csi-infra-default
    size: 2Gi
  walStorage:
    storageClass: kubevirt-csi-infra-default
    size: 2Gi
```

<!--
Alt er deklarativt.
-->

---

# Backup og gjenoppretting

Automatisert med Barman Cloud Plugin

<div class="columns">
<div>

### Scheduled/planlagte backups

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: workshop-scheduled-backup
spec:
  schedule: "0 0 8,12,18 * * *"
  cluster:
    name: workshop-pg-cluster
  immediate: true
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
```

3x daglig backup - kl. 08, 12 og 18.

</div>
<div>

### Object Store

```yaml
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: workshop-backup-azure-object-store
spec:
  retentionPolicy: "1d"
  configuration:
    azureCredentials:
      storageAccount:
        name: azure-storage-account-credentials
        key: account_name
      storageKey:
        name: azure-storage-account-credentials
        key: account_key
    destinationPath: >-
      https://cnpgworkshop.blob.core.windows.net/backup/v1
    wal:
      compression: gzip
```

Støtter Azure, S3 og GCS.

</div>
</div>

<!--
Backupen er fullstendig automatisert. WAL-arkivering kjører kontinuerlig, og base backups blir tatt etter definert cron schedule.
-->

---

# Point-in-Time Recovery (PITR)

Gjenopprett databasen til et vilkårlig tidspunkt

```yaml
bootstrap:
  recovery:
    database: app
    owner: app
    source: clusterBackup
    recoveryTarget:
      backupID: "20251009T072751"
externalClusters:
  - name: clusterBackup
    plugin:
      name: barman-cloud.cloudnative-pg.io
      parameters:
        barmanObjectName: workshop-restore-azure-object-store
        serverName: workshop-pg-cluster
```

<div class="highlight">

**Hvordan det fungerer:** CNPG restorer siste base backup og tygge gjennom WAL-filer fremover i tid til det angitte tidspunktet. Du kan velge et spesifikt backupID eller et tidspunkt.

</div>

<!--
PITR er en av de viktigste funksjonene. Har du slettet data ved et uhell klokka 14:32? Gjenopprett til 14:31. Alt takket være kontinuerlig WAL-arkivering.
-->

---

# Connection Pooling med PgBouncer

Innebygd støtte for connection pooling

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Pooler
metadata:
  name: workshop-pg-pooler-rw
spec:
  cluster:
    name: workshop-pg-cluster
  instances: 3
  type: rw                    # rw = read-write, ro = read-only
  pgbouncer:
    poolMode: session
    parameters:
      max_client_conn: "100"
      default_pool_size: "20"
```

<div class="columns">
<div>

### Read-Write Pooler
- Ruter til **primary**
- For skriveoperasjoner
- `workshop-pg-pooler-rw:5432`

</div>
<div>

### Read-Only Pooler
- Fordeler last over **replicas**
- For lesespørringer
- `workshop-pg-pooler-ro:5432`

</div>
</div>

<!--
PgBouncer er innebygd i CNPG. Du slipper å sette det opp separat. Med dedikerte poolere for lese- og skrivetrafikk kan applikasjonen nå riktig instans automatisk.
-->

---

# Lagring

<div class="columns">
<div>

### Egne volum for data og WAL

```yaml
storage:
  storageClass: kubevirt-csi-infra-default
  size: 2Gi
walStorage:
  storageClass: kubevirt-csi-infra-default
  size: 2Gi
```

#### Hvorfor eget WAL-volum?

- Bedre I/O-ytelse
- WAL og data konkurrerer ikke om disk
- Mer forutsigbar latency
- Enklere å overvåke plass

</div>
<div>

### Lagringsredundans

For produksjon bør du velge riktig redundansnivå:

| Type | Beskrivelse |
|------|-------------|
| **LRS** | Lokalt redundant - kun demo |
| **ZRS** | Sone-redundant - minstekrav for prod |
| **GRS** | Geo-redundant - ideelt for prod |

> **Tips:** Denne workshopen bruker LRS for demo. I produksjon bør du bruke minst ZRS for å tåle sonefeil.

</div>
</div>

<!--
Separat WAL-lagring er best practice. Det betyr at skriving av transaksjonslogg ikke konkurrerer med vanlig datalagring. I produksjon bør du også tenke på lagringsredundans.
-->

---

<!-- _class: lead -->

# Demo

### Workshop-repoet

<div class="columns">
<div>

**Oppsett**
- 3-instans PostgreSQL-cluster
- PgBouncer RW + RO poolere
- Barman backup til Azure
- PgAdmin for administrasjon
- ArgoCD for GitOps

</div>
<div>

**Testskript**
- `populate-database.sql` - Opprett skjema
- `generate-load.sql` - Load test kjør backup her
- `generate-wal-load.sql` - WAL/PITR-test, kjør dette, så drep clusteret
- `cleanup-database.sql` - Rydd opp

</div>
</div>

<!--
La oss se hvordan alt dette henger sammen i praksis. Workshopen har ferdiglagde skript for å teste de ulike funksjonene.
-->

---

# Monitoring og observability

Innebygd støtte for Prometheus og logging

<div class="columns">
<div>

### Prometheus-metrikker

- Metrics-eksportør på port **9187**
- Ferdiglagde Grafana-dashbord, krever litt jobb men du må ikke lage alt selv.
- Metrikker for:
  - Replication lag
  - Transaksjoner per sekund
  - Tilkoblinger
  - Buffer cache hit ratio
  - WAL-produksjon

</div>
<div>

### Strukturert logging

- JSON-formatert logging til stdout
- Enkel integrasjon med log-aggregering
- Egnet for ELK, Loki, Splunk osv.

```json
{
  "level": "info",
  "ts": "2025-10-09T07:27:51Z",
  "logger": "postgres",
  "msg": "checkpoint complete",
  "logging_pod": "workshop-pg-cluster-1"
}
```

</div>
</div>

<!--
CNPG leverer metrikker i Prometheus-format ut av boksen. Sammen med JSON-logging får du god observabilitet uten ekstra oppsett.
-->

---

# Andre nyttige funksjoner

<div class="columns">
<div>

### Deklarative rolling updates
- Automatisk ved minor-versjonsoppgradering
- Ingen nedetid ved operatoroppgradering
- Kontrollert utrulling

### Synkron replikering
- Quorum-basert eller prioritetsbasert
- Økt dataholdbarhet
- Konfigurerbart per cluster

### Replica clusters
- Distribuert topologi på tvers av clustere
- Private, public, hybrid og multi-cloud
- Delayed replicas for historisk datatilgang

</div>
<div>

### TLS-støtte
- Sikre tilkoblinger som standard
- Klientsertifikat-autentisering
- Integrasjon med cert-manager, man kan laste inn egne serfikater om man vil.

### cnpg kubectl-plugin
- Forenkler clusteroperasjoner
- Status, promote, fencing osv.

```bash
kubectl cnpg status workshop-pg-cluster
kubectl cnpg promote workshop-pg-cluster 2
```

</div>
</div>

<!--
CNPG har mange flere funksjoner. Her er et utvalg av de som kan være nyttige å kjenne til.
-->

---

<!-- _class: lead -->

# Oppsummering

| Egenskap | CNPG-løsning |
|----------|-------------|
| **Høy tilgjengelighet** | Automatisk failover, self healing |
| **Backup** | Barman Cloud, PITR, planlagte backups |
| **Connection pooling** | Innebygd PgBouncer (RW + RO) |
| **Lagring** | Egne volum for data og WAL |
| **Sikkerhet** | TLS, sertifikater, secrets |
| **Overvåking** | Prometheus-metrikker, JSON-logging |
| **CLI** | kubectl-plugin, hibernation(dvale), fencing |

**CNPG gjør det enkelt å kjøre PostgreSQL i produksjon på Kubernetes.**

<!--
CNPG dekker det meste du trenger for å kjøre PostgreSQL på Kubernetes. Alt er deklarativt, automatisert og Kubernetes-native.
-->

---

<!-- _class: lead -->

# Takk for oppmerksomheten!

Workshop-repo: [github.com/cmarker0/cnpg-workshop](https://github.com/cmarker0/cnpg-workshop)

CNPG-dokumentasjon: [cloudnative-pg.io](https://cloudnative-pg.io)

**Spørsmål?**



