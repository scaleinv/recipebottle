## Theurge & Ifrit: Crucible Security Testing

Read this file when working on theurge (test orchestrator), ifrit (attack binary), or crucible test cases. This is Recipe Bottle's internal test infrastructure only — Recipe Bottle does not require users to have Rust compilation tools.

### Architecture

Two Rust binaries with completely different roles and build targets:

- **Theurge** (`Tools/rbk/rbtd/`) — test orchestrator, runs on the **host** (macOS/Linux). Charges a crucible (sentry + pentacle + bottle containers), invokes attacks, observes results, produces verdicts. Built via `tt/rbw-tb.Build.sh`.
- **Ifrit** (`rbev-vessels/common-ifrit-context/`) — attack binary, runs **inside the bottle container**. Probes network security boundaries from the attacker's perspective. Source lives in the shared build context consumed by `rbev-bottle-ifrit-tether` (and the forthcoming airgap variant). Built inside the Docker image during `docker build` — there is no host-side compilation, no cross-compile, no `cargo check` on macOS. The Dockerfile IS the build system.

**Coordinated tests** are the distinctive capability: theurge simultaneously observes from outside (via sentry writ/fiat commands) while ifrit attacks from inside. Neither binary alone can do this.

### Crucible Iteration Loop

The typical development cycle when changing ifrit or theurge code:

#### Iteration strategy: single cases first, full suite last

The full tadmor fixture takes ~10 minutes (charge + 50+ cases + quench). **Do not run it as the first verification step** — whether debugging failures or verifying new code. Instead:

1. Charge the crucible once
2. Run single-case against each new or changed test to verify it passes
3. Run the full fixture only after all targeted cases pass — as a final regression check
4. Quench

This applies to **all** crucible verification: new tests, bug fixes, refactors. The full suite is always the last step, never the first.

#### Full run (charge + all cases + quench in one command)

1. Edit ifrit source (`rbev-vessels/common-ifrit-context/src/`) or theurge source (`Tools/rbk/rbtd/src/`)
2. If ifrit changed: kludge-rebuild the bottle image
   ```
   tt/rbw-cKB.KludgeBottle.sh tadmor
   ```
   This builds a new container image and drives the kludge hallmark into the nameplate's `rbrn.env`.
3. Git commit the hallmark change (kludge dirties `rbrn.env` — a clean working tree is required for charge, and the commit trail maintains audit integrity)
4. Run the full tadmor fixture:
   ```
   tt/rbw-tf.FixtureRun.sh tadmor
   ```
   This charges the crucible, runs all cases, and quenches — one command.

#### Single-case debugging (manual charge/quench lifecycle)

When iterating on a specific failing test case:

1. Charge the crucible (starts containers, leaves them running):
   ```
   tt/rbw-cC.Charge.tadmor.sh
   ```
2. Run individual cases against the live crucible:
   ```
   tt/rbw-tc.FixtureCase.sh tadmor case-name
   ```
   Omit the case name to list all available cases. Omit the fixture name to list all available fixtures.
3. Edit code, rebuild as needed (kludge for ifrit, `tt/rbw-tb.Build.sh` for theurge), re-run the single case. Repeat.
4. Quench when done:
   ```
   tt/rbw-cQ.Quench.tadmor.sh
   ```

#### Ordaining after green

Kludge builds are for rapid local iteration. Once all tests pass with the kludge hallmark, ordain for a production-grade Cloud Build image:

1. Ordain the vessel:
   ```
   tt/rbw-fO.DirectorOrdainsHallmark.sh rbev-bottle-ifrit-tether
   ```
2. Summon the ordained hallmark locally:
   ```
   tt/rbw-fs.RetrieverSummonsHallmark.sh rbev-bottle-ifrit-tether <hallmark>
   ```
3. Drive the ordained hallmark into the nameplate with `tt/rbw-nd.DriveNameplateHallmark.sh tadmor bottle <hallmark>` (or omit `<hallmark>` to chain-read it from the ordain you just ran), commit, and re-run the full fixture to verify.

**Hallmark prefixes** tell you what you have: `k` = kludge (local build), `c` = conjured (Cloud Build ordained).

### Test Cases

Bottle/sentry security cases — shared verbatim by the `tadmor` and `moriah` fixtures (`RBTDRC_CASES_SECURITY` in `rbtdrc_crucible.rs`). The two fixtures differ only in provenance: tadmor runs against a locally-kludged bottle, moriah against the cloud-built airgap bottle. Runtime semantics are identical.

Cases group by purpose in source order (no formal section structure):

- **basic-infra** — smoke tests: pentacle ping, dnsmasq responds
- **ifrit-attacks** — single ifrit attack, verdict from inside only: dns-allowed/blocked, apt blocked
- **observation** — sentry-side observation of bottle behavior: iptables loaded, blocked-with-observation
- **correlated** — theurge resolves on sentry, ifrit attacks with result: tcp443 allow/block, ICMP hop tests
- **sortie-attacks** — multi-step ifrit sorties: DNS exfil, metadata probe, raw socket smuggle
- **unilateral-novel** — ifrit sorties testing novel attack vectors: route manipulation, subnet escape, DNAT reflection
- **coordinated-attacks** — simultaneous attack + observation: ARP gratuitous/poison, table stability
- **coordinated-integrity** — attack then verify sentry state unchanged: sentry integrity, DNS cache integrity, MAC flood

### Reveille-Tier Cases: Credless by Construction

The reveille suite's fixtures carry `credless: true` on their `rbtdre_Fixture` static. While such a fixture runs, every tabtarget Command theurge builds (via `rbtdri_tabtarget_command` — including the direct-Command helpers) carries the credless-guard tweak (`RBCC_tweak_credless_guard` / `RBTDGC_TWEAK_CREDLESS_GUARD`), and both token-mint membranes (`rba_avow`, `zrbgp_authenticate_capture`) reject under it with the credless band code (`BUBC_band_credless` / `RBTDGC_BAND_CREDLESS`) before touching any credential. The guard rides the fixture, not the suite — a reveille fixture hosted in picket/echelon is still guarded.

Rules for authoring a reveille-tier case:

- **A reveille case may invoke any tabtarget freely** — if its chain reaches a token mint, the run dies with the credless band code instead of spending money or mutating the depot. The proof case is `rbtdrf_rs_credless_guard_mint_refusal` (regime-smoke).
- **Fast cases carry no tweaks of their own.** The BURE tweak slot belongs to the guard in the reveille tier (one tweak at a time, and the suite reserves the slot); `rbtdri_invoke*` fails loud if a guarded case supplies `BURE_TWEAK_NAME`. A case that needs a test seam has self-identified as not belonging in reveille — home it in a higher tier.
- **A new reveille fixture must set `credless: true`** and join the reveille suite list in `rbtdrc_crucible.rs`; fixtures in higher tiers set `credless: false`.

### Fixture Config-Evolution Console

A fixture that walks an onboarding or freehold track *evolves* the tracked
config it tests — driving hallmarks into nameplates, electing vessel anchors,
setting regime fields — and commits each step so the next sees a clean tree.
Those write-side actions are a named cohort homed in `rbtdre_engine.rs` (the
"Fixture config-evolution console"), beside the read-side `rbtdre_tree_clean`.
**When a fixture commits config, it goes through the console — never an ad-hoc
`git add`/`git commit`.**

The console commits config in exactly three classes, each through its own
scoped verb that derives its own paths from a class identifier and stages only
those:

| Class | Identifier | Verb | Stages |
|-------|-----------|------|--------|
| nameplate | nameplate moniker(s) | `rbtdre_commit_nameplates` | `<moorings>/<np>/rbrn.env` |
| vessel | vessel dir(s) | `rbtdre_commit_vessels` / `rbtdre_commit_vessels_all` | `<vessel_dir>/rbrv.env` |
| regime | `rbtdre_RegimeFile` tag(s) | `rbtdre_commit_regime` | `<moorings>/rbrd.env` / `<moorings>/rbrr.env` |

The load-bearing property is **no free-form file list**. The only entry that
takes an arbitrary path set, `rbtdre_commit_paths`, is private to the engine
module; every public verb is class-typed. So a fixture is *structurally
incapable* of sweeping a surprise edit — another officium's work, an operator's
half-finished change — into its commit (the wrap-sweeps-everything hazard). A
scoped `git status --porcelain -- <derived-paths>` runs first; if nothing in the
class changed, the commit is a clean no-op, not an error.

**Config-zero** (`rbtdre_config_zero`) is the console's reset seam, for the
marshal-zero family of in-place TRACKED config. Zeroing a field before an
in-place write defeats the stale-value false-green — a silently-skipped write
then leaves an obviously-empty value, not a passing stale one — and its
fail-on-absent doubles as a schema-drift catch: a renamed field stops the run
instead of writing nothing. It shares one validated core
(`rbtdre_config_set_field`) with the vessel-env write; it is **one seam, never a
per-field function farm**. Temp-vessel cases that construct known bytes need no
zero call.

**Dispersed sibling (not yet in the console).** The same validated
field-rewrite still lives in `rbtdrk_replace_env_fields` (the regime multi-field
rewrite). It is a migration candidate — fold it onto `rbtdre_config_set_field`
when next in that code — left in place only to keep the console's introduction
scoped. (The former `rbtdro_drive_hallmark` nameplate-hallmark rewrite is gone:
onboarding now invokes the real `rbw-nd` drive tabtarget, so that write lives in
one bash home, `rbrn_drive`.) New fixture state-mutation helpers land in the
console; they do not re-grow per module.

### Adding a New Test

**New ifrit attack** (simple probe, single command):
1. Add constant, enum variant, `from_selector`/`selector`/`all_selectors` entries in `rbida_attacks.rs`
2. Add dispatch arm in `rbida_run()`
3. Add theurge case function calling `rbtdrc_invoke_ifrit(ctx, "selector-name", dir)`
4. Register in `RBTDRC_CASES_SECURITY` (or the relevant fixture's case array)

**New ifrit sortie** (complex multi-step attack):
1. Add `pub fn sortie_name()` in `rbida_sorties.rs`
2. Add constant, enum variant, and dispatch in `rbida_attacks.rs` (same as above)
3. Add theurge case — sorties may need coordinated observation (writ/fiat before/after)
4. Register in `RBTDRC_CASES_SECURITY` (or the relevant fixture's case array)

**Crucible verification workflow** (applies to all new tests and changes):

1. Build theurge: `tt/rbw-tb.Build.sh` and run unit tests: `tt/rbw-tt.Test.sh`
2. If ifrit source changed: kludge-rebuild, commit hallmark, then charge:
   ```
   tt/rbw-cKB.KludgeBottle.sh tadmor    # builds image, drives hallmark into rbrn.env
   # commit the rbrn.env change (clean tree required for charge)
   tt/rbw-cC.Charge.tadmor.sh
   ```
3. Verify each new/changed case individually against the live crucible:
   ```
   tt/rbw-tc.FixtureCase.sh tadmor rbtdrc_sortie_new_case_name
   ```
4. Only after all targeted cases pass, run the full fixture for regression:
   ```
   tt/rbw-tf.FixtureRun.sh tadmor
   ```
   Note: this charges and quenches internally — quench the manual crucible first if one is active (`tt/rbw-cQ.Quench.tadmor.sh`).
