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
// RBTDRO — gauntlet onboarding-sequence fixture (§3 of release qualification)
//
// Each case walks the operator-facing onboarding handbook track for one
// vessel-construction mode, invoking the handbook's prescribed tabtargets
// in the prescribed order. Case order and per-case docs live with the
// functions below; the registered order is the source of truth (see the
// `RBTDRO_CASES_ONBOARDING_SEQUENCE` array).
//
// Disposition: StateProgressing. Build-only — no charge, no test. Cases stop
// when each handbook-prescribed hallmark lands in GAR. Per-case precondition
// probes enable a-la-carte single-case rerun.
//
// conclave_reliquary yokes the reliquary touchmark into vessel rbrv.env files
// and commits. Downstream cases verify it ran by reading RBRV_RELIQUARY from
// a stable yoked vessel's rbrv.env — no out-of-source-tree scratch state.

use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};

use crate::case;
use crate::rbtdrb_probe::{rbtdrb_assert, rbtdrb_Probe};
use crate::rbtdrc_crucible::rbtdrc_with_ctx;
use crate::rbtdrv_patrol::{
    rbtdrv_docker_inspect, rbtdrv_docker_layers_capture, rbtdrv_docker_rmi,
    rbtdrv_rekon_basename_yes, RBTDRV_ARK_BASENAME_ABOUT,
    RBTDRV_ARK_BASENAME_ATTEST, RBTDRV_ARK_BASENAME_IMAGE, RBTDRV_ARK_BASENAME_POUCH,
    RBTDRV_ARK_BASENAME_VOUCH, RBTDRV_GAR_CATEGORY_HALLMARKS,
};
use crate::rbtdre_engine::{
    rbtdre_Tariff,
    rbtdre_commit_nameplates, rbtdre_commit_vessels, rbtdre_commit_vessels_all,
    rbtdre_config_set_field, rbtdre_Case, rbtdre_Disposition, rbtdre_Fixture, rbtdre_Verdict,
};
use crate::rbtdri_invocation::{
    rbtdri_gar_ref_categorical, rbtdri_gar_ref_fact, rbtdri_invoke_or_fail, rbtdri_ordain_capture,
    rbtdri_ordain_capture_full, rbtdri_read_burv_fact, rbtdri_Context, RBTDRI_BURE_CONFIRM_KEY,
    RBTDRI_BURE_CONFIRM_SKIP,
};
use crate::rbtdgc_consts::{
    RBTDGC_ABJURE_HALLMARK,
    RBTDGC_ANOINT_GRAFT,
    RBTDGC_CONTAINER_BOTTLE,
    RBTDGC_CONTAINER_SENTRY,
    RBTDGC_CRUCIBLE_KLUDGE_BOTTLE,
    RBTDGC_CRUCIBLE_KLUDGE_SENTRY,
    RBTDGC_DRIVE_HALLMARK,
    RBTDGC_ENSCONCE_BOLE,
    RBTDGC_CONCLAVE_RELIQUARY,
    RBTDGC_FEOFF_BOLE,
    RBTDGC_JETTISON_HALLMARK_IMAGE,
    RBTDGC_PLUMB_COMPACT,
    RBTDGC_PLUMB_FULL,
    RBTDGC_RBRV_FILE,
    RBTDGC_REKON_HALLMARK,
    RBTDGC_SUMMON_HALLMARK,
    RBTDGC_VERB_ANOINT,
    RBTDGC_VERB_DRIVE,
    RBTDGC_VERB_KLUDGE,
    RBTDGC_VERB_YOKE,
    RBTDGC_WREST_HALLMARK_IMAGE,
    RBTDGC_YOKE_RELIQUARY,
};
use crate::rbtdrm_manifest::{
    RBTDRM_FIXTURE_KLUDGE_TADMOR,
    RBTDRM_FIXTURE_ONBOARDING_SEQUENCE,
};

// ── Vessel directories ────────────────────────────────────────

// Vessel dirs composed from the crate-canonical vessels dir (single source).
const RBTDRO_VESSEL_DIR_SENTRY_TETHER: &str = concat!(crate::rbtd_vessels_dir!(), "/rbev-sentry-deb-tether");
const RBTDRO_VESSEL_DIR_AIRGAP_FORGE: &str = concat!(crate::rbtd_vessels_dir!(), "/rbev-bottle-ifrit-forge");
const RBTDRO_VESSEL_DIR_AIRGAP_BOTTLE: &str = concat!(crate::rbtd_vessels_dir!(), "/rbev-bottle-ifrit-airgap");
const RBTDRO_VESSEL_DIR_PLANTUML: &str = concat!(crate::rbtd_vessels_dir!(), "/rbev-bottle-plantuml");
const RBTDRO_VESSEL_DIR_JUPYTER: &str = concat!(crate::rbtd_vessels_dir!(), "/rbev-bottle-anthropic-jupyter");
const RBTDRO_VESSEL_DIR_GRAFT: &str = concat!(crate::rbtd_vessels_dir!(), "/rbev-graft-demo");

// ── Nameplate monikers ────────────────────────────────────────

const RBTDRO_NAMEPLATE_TADMOR: &str = "tadmor";
const RBTDRO_NAMEPLATE_CCYOLO: &str = "ccyolo";
const RBTDRO_NAMEPLATE_MORIAH: &str = "moriah";
const RBTDRO_NAMEPLATE_SRJCL: &str = "srjcl";
const RBTDRO_NAMEPLATE_PLUML: &str = "pluml";

// ── Consumer arrays ───────────────────────────────────────────

/// Nameplates that receive the sentry-tether hallmark from ordain-conjure.
const RBTDRO_CONSUMERS_SENTRY_TETHER: &[&str] = &[
    RBTDRO_NAMEPLATE_MORIAH,
    RBTDRO_NAMEPLATE_SRJCL,
    RBTDRO_NAMEPLATE_PLUML,
];

/// Nameplates that receive the airgap-bottle hallmark from ordain-airgap.
const RBTDRO_CONSUMERS_AIRGAP_BOTTLE: &[&str] = &[RBTDRO_NAMEPLATE_MORIAH];

/// Nameplates that receive the plantuml-bottle hallmark from ordain-bind.
const RBTDRO_CONSUMERS_PLANTUML_BOTTLE: &[&str] = &[RBTDRO_NAMEPLATE_PLUML];

/// Nameplates that receive the jupyter-bottle hallmark from conjure-srjcl.
const RBTDRO_CONSUMERS_JUPYTER_BOTTLE: &[&str] = &[RBTDRO_NAMEPLATE_SRJCL];

// ── Hallmark-base locator construction ───────────────────────
//
// Used to compose the airgap-bottle's RBRV_IMAGE_1_ANCHOR after the forge
// hallmark is captured. Orchestration writes a hallmark-namespace locator
// directly into the consumer vessel's rbrv.env; conjure resolves the locator
// at airgap-bottle build time. The forge hallmark's existence in GAR is
// established by ordain-forge's success — no separate base-capture validation
// step on the consumer.

/// Slot 1 of the airgap-bottle vessel — the only base-image slot the airgap
/// supply chain populates from a hallmark.
const RBTDRO_AIRGAP_BASE_ANCHOR_VAR: &str = "RBRV_IMAGE_1_ANCHOR";

// ── Bole feoff election witness ───────────────────────
//
// The forge vessel is conjure mode with exactly one populated ORIGIN slot
// (RBRV_IMAGE_1_ORIGIN), so the ensconce->feoff chain's election rewrites
// RBRV_IMAGE_1_ANCHOR to the captured Lode locator. These mirror
// rbgc_constants.sh (RBGC_GAR_CATEGORY_LODES / RBGC_LODE_TAG_BOLE) and
// rbflf_feoff.sh's `${RBGL_LODES_ROOT}/${touchmark}:${tag}`
// locator shape, so the fixture can assert feoff fired against a fresh
// touchmark rather than leaving the prior committed anchor in place.

/// Forge-vessel slot feoff rewrites (its single ORIGIN slot).
const RBTDRO_FORGE_BASE_ANCHOR_VAR: &str = "RBRV_IMAGE_1_ANCHOR";

/// Bole touchmark chaining fact ensconce writes to current/. Mirrors
/// rbgc_constants.sh RBF_FACT_LODE_TOUCHMARK.
const RBTDRO_FACT_LODE_TOUCHMARK: &str = "rbf_fact_lode_touchmark";

/// GAR Lode namespace root in an elected anchor locator. Mirrors
/// rbgc_constants.sh RBGC_GAR_CATEGORY_LODES.
const RBTDRO_LODE_ROOT: &str = "rbi_ld";

/// Bole member tag in an elected anchor locator. Mirrors rbgc_constants.sh
/// RBGC_LODE_TAG_BOLE.
const RBTDRO_LODE_TAG_BOLE: &str = "rbi_bole";

// ── Reliquary touchmark witness ──────────────────────────────────

/// Field name yoked by case 1 in each vessel rbrv.env. Presence (non-empty)
/// is the cross-case witness that case 1 ran.
const RBTDRO_FIELD_RBRV_RELIQUARY: &str = "RBRV_RELIQUARY";

/// Stable vessel chosen for the case-1 witness probe. Yoke is wildcard-
/// fan-out across every vessel under ${RBRR_VESSEL_DIR}; sentry-tether is a
/// guaranteed-present member of that set, so its rbrv.env always carries
/// the touchmark after case 1.
const RBTDRO_WITNESS_VESSEL_DIR: &str = RBTDRO_VESSEL_DIR_SENTRY_TETHER;

// ── Graft anoint witness ─────────────────────────────────────

/// Field the ccyolo kludge case's anoint chain writes into the graft vessel's
/// rbrv.env; the ordain-graft case reads the committed value back as its
/// image source. Presence of a tagged ref is the cross-case witness.
const RBTDRO_FIELD_RBRV_GRAFT_IMAGE: &str = "RBRV_GRAFT_IMAGE";

// ── Probes ───────────────────────────────────────────────────
//
// Probes are pure `fn() -> Result<(), String>` per the rbtdrb_Probe shape and
// have no context, so they read the project root from current_dir() — theurge
// always launches from the project root.

fn rbtdro_probe_root() -> Result<PathBuf, String> {
    std::env::current_dir().map_err(|e| format!("cannot resolve project root: {}", e))
}

/// Read an env-file value or None if absent. Mirrors the helpers in rbtdrk
/// and rbtdrp — kept local to avoid cross-module coupling.
fn rbtdro_read_env_value(path: &Path, key: &str) -> Option<String> {
    let content = std::fs::read_to_string(path).ok()?;
    let prefix = format!("{}=", key);
    for line in content.lines() {
        let trimmed = line.trim_start();
        if trimmed.starts_with('#') {
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix(&prefix) {
            return Some(rest.to_string());
        }
    }
    None
}

/// Cases 3-7 probe: reliquary touchmark yoked into the witness vessel's rbrv.env.
/// Case 1's yoke fan-out writes RBRV_RELIQUARY into every ordain-path vessel
/// and commits; reading the witness vessel's committed value is the cross-case
/// evidence that case 1 ran. No out-of-source-tree scratch state.
/// Kludge is local-only (no GCP), so governor avowal is not a load-bearing
/// precondition for kludge; the witness presence confirms case 1 completed.
fn rbtdro_probe_reliquary_touchmark() -> Result<(), String> {
    let root = rbtdro_probe_root()?;
    let rbrv = root
        .join(RBTDRO_WITNESS_VESSEL_DIR)
        .join(RBTDGC_RBRV_FILE);
    let value = rbtdro_read_env_value(&rbrv, RBTDRO_FIELD_RBRV_RELIQUARY).ok_or_else(|| {
        format!(
            "{} missing from {}",
            RBTDRO_FIELD_RBRV_RELIQUARY,
            rbrv.display()
        )
    })?;
    if value.trim().is_empty() {
        return Err(format!(
            "{} is empty in {}",
            RBTDRO_FIELD_RBRV_RELIQUARY,
            rbrv.display()
        ));
    }
    Ok(())
}

/// Assert the reliquary-touchmark precondition shared by every reliquary-
/// consuming onboarding case: case 1's conclave yoked RBRV_RELIQUARY into the
/// witness vessel. One home for the probe the cases formerly inlined byte-for-
/// byte; on Err the case returns the verdict immediately, as the inline form did.
fn rbtdro_assert_reliquary_touchmark() -> Result<(), rbtdre_Verdict> {
    let probe = rbtdrb_Probe {
        name: "reliquary touchmark captured",
        check: rbtdro_probe_reliquary_touchmark,
        remediation: "rerun rbtdro_onboarding_conclave_reliquary before this case",
    };
    rbtdrb_assert(&probe)
}

/// Graft case probe: RBRV_GRAFT_IMAGE anointed into the graft vessel's
/// committed rbrv.env by the ccyolo kludge case's anoint chain. A tagged ref
/// is the cross-case witness; local docker presence is asserted in the case
/// body where the failure message can carry the ref.
fn rbtdro_probe_graft_anointed() -> Result<(), String> {
    let root = rbtdro_probe_root()?;
    let rbrv = root
        .join(RBTDRO_VESSEL_DIR_GRAFT)
        .join(RBTDGC_RBRV_FILE);
    let value = rbtdro_read_env_value(&rbrv, RBTDRO_FIELD_RBRV_GRAFT_IMAGE).ok_or_else(|| {
        format!(
            "{} missing from {}",
            RBTDRO_FIELD_RBRV_GRAFT_IMAGE,
            rbrv.display()
        )
    })?;
    if !value.contains(':') {
        return Err(format!(
            "{} in {} is not a tagged image ref (unanointed?): {}",
            RBTDRO_FIELD_RBRV_GRAFT_IMAGE,
            rbrv.display(),
            value
        ));
    }
    Ok(())
}

// ── Helpers ──────────────────────────────────────────────────

/// Yoke the reliquary touchmark into every vessel's rbrv.env. The yoke tabtarget
/// validates the touchmark once against GAR, then wildcard-iterates every vessel
/// under ${RBRR_VESSEL_DIR}. The orchestrator commits the resulting rbrv.env
/// changes after this primitive returns.
fn rbtdro_yoke(
    ctx: &mut rbtdri_Context,
    dir: &Path,
    touchmark: &str,
    label: &str,
) -> Result<(), rbtdre_Verdict> {
    rbtdri_invoke_or_fail(
        ctx,
        RBTDGC_VERB_YOKE,
        "",
        RBTDGC_YOKE_RELIQUARY,
        &[touchmark],
        &[],
        dir,
        label,
    )?;
    Ok(())
}

/// Ensconce one vessel's upstream base into a bole Lode (rbw-lE). Capture-pure:
/// it emits the touchmark chaining fact but writes no vessel config. The
/// subsequent feoff reads that fact and populates the vessel's
/// RBRV_IMAGE_n_ANCHOR, so ensconce must immediately precede feoff.
fn rbtdro_ensconce(
    ctx: &mut rbtdri_Context,
    dir: &Path,
    vessel_sigil: &str,
    label: &str,
) -> Result<String, rbtdre_Verdict> {
    let result = rbtdri_invoke_or_fail(
        ctx,
        "ensconce",
        vessel_sigil,
        RBTDGC_ENSCONCE_BOLE,
        &[vessel_sigil],
        &[],
        dir,
        label,
    )?;
    // Capture-pure ensconce hands the touchmark forward as a chaining fact in
    // current/. Read it now, before the chained feoff runs: that feoff's
    // dispatch promotes this current/ into its previous/ (where feoff reads the
    // fact), moving it out of current/ where this read looks.
    let touchmark = rbtdri_read_burv_fact(&result, RBTDRO_FACT_LODE_TOUCHMARK).map_err(|e| {
        rbtdre_Verdict::Fail(format!("read touchmark fact after ensconce {}: {}", vessel_sigil, e))
    })?;
    let _ = std::fs::write(dir.join(format!("{}-touchmark.txt", label)), &touchmark);
    Ok(touchmark)
}

/// Feoff one vessel's base anchor from the chained bole touchmark (rbw-rvf).
/// The chain LINK extracted out of conjure: it reads the touchmark the preceding
/// ensconce handed forward and rewrites RBRV_IMAGE_n_ANCHOR. Must be chained off
/// that ensconce (chain_next_invoke before it) so the touchmark fact lands in
/// feoff's previous/. Leaves conjure a pure head — ordain reads no fact.
fn rbtdro_feoff(
    ctx: &mut rbtdri_Context,
    dir: &Path,
    vessel_sigil: &str,
    label: &str,
) -> Result<(), rbtdre_Verdict> {
    rbtdri_invoke_or_fail(
        ctx,
        "feoff",
        vessel_sigil,
        RBTDGC_FEOFF_BOLE,
        &[vessel_sigil],
        &[],
        dir,
        label,
    )?;
    Ok(())
}

/// Write a value into a vessel's rbrv.env. Delegates to the engine's validated
/// config-field seam (rbtdre_config_set_field) — the generalization of this
/// embryo — so the find-or-err + atomic-rename pattern lives in one home.
/// Returns Err if the variable line is not found.
fn rbtdro_write_vessel_env(
    root: &Path,
    vessel_dir: &str,
    var_name: &str,
    value: &str,
) -> Result<(), String> {
    let rbrv_path = root.join(vessel_dir).join(RBTDGC_RBRV_FILE);
    rbtdre_config_set_field(&rbrv_path, var_name, value)
}

/// Read a single `VAR=value` line's value from a vessel's rbrv.env. The
/// read-side complement of `rbtdro_write_vessel_env`; used to witness feoff's
/// anchor write before the ordain. Errs if the variable is absent.
fn rbtdro_read_vessel_env(
    root: &Path,
    vessel_dir: &str,
    var_name: &str,
) -> Result<String, String> {
    let rbrv_path = root.join(vessel_dir).join(RBTDGC_RBRV_FILE);
    let file = std::fs::File::open(&rbrv_path)
        .map_err(|e| format!("open rbrv.env for {}: {}", vessel_dir, e))?;
    let prefix = format!("{}=", var_name);
    for line in BufReader::new(file).lines() {
        let line = line.map_err(|e| format!("read rbrv.env for {}: {}", vessel_dir, e))?;
        if let Some(value) = line.strip_prefix(&prefix) {
            return Ok(value.to_string());
        }
    }
    Err(format!("variable {} not found in {}/rbrv.env", var_name, vessel_dir))
}

/// Drive a freshly-built hallmark into a nameplate's RBRN_{BOTTLE,SENTRY}_HALLMARK
/// by invoking the real rbw-nd drive tabtarget — the unified drive-link — with the
/// hallmark passed EXPRESS (`field` is the two-value selector `bottle`|`sentry`).
/// Replaces the former in-process rbtdro_drive_hallmark reimplementation: the
/// onboarding harness now exercises the same operator verb the cloud path ships,
/// and the durable-config discipline (relay-then-read, band-reject) lives in ONE bash home.
/// The drive does not commit; callers commit via rbtdre_commit_nameplates.
fn rbtdro_drive_nameplate(
    ctx: &mut rbtdri_Context,
    dir: &Path,
    nameplate: &str,
    field: &str,
    hallmark: &str,
) -> Result<(), rbtdre_Verdict> {
    rbtdri_invoke_or_fail(
        ctx,
        &format!("{} {}", RBTDGC_VERB_DRIVE, field),
        nameplate,
        RBTDGC_DRIVE_HALLMARK,
        &[nameplate, field, hallmark],
        &[],
        dir,
        &format!("{}-{}-{}", RBTDGC_VERB_DRIVE, field, nameplate),
    )?;
    Ok(())
}

/// Kludge helper: build sentry and bottle locally for a nameplate. Both steps
/// are local docker builds with no GCP dependency. The kludge tabtargets drive
/// hallmarks directly into the nameplate's rbrn.env via the rbrn_drive drive-link
/// they compose. rbw-cKS and rbw-cKB are global (param1-channel) tabtargets — no
/// imprint suffix, nameplate passed as a positional argument.
fn rbtdro_kludge_nameplate(
    ctx: &mut rbtdri_Context,
    dir: &Path,
    nameplate: &str,
) -> Result<(), rbtdre_Verdict> {
    let root = ctx.project_root().to_path_buf();

    rbtdri_invoke_or_fail(
        ctx,
        &format!("{} {}", RBTDGC_VERB_KLUDGE, RBTDGC_CONTAINER_SENTRY),
        nameplate,
        RBTDGC_CRUCIBLE_KLUDGE_SENTRY,
        &[nameplate],
        &[],
        dir,
        &format!("{}-{}-{}", RBTDGC_VERB_KLUDGE, RBTDGC_CONTAINER_SENTRY, nameplate),
    )?;

    // Commit sentry hallmark before bottle kludge — kludge asserts clean tree.
    rbtdre_commit_nameplates(
        &root,
        &[nameplate],
        &format!(
            "{}-{}: {} hallmark",
            RBTDGC_VERB_KLUDGE, nameplate, RBTDGC_CONTAINER_SENTRY
        ),
    )
    .map_err(rbtdre_Verdict::Fail)?;

    rbtdri_invoke_or_fail(
        ctx,
        &format!("{} {}", RBTDGC_VERB_KLUDGE, RBTDGC_CONTAINER_BOTTLE),
        nameplate,
        RBTDGC_CRUCIBLE_KLUDGE_BOTTLE,
        &[nameplate],
        &[],
        dir,
        &format!("{}-{}-{}", RBTDGC_VERB_KLUDGE, RBTDGC_CONTAINER_BOTTLE, nameplate),
    )?;

    rbtdre_commit_nameplates(
        &root,
        &[nameplate],
        &format!(
            "{}-{}: {} hallmark",
            RBTDGC_VERB_KLUDGE, nameplate, RBTDGC_CONTAINER_BOTTLE
        ),
    )
    .map_err(rbtdre_Verdict::Fail)?;
    Ok(())
}

/// Conclave the depot-wide reliquary toolchain. Captures the reliquary
/// touchmark from BURV fact, persists it to the fixture scratch file, then
/// yokes the touchmark into all ordain-side vessels in one pass and auto-commits.
fn rbtdro_onboarding_conclave_reliquary(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdro_onboarding_conclave_reliquary_impl(ctx, dir))
}

fn rbtdro_onboarding_conclave_reliquary_impl(
    ctx: &mut rbtdri_Context,
    dir: &Path,
) -> rbtdre_Verdict {
    let root = ctx.project_root().to_path_buf();
    let result = match rbtdri_invoke_or_fail(
        ctx,
        "conclave",
        "",
        RBTDGC_CONCLAVE_RELIQUARY,
        &[],
        &[],
        dir,
        "conclave",
    ) {
        Ok(r) => r,
        Err(v) => return v,
    };

    let touchmark = match rbtdri_read_burv_fact(&result, RBTDRO_FACT_LODE_TOUCHMARK) {
        Ok(s) => s,
        Err(e) => return rbtdre_Verdict::Fail(format!("read reliquary fact: {}", e)),
    };
    let _ = std::fs::write(dir.join("reliquary-touchmark.txt"), &touchmark);

    // Wildcard-yoke: single invocation writes RBRV_RELIQUARY into every
    // vessel under ${RBRR_VESSEL_DIR}.
    if let Err(v) = rbtdro_yoke(ctx, dir, &touchmark, RBTDGC_VERB_YOKE) {
        return v;
    }

    // Commit the rbrv.env changes for all yoked vessels — the wildcard yoke
    // rewrites every vessel's rbrv.env, so the vessel-class verb stages that
    // whole enumerated set and nothing else.
    if let Err(e) = rbtdre_commit_vessels_all(
        &root,
        &format!(
            "conclave-reliquary: {} touchmark across all vessels",
            RBTDGC_VERB_YOKE
        ),
    ) {
        return rbtdre_Verdict::Fail(e);
    }

    rbtdre_Verdict::Pass
}

/// Build tadmor sentry and bottle locally. Kludge is local docker — no GCP.
/// Probe: reliquary scratch present (confirms case 1 completed).
fn rbtdro_onboarding_kludge_tadmor(dir: &Path) -> rbtdre_Verdict {
    if let Err(v) = rbtdro_assert_reliquary_touchmark() {
        return v;
    }
    rbtdrc_with_ctx(|ctx| rbtdro_onboarding_kludge_tadmor_impl(ctx, dir))
}

fn rbtdro_onboarding_kludge_tadmor_impl(ctx: &mut rbtdri_Context, dir: &Path) -> rbtdre_Verdict {
    match rbtdro_kludge_nameplate(ctx, dir, RBTDRO_NAMEPLATE_TADMOR) {
        Ok(()) => rbtdre_Verdict::Pass,
        Err(v) => v,
    }
}

/// Standalone tadmor kludge for the self-contained build+run path (rbw-ts.TestSuite.tadmor).
/// Same build+commit of both vessels as the onboarding case, but WITHOUT the
/// reliquary-touchmark probe: that probe is an onboarding-sequence sequencing
/// witness, not a local-kludge dependency (kludge is local docker, no GCP, no
/// reliquary). Drives + commits the sentry and bottle hallmarks so the tadmor
/// crucible fixture that follows charges against a clean nameplate.
fn rbtdro_kludge_tadmor_standalone(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdro_onboarding_kludge_tadmor_impl(ctx, dir))
}

pub static RBTDRO_CASES_KLUDGE_TADMOR: &[rbtdre_Case] =
    &[case!(rbtdro_kludge_tadmor_standalone)];

pub static RBTDRO_FIXTURE_KLUDGE_TADMOR: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_KLUDGE_TADMOR,
    disposition: rbtdre_Disposition::StateProgressing,
    setup: None,
    teardown: None,
    cases: RBTDRO_CASES_KLUDGE_TADMOR,
    credless: false,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: Some(600), invocations: None },
};

/// Build ccyolo sentry and bottle locally, then anoint graft-demo off the
/// bottle kludge's chained facts. Kludge and anoint are local — no GCP.
/// Probe: reliquary scratch present (confirms case 1 completed).
fn rbtdro_onboarding_kludge_ccyolo(dir: &Path) -> rbtdre_Verdict {
    if let Err(v) = rbtdro_assert_reliquary_touchmark() {
        return v;
    }
    rbtdrc_with_ctx(|ctx| rbtdro_onboarding_kludge_ccyolo_impl(ctx, dir))
}

fn rbtdro_onboarding_kludge_ccyolo_impl(ctx: &mut rbtdri_Context, dir: &Path) -> rbtdre_Verdict {
    let root = ctx.project_root().to_path_buf();

    if let Err(v) = rbtdro_kludge_nameplate(ctx, dir, RBTDRO_NAMEPLATE_CCYOLO) {
        return v;
    }

    // Chain anoint off the bottle kludge above: theurge isolates each invoke
    // in its own BURV root, so without this the kludge's hallmark fact never
    // lands in anoint's previous/ and the chain read dies on the broken chain
    // (band 105). This makes anoint reuse the bottle kludge's root, so bud
    // promotes the hallmark into anoint's previous/ — the operator's shared
    // ../output-buk depth-1 flow, restored for just this pair. The intervening
    // hallmark commit is not a dispatch, so the depth-1 invoke chain holds.
    ctx.chain_next_invoke();

    // Anoint graft-demo off the bottle kludge that just ran: the anoint
    // dispatch reads the kludge's chained build facts (previous-dir baton)
    // and rewrites the graft vessel's RBRV_GRAFT_IMAGE. Must follow the
    // kludge immediately — any intervening dispatch breaks the depth-1
    // chain. The ordain-graft case consumes the committed value.
    if let Err(v) = rbtdri_invoke_or_fail(
        ctx,
        RBTDGC_VERB_ANOINT,
        RBTDRO_VESSEL_DIR_GRAFT,
        RBTDGC_ANOINT_GRAFT,
        &[RBTDRO_VESSEL_DIR_GRAFT],
        &[],
        dir,
        "anoint-graft-demo",
    ) {
        return v;
    }

    // Commit the anointed slot — anoint is operator-committed by design, and
    // downstream cases gate on a clean tree.
    if let Err(e) = rbtdre_commit_vessels(
        &root,
        &[RBTDRO_VESSEL_DIR_GRAFT],
        &format!(
            "{}: graft-demo image from ccyolo {}",
            RBTDGC_VERB_ANOINT, RBTDGC_VERB_KLUDGE
        ),
    ) {
        return rbtdre_Verdict::Fail(e);
    }

    rbtdre_Verdict::Pass
}

/// Ordain rbev-sentry-deb-tether (conjure mode). Case 1 yoked the reliquary
/// touchmark into the vessel. Propagates the resulting hallmark to all sentry-tether
/// consumers (moriah, srjcl, pluml) via RBRN_SENTRY_HALLMARK.
fn rbtdro_onboarding_ordain_conjure_sentry(dir: &Path) -> rbtdre_Verdict {
    if let Err(v) = rbtdro_assert_reliquary_touchmark() {
        return v;
    }
    rbtdrc_with_ctx(|ctx| rbtdro_onboarding_ordain_conjure_sentry_impl(ctx, dir))
}

fn rbtdro_onboarding_ordain_conjure_sentry_impl(ctx: &mut rbtdri_Context, dir: &Path) -> rbtdre_Verdict {
    let root = ctx.project_root().to_path_buf();

    let (hallmark, gar_root, ark_stem) = match rbtdri_ordain_capture_full(
        ctx,
        dir,
        RBTDRO_VESSEL_DIR_SENTRY_TETHER,
        &[],
        "ordain-conjure",
    ) {
        Ok(facts) => facts,
        Err(v) => return v,
    };

    // Verification tail: wrest, summon, plumb_full, rekon — exercises the
    // hallmark supply chain end-to-end. Abjure is omitted because downstream
    // crucible fixtures consume this hallmark.
    let wrest_locator = rbtdri_gar_ref_categorical(
        RBTDRV_GAR_CATEGORY_HALLMARKS,
        RBTDRV_ARK_BASENAME_IMAGE,
        &hallmark,
    );
    if let Err(v) = rbtdri_invoke_or_fail(
        ctx,
        "wrest",
        &wrest_locator,
        RBTDGC_WREST_HALLMARK_IMAGE,
        &[&wrest_locator],
        &[],
        dir,
        "wrest-conjure",
    ) {
        return v;
    }

    let image_ref = rbtdri_gar_ref_fact(&gar_root, &ark_stem, RBTDRV_ARK_BASENAME_IMAGE, &hallmark);
    let about_ref = rbtdri_gar_ref_fact(&gar_root, &ark_stem, RBTDRV_ARK_BASENAME_ABOUT, &hallmark);
    let vouch_ref = rbtdri_gar_ref_fact(&gar_root, &ark_stem, RBTDRV_ARK_BASENAME_VOUCH, &hallmark);

    if let Err(v) = rbtdri_invoke_or_fail(
        ctx,
        "summon",
        &hallmark,
        RBTDGC_SUMMON_HALLMARK,
        &[&hallmark],
        &[],
        dir,
        "summon-conjure",
    ) {
        return v;
    }
    for ark_ref in [&image_ref, &about_ref, &vouch_ref] {
        if !rbtdrv_docker_inspect(ark_ref) {
            return rbtdre_Verdict::Fail(format!(
                "summon: ark not local after pull: {}",
                ark_ref
            ));
        }
    }

    let plumb_full = match rbtdri_invoke_or_fail(
        ctx,
        "plumb_full",
        &hallmark,
        RBTDGC_PLUMB_FULL,
        &[&hallmark],
        &[],
        dir,
        "plumb-full-conjure",
    ) {
        Ok(r) => r,
        Err(v) => return v,
    };
    for marker in ["SLSA", "SBOM", "Dockerfile"] {
        if !plumb_full.stdout.contains(marker) {
            return rbtdre_Verdict::Fail(format!(
                "plumb_full: marker '{}' not in stdout",
                marker
            ));
        }
    }

    let rekon = match rbtdri_invoke_or_fail(
        ctx,
        "rekon",
        &hallmark,
        RBTDGC_REKON_HALLMARK,
        &[&hallmark],
        &[],
        dir,
        "rekon-conjure",
    ) {
        Ok(r) => r,
        Err(v) => return v,
    };
    for basename in [
        RBTDRV_ARK_BASENAME_IMAGE,
        RBTDRV_ARK_BASENAME_ABOUT,
        RBTDRV_ARK_BASENAME_VOUCH,
        RBTDRV_ARK_BASENAME_ATTEST,
    ] {
        if !rbtdrv_rekon_basename_yes(&rekon.stdout, basename) {
            return rbtdre_Verdict::Fail(format!(
                "rekon: basename '{}' not marked yes\nstdout:\n{}",
                basename, rekon.stdout
            ));
        }
    }

    for nameplate in RBTDRO_CONSUMERS_SENTRY_TETHER {
        if let Err(v) =
            rbtdro_drive_nameplate(ctx, dir, nameplate, RBTDGC_CONTAINER_SENTRY, &hallmark)
        {
            return v;
        }
    }

    if let Err(e) = rbtdre_commit_nameplates(
        &root,
        RBTDRO_CONSUMERS_SENTRY_TETHER,
        "ordain-conjure: sentry-tether hallmark + propagate to consumers",
    ) {
        return rbtdre_Verdict::Fail(e);
    }

    rbtdre_Verdict::Pass
}

/// Ordain rbev-bottle-anthropic-jupyter (conjure mode). Propagates the
/// resulting hallmark to srjcl via RBRN_BOTTLE_HALLMARK.
fn rbtdro_onboarding_ordain_conjure_jupyter(dir: &Path) -> rbtdre_Verdict {
    if let Err(v) = rbtdro_assert_reliquary_touchmark() {
        return v;
    }
    rbtdrc_with_ctx(|ctx| rbtdro_onboarding_ordain_conjure_jupyter_impl(ctx, dir))
}

fn rbtdro_onboarding_ordain_conjure_jupyter_impl(ctx: &mut rbtdri_Context, dir: &Path) -> rbtdre_Verdict {
    let root = ctx.project_root().to_path_buf();

    let hallmark = match rbtdri_ordain_capture(
        ctx,
        dir,
        RBTDRO_VESSEL_DIR_JUPYTER,
        &[],
        "ordain-jupyter",
    ) {
        Ok(h) => h,
        Err(v) => return v,
    };

    for nameplate in RBTDRO_CONSUMERS_JUPYTER_BOTTLE {
        if let Err(v) =
            rbtdro_drive_nameplate(ctx, dir, nameplate, RBTDGC_CONTAINER_BOTTLE, &hallmark)
        {
            return v;
        }
    }

    if let Err(e) = rbtdre_commit_nameplates(
        &root,
        RBTDRO_CONSUMERS_JUPYTER_BOTTLE,
        "conjure-srjcl: jupyter-bottle hallmark + propagate to srjcl",
    ) {
        return rbtdre_Verdict::Fail(e);
    }

    rbtdre_Verdict::Pass
}

/// Walk the airgap supply chain: ensconce upstream rust base into forge,
/// conjure the forge tethered, write the forge-hallmark locator into the
/// airgap vessel's base anchor (no copy — orchestration writes the locator
/// directly), conjure the airgap bottle.
/// Case 1 yoked the reliquary touchmark into both forge and airgap vessels.
/// Propagates airgap-bottle hallmark to moriah via RBRN_BOTTLE_HALLMARK.
fn rbtdro_onboarding_ordain_airgap_chain(dir: &Path) -> rbtdre_Verdict {
    if let Err(v) = rbtdro_assert_reliquary_touchmark() {
        return v;
    }
    rbtdrc_with_ctx(|ctx| rbtdro_onboarding_ordain_airgap_chain_impl(ctx, dir))
}

fn rbtdro_onboarding_ordain_airgap_chain_impl(ctx: &mut rbtdri_Context, dir: &Path) -> rbtdre_Verdict {
    let root = ctx.project_root().to_path_buf();

    let forge_sigil = RBTDRO_VESSEL_DIR_AIRGAP_FORGE
        .rsplit('/')
        .next()
        .unwrap_or(RBTDRO_VESSEL_DIR_AIRGAP_FORGE);

    // Ensconce the forge vessel's upstream rust base into a bole Lode. Capture is
    // pure — it emits the touchmark chaining fact but writes no vessel config, so
    // there is nothing to commit yet, and ensconce must immediately precede feoff
    // so the depth-1 chain carries the touchmark forward. Capture the fresh
    // touchmark now; feoff below must rewrite the forge anchor to it (a stale
    // committed anchor proves feoff never fired).
    let touchmark = match rbtdro_ensconce(ctx, dir, forge_sigil, "ensconce-upstream") {
        Ok(t) => t,
        Err(v) => return v,
    };

    // Chain feoff off the ensconce above: theurge isolates each invoke in its own
    // BURV root, so without this the touchmark fact never lands in feoff's
    // previous/ and the express-or-chain resolve dies on the broken chain. This
    // makes feoff reuse the ensconce's root, so bud promotes the touchmark into
    // feoff's previous/ — the operator's shared ../output-buk flow, restored for
    // just this pair. (Ordain below is NOT chained — conjure reads no fact.)
    ctx.chain_next_invoke();

    // Feoff the forge vessel — the chain LINK extracted out of conjure reads the
    // touchmark the ensconce handed forward and writes RBRV_IMAGE_n_ANCHOR. The
    // ceremony is ensconce -> feoff -> commit -> ordain; conjure then builds from
    // the committed anchor as a pure head.
    if let Err(v) = rbtdro_feoff(ctx, dir, forge_sigil, "feoff-forge") {
        return v;
    }

    // Assert feoff fired: the forge anchor must now be the Lode locator for the
    // touchmark the ensconce just minted. A broken chain or a no-op (the bug this
    // case guards) leaves the prior committed anchor — a different, older
    // touchmark — so this comparison fails, turning the false green red.
    let expected_anchor = format!("{}/{}:{}", RBTDRO_LODE_ROOT, touchmark, RBTDRO_LODE_TAG_BOLE);
    match rbtdro_read_vessel_env(&root, RBTDRO_VESSEL_DIR_AIRGAP_FORGE, RBTDRO_FORGE_BASE_ANCHOR_VAR) {
        Ok(actual) if actual == expected_anchor => {
            let _ = std::fs::write(dir.join("forge-elected-anchor.txt"), &actual);
        }
        Ok(actual) => {
            return rbtdre_Verdict::Fail(format!(
                "feoff did not fire: forge {} is '{}', expected '{}' \
                 (the ensconce->feoff chain did not carry the touchmark to feoff)",
                RBTDRO_FORGE_BASE_ANCHOR_VAR, actual, expected_anchor
            ));
        }
        Err(e) => return rbtdre_Verdict::Fail(format!("read forge base anchor: {}", e)),
    }

    // Commit the elected ANCHOR that feoff wrote into the forge vessel — feoff is
    // operator-committed, and a clean tree is needed before ordain-forge (which
    // gates on a clean tree) and the airgap-bottle anchor write below.
    if let Err(e) = rbtdre_commit_vessels(
        &root,
        &[RBTDRO_VESSEL_DIR_AIRGAP_FORGE],
        "ordain-airgap: feoff bole touchmark into forge vessel base anchor",
    ) {
        return rbtdre_Verdict::Fail(e);
    }

    // Ordain the forge vessel — now a pure head: it reads no chain and builds from
    // the committed anchor feoff elected above. The forge hallmark becomes the
    // airgap-bottle's base via a hallmark-namespace locator (mechanism (c)).
    let forge_hallmark = match rbtdri_ordain_capture(
        ctx,
        dir,
        RBTDRO_VESSEL_DIR_AIRGAP_FORGE,
        &[],
        "ordain-forge",
    ) {
        Ok(h) => h,
        Err(v) => return v,
    };

    // Write the hallmark-base locator into airgap-bottle's rbrv.env. The slot
    // points at the forge image inside its hallmark subtree; conjure resolves
    // this locator to a full GAR ref at airgap-bottle build time.
    let airgap_anchor = rbtdri_gar_ref_categorical(
        RBTDRV_GAR_CATEGORY_HALLMARKS,
        RBTDRV_ARK_BASENAME_IMAGE,
        forge_hallmark.trim(),
    );
    if let Err(e) = rbtdro_write_vessel_env(
        &root,
        RBTDRO_VESSEL_DIR_AIRGAP_BOTTLE,
        RBTDRO_AIRGAP_BASE_ANCHOR_VAR,
        &airgap_anchor,
    ) {
        return rbtdre_Verdict::Fail(format!("write airgap-bottle anchor: {}", e));
    }
    let _ = std::fs::write(dir.join("airgap-anchor.txt"), &airgap_anchor);

    // Commit the locator write before ordain-airgap: ordain has clean-tree
    // precondition. The forge hallmark's existence in GAR is established by
    // ordain-forge's success above — no separate base-capture validation step.
    if let Err(e) = rbtdre_commit_vessels(
        &root,
        &[RBTDRO_VESSEL_DIR_AIRGAP_BOTTLE],
        "ordain-airgap: write forge-hallmark locator into airgap-bottle base anchor",
    ) {
        return rbtdre_Verdict::Fail(e);
    }

    let airgap_hallmark = match rbtdri_ordain_capture(
        ctx,
        dir,
        RBTDRO_VESSEL_DIR_AIRGAP_BOTTLE,
        &[],
        "ordain-airgap",
    ) {
        Ok(h) => h,
        Err(v) => return v,
    };

    for nameplate in RBTDRO_CONSUMERS_AIRGAP_BOTTLE {
        if let Err(v) =
            rbtdro_drive_nameplate(ctx, dir, nameplate, RBTDGC_CONTAINER_BOTTLE, &airgap_hallmark)
        {
            return v;
        }
    }

    if let Err(e) = rbtdre_commit_nameplates(
        &root,
        RBTDRO_CONSUMERS_AIRGAP_BOTTLE,
        "ordain-airgap: airgap-bottle hallmark + propagate to moriah",
    ) {
        return rbtdre_Verdict::Fail(e);
    }

    rbtdre_Verdict::Pass
}

/// Pin upstream PlantUML by digest. Bind mode reads RBRV_BIND_IMAGE from
/// rbev-bottle-plantuml/rbrv.env and mirrors the digest into GAR via Cloud
/// Build (gcrane from reliquary + about/vouch metadata). Propagates plantuml
/// hallmark to pluml via RBRN_BOTTLE_HALLMARK.
fn rbtdro_onboarding_ordain_bind_plantuml(dir: &Path) -> rbtdre_Verdict {
    if let Err(v) = rbtdro_assert_reliquary_touchmark() {
        return v;
    }
    rbtdrc_with_ctx(|ctx| rbtdro_onboarding_ordain_bind_plantuml_impl(ctx, dir))
}

fn rbtdro_onboarding_ordain_bind_plantuml_impl(ctx: &mut rbtdri_Context, dir: &Path) -> rbtdre_Verdict {
    let root = ctx.project_root().to_path_buf();

    let hallmark = match rbtdri_ordain_capture(
        ctx,
        dir,
        RBTDRO_VESSEL_DIR_PLANTUML,
        &[],
        "ordain-bind",
    ) {
        Ok(h) => h,
        Err(v) => return v,
    };

    // Verification tail: wrest, plumb_compact, surgical pouch jettison.
    // Pouch jettison + post-rekon proves selective ark deletion preserves
    // image (load-bearing for downstream pluml, which needs only the image).
    // Abjure is omitted because pluml consumes this hallmark.
    let wrest_locator = rbtdri_gar_ref_categorical(
        RBTDRV_GAR_CATEGORY_HALLMARKS,
        RBTDRV_ARK_BASENAME_IMAGE,
        &hallmark,
    );
    if let Err(v) = rbtdri_invoke_or_fail(
        ctx,
        "wrest",
        &wrest_locator,
        RBTDGC_WREST_HALLMARK_IMAGE,
        &[&wrest_locator],
        &[],
        dir,
        "wrest-bind",
    ) {
        return v;
    }

    let plumb_compact = match rbtdri_invoke_or_fail(
        ctx,
        "plumb_compact",
        &hallmark,
        RBTDGC_PLUMB_COMPACT,
        &[&hallmark],
        &[],
        dir,
        "plumb-compact-bind",
    ) {
        Ok(r) => r,
        Err(v) => return v,
    };
    if !plumb_compact.stdout.contains(&hallmark) {
        return rbtdre_Verdict::Fail(format!(
            "plumb_compact: hallmark '{}' not in stdout",
            hallmark
        ));
    }
    if !plumb_compact.stdout.contains("HALLMARK PLUMB:") {
        return rbtdre_Verdict::Fail(
            "plumb_compact: expected 'HALLMARK PLUMB:' marker in stdout".to_string(),
        );
    }

    let jettison_locator = rbtdri_gar_ref_categorical(
        RBTDRV_GAR_CATEGORY_HALLMARKS,
        RBTDRV_ARK_BASENAME_POUCH,
        &hallmark,
    );
    if let Err(v) = rbtdri_invoke_or_fail(
        ctx,
        "jettison",
        &jettison_locator,
        RBTDGC_JETTISON_HALLMARK_IMAGE,
        &[&jettison_locator],
        &[(RBTDRI_BURE_CONFIRM_KEY, RBTDRI_BURE_CONFIRM_SKIP)],
        dir,
        "jettison-pouch-bind",
    ) {
        return v;
    }

    let rekon_after = match rbtdri_invoke_or_fail(
        ctx,
        "rekon",
        &hallmark,
        RBTDGC_REKON_HALLMARK,
        &[&hallmark],
        &[],
        dir,
        "rekon-after-jettison-bind",
    ) {
        Ok(r) => r,
        Err(v) => return v,
    };
    if rbtdrv_rekon_basename_yes(&rekon_after.stdout, RBTDRV_ARK_BASENAME_POUCH) {
        return rbtdre_Verdict::Fail(format!(
            "rekon: pouch still present after jettison\nstdout:\n{}",
            rekon_after.stdout
        ));
    }
    if !rbtdrv_rekon_basename_yes(&rekon_after.stdout, RBTDRV_ARK_BASENAME_IMAGE) {
        return rbtdre_Verdict::Fail(format!(
            "rekon: image disappeared after pouch jettison (collateral damage)\nstdout:\n{}",
            rekon_after.stdout
        ));
    }

    for nameplate in RBTDRO_CONSUMERS_PLANTUML_BOTTLE {
        if let Err(v) =
            rbtdro_drive_nameplate(ctx, dir, nameplate, RBTDGC_CONTAINER_BOTTLE, &hallmark)
        {
            return v;
        }
    }

    if let Err(e) = rbtdre_commit_nameplates(
        &root,
        RBTDRO_CONSUMERS_PLANTUML_BOTTLE,
        "ordain-bind: plantuml-bottle hallmark + propagate to pluml",
    ) {
        return rbtdre_Verdict::Fail(e);
    }

    rbtdre_Verdict::Pass
}

/// Ordain rbev-graft-demo from its committed RBRV_GRAFT_IMAGE — anointed by
/// the ccyolo kludge case's chain, consumed here as any operator-set regime
/// value, no injection. No consumers — graft-demo is terminal.
fn rbtdro_onboarding_ordain_graft_demo(dir: &Path) -> rbtdre_Verdict {
    if let Err(v) = rbtdro_assert_reliquary_touchmark() {
        return v;
    }
    let probe = rbtdrb_Probe {
        name: "graft-demo anointed",
        check: rbtdro_probe_graft_anointed,
        remediation: "rerun rbtdro_onboarding_kludge_ccyolo (its anoint chain writes RBRV_GRAFT_IMAGE) before this case",
    };
    if let Err(v) = rbtdrb_assert(&probe) {
        return v;
    }
    rbtdrc_with_ctx(|ctx| rbtdro_onboarding_ordain_graft_demo_impl(ctx, dir))
}

fn rbtdro_onboarding_ordain_graft_demo_impl(ctx: &mut rbtdri_Context, dir: &Path) -> rbtdre_Verdict {
    // Read the anointed graft image from the committed vessel regime.
    let rbrv = ctx
        .project_root()
        .join(RBTDRO_VESSEL_DIR_GRAFT)
        .join(RBTDGC_RBRV_FILE);
    let graft_image = match rbtdro_read_env_value(&rbrv, RBTDRO_FIELD_RBRV_GRAFT_IMAGE) {
        Some(v) if !v.trim().is_empty() => v,
        _ => {
            return rbtdre_Verdict::Fail(format!(
                "{} absent from {}",
                RBTDRO_FIELD_RBRV_GRAFT_IMAGE,
                rbrv.display()
            ))
        }
    };

    // Capture source layer DiffIDs before ordain — graft pushes bytes through
    // GAR's manifest-envelope normalization; round-trip identity proves the
    // bytes survived unchanged. Doubles as the local-presence gate: the
    // anointed image must still sit in the docker cache from its kludge.
    let source_layers = match rbtdrv_docker_layers_capture(&graft_image) {
        Ok(v) => v,
        Err(e) => {
            return rbtdre_Verdict::Fail(format!(
                "anointed image {} inspect: {}",
                graft_image, e
            ))
        }
    };
    let _ = std::fs::write(dir.join("source-layers.txt"), &source_layers);

    let (hallmark, gar_root, ark_stem) = match rbtdri_ordain_capture_full(
        ctx,
        dir,
        RBTDRO_VESSEL_DIR_GRAFT,
        &[],
        "ordain-graft",
    ) {
        Ok(facts) => facts,
        Err(v) => return v,
    };

    // Verification tail: wrest, layer-DiffID round-trip, abjure. graft-demo
    // is terminal (no consumers), so abjure is safe.
    let wrest_locator = rbtdri_gar_ref_categorical(
        RBTDRV_GAR_CATEGORY_HALLMARKS,
        RBTDRV_ARK_BASENAME_IMAGE,
        &hallmark,
    );
    if let Err(v) = rbtdri_invoke_or_fail(
        ctx,
        "wrest",
        &wrest_locator,
        RBTDGC_WREST_HALLMARK_IMAGE,
        &[&wrest_locator],
        &[],
        dir,
        "wrest-graft",
    ) {
        return v;
    }

    let image_ref = rbtdri_gar_ref_fact(&gar_root, &ark_stem, RBTDRV_ARK_BASENAME_IMAGE, &hallmark);
    let wrested_layers = match rbtdrv_docker_layers_capture(&image_ref) {
        Ok(v) => v,
        Err(e) => return rbtdre_Verdict::Fail(format!("wrested image inspect: {}", e)),
    };
    let _ = std::fs::write(dir.join("wrested-layers.txt"), &wrested_layers);
    if source_layers != wrested_layers {
        return rbtdre_Verdict::Fail(format!(
            "graft round-trip layer mismatch:\n  source:  {}\n  wrested: {}",
            source_layers, wrested_layers
        ));
    }

    if let Err(e) = rbtdrv_docker_rmi(&[&image_ref]) {
        return rbtdre_Verdict::Fail(format!("rmi: {}", e));
    }

    if let Err(v) = rbtdri_invoke_or_fail(
        ctx,
        "abjure",
        &hallmark,
        RBTDGC_ABJURE_HALLMARK,
        &[&hallmark],
        &[(RBTDRI_BURE_CONFIRM_KEY, RBTDRI_BURE_CONFIRM_SKIP)],
        dir,
        "abjure-graft",
    ) {
        return v;
    }

    rbtdre_Verdict::Pass
}

// ── Case registry ────────────────────────────────────────────

pub static RBTDRO_CASES_ONBOARDING_SEQUENCE: &[rbtdre_Case] = &[
    case!(rbtdro_onboarding_conclave_reliquary),
    case!(rbtdro_onboarding_kludge_tadmor),
    case!(rbtdro_onboarding_kludge_ccyolo),
    case!(rbtdro_onboarding_ordain_conjure_sentry),
    case!(rbtdro_onboarding_ordain_conjure_jupyter),
    case!(rbtdro_onboarding_ordain_airgap_chain),
    case!(rbtdro_onboarding_ordain_bind_plantuml),
    case!(rbtdro_onboarding_ordain_graft_demo),
];

pub static RBTDRO_FIXTURE_ONBOARDING_SEQUENCE: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_ONBOARDING_SEQUENCE,
    disposition: rbtdre_Disposition::StateProgressing,
    setup: None,
    teardown: None,
    cases: RBTDRO_CASES_ONBOARDING_SEQUENCE,
    credless: false,
    tariff: rbtdre_Tariff { min_secs: Some(60), max_secs: None, invocations: None },
};
const _: () = assert!(RBTDRO_FIXTURE_ONBOARDING_SEQUENCE.cases.len() == 8);
