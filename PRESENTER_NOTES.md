# Presentatørnotater: CNPG Backup og Restore Workshop

Disse notatene dekker hva du sier og gjør på hvert steg. Deltakerne følger [TASKS.md](TASKS.md) selv, så din rolle er å forklare *hvorfor* ting fungerer som de gjør, ikke bare klikke gjennom stegene.

**Forutsetning:** Operatorer, ArgoCD, GitOps-prosjekt, secrets og alle ArgoCD-applikasjoner er allerede synket og kjørende før presentasjonen starter. Workshopen begynner direkte med pgAdmin og backup/restore.

---

## Før workshopen

- Bekreft at alle deltakeres clustere er oppe: CNPG-cluster med 3 instanser, Barman og pgAdmin skal være grønne i ArgoCD.
- Verifiser at WAL-arkivering fungerer ved å sjekke Barman-sidecar-loggene i en av podene.
- Ha [development/database/backup-on-demand.yaml](development/database/backup-on-demand.yaml) åpen og klar til å kopiere/lime inn.
- Bekreft at `backup.objectstore.yaml` og `restore.objectstore.yaml` peker på riktige paths i Azure.

---

## Kort intro: hva er satt opp og hvorfor

Ta 5 minutter til å forklare arkitekturen før dere begynner.

**Hva du sier:**

- CNPG-clusteret kjører 3 PostgreSQL-instanser: én primær og to replikaer. Pod anti-affinity sørger for at de ikke havner på samme node.
  - I produksjon ville man nok også hatt geografisk spredning.
- Barman kjører som en sidecar i hver pod og sender WAL-segmenter løpende til Azure Blob Storage. Dette er grunnlaget for Point-in-Time Recovery (PITR).
- Det er to separate ObjectStore-ressurser:
  - `backup.objectstore.yaml` (navn: `workshop-backup-azure-object-store`): dit WAL og basebackuper *skrives* fra dette clusteret.
  - `restore.objectstore.yaml` (navn: `workshop-restore-azure-object-store`): dit CNPG *leser* backuper fra under recovery. Peker på en tidligere versjonskatalog (`v3`).
- Separasjonen mellom lese- og skrive-store gjør at du kan restore fra en stabil kilde uten å overskrive den med ny WAL.

---

## Steg 1: Populer databasen

**Hva du sier:** Vi fyller databasen med demodata slik at det er noe meningsfullt å miste og deretter gjenopprette.

Kjør i pgAdmin, i rekkefølge:

1. [scripts/create-tables.sql](scripts/create-tables.sql)
2. [scripts/populate-database.sql](scripts/populate-database.sql)

Passordet for tilkoblingsprompten er `app`.

---

## Steg 2: Ta en on-demand backup

**Hva du sier:** CNPG tar planlagte backuper automatisk (se `backup.yaml`: hver dag kl. 08:00, 12:00 og 18:00), men her trigges én manuelt slik at vi kontrollerer nøyaktig når backup-punktet er.

**Slik gjøres det:**

```bash
kubectl apply -f development/database/backup-on-demand.yaml
```

Følg med på statusfeltet:

```bash
kubectl get backup -n workshop-pg-cluster -w
```

**Vent til backup-status viser `completed`.** Dette er viktig: hvis du kjører WAL-lasten før backupen er ferdig, kan data som ble skrevet i det vinduet ikke restores pålitelig fra basebackupen alene.

**Kopier `backupID`** fra backup-ressursens status. Den ser ut som `20260224T121047`. Du trenger dette i `cluster.yaml` senere.

**Verifiser at backupID finnes i Azure:** Åpne Azure Portal og naviger til storage accounten `cnpgworkshop`, container `cnpg-workshop-pg-backup`, og mappen som tilsvarer `destinationPath` i `backup.objectstore.yaml` (f.eks. `v1`). Under `base/` skal det ligge en mappe med nøyaktig samme ID som `backupID` du nettopp kopierte:

```text
v1/
  base/
    20260224T121047/    <-- samme som backupID
      data.tar
      ...
  wals/
    ...
```

**Hva du sier:** Dette bekrefter at Barman faktisk lastet opp basebackupen til Azure. `backupID` er ikke bare et internt Kubernetes-konsept, det er navnet på mappen i blob storage. Når CNPG restorer, bruker den nettopp dette mappenavnet for å finne riktig basebackup og spille av WAL-segmentene derfra.

---

## Steg 3: Generer WAL-last etter backupen

**Hva du sier:** Nå skriver vi mer data *etter* backupen. Dette simulerer normal applikasjonsaktivitet. WAL-arkivereren sender kontinuerlig disse WAL-segmentene til Azure. Dette er det som muliggjør PITR: vi kan gjenopprette til et hvilket som helst tidspunkt etter siste basebackup, så lenge WAL-segmentene er intakte.

Kjør [scripts/generate-wal-load.sql](scripts/generate-wal-load.sql) i pgAdmin. Skriptet:

- Setter inn 500 kunder én etter én (mange små WAL-poster).
- Masseinsetter produkter og ordrer.
- Gjør tunge oppdateringer og slettinger (dyrt i WAL pga. MVCC).
- Skriver store TOAST-rader.
- Oppretter indekser og kjører ANALYZE.

Skriptet logger også en `wal_demo_log`-tabell med tidsstempler for hver fase. Disse tidsstemplene kan brukes som PITR-mål hvis du vil restore til en spesifikk fase.

**Poeng å løfte frem:** Hvis du hadde et dårlig deploy som korruperte data i, si, fase 4, kunne du restore til rett før fase 4 ved å bruke `targetTime` i stedet for `backupID`.

---

## Steg 4: Slett clusteret (forbered restore)

**Hva du sier:** CNPG støtter ikke in-place recovery. For å restore må du slette clusteret og la ArgoCD gjenskape det fra den oppdaterte `cluster.yaml`. Dette speiler hva du ville gjort under en reell hendelse.

**Før sletting:** Sørg for at `backupID` fra Steg 2 allerede er committed til `cluster.yaml` under `bootstrap.recovery.recoveryTarget.backupID`. Ellers kommer clusteret tilbake i recovery-modus men peker på feil backup.

**Slik sletter du via ArgoCD:**

1. Åpne `database`-appen i ArgoCD.
2. Finn `Cluster`-ressursen (`workshop-pg-cluster`).
3. Slett den fra ArgoCD-UI-et (ikke hele appen, bare Cluster-ressursen).

PVC-ene må også slettes for at CNPG skal bootstrappe med fersk lagring.

---

## Steg 5: Oppdater `cluster.yaml` for restore og push

**Hva du sier:** `cluster.yaml` har allerede `recovery`-bootstrap-seksjonen klar. Du trenger å:

1. Sjekk at `initdb` er kommentert ut (det er det som standard i dette repoet).
2. Sjekk at `recovery` er aktiv (det er det som standard i dette repoet).
3. Sett `backupID` til verdien du kopierte i Steg 2:

   ```yaml
   recoveryTarget:
     backupID: 20260224T121047  # ditt faktiske backup-ID
   ```

   Alternativt, bruk `targetTime` for PITR:

   ```yaml
   recoveryTarget:
     targetTime: "2026-02-24T12:13:40+00:00"
   ```

4. Inkrementer `destinationPath`-versjonen i `backup.objectstore.yaml` (f.eks. `v4` til `v5`). Det nye clusteret trenger en fersk, tom backup-destinasjon.
5. Commit og push.

ArgoCD oppdager endringen og gjenskaper clusteret. CNPG kobler til `restore.objectstore.yaml`-kilden, laster ned basebackupen, spiller av WAL-segmenter opp til målet, og bringer clusteret online.

---

## Steg 6: Verifiser restoren

Etter at clusteret er friskt (alle 3 instanser grønne i ArgoCD/OpenShift):

1. Åpne pgAdmin og koble til serveren igjen.
2. Sjekk at data fra før backupen finnes.
3. Sjekk at `wal_demo_log`-tabellen finnes og viser rader opp til (men ikke etter) recovery-målpunktet.

**Hva du sier:** `wal_demo_log`-tidsstemplene er beviset ditt på at PITR fungerte. Hvis du restoret til `backupID`, vil du ikke se noen `wal_demo_log`-rader fordi den tabellen ble opprettet etter backupen. Hvis du restoret til en `targetTime` under WAL-lasten, vil du bare se fasene som ble fullført før det tidspunktet.

---

## Steg 7: Oppgrader PostgreSQL fra 17 til 18

**Hva du sier:** CNPG støtter in-place major version upgrade ved å endre `imageName` i `cluster.yaml`. Operatoren håndterer pg_upgrade automatisk, uten manuell intervensjon. La oss se hvordan det fungerer i praksis.

**Forutsetning:** Clusteret kjører på PostgreSQL 17 (imageName ender på `17.x`). Gjør denne demoen etter at restore-flowet er ferdig og clusteret er stabilt, eller som en separat demo mot et rent cluster.

**Slik gjøres det:**

1. Åpne [development/database/cluster.yaml](development/database/cluster.yaml).
2. Finn `imageName`-feltet:

   ```yaml
   imageName: ghcr.io/cloudnative-pg/postgresql:17.x-system-trixie
   ```

3. Endre det til PostgreSQL 18:

   ```yaml
   imageName: ghcr.io/cloudnative-pg/postgresql:18.1-system-trixie
   ```

4. Commit og push.

**Hva skjer i clusteret:**

- ArgoCD synker endringen og CNPG-operatoren plukker opp den nye `imageName`.
- Operatoren starter en in-place major version upgrade via `pg_upgrade`.
- Clusteret går midlertidig ned under selve oppgraderingen (kort nedetid).
- Etter oppgraderingen starter CNPG primary-poden på nytt med PostgreSQL 18, og replikaene re-synkroniserer mot den nye primaryen.
- Følg med i OpenShift/ArgoCD: clusteret går fra `Updating` til `Healthy`.

**Hva du sier:** Dette er en av de store fordelene med CNPG kontra å administrere PostgreSQL manuelt. En major version upgrade er en Git-commit. Selve `pg_upgrade`-prosessen kjøres av operatoren inne i poden, og du slipper å SSH-e inn og kjøre skript manuelt. Revisjonsloggen er i Git.

**Poeng å løfte frem:**

- CNPG krever at du hopper til neste major version (ikke hopp over versjoner, f.eks. 16 direkte til 18).
- Backup-kompatibilitet: WAL-formatet endres mellom major versjoner. Etter oppgradering vil ny WAL skrives i PG18-format. Restore til en `targetTime` som krysser oppgraderingstidspunktet er ikke mulig med standard PITR.
- Ta alltid en ny basebackup rett etter oppgraderingen for å ha et rent utgangspunkt på ny versjon.

---

## Vanlige problemer

| Problem                               | Sannsynlig årsak                       | Løsning                                                   |
| ------------------------------------- | -------------------------------------- | --------------------------------------------------------- |
| Cluster henger i `Recovering`         | Feil `backupID` eller korrupt WAL-path | Sjekk sidecar-loggene i primær-poden                      |
| Barman-sidecar OOMKilled              | For lav minnegrense                    | Øk `instanceSidecarConfiguration.resources.limits.memory` |
| ObjectStore auth-feil                 | Feil nøkler i secreten                 | Sjekk `account_name` / `account_key` i secreten på nytt   |
| `destinationPath`-konflikt            | Gjenbruk av eksisterende ikke-tom path | Inkrementer versjonen i `backup.objectstore.yaml`         |
| PVC ikke slettet før restore          | Gammel lagring forvirrer CNPG          | Slett PVC-ene manuelt før re-sync                         |
| pgAdmin kobler ikke til etter restore | Service eller pooler ikke klar ennå    | Vent til alle 3 clusterinstanser er `Running`             |

---

## Nøkkelkonsepter å forsterke på slutten

- **Basebackup vs. WAL:** En basebackup er et fullstendig øyeblikksbilde. WAL-segmenter er den kontinuerlige strømmen av endringer oppå det. Du trenger begge for PITR.
- **`backupID` vs. `targetTime`:** Bruk `backupID` for å restore til nøyaktig en kjent backup. Bruk `targetTime` for å restore til et hvilket som helst tidspunkt mellom backuper, så lenge WAL er tilgjengelig.
- **To ObjectStorer:** Separate lese- (restore) og skrive- (backup) storer lar deg restore fra en stabil kilde uten å kontaminere den med ny WAL.
- **GitOps for katastrofegjenoppretting:** Hele restore-prosedyren er en Git-commit. Det betyr at den er revisjonsbar, repeterbar og kan code-reviewes.
