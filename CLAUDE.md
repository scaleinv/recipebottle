# Claude Code Project Memory — Recipe Bottle

Recipe Bottle enables developers to safely run untrusted containers by interposing a security layer (sentry container) between untrusted containers (bottle containers) and system resources. It uses only `bash`, `git`, `curl`, `openssh`, `jq`, and `docker` natively. Infrastructure runs on Google Cloud Build and Google Artifact Registry with SLSA provenance verification.

Project page: https://scaleinv.github.io/recipebottle

## Getting Started

New users: start with the README.md at the project root. It walks through the full setup sequence from clone to running bottle.

After initial payor setup, the adaptive onboarding guide reads your current state and shows the next step:
```
tt/rbw-o.ONBOARDING.sh
```

## Domain Vocabulary

Recipe Bottle uses domain-specific terminology throughout its CLI and documentation. **When you encounter an unfamiliar term, read `README.md`** — it contains anchored definitions (`<a id>`) for all concepts. Navigate directly via anchor links (e.g., `#Ordain`, `#Depot`, `#Charge`).

Key term categories in README.md:
- **Architecture**: Foundry, Manor, Depot, Crucible, Vessel, Hallmark, Ark, Nameplate, Regime, Tabtarget
- **Roles**: Payor, Governor, Director, Retriever — the last three are Mantles worn by federated Citizens
- **Identity**: Citizen, Mantle, Foedus, Sitting, Terrier, Muniment
- **Containers**: Sentry, Pentacle, Bottle
- **Foundry Operations** (appendix, grouped): Infrastructure, Identity and Admission, Supply Chain, Building, Chain Links, Verification, Distribution, Removal, Diagnostics
- **Crucible Operations** (appendix): Charge, Quench, Rack, Hail, Scry
- **Testing**: Ifrit, Theurge

## Verb Guide

Recipe Bottle uses domain-specific verbs instead of generic ones (create, delete, start, stop). The frontispiece in each tabtarget filename uses these verbs — this guide maps what you want to do to the vocabulary you will encounter.

### How do I build a container image?

| Verb | What it does |
|------|-------------|
| **conclave** | Capture the co-versioned cohort of builder tool images from upstream into one Lode (the reliquary), identified by its touchmark. Prerequisite for ensconce and ordain. |
| **ensconce** | Capture an upstream base image into your private GAR as a bole Lode, pinned by content hash. Supply-chain hardening: your builds pull from your own registry. |
| **ordain** | Build a hallmark. Mode-aware: detects the vessel type and dispatches accordingly (conjure, bind, or graft). |
| **conjure** | Build from source via Cloud Build (full SLSA provenance). A mode of ordain, not a separate command. |
| **bind** | Mirror an upstream image pinned by digest (digest-pin verification). A mode of ordain. |
| **graft** | Push a locally-built image to GAR (no provenance chain). A mode of ordain. |
| **kludge** | Build a vessel image locally for development iteration. No Cloud Build, no hallmark — just a local image. |

The supply chain has three layers: conclave captures the builder-tool Lode (the reliquary), ensconce captures base images as bole Lodes, ordain builds your vessel using both.

### How do I verify and inspect images?

| Verb | What it does |
|------|-------------|
| **audit** | List hallmark identifiers — director-tier flat catalog, no health detail (Lodes are enumerated by divine instead) |
| **tally** | Count and classify hallmarks in the registry by health state — retriever-tier, hallmarks only |
| **vouch** | Verify SLSA provenance — proves a hallmark was built by trusted infrastructure |
| **plumb** | Examine an image's provenance details: SBOM, build info, Dockerfile |

### How do I get images onto my workstation?

| Verb | What it does |
|------|-------------|
| **summon** | Pull a vouched hallmark image locally (full vouch ceremony first) |
| **wrest** | Pull a specific image by locator — path-polymorphic across hallmark members and Lode members (direct pull, no vouch) |

### How do I remove images?

| Verb | What it does |
|------|-------------|
| **abjure** | Delete a hallmark's artifacts from GAR (the full set: image + about + vouch) |
| **jettison** | Delete a specific image tag by locator — path-polymorphic across hallmark members and Lode members (surgical, single artifact) |

### How do I run containers?

| Verb | What it does |
|------|-------------|
| **charge** | Start the crucible — bring up sentry, pentacle, and bottle containers |
| **quench** | Stop the crucible — tear down all three containers |

### How do I inspect running containers?

| Verb | What it does |
|------|-------------|
| **rack** | Shell into the bottle container (compel the demon to reveal its state) |
| **hail** | Shell into the sentry container (call out to the guard) |
| **scry** | Observe network traffic across crucible containers (divine the topology) |

### How do I manage infrastructure?

| Verb | What it does |
|------|-------------|
| **establish** | Stand up the manor — GCP project, billing, OAuth client (guided; the one manual console procedure) |
| **instaurate** | Ensure the manor's identity substrate — the workforce pool every depot's sign-in trusts, and the terrier that records who holds what |
| **affiance** | Seat an external identity provider under the manor pool as a foedus (the trust your sign-in runs against) |
| **jilt** | Remove one foedus's provider from the manor pool |
| **levy** | Provision a depot — GCP project, artifact registry, build infrastructure |
| **unmake** | Permanently remove a depot |

### How do I admit people, and how do I authenticate?

Nobody holds a long-lived key. An operator is a **citizen** of a **foedus**; a role is a **mantle** the citizen is admitted to wear. Signing in opens a **sitting**, and each privileged call mints a short-lived token for one mantle.

| Verb | What it does |
|------|-------------|
| **avow** | Open a sitting — federated sign-in (device flow) against the active foedus |
| **novate** | Open a fresh full-window sitting, extinguishing any standing one |
| **espy** | Report whether a sitting stands and how much runway is left (read-only, no network) |
| **don** | Mint a short-lived token for one mantle, for one call |
| **gird** | Payor seats a depot's founding governor — the one admission outside governor wielding |
| **brevet** | Governor admits a citizen onto a mantle in this depot |
| **unseat** | Governor removes a citizen from one mantle (suspension, not erasure) |
| **attaint** | Governor expels a citizen from the depot entirely |
| **rehearse** | Recount the terrier — who holds which mantle, manor-wide (read-only) |

## Roles

Recipe Bottle uses a role-based security model. The payor stands apart; the other three are mantles worn by federated citizens.

| Role | Authentication | Purpose |
|------|---------------|---------|
| **Payor** | OAuth (browser flow) | Establishes the manor, funds depots, girds the first governor |
| **Governor** | Federated sitting → governor mantle | Admits citizens to mantles within a depot; keeps the terrier |
| **Director** | Federated sitting → director mantle | Submits builds, manages images, verifies provenance |
| **Retriever** | Federated sitting → retriever mantle | Pulls images for local use |

The payor is the only role requiring manual console work. Every other role signs in against the foedus and dons its mantle per call, so authority is short-lived by construction and each use is attributable to the human who wore it.

## Credential Safety

**The payor OAuth credential is the system's sole standing secret.** There are no service-account keyfiles to protect, back up, or rotate — the mantle roles hold no durable credential at all.

- **Payor OAuth** (`rbro.env`, under `RBRR_SECRETS_DIR`): client secret + refresh token. `600` permissions, only on the administrator's workstation, never committed.
- **Mantle tokens**: minted per call from a live sitting and never written to disk as durable credentials. Lose your sitting and you re-avow; there is nothing to restore.

@Tools/buk/claude-buk-core.md

@Tools/rbk/claude-rbk-acronyms.md

@Tools/rbk/claude-rbk-conduct.md

@Tools/rbk/claude-rbk-tabtarget-context.md

Test suite/fixture tabtargets use the `rbw-ts` (suites), `rbw-tf` (single fixture), and `rbw-tc` (single case) colophons:
- Available test suites: `ls tt/rbw-ts.TestSuite.*`
- Run one fixture: `tt/rbw-tf.FixtureRun.sh <fixture>` (run `tt/rbw-tc.FixtureCase.sh` with no argument to list fixtures)

For theurge/ifrit crucible testing work (editing test cases, adding new security probes, debugging test failures), read `Tools/rbk/claude-rbk-theurge-ifrit-context.md` — covers the two-binary architecture, the kludge/charge/test/ordain iteration loop, and how to add new test cases.

### Regime Inspection

Regimes follow a consistent pattern: `rbw-r{code}{r|v|l}` where `r` = render, `v` = validate, `l` = list.

| Code | Regime | Purpose | Render | Validate |
|------|--------|---------|--------|----------|
| `rp` | RBRP | Payor — GCP billing project identity | `rbw-rpr` | `rbw-rpv` |
| `rr` | RBRR | Repo — region, runtime prefix, vessel and secrets dirs, active foedus | `rbw-rrr` | `rbw-rrv` |
| `rd` | RBRD | Depot — depot project identity, build machine type | `rbw-rdr` | `rbw-rdv` |
| `rn` | RBRN | Nameplate — per-vessel hallmarks, runtime | `rbw-rnr` | `rbw-rnv` |
| `rv` | RBRV | Vessel — container image build definitions | `rbw-rvr` | `rbw-rvv` |
| `rf` | RBRF | Federation — the foedus: identity provider trust values | `rbw-rfr` | `rbw-rfv` |
| `rw` | RBRW | Workforce — the manor's identity pool | `rbw-rwr` | `rbw-rwv` |
| `ro` | RBRO | OAuth — payor refresh token (managed) | `rbw-ror` | `rbw-rov` |

**User-configured**: RBRP, RBRR, RBRD, RBRN, RBRV, RBRF, RBRW — you edit these during setup.
**Managed/generated**: RBRO (by payor install).

List operations: `rbw-rnl` (all nameplates), `rbw-rvl` (all vessel sigils).
Cross-regime operations: `rbw-ni` (nameplate info/survey), `rbw-nv` (validate all nameplates).

### BUK Infrastructure

| Colophon | Frontispiece | Purpose |
|----------|-------------|---------|
| `buw-tt-ll` | ListLaunchers | List all registered launchers |
| `buw-rcv` | ValidateConfigRegime | Validate BURC regime |
| `buw-rcr` | RenderConfigRegime | Render BURC regime |
| `buw-rsv` | ValidateStationRegime | Validate BURS regime |
| `buw-rsr` | RenderStationRegime | Render BURS regime |

## Configuration Regimes

A Config Regime is a structured configuration system: a specification document, a shell-sourceable assignment file (`.env`), and validation/render scripts. Each regime uses a unique uppercase variable prefix to prevent collisions.

**Two layers shared by all tools:**
- **BURC** (`rbmm_moorings/burc.env`) — project structure: tabtarget dir, tools dir, temp/output dirs
- **BURS** (`../station-files/burs.env`) — developer machine: log directory. Not in git.

**Recipe Bottle regimes** (in `rbmm_moorings/`):
- **RBRP** (`rbrp.env`) — Payor project identity. Set `RBRP_PAYOR_PROJECT_ID` to your GCP project.
- **RBRR** (`rbrr.env`) — Repository configuration. Runtime prefix, vessel directory, secrets directory, build timeouts, and `RBRR_ACTIVE_FOEDUS` — the selector naming which foedus you sign in against.
- **RBRD** (`rbrd.env`) — Depot identity. Cloud prefix, depot moniker, GCP region, build machine type.
- **RBRW** (`rbrw.env`) — Workforce. The manor's one identity pool, which every depot's sign-in trusts.
- **RBRF** (`rbmf_foedera/{foedus}/rbrf.env`) — Federation. One per standing foedus: the identity provider's trust values. Stored once in the library; the active one is resolved through `RBRR_ACTIVE_FOEDUS`, never copied.
- **RBRN** (`{moniker}/rbrn.env`) — Nameplate. Per-vessel: runtime (`docker`), vessel names, hallmark values (set after builds complete).
- **RBRV** (`rbmv_vessels/{vessel}/rbrv.env`) — Vessel definitions. One per container image you want to build.

## Architecture

```
Project Root/
├── rbmm_moorings/           # Consumer config root (BUK + Recipe Bottle)
│   ├── burc.env             # BURC — project structure config
│   ├── rbrp.env             # RBRP — Payor regime
│   ├── rbrr.env             # RBRR — Repo regime (holds RBRR_ACTIVE_FOEDUS)
│   ├── rbrd.env             # RBRD — Depot regime
│   ├── rbrw.env             # RBRW — Workforce regime (the manor's identity pool)
│   ├── rbmf_foedera/        # RBRF — Foedus library (one rbrf.env per standing foedus)
│   ├── {moniker}/rbrn.env   # RBRN — Nameplate regimes (per crucible)
│   ├── rbml_launchers/      # Launcher scripts (environment gates)
│   └── rbmv_vessels/        # Vessel definitions (rbrv.env + optional Dockerfile per vessel)
├── tt/                      # TabTargets (ls this to see all commands)
└── Tools/
    ├── buk/                 # Bash Utility Kit (portable infrastructure)
    └── rbk/                 # Recipe Bottle Kit (domain logic)
```

## Bash Conventions

- **Bash 3.2 compatibility** — works with macOS default shell
- **`set -euo pipefail`** at script start — crash-fast error handling
- **Braced, quoted variable expansion** — always `"${var}"`, never `$var`
- **Functional style** with clear error handling
- **No `gcloud` on workstation** — only `bash`, `curl`, `jq` for cloud operations

## Documentation

- `.adoc` files — AsciiDoc specifications (formal, with linked term vocabulary)
- `.md` files — guides and procedures
- `Tools/buk/README.md` — full BUK infrastructure documentation (tabtargets, launchers, regimes, dispatch)

## Troubleshooting

- **Regime validation fails on startup**: Run the regime's render command to see current values, then validate to identify the specific error. Fix the `.env` file and retry.
- **OAuth token expired**: re-run payor install with the saved client-secret JSON (`tt/rbw-gPI.PayorInstall.sh «RBRR_SECRETS_DIR»/client_secrets/client_secret_*.json`) — a dead token needs no new JSON.
- **A verb refuses for want of authority**: check the sitting first — `tt/rbw-as.EspySitting.sh` reports whether one stands and how much runway is left; `tt/rbw-aN.NovateSitting.sh` opens a fresh one. If the sitting is healthy, you are not brevetted onto the mantle that verb wields: a governor must `brevet` you (`tt/rbw-pB.GovernorBrevetsCitizen.sh`). Confirm with `tt/rbw-pr.GovernorRehearsesTerrier.sh`, which shows who holds what.
- **Federated sign-in fails outright**: descry the active foedus with `tt/rbw-jd.FoedusDescry.sh` — it reports the provider's health under the manor pool, or names the deficit.
- **Tabtarget not found**: Run `tt/rbw-tq.QualifyFast.sh` to check tabtarget and colophon health.
- **Build fails**: Check `tt/rbw-ft.RetrieverTalliesHallmarks.sh` for build status. Review logs in the GCP Console for the depot project.
