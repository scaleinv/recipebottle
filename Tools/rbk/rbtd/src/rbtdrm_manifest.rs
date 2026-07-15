// Copyright 2026 Scale Invariant, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Author: Brad Hyslop <bhyslop@scaleinvariant.org>
//
// RBTDRM — colophon manifest verification for theurge

// Colophon names are projected from the zipper registry into the generated
// RBTDGC_* consts (rbtdgc_consts.rs). This module consumes them for the
// per-fixture required-colophon manifest and the role→probe mapping. Colophon
// existence is now enforced by compilation (this map references the generated
// consts directly) plus the build-time diff gate (rbq regenerates and diffs
// the consts against the zipper); the former runtime drift check is retired.
use crate::rbtdgc_consts::*;

// Credential roles are projected from rbcc_constants.sh into the generated
// RBTDGC_ACCOUNT_* consts (rbtdgc_consts.rs) — consumed here and across the access
// probe surface. The former hand-written RBTDRM_ROLE_* mirror is retired.

/// Map a credential role to its access-probe colophon. Returns None for
/// unknown roles. Only the payor OAuth probe survives the keyfile JWT-probe
/// demolition; the governor/director/retriever JWT probes retired with the
/// RBRA estate (their federation persona readiness rides avowal + the
/// mantle don under freehold-establish, not this map).
pub fn rbtdrm_credential_check_colophon(role: &str) -> Option<&'static str> {
    match role {
        RBTDGC_ACCOUNT_PAYOR => Some(RBTDGC_CHECK_PAYOR),
        _ => None,
    }
}

// Fixture name consts — single definition per String Boundary Discipline.
// Crucible fixtures (charge/quench lifecycle)
pub const RBTDRM_FIXTURE_TADMOR: &str = "tadmor";
pub const RBTDRM_FIXTURE_MORIAH: &str = "moriah";
pub const RBTDRM_FIXTURE_SRJCL: &str = "srjcl";
pub const RBTDRM_FIXTURE_PLUML: &str = "pluml";
// Bare fixtures (GCP credentials, no container runtime)
pub const RBTDRM_FIXTURE_HALLMARK_LIFECYCLE: &str = "hallmark-lifecycle";
pub const RBTDRM_FIXTURE_BATCH_VOUCH: &str = "batch-vouch";
pub const RBTDRM_FIXTURE_ACCESS_PROBE: &str = "access-probe";
// Credential-readiness — the standing-freehold readiness leader of the release
// ladders: skirmish/dogfight/blockade run it ahead of any cloud spend, and
// gauntlet re-verifies right after freehold-establish. Espy the sitting
// (fail-fast advisory when absent), a promptless baseline avow (the runway
// gate band-rejects a short sitting with the novate advisory), then don
// director + retriever — the mantles the ladders' inner bodies wield. Restores
// the up-front credential step the keyfile re-enrobe preamble provided before
// the estate demolition; a deficit surfaces in seconds, never minutes into a
// build. Pure consumer of the espy/gate/novate surfaces — no new mechanism.
pub const RBTDRM_FIXTURE_CREDENTIAL_READINESS: &str = "credential-readiness";
// Lode-lifecycle fixture — fetched-side base capture against live GAR:
// ensconce -> divine (enumerate + inspect) -> banish, registry restored.
pub const RBTDRM_FIXTURE_LODE_LIFECYCLE: &str = "lode-lifecycle";
// Reliquary-lifecycle fixture — fetched-side cohort capture against live GAR:
// conclave -> divine (enumerate + inspect members) -> banish, registry restored.
pub const RBTDRM_FIXTURE_RELIQUARY_LIFECYCLE: &str = "reliquary-lifecycle";
// Wsl-lifecycle fixture — fetched-side rootfs capture against live GAR:
// underpin -> divine (enumerate + inspect rootfs member) -> banish, restored.
pub const RBTDRM_FIXTURE_WSL_LIFECYCLE: &str = "wsl-lifecycle";
// Podvm-lifecycle fixture — fetched-side podvm disk-leaf capture against live GAR:
// immure -> divine (cohort) -> augur (members + envelope) -> per-member jettison -> banish, restored.
pub const RBTDRM_FIXTURE_PODVM_LIFECYCLE: &str = "podvm-lifecycle";
// Foedus-lifecycle fixture — federation IdP-trust round-trip against the live org:
// probe payor -> affiance a throwaway pool -> jilt (DELETED) -> re-jilt (no-op).
// Quota-touching (a genuine create cannot reuse a soft-deleted id; soft-deleted
// pools hold the 100-per-org cap ~30 days), so operator-invoked only — registered
// for discovery, a member of no suite. The payor-credential gate fails loud, never
// skips: this fixture is never a suite passenger (see the pace docket).
pub const RBTDRM_FIXTURE_FOEDUS_LIFECYCLE: &str = "foedus-lifecycle";
// Foedus-reuse fixture — the standing-freehold REUSE credential leg the release
// ladders (skirmish/dogfight/blockade) assume but no fixture established. Probes
// the standing foedus (descry), reuses it cap-flat when healthy (affiance only on
// check-failure), re-points the selector (instate), then heals the credentials
// (avow + don governor/director/retriever). No pool churn on the reuse path, so —
// unlike foedus-lifecycle — it is quota-neutral; still operator-invoked (human-
// present avow, live mantle dons), a member of no suite, payor-gate fails loud.
pub const RBTDRM_FIXTURE_FOEDUS_REUSE: &str = "foedus-reuse";
// Polity-denial fixture — proves the polity verbs reject with the exact precision
// band across their failure surface. Admission arc: a governor-wielded verb's don is
// refused when the citizen is not brevetted onto the mantle (RBTDGC_BAND_ADMISSION) —
// don retriever (baseline) -> unseat retriever -> poll the don to the admission band
// -> isolation (held mantles still reach AR) -> brevet back -> poll positive (restore).
// Terrier-band arc (the regime-poison analogue for HTTP, folded in to supersede the
// retired interim terrier-atomicity rbw-dT proof): the same real verbs under the rbuh
// http-fault seam reject in the engross/expunge/peruse bands (brevet/unseat/rehearse),
// on a synthetic subject with pre-clean + final sweep. Picket-suite member; self-skips
// when the payor credential is unreachable (suite-passenger protection).
pub const RBTDRM_FIXTURE_POLITY_DENIAL: &str = "polity-denial";
// Parley fixture — the POSITIVE federation admission round-trip (the positive mirror
// of polity-denial, which owns every rejection-band assertion). Drives the real
// polity verbs against the REAL freehold subject: baseline rehearse (muniment stands)
// -> unseat retriever -> rehearse (muniment vanishes) -> restore-brevet -> rehearse
// (muniment stands again) -> poll the retriever don green, leaving the freehold as
// found. The novel content is rehearse's POSITIVE manor-roll assertions (asserted
// nowhere else). Picket-suite member (and its own base-free probe suite); self-skips
// when the payor credential is unreachable (suite-passenger protection).
pub const RBTDRM_FIXTURE_PARLEY: &str = "parley";
// Reveille fixtures (no external dependencies)
pub const RBTDRM_FIXTURE_ENROLLMENT_VALIDATION: &str = "enrollment-validation";
pub const RBTDRM_FIXTURE_RECIPE_VALIDATION: &str = "recipe-validation";
pub const RBTDRM_FIXTURE_REGIME_VALIDATION: &str = "regime-validation";
pub const RBTDRM_FIXTURE_REGIME_SMOKE: &str = "regime-smoke";
// Regime-poison — in-universe negatives. Drives the real validate verbs against
// real (in-tree or staged) regimes with one field corrupted via the
// regime-poison tweak, asserting the specific band code of the gate that fires.
// NOT credless: the tweak slot carries the per-case poison, so this fixture
// cannot ride reveille (whose slot belongs to the credless guard) — it enrolls in
// picket/bivouac/echelon instead.
pub const RBTDRM_FIXTURE_REGIME_POISON: &str = "regime-poison";
pub const RBTDRM_FIXTURE_HANDBOOK_RENDER: &str = "handbook-render";
pub const RBTDRM_FIXTURE_DOCKERFILE_HYGIENE: &str = "dockerfile-hygiene";
// Conformance — vocabulary-eviction static analysis over Tools/ and tt/. No
// external dependency; the standing home for evicted-term assertions (ACG).
pub const RBTDRM_FIXTURE_CONFORMANCE: &str = "conformance";
// Foundry-path — buc_native_path_capture Cygwin /cygdrive normalizer. No
// external dependency; pure bash-function unit test sourced direct (no kindle).
pub const RBTDRM_FIXTURE_FOUNDRY_PATH: &str = "foundry-path";
// Clipboard — buc_clipboard_copy_predicate platform normalizer (BUK footing,
// foundry-path sibling). Credless, but roster-only (member of no suite): the
// round-trip case reads and mutates the live desktop clipboard via arboard
// (read capability deliberately confined to this test binary — never on the
// shipped bash surface), with save/restore best-effort. Operator-invoked via
// FixtureRun; the no-tool decline case is deterministic everywhere.
pub const RBTDRM_FIXTURE_CLIPBOARD: &str = "clipboard";
// Podvm-resolve — host-side zrbld_immure_resolve_family brand mapping. No GCP
// creds or container runtime required; invokes the presage colophon (rbw-lp),
// the read-only dry-run verb that resolves a family and reports what immure
// would capture, expecting exit 0 with a brand-mapping-line assertion.
pub const RBTDRM_FIXTURE_PODVM_RESOLVE: &str = "podvm-resolve";
// Chaining-fact-band — the band matrix for the durable-config chain LINKS (feoff,
// yoke). Drives the real verbs through the exec path against a staged temp
// vessel + a seeded previous/ fact, asserting the specific chain-rejection band
// on wrong-kind / unknown-prefix / broken chain, the good election, express-
// beats-chain precedence, and fact-intact (rejection precedes any write). The
// band fires only at the RBK consumer, so this is the home the footing (BUK)
// self-test cannot reach. Credless — nothing here mints a token.
pub const RBTDRM_FIXTURE_CHAINING_FACT_BAND: &str = "chaining-fact-band";
// Chaining-fact-livery — the cloud sibling of the local chaining-fact-band
// matrix. Proves the GENUINE producer->consumer succession: a real bole ensconce
// captures into live GAR and hands its touchmark forward, the chain wires it to a
// real feoff, and feoff elects the base anchor into a STAGED TEMP vessel (no
// tracked config, no commit). Catches drift between what a live ensconce writes
// and what a live feoff reads — which the synthetic band matrix cannot. Service
// tier; the touchmark is pinned via the ensconce-stamp tweak for a stable reset
// handle, and the case self-contains a banish-if-present baseline + best-effort
// cleanup (no setup hook — that channel is the crucible-charge signal).
pub const RBTDRM_FIXTURE_CHAINING_LIVERY: &str = "chaining-fact-livery";
// Cupel — BCG command-dependency static analysis over all Tools/ bash. No
// external dependency; partitions kit-bash (strict) from GCB-bash (looser).
pub const RBTDRM_FIXTURE_CUPEL: &str = "cupel";
// Pyx — release-hygiene tree-invariants: crate-license allowlist over the
// committed Cargo.lock, root LICENSE presence, a curated secret-shape scan over
// the shipping roots, and the handbook-anchor check against README. No external
// dependency; every root is existence-tolerant so the checks hold on the
// stripped candidate tree as well as on main.
pub const RBTDRM_FIXTURE_PYX: &str = "pyx";

// Loupe — the veil-leak case evicted from pyx: no shipping file may name what
// the distribution withholds, by veiled-directory path or by the basename of any
// withheld document. SOURCE-TREE ONLY — it harvests its needle set from the
// veiled trees themselves, so unlike pyx's other cases it is never re-run on the
// stripped candidate, where those trees are gone and the census would be empty
// by construction. No external dependency.
pub const RBTDRM_FIXTURE_LOUPE: &str = "loupe";

/// damnatio — the delivered-tree identity assay. A member of no suite: every case
/// is true only of a stripped, lustrated candidate, so it is red by construction
/// against the maintainer's working tree. The release ceremony invokes it by name.
pub const RBTDRM_FIXTURE_DAMNATIO: &str = "damnatio";

/// perambulation — the ship/withhold judgment over every tracked path is TOTAL,
/// and the object-graph sweep that enforces it catches a planted leak. Named for
/// the manorial walking of the bounds: the act that fixes what lies within the
/// delivered estate and what lies without, and which by its nature must close.
/// A member of no suite, for loupe's reason: the delivered tree tracks only the
/// shipped paths, so every withhold row would go dead in a consumer's hands. The
/// maintainer's assay of the maintainer's tree — expede refuses to cut while it
/// is red.
pub const RBTDRM_FIXTURE_PERAMBULATION: &str = "perambulation";
// Depot-lifecycle fixture (marshal-zero gate + ephemeral create→destroy arc).
// Shares the freehold scheme with the durable fixtures; tears down only the
// fresh leasehold it mints, never the standing freehold.
pub const RBTDRM_FIXTURE_DEPOT_LIFECYCLE: &str = "depot-lifecycle";
// Gauntlet freehold-establish fixture (§2: freehold ensure (reuse-or-levy) +
// federation-persona admission — avow, gird, brevet+don director/retriever,
// recognosce — with per-case precondition probes)
pub const RBTDRM_FIXTURE_FREEHOLD_ESTABLISH: &str = "freehold-establish";
// Freehold-churn fixture — the deliberate teardown of the standing freehold
// (rotate moniker off the live project, then unmake) that makes room for a fresh
// levy. Member of no suite; operator-invoked, like the lifecycle round-trips.
pub const RBTDRM_FIXTURE_FREEHOLD_CHURN: &str = "freehold-churn";
// Gauntlet onboarding-sequence fixture (§3: handbook-walked vessel
// construction — conclave reliquary, ensconce bases, kludge tadmor/ccyolo,
// plus one ordain-* case per director-mode handbook track, build-only)
pub const RBTDRM_FIXTURE_ONBOARDING_SEQUENCE: &str = "onboarding-sequence";
// Self-contained tadmor build fixture (rbw-ts.TestSuite.tadmor): kludges tadmor sentry+bottle
// locally and commits each hallmark (so the subsequent tadmor crucible fixture
// charges against a clean nameplate). Reuses onboarding's kludge helper minus
// its reliquary-touchmark witness probe — local kludge has no GCP/reliquary dep.
pub const RBTDRM_FIXTURE_KLUDGE_TADMOR: &str = "kludge-tadmor";
// Dogfight cloud-build viability fixture — runs against a standing
// operator-levied depot, proving the cloud-build → summon → run path yields a
// runnable artifact with NO crucible charged (the orthogonal axis skirmish
// covers). Ordains conjure-mode busybox, summons it, runs a degenerate
// container-runtime command proving executability, then abjures.
pub const RBTDRM_FIXTURE_DOGFIGHT: &str = "dogfight";
// Calibrant fixtures — synthetic deterministic-verdict fixtures, the test
// subjects the touchstone surface fixture spawns as child rbtd runs. Internal
// framework-test plumbing.
pub const RBTDRM_FIXTURE_CALIBRANT_VERDICTS: &str = "calibrant-verdicts";
pub const RBTDRM_FIXTURE_CALIBRANT_FAIL_FAST: &str = "calibrant-fail-fast";
pub const RBTDRM_FIXTURE_CALIBRANT_PROGRESSING: &str = "calibrant-progressing";
pub const RBTDRM_FIXTURE_CALIBRANT_SENTINEL: &str = "calibrant-sentinel";
// Calibrant coverage fixtures — prove the colophon census enforcement lands
// its diagnostics against the synthetic RBTDGC_THEURGE_NIHIL colophon:
// aligned declares+invokes (Pass), undeclared invokes without declaring
// (fixture FAILs via the positive check), unused declares without invoking
// (fixture FAILs via the negative check). Roster-only, driven by the
// touchstone surface fixture's coverage cases, never by any suite.
pub const RBTDRM_FIXTURE_CALIBRANT_COVERAGE_ALIGNED: &str = "calibrant-coverage-aligned";
pub const RBTDRM_FIXTURE_CALIBRANT_COVERAGE_UNDECLARED: &str = "calibrant-coverage-undeclared";
pub const RBTDRM_FIXTURE_CALIBRANT_COVERAGE_UNUSED: &str = "calibrant-coverage-unused";
// Touchstone — the surface fixture: theurge certifying its own operator
// surface. A reveille member whose cases spawn child rbtd runs through the
// real tabtarget chain against the deliberately-failing calibrant fixtures,
// asserting the child's exit code, diagnostic shape on the operator-visible
// stream, and sentinel/trace files. The watcher passes; the watched calibrant
// fixtures stay out of every dependency-tier and release suite.
pub const RBTDRM_FIXTURE_TOUCHSTONE: &str = "touchstone";

// Operation verbs and container roles are generated as RBTDGC_VERB_* and
// RBTDGC_CONTAINER_* (rbtdgc_consts.rs) from their canonical bash home in
// rbcc_constants.sh; consumers source those directly. Compound operations like
// "kludge sentry" are composed at the call site from RBTDGC_VERB_KLUDGE and the
// relevant RBTDGC_CONTAINER_* constant.

/// Per-fixture required colophons. Returns None for unknown fixtures.
pub fn rbtdrm_required_colophons(fixture: &str) -> Option<&'static [&'static str]> {
    match fixture {
        // The security-case crucibles: both fixtures run RBTDRC_CASES_SECURITY,
        // which execs into sentry (writ) and pentacle (fiat) and drives the
        // ifrit from the bottle (bark).
        RBTDRM_FIXTURE_TADMOR | RBTDRM_FIXTURE_MORIAH => Some(&[
            RBTDGC_CRUCIBLE_CHARGE,
            RBTDGC_CRUCIBLE_QUENCH,
            RBTDGC_CRUCIBLE_WRIT,
            RBTDGC_CRUCIBLE_FIAT,
            RBTDGC_CRUCIBLE_BARK,
            RBTDGC_CRUCIBLE_ACTIVE,
        ]),
        // srjcl reaches the bottle to probe jupyter, but never execs into
        // sentry or pentacle.
        RBTDRM_FIXTURE_SRJCL => Some(&[
            RBTDGC_CRUCIBLE_CHARGE,
            RBTDGC_CRUCIBLE_QUENCH,
            RBTDGC_CRUCIBLE_BARK,
            RBTDGC_CRUCIBLE_ACTIVE,
        ]),
        // pluml drives the rendering server over host-side HTTP alone; charge
        // and quench (with their active assertions) are its whole colophon
        // surface.
        RBTDRM_FIXTURE_PLUML => Some(&[
            RBTDGC_CRUCIBLE_CHARGE,
            RBTDGC_CRUCIBLE_QUENCH,
            RBTDGC_CRUCIBLE_ACTIVE,
        ]),
        RBTDRM_FIXTURE_HALLMARK_LIFECYCLE => Some(&[
            RBTDGC_ORDAIN_HALLMARK,
            RBTDGC_ABJURE_HALLMARK,
            RBTDGC_REKON_HALLMARK,
            RBTDGC_AUDIT_HALLMARKS,
            RBTDGC_SUMMON_HALLMARK,
            RBTDGC_PLUMB_FULL,
        ]),
        RBTDRM_FIXTURE_LODE_LIFECYCLE => Some(&[
            RBTDGC_ENSCONCE_BOLE,
            RBTDGC_DIVINE_LODES,
            RBTDGC_AUGUR_LODE,
            RBTDGC_BANISH_LODE,
        ]),
        RBTDRM_FIXTURE_RELIQUARY_LIFECYCLE => Some(&[
            RBTDGC_CONCLAVE_RELIQUARY,
            RBTDGC_DIVINE_LODES,
            RBTDGC_AUGUR_LODE,
            RBTDGC_LIST_IMAGES,
            RBTDGC_JETTISON_IMAGE,
            RBTDGC_BANISH_LODE,
        ]),
        RBTDRM_FIXTURE_WSL_LIFECYCLE => Some(&[
            RBTDGC_UNDERPIN_WSL,
            RBTDGC_DIVINE_LODES,
            RBTDGC_AUGUR_LODE,
            RBTDGC_BANISH_LODE,
        ]),
        RBTDRM_FIXTURE_PODVM_LIFECYCLE => Some(&[
            RBTDGC_IMMURE_PODVM,
            RBTDGC_DIVINE_LODES,
            RBTDGC_AUGUR_LODE,
            RBTDGC_LIST_IMAGES,
            RBTDGC_JETTISON_IMAGE,
            RBTDGC_BANISH_LODE,
        ]),
        RBTDRM_FIXTURE_FOEDUS_LIFECYCLE => Some(&[
            RBTDGC_CHECK_PAYOR,
            RBTDGC_AFFIANCE_MANOR,
            RBTDGC_CANVASS_FOEDUS,
            RBTDGC_JILT_MANOR,
        ]),
        RBTDRM_FIXTURE_FOEDUS_REUSE => Some(&[
            RBTDGC_CHECK_PAYOR,
            RBTDGC_DESCRY_FOEDUS,
            RBTDGC_INSTATE_FOEDUS,
            RBTDGC_CHECK_AVOWAL,
            RBTDGC_CHECK_MANTLE,
        ]),
        RBTDRM_FIXTURE_POLITY_DENIAL => Some(&[
            RBTDGC_CHECK_PAYOR,
            RBTDGC_CHECK_MANTLE,
            RBTDGC_UNSEAT_POLITY,
            RBTDGC_BREVET_POLITY,
            RBTDGC_REHEARSE_POLITY,
        ]),
        RBTDRM_FIXTURE_PARLEY => Some(&[
            RBTDGC_CHECK_PAYOR,
            RBTDGC_CHECK_MANTLE,
            RBTDGC_UNSEAT_POLITY,
            RBTDGC_BREVET_POLITY,
            RBTDGC_REHEARSE_POLITY,
        ]),
        RBTDRM_FIXTURE_BATCH_VOUCH => Some(&[
            RBTDGC_ORDAIN_HALLMARK,
            RBTDGC_ABJURE_HALLMARK,
            RBTDGC_JETTISON_HALLMARK_IMAGE,
            RBTDGC_VOUCH_HALLMARKS,
            RBTDGC_TALLY_HALLMARKS,
        ]),
        RBTDRM_FIXTURE_ACCESS_PROBE => Some(&[
            RBTDGC_CHECK_PAYOR,
            RBTDGC_CHECK_AVOWAL,
            RBTDGC_ESPY_SITTING,
        ]),
        RBTDRM_FIXTURE_CREDENTIAL_READINESS => Some(&[
            RBTDGC_ESPY_SITTING,
            RBTDGC_CHECK_AVOWAL,
            RBTDGC_CHECK_MANTLE,
        ]),
        RBTDRM_FIXTURE_ENROLLMENT_VALIDATION
        | RBTDRM_FIXTURE_RECIPE_VALIDATION
        | RBTDRM_FIXTURE_REGIME_VALIDATION
        | RBTDRM_FIXTURE_REGIME_SMOKE
        | RBTDRM_FIXTURE_FOUNDRY_PATH
        | RBTDRM_FIXTURE_CLIPBOARD
        | RBTDRM_FIXTURE_CUPEL
        | RBTDRM_FIXTURE_PYX
        | RBTDRM_FIXTURE_LOUPE
        | RBTDRM_FIXTURE_DAMNATIO
        | RBTDRM_FIXTURE_CONFORMANCE
        | RBTDRM_FIXTURE_CALIBRANT_VERDICTS
        | RBTDRM_FIXTURE_CALIBRANT_FAIL_FAST
        | RBTDRM_FIXTURE_CALIBRANT_PROGRESSING
        | RBTDRM_FIXTURE_CALIBRANT_SENTINEL => Some(&[]),
        // DELIBERATELY EMPTY — do not "repair" by adding RBTDGC_THEURGE_NIHIL.
        // The arm above is empty because those fixtures invoke nothing; this one
        // is empty though its case DOES invoke nihil, which is the whole point:
        // the mismatch is what trips the positive census check, and the
        // fixture's expected verdict is FAIL. Declaring the colophon here would
        // turn the fixture green and silently delete the test.
        RBTDRM_FIXTURE_CALIBRANT_COVERAGE_UNDECLARED => Some(&[]),
        RBTDRM_FIXTURE_CALIBRANT_COVERAGE_ALIGNED | RBTDRM_FIXTURE_CALIBRANT_COVERAGE_UNUSED => {
            Some(&[RBTDGC_THEURGE_NIHIL])
        }
        RBTDRM_FIXTURE_PODVM_RESOLVE => Some(&[
            RBTDGC_PRESAGE_IMMURE,
        ]),
        // touchstone drives the theurge's own runner tabtargets — its children
        // are rbtd invocations of the fixture, suite, and single-case runners.
        RBTDRM_FIXTURE_TOUCHSTONE => Some(&[
            RBTDGC_THEURGE_FIXTURE,
            RBTDGC_THEURGE_SUITE,
            RBTDGC_THEURGE_CASE,
        ]),
        RBTDRM_FIXTURE_DOCKERFILE_HYGIENE => Some(&[
            RBTDGC_HYGIENE_CHECK_DOCKERFILE,
            RBTDGC_HYGIENE_CHECK_VESSEL,
        ]),
        RBTDRM_FIXTURE_DEPOT_LIFECYCLE => Some(&[
            RBTDGC_LEVY_DEPOT,
            RBTDGC_LIST_DEPOT,
            RBTDGC_UNMAKE_DEPOT,
        ]),
        RBTDRM_FIXTURE_FREEHOLD_ESTABLISH => Some(&[
            RBTDGC_LIST_DEPOT,
            RBTDGC_RECOGNOSCE_DEPOT,
            RBTDGC_CHECK_AVOWAL,
            RBTDGC_GIRD_POLITY,
            RBTDGC_BREVET_POLITY,
            RBTDGC_CHECK_MANTLE,
        ]),
        RBTDRM_FIXTURE_FREEHOLD_CHURN => Some(&[
            RBTDGC_UNMAKE_DEPOT,
            RBTDGC_LIST_DEPOT,
        ]),
        // kludge-tadmor builds both vessels locally; only the two kludge
        // colophons are exercised (no charge/credential colophons here).
        RBTDRM_FIXTURE_KLUDGE_TADMOR => Some(&[
            RBTDGC_CRUCIBLE_KLUDGE_SENTRY,
            RBTDGC_CRUCIBLE_KLUDGE_BOTTLE,
        ]),
        // dogfight ordains/summons/abjures a single conjure-mode hallmark; the
        // bare container-runtime run is shelled directly, not via a colophon.
        RBTDRM_FIXTURE_DOGFIGHT => Some(&[
            RBTDGC_ORDAIN_HALLMARK,
            RBTDGC_SUMMON_HALLMARK,
            RBTDGC_ABJURE_HALLMARK,
        ]),
        RBTDRM_FIXTURE_ONBOARDING_SEQUENCE => Some(&[
            RBTDGC_CONCLAVE_RELIQUARY,
            RBTDGC_YOKE_RELIQUARY,
            RBTDGC_ENSCONCE_BOLE,
            RBTDGC_FEOFF_BOLE,
            RBTDGC_ORDAIN_HALLMARK,
            RBTDGC_ANOINT_GRAFT,
            RBTDGC_DRIVE_HALLMARK,
            RBTDGC_CRUCIBLE_KLUDGE_SENTRY,
            RBTDGC_CRUCIBLE_KLUDGE_BOTTLE,
            RBTDGC_WREST_HALLMARK_IMAGE,
            RBTDGC_SUMMON_HALLMARK,
            RBTDGC_PLUMB_FULL,
            RBTDGC_PLUMB_COMPACT,
            RBTDGC_REKON_HALLMARK,
            RBTDGC_JETTISON_HALLMARK_IMAGE,
            RBTDGC_ABJURE_HALLMARK,
        ]),
        RBTDRM_FIXTURE_HANDBOOK_RENDER => Some(&[
            RBTDGC_ONBOARD_START_HERE,
            RBTDGC_ONBOARD_CRASH_COURSE,
            RBTDGC_ONBOARD_FIRST_CRUCIBLE,
            RBTDGC_ONBOARD_DIR_FIRST_BUILD,
            RBTDGC_ONBOARD_PAYOR_HB,
            RBTDGC_PAYOR_ESTABLISH,
            RBTDGC_QUOTA_BUILD,
        ]),
        // Chaining-fact-band drives every band case through a per-verb funnel
        // (feoff/yoke/anoint/nameplate) or the shared readside funnel
        // (summon/plumb/augur/rekon); each of the 8 colophons below fires
        // unconditionally in at least one case, so none are permitted-only.
        RBTDRM_FIXTURE_CHAINING_FACT_BAND => Some(&[
            RBTDGC_FEOFF_BOLE,
            RBTDGC_YOKE_RELIQUARY,
            RBTDGC_ANOINT_GRAFT,
            RBTDGC_DRIVE_HALLMARK,
            RBTDGC_SUMMON_HALLMARK,
            RBTDGC_PLUMB_FULL,
            RBTDGC_AUGUR_LODE,
            RBTDGC_REKON_HALLMARK,
        ]),
        // Chaining-fact-livery's producer->consumer arc (ensconce -> feoff)
        // and the reset's divine both fire every run; banish is the
        // banish-if-present cleanup, declared permitted below.
        RBTDRM_FIXTURE_CHAINING_LIVERY => Some(&[
            RBTDGC_DIVINE_LODES,
            RBTDGC_ENSCONCE_BOLE,
            RBTDGC_FEOFF_BOLE,
        ]),
        // Every regime-poison case launches its validate colophon, so all eight
        // are required — the operator-local pair (oauth, station tincture)
        // included. Their self-skip elides only the POISONED invocation: the
        // un-poisoned baseline probe launches first and unconditionally, and
        // the census records at the launch (rbtdri_tabtarget_command), so
        // neither can ever go unused. On a station where those regimes are
        // absent the case skips, and a skipped case suppresses the negative
        // check outright — so requiring them cannot false-fail there either.
        RBTDRM_FIXTURE_REGIME_POISON => Some(&[
            RBTDGC_VALIDATE_REPO,
            RBTDGC_VALIDATE_DEPOT,
            RBTDGC_VALIDATE_PAYOR,
            BUWGC_RC_VALIDATE,
            RBTDGC_VALIDATE_NAMEPLATE,
            RBTDGC_VALIDATE_VESSEL,
            RBTDGC_VALIDATE_OAUTH,
            BUWGC_RS_VALIDATE,
        ]),
        _ => None,
    }
}

/// Per-fixture permitted colophons — the positive-only census tier. Admitted
/// at the invoke chokepoint exactly like a required colophon, but never
/// demanded by the negative (post-fixture) check: a permitted colophon may go
/// unused on a healthy run without failing the fixture. Defaults to empty for
/// every fixture not listed here. Reserved for invocations that are
/// conditional by design — a fixture whose real-world path only sometimes
/// reaches a colophon (e.g. reuse-vs-mint branches).
pub fn rbtdrm_permitted_colophons(fixture: &str) -> &'static [&'static str] {
    match fixture {
        // Affiance fires only on a descry deficit — the healthy reuse path
        // never reaches it, so it cannot be required.
        RBTDRM_FIXTURE_FOEDUS_REUSE => &[RBTDGC_AFFIANCE_MANOR],
        // Levy fires only when the standing freehold is absent — the healthy
        // reuse path never reaches it, so it cannot be required.
        RBTDRM_FIXTURE_FREEHOLD_ESTABLISH => &[RBTDGC_LEVY_DEPOT],
        // Banish fires only when the reset's divine finds the pinned
        // touchmark already present — the steady-state pass never reaches it.
        RBTDRM_FIXTURE_CHAINING_LIVERY => &[RBTDGC_BANISH_LODE],
        _ => &[],
    }
}

