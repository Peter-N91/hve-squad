# Decision rules — SQL Server → Azure (distilled from the knowledge base)

Apply Steps **A → D** in order. Deterministic: same answers ⇒ same recommendation.
Source of truth: `docs/sql-server-to-azure-migration.md` (fredgis/sql-migration-advisor), verified June 2026.

> Adapted for the HVE squad from [fredgis/sql-migration-advisor](https://github.com/fredgis/sql-migration-advisor) under the MIT License. This is the offline fallback distillation; the live source doc wins on any disagreement.

Three layers, never mixed:

- **Target** = where the DB ends up (runtime).
- **Control plane** = how you assess/orchestrate (Azure Migrate, Arc, SSMS 22, DMS).
- **Method** = the data-movement vehicle (MI Link, LRS, backup/restore, …).

---

## Step A — Pick the TARGET (decision tree, first match wins)

1. **In-place / not ready to move** (driver = "modernize but stay", or assessment-only) →
   **SQL Server enabled by Azure Arc** (control plane): inventory, best-practices assessment,
   **ESU**, Copilot-assisted portal migration later. *Not a runtime target.*

2. **VM-only feature OR OS control** — any of FILESTREAM/FileTable, PolyBase, cross-instance
   DTC, third-party agents, exact-version pinning, or management model = "Need OS/engine control":
   - Source is a **VMware estate doing a data-center exit** (driver = data-center exit) →
     **Azure VMware Solution (AVS)** (keeps FCI + Always On AG; migrate with HCX/vMotion).
   - Otherwise → **SQL Server on Azure VM** (IaaS rehost; **free ESU** for end-of-support).

3. **Kubernetes / edge / sovereign-multicloud** (management model = "Need Kubernetes on-prem/edge"):
   - Want a **managed engine** (auto patch/backup/HA via Arc data controller) →
     **Arc-enabled SQL Managed Instance** (any K8s: AKS/ARO/EKS/GKE).
   - Dev/test/edge, full DIY → **SQL Server in a container** (AKS/ARO/ACI/ACA). *You own HA/patch/backup.*

4. **Instance-level features but PaaS OK** — any of SQL Agent, cross-DB queries, linked servers,
   SQL CLR, Service Broker (single-instance), and **none** of the VM-only features above →
   **Azure SQL Managed Instance** (the default **managed lift-and-shift**; tiers GP / BC).

5. **Cloud-native / no instance features** (management = "Fully managed", feature deps = none) →
   **Azure SQL Database**, choose the model:
   - **> 4 TB** or heavy concurrent write I/O / HTAP → **Hyperscale**.
   - Intermittent / dev / microservice → **Serverless** (auto-pause).
   - Multi-tenant SaaS consolidation → **Elastic Pool** (or Hyperscale per large tenant).
   - Otherwise → single DB, **General Purpose** (or **Business Critical** for low-latency/HA).

6. **Analytics-first / Fabric-native AND small/simple schema** (driver = analytics/Fabric, size small,
   DACPAC ≤ 20 MB, no Private Link need) → **SQL database in Fabric** *(Preview)* +
   **Fabric Mirroring** for the analytical copy. Do **not** position as enterprise OLTP prod yet.

**Tie-breakers by workload profile** (doc §12):

| Profile | Lean target |
| --- | --- |
| Banking / regulated / strong on-prem | SQL VM + ESU via Arc, or AVS |
| Heavy legacy ERP (SAP, on-prem Dynamics) | SQL MI or SQL VM |
| Multi-tenant SaaS ISV | SQL DB Hyperscale / Elastic Pool |
| Modern microservice | SQL DB serverless |
| Fabric-native / analytics-first | SQL DB in Fabric + Mirroring |
| Edge / sovereign / multi-cloud | Arc-enabled SQL MI on local AKS |
| Short-term data-center exit | AVS + VMware HCX |
| Off end-of-support, minimal change | SQL VM "as-is" + free ESU |

---

## Step B — Pick the METHOD (given target + downtime + version + size + network)

### → SQL Server on Azure VM

| Downtime wanted | Method | Gate |
| --- | --- | --- |
| Near-zero | **Distributed AG** or **Always On AG** (fail onto Azure replicas) | DAG: source 2016+, needs **AD DS** (or workgroup AG + certs), ports open |
| Minimal | **Log shipping** | Windows-only source |
| Offline | **Native backup/restore** — Backup-to-URL (≤12.8 TB on 2016+) or `.bak`+AzCopy; detach/attach for very large | — |
| Whole VM/instance | **Azure Migrate** (replication, incl. FCI/AG) | source 2008 SP4 |
| Multi-TB / limited WAN | **Data Box** seed → sync delta | — |

### → AVS

- **VMware HCX / vMotion** (zero-refactor, keeps FCI/AG). No DMS/MI Link.

### → Azure SQL Managed Instance

| Downtime wanted | Method | Gate |
| --- | --- | --- |
| Near-zero (online) | **MI Link** (preferred, incl. large Business Critical) | source **2016+**, **port 5022** both ways, ≤10 simultaneous DBs |
| Offline (planned) | **Log Replay Service (LRS)** | source **2012+**, public endpoint, no R/O target |
| Offline, simplest | **Native backup/restore (.bak)** | source **2008+**; **migrate TDE cert first**; master/msdb not restorable |
| Online subset | **Transactional replication** | source 2012+ |
| Data-only / bulk | bcp / Smart Bulk Copy / BACPAC / ADF | — |

> If **port 5022 is blocked** and can't be opened → MI Link is out → use **LRS** (offline).

### → Azure SQL Database

| Downtime wanted | Method | Gate |
| --- | --- | --- |
| Offline | **modern DMS (offline)** — *online not available to SQL DB* | source 2008+ |
| Offline | **BACPAC / SqlPackage** | smaller/medium; SqlPackage for scale |
| Online subset | **Transactional replication** | source **2016–2019 only**, push subscription, article limits |
| Bulk / integration | bcp / Smart Bulk Copy / **ADF Copy** | — |

> **Not supported to SQL DB:** native `.bak` restore, detach/attach, MI Link.
> SQL Agent → **Elastic Jobs**.

### → SQL database in Fabric (Preview)

- **Fabric Migration Assistant** — schema via **DACPAC ≤ 20 MB**; data via **Fabric Data Factory
  copy job** + **on-prem data gateway** (no VNet gateway / Private Link). Offline.

### → Arc-enabled SQL MI / container

- **Native backup/restore** (Arc MI exposes a SQL MI endpoint → §MI methods apply); container =
  backup/restore via mounted volume, detach/attach, BACPAC, bcp, ADF.

### Large estates / multi-TB (any target) — **seed-then-sync**

Ship the **initial full backup via Data Box** (or AzCopy over ExpressRoute), then catch up the
delta with **LRS / MI Link / transactional replication / log shipping** before cutover.
Don't size the cutover as `size ÷ bandwidth` — **test AzCopy + one full backup** first; plan a rollback window.

---

## Step C — Downtime class, BLOCKERS & remediations

**Downtime class:** near-zero {MI Link, Distributed/Always On AG, Striim} · minimal {transactional
replication, log shipping, native restore + diff/log} · offline {native backup/restore, LRS,
BACPAC, bcp, detach/attach, ADF, Data Box}.

**Cutover blockers (check every time):**

| Blocker | Remediation |
| --- | --- |
| **TDE** encrypted DB | Migrate the **server-level certificate FIRST**, before any native restore to MI (else restore fails ~80% in, no clear error). |
| **Windows logins** | DMS skips them by default — enable the option + grant MI read to Entra ID; script + recreate logins/users. |
| **MI Link ports** | Open **5022** both directions (often blocked in banking/industrial nets). |
| Other methods' network | DMS/LRS/replication need outbound **443** to Blob, **1433** (+ **1434/UDP** for named instances). |
| **DAG** | Requires **AD Domain Services** (or workgroup AG + certs). |
| **Transactional replication → SQL DB** | Source **2016–2019** only; article-type limits (no `hierarchyid`, `sql_variant`…). |
| **SQL Agent jobs** | MI: native · SQL DB: **Elastic Jobs**. |
| **Linked servers / cross-DB** | OK on VM/MI; **not on SQL DB** — refactor. |
| **SSIS** | **Azure-SSIS Integration Runtime** (SSISDB via DMS). |
| **SSRS** | **Power BI paginated reports** (RDL). |
| **SSAS** | **Azure Analysis Services** or **Power BI Premium** (XMLA). |
| Dependency gap | ~60% of migrations stumble on undocumented linked servers / SQL Agent jobs — run a **dependency map** (Azure Migrate / third-party) before committing. |

**Pre-cutover validation:** **DEA** (capture + replay) for performance-sensitive workloads.

---

## Step D — Cost levers, program fit, assessment tool

**Cost levers:**

- **Azure Hybrid Benefit (AHB):** applies to **SQL DB (vCore), SQL MI, SQL VM** — **not** Fabric SQL DB.
- **ESU:** **free on Azure VMs** (3 years); on-prem only **via Azure Arc (paid)** — changes stay-vs-migrate math.
- Combine AHB + reservations + ESU for up to ~85% savings.
- **Sizing:** never size MI/SQL DB on average CPU — use a **Perfmon baseline ≥ 7 days + ~20% headroom**.

**Assessment / control plane to run next (pick by audience):**

- DBA-first, Windows → **SSMS 22 Migration Component** (assess + launch path).
- Any Arc-enabled source → **SQL Server migration in Azure Arc** (portal, **Copilot** recommends MI Link vs LRS).
- Estate scale / business case → **Azure Migrate** (appliance / import / Arc-based discovery).
- Orchestrate at scale / CI-CD → **modern Azure DMS** + **`Az.DataMigration`** (only viable path beyond ~50 DBs).
- **Heterogeneous source** (Oracle/Sybase/DB2/MySQL/Access) → **SSMA** (not for homogeneous SQL→SQL).

**Microsoft program fit:** **Cloud Accelerate Factory** (zero-cost delivery) · **SQL in a Day**
(EMEA EPS Data Motion) · **Azure Accelerate / FastTrack**.

**SLA reference (align to the app):** MI BC 99.99% · SQL DB BC 99.995% (zone-redundant) ·
SQL DB Hyperscale 99.99% · SQL VM depends on the AG.

---

## Retired — never recommend (use the replacement)

| Retired | Date | Use instead |
| --- | --- | --- |
| Data Migration Assistant (DMA) | 16 Jul 2025 | SSMS 22 / Arc / Azure Migrate |
| Azure Data Studio + SQL Migration extension | 28 Feb 2026 | VS Code + MSSQL; SSMS 22 / DMS |
| Azure DMS *classic* — SQL scenarios | 15 Mar 2026 | **modern** DMS (portal / PowerShell / CLI) |
| SQL Data Sync | retires 30 Sep 2027 | ADF / transactional replication / AG |

---

## Cross-cloud sources & reverse path

- Supported sources for DMS/LRS/MI Link/native restore: **AWS EC2, AWS RDS for SQL Server,
  GCP Compute Engine, GCP Cloud SQL for SQL Server**.
- Reverse/exit: SQL DB → SQL Server via **BACPAC + scripts** (heavy); **MI → SQL Server 2022/2025
  via MI Link reverse failback** (trivial — a portability argument).
