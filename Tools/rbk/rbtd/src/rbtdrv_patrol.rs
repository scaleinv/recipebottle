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
// RBTDRV — the patrol: bare cloud-service fixtures (no crucible charge/quench).
//
// The credentialed GCP lifecycle fixtures (hallmark, lode, reliquary, wsl,
// podvm, foedus, batch-vouch, access-probe, terrier scaffold/atomicity,
// chaining-livery), each a single case that drives a live cloud lifecycle and
// cleans up after itself. Also homes the shared ark/GAR vocabulary and docker
// inspection helpers consumed here and by rbtdrd_dogfight / rbtdro_onboarding.

use std::path::Path;
use std::process::{Command, Stdio};

use crate::case;
use crate::rbtdrc_crucible::rbtdrc_with_ctx;
use crate::rbtdre_engine::{rbtdre_Case, rbtdre_Disposition, rbtdre_Fixture, rbtdre_Tariff, rbtdre_Verdict};
use crate::rbtdri_invocation::{
    rbtdri_Context, rbtdri_InvokeResult, rbtdri_gar_ref_categorical, rbtdri_invoke_global,
    rbtdri_invoke_or_fail,
    rbtdri_ordain_capture, rbtdri_read_burv_fact, rbtdri_read_burv_facts_multi,
    RBTDRI_BURE_CONFIRM_KEY, RBTDRI_BURE_CONFIRM_SKIP,
    RBTDRI_BURE_TWEAK_NAME_KEY, RBTDRI_BURE_TWEAK_VALUE_KEY,
};
use crate::rbtdgc_consts::{
    RBTDGC_ABJURE_HALLMARK, RBTDGC_ACCOUNT_PAYOR,
    RBTDGC_ACCOUNT_RETRIEVER, RBTDGC_AFFIANCE_MANOR, RBTDGC_AUDIT_HALLMARKS,
    RBTDGC_AUGUR_LODE, RBTDGC_BAND_ADMISSION, RBTDGC_BAND_ENGROSS, RBTDGC_BAND_EXPUNGE,
    RBTDGC_BAND_PERUSE, RBTDGC_BAND_RUNWAY, RBTDGC_BAND_VACANT, RBTDGC_BANISH_LODE,
    RBTDGC_BREVET_POLITY,
    RBTDGC_CANVASS_FOEDUS,
    RBTDGC_CHECK_AVOWAL, RBTDGC_CHECK_MANTLE,
    RBTDGC_CHECK_PAYOR, RBTDGC_CONCLAVE_RELIQUARY, RBTDGC_DESCRY_FOEDUS,
    RBTDGC_DIVINE_LODES, RBTDGC_ENSCONCE_BOLE, RBTDGC_ESPY_SITTING, RBTDGC_FACT_EXT_FOEDUS, RBTDGC_FACT_EXT_FOEDUS_HEALTH, RBTDGC_FACT_EXT_SITTING, RBTDGC_FEOFF_BOLE,
    RBTDGC_FREEHOLD_SUBJECT, RBTDGC_IMMURE_PODVM, RBTDGC_INSTATE_FOEDUS,
    RBTDGC_JETTISON_HALLMARK_IMAGE, RBTDGC_JETTISON_IMAGE, RBTDGC_JILT_MANOR, RBTDGC_LIST_IMAGES,
    RBTDGC_MANTLE_DIRECTOR, RBTDGC_MANTLE_GOVERNOR, RBTDGC_MANTLE_RETRIEVER,
    RBTDGC_NOVATE_SITTING,
    RBTDGC_PLUMB_FULL, RBTDGC_RBRD_FILE, RBTDGC_RBRR_FILE, RBTDGC_RBRV_FILE, RBTDGC_REHEARSE_POLITY, RBTDGC_REKON_HALLMARK,
    RBTDGC_SUMMON_HALLMARK,
    RBTDGC_TALLY_HALLMARKS,
    RBTDGC_TWEAK_HTTP_FAULT,
    RBTDGC_TWEAK_REGIME_POISON, RBTDGC_TWEAK_REDON_CADENCE, RBTDGC_UNDERPIN_WSL,
    RBTDGC_UNSEAT_POLITY, RBTDGC_VOUCH_HALLMARKS,
};
use crate::rbtdrm_manifest::rbtdrm_credential_check_colophon;

// ── Bare fixtures owned by rbtdrc (no charge/quench) ─────────

pub static RBTDRV_FIXTURE_HALLMARK_LIFECYCLE: rbtdre_Fixture = rbtdre_Fixture {
    name: crate::rbtdrm_manifest::RBTDRM_FIXTURE_HALLMARK_LIFECYCLE,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRV_CASES_HALLMARK_LIFECYCLE,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};

pub static RBTDRV_FIXTURE_LODE_LIFECYCLE: rbtdre_Fixture = rbtdre_Fixture {
    name: crate::rbtdrm_manifest::RBTDRM_FIXTURE_LODE_LIFECYCLE,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRV_CASES_LODE_LIFECYCLE,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};

pub static RBTDRV_FIXTURE_RELIQUARY_LIFECYCLE: rbtdre_Fixture = rbtdre_Fixture {
    name: crate::rbtdrm_manifest::RBTDRM_FIXTURE_RELIQUARY_LIFECYCLE,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRV_CASES_RELIQUARY_LIFECYCLE,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};

pub static RBTDRV_FIXTURE_WSL_LIFECYCLE: rbtdre_Fixture = rbtdre_Fixture {
    name: crate::rbtdrm_manifest::RBTDRM_FIXTURE_WSL_LIFECYCLE,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRV_CASES_WSL_LIFECYCLE,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};

pub static RBTDRV_FIXTURE_PODVM_LIFECYCLE: rbtdre_Fixture = rbtdre_Fixture {
    name: crate::rbtdrm_manifest::RBTDRM_FIXTURE_PODVM_LIFECYCLE,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRV_CASES_PODVM_LIFECYCLE,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};

pub static RBTDRV_FIXTURE_FOEDUS_LIFECYCLE: rbtdre_Fixture = rbtdre_Fixture {
    name: crate::rbtdrm_manifest::RBTDRM_FIXTURE_FOEDUS_LIFECYCLE,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRV_CASES_FOEDUS_LIFECYCLE,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};

pub static RBTDRV_FIXTURE_FOEDUS_REUSE: rbtdre_Fixture = rbtdre_Fixture {
    name: crate::rbtdrm_manifest::RBTDRM_FIXTURE_FOEDUS_REUSE,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRV_CASES_FOEDUS_REUSE,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};

pub static RBTDRV_FIXTURE_BATCH_VOUCH: rbtdre_Fixture = rbtdre_Fixture {
    name: crate::rbtdrm_manifest::RBTDRM_FIXTURE_BATCH_VOUCH,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRV_CASES_BATCH_VOUCH,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};

pub static RBTDRV_FIXTURE_ACCESS_PROBE: rbtdre_Fixture = rbtdre_Fixture {
    name: crate::rbtdrm_manifest::RBTDRM_FIXTURE_ACCESS_PROBE,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRV_CASES_ACCESS_PROBE,
    credless: false,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: Some(60), invocations: None },
};

pub static RBTDRV_FIXTURE_CREDENTIAL_READINESS: rbtdre_Fixture = rbtdre_Fixture {
    name: crate::rbtdrm_manifest::RBTDRM_FIXTURE_CREDENTIAL_READINESS,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRV_CASES_CREDENTIAL_READINESS,
    credless: false,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: Some(60), invocations: None },
};

pub static RBTDRV_FIXTURE_POLITY_DENIAL: rbtdre_Fixture = rbtdre_Fixture {
    name: crate::rbtdrm_manifest::RBTDRM_FIXTURE_POLITY_DENIAL,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRV_CASES_POLITY_DENIAL,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};

pub static RBTDRV_FIXTURE_PARLEY: rbtdre_Fixture = rbtdre_Fixture {
    name: crate::rbtdrm_manifest::RBTDRM_FIXTURE_PARLEY,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRV_CASES_PARLEY,
    credless: false,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: Some(120), invocations: None },
};

// Chaining-fact livery — the cloud sibling of the local chaining-fact band
// matrix. A bare cloud fixture (no crucible): the single case self-contains its
// reset baseline and best-effort cleanup (banish-if-present, body below), so
// setup/teardown stay None — the single-case runner reads a setup hook as
// "crucible fixture, verify it is charged", which this fixture is not.
pub static RBTDRV_FIXTURE_CHAINING_LIVERY: rbtdre_Fixture = rbtdre_Fixture {
    name: crate::rbtdrm_manifest::RBTDRM_FIXTURE_CHAINING_LIVERY,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRV_CASES_CHAINING_LIVERY,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};

// ── Hallmark / ark vocabulary and docker helpers ─────────────

/// Ark basenames — matching rbgc_constants.sh RBGC_ARK_BASENAME_* values.
pub(crate) const RBTDRV_ARK_BASENAME_IMAGE: &str = "image";
pub(crate) const RBTDRV_ARK_BASENAME_VOUCH: &str = "vouch";
pub(crate) const RBTDRV_ARK_BASENAME_ABOUT: &str = "about";
pub(crate) const RBTDRV_ARK_BASENAME_ATTEST: &str = "attest";
pub(crate) const RBTDRV_ARK_BASENAME_POUCH: &str = "pouch";

/// GAR categorical namespace literal — matches RBGC_GAR_CATEGORY_HALLMARKS.
/// Used to build wrest locators (paths within a GAR repo, prefix-free).
pub(crate) const RBTDRV_GAR_CATEGORY_HALLMARKS: &str = "rbi_hm";

/// Docker wrapper: inspect image (returns true if exists).
pub(crate) fn rbtdrv_docker_inspect(image_ref: &str) -> bool {
    Command::new("docker")
        .args(["inspect", image_ref])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// Docker wrapper: remove images.
pub(crate) fn rbtdrv_docker_rmi(refs: &[&str]) -> Result<(), String> {
    let status = Command::new("docker")
        .arg("rmi")
        .args(refs)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_err(|e| format!("docker rmi exec failed: {}", e))?;
    if !status.success() {
        return Err(format!("docker rmi exited {}", status.code().unwrap_or(-1)));
    }
    Ok(())
}

/// Parse a rekon stdout line for a given basename and return whether the
/// EXISTS column reads "yes". Returns false if the basename row is absent.
/// Rekon prints rows of `  <basename>  <yes|no>  <path-or-(absent)>`.
pub(crate) fn rbtdrv_rekon_basename_yes(stdout: &str, basename: &str) -> bool {
    for line in stdout.lines() {
        let mut fields = line.split_whitespace();
        if fields.next() == Some(basename) {
            return fields.next() == Some("yes");
        }
    }
    false
}

/// Docker wrapper: capture RootFS layer DiffIDs as a JSON array string.
/// Layer DiffIDs are SHA256s of uncompressed layer file content — byte-preserved
/// across registry round-trips even when manifest envelope normalizes (e.g.,
/// multi-arch index → single-platform manifest). Robust round-trip fingerprint.
pub(crate) fn rbtdrv_docker_layers_capture(image_ref: &str) -> Result<String, String> {
    let output = Command::new("docker")
        .args(["inspect", "--format={{json .RootFS.Layers}}", image_ref])
        .output()
        .map_err(|e| format!("docker inspect exec failed: {}", e))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
        return Err(format!(
            "docker inspect {} exited {}: {}",
            image_ref,
            output.status.code().unwrap_or(-1),
            stderr
        ));
    }
    let layers = String::from_utf8_lossy(&output.stdout).trim().to_owned();
    if layers.is_empty() || layers == "null" {
        return Err(format!("docker inspect {} returned empty layers", image_ref));
    }
    Ok(layers)
}

/// Docker wrapper: read one image config label's value via inspect's Go-template
/// `index`. Returns the value; an absent key yields an empty string (every
/// conjure image carries hallmark/git.* labels, so `.Config.Labels` is never
/// nil and `index` cannot fault on it). Used to read the rbi_resolved_base_n
/// provenance labels off a summoned consumer image, whose config is
/// byte-identical to the signed attest image's (RBr_b4e).
pub(crate) fn rbtdrv_docker_config_label(image_ref: &str, label_key: &str) -> Result<String, String> {
    let fmt = format!("--format={{{{index .Config.Labels \"{}\"}}}}", label_key);
    let output = Command::new("docker")
        .args(["inspect", &fmt, image_ref])
        .output()
        .map_err(|e| format!("docker inspect exec failed: {}", e))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
        return Err(format!(
            "docker inspect {} exited {}: {}",
            image_ref,
            output.status.code().unwrap_or(-1),
            stderr
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_owned())
}

// Hallmark-lifecycle fixture — round-trip ark inventory across the
// ordain/abjure boundary on a conjure-mode hallmark. Verifies that abjure
// removes every ark basename (image, about, vouch, attest, pouch) without
// collateral damage to other hallmarks in the registry.
//
// Sequence:
//   1. Audit hallmarks → capture baseline.
//   2. Ordain rbev-busybox in conjure mode → capture new hallmark.
//   3. Audit hallmarks → assert baseline ∪ {new_hallmark}.
//   4. Rekon new_hallmark → assert all five basenames yes.
//   5. Abjure new_hallmark.
//   6. Rekon new_hallmark → assert all five basenames not yes.
//   7. Audit hallmarks → assert == baseline (no collateral damage).
//
// rbev-busybox is the load-bearing vessel — small, fast, conjure-mode
// (full ark inventory). Also referenced by rbtdrv_batch_vouch_lifecycle.

pub(crate) const RBTDRV_BUSYBOX_VESSEL_DIR: &str = concat!(crate::rbtd_vessels_dir!(), "/rbev-busybox");

/// All five ark basenames produced by a conjure-mode hallmark.
const ZRBTDRV_ARK_BASENAMES_ALL: &[&str] = &[
    RBTDRV_ARK_BASENAME_IMAGE,
    RBTDRV_ARK_BASENAME_ABOUT,
    RBTDRV_ARK_BASENAME_VOUCH,
    RBTDRV_ARK_BASENAME_ATTEST,
    RBTDRV_ARK_BASENAME_POUCH,
];

/// Multi-fact extension emitted by `rbw-iah` (rbfl_audit_hallmarks): one
/// `<hallmark>.audit-hallmark` file per discovered hallmark. Mirrors
/// rbcc_constants.sh RBCC_fact_ext_audit_hallmark.
const RBTDRV_FACT_EXT_AUDIT_HALLMARK: &str = "audit-hallmark";

/// Single-form chaining fact emitted host-side by `rbw-lE` (rbld_ensconce): the
/// captured Lode touchmark. The derived-pull base-anchor election reads it at
/// conjure; the provenance envelope lives only in GAR (:rbi_vouch), never
/// host-side. Mirrors rbgc_constants.sh RBF_FACT_LODE_TOUCHMARK.
const RBTDRV_FACT_LODE_TOUCHMARK: &str = "rbf_fact_lode_touchmark";

/// Bole-Lode member tags asserted by augur. Mirror rbgc_constants.sh
/// RBGC_LODE_TAG_BOLE / RBGC_LODE_TAG_VOUCH / RBGC_LODE_TAG_DIGEST_PREFIX.
const RBTDRV_LODE_TAG_BOLE: &str = "rbi_bole";
const RBTDRV_LODE_TAG_VOUCH: &str = "rbi_vouch";
const RBTDRV_LODE_TAG_DIGEST_PREFIX: &str = "rbi_sha256-";

/// Envelope-decode markers asserted by augur — values that live *inside* the
/// decoded :rbi_vouch envelope (the trust_grade field and a member's
/// verification field), never in a bare tag listing. Their presence in augur's
/// output is the load-bearing proof that augur decoded the envelope, not merely
/// enumerated tags as divine's retired inspect branch did. Mirror
/// rbgc_constants.sh RBGC_LODE_TRUST_VERIFIED and the rbgjl0* "oci-digest"
/// verification literal.
const RBTDRV_LODE_TRUST_VERIFIED: &str = "verified-against-published";
const RBTDRV_LODE_VERIFICATION_OCI: &str = "oci-digest";

/// Reliquary-Lode member tags asserted by divine inspect — a representative
/// pair of the build-tool cohort (one Google-hosted, one third-party). Compose
/// rbgc_constants.sh RBGC_LODE_TAG_SPRUE with the cohort tool names.
const RBTDRV_RELIQUARY_TAG_GCLOUD: &str = "rbi_gcloud";
const RBTDRV_RELIQUARY_TAG_GCRANE: &str = "rbi_gcrane";

/// GAR Lode package-root — the raw path the type-blind image verbs (rbw-il /
/// rbw-iJ) address a Lode by: rbi_ld/<touchmark>. Mirrors rbgc_constants.sh
/// RBGC_GAR_CATEGORY_LODES.
const RBTDRV_LODES_ROOT: &str = "rbi_ld";

/// Wsl-Lode member tag asserted by divine inspect — the single opaque rootfs
/// blob. Mirrors rbgc_constants.sh RBGC_LODE_TAG_ROOTFS.
const RBTDRV_LODE_TAG_ROOTFS: &str = "rbi_rootfs";

/// Underpin version arguments — the wsl substrate release + point the fixture
/// captures. Declarative version intent (no FQIN); the host assembles the cdimage
/// URL and the cloud step discovers + GPG-verifies the checksum (RBSLU).
const RBTDRV_WSL_RELEASE: &str = "24.04";
const RBTDRV_WSL_POINT: &str = "4";

/// BURE_TWEAK signal recognized by rbld_ensconce (rbldb_bole.sh) to pin the Lode
/// stamp, driving two captures onto one touchmark so the cloud-side collision
/// guard's idempotent/collision branches fire. Mirror: rbldb_bole.sh
/// `z_ensconce_stamp_tweak_name` — same literal. Carries the buo tweak sprue,
/// enforced by BURE.
const RBTDRV_ENSCONCE_STAMP_TWEAK_NAME: &str = "buorb_ensconce_stamp";

/// Re-don cadence tweak value for the hallmark-lifecycle ordain: polls between
/// mid-flight re-dons (RBTDGC_TWEAK_REDON_CADENCE seam). 4 polls × 5 s = 20 s
/// — small enough that even the fastest real build crosses at least one tick,
/// large enough to keep the extra generateAccessToken traffic modest.
const RBTDRV_REDON_CADENCE_POLLS: &str = "4";

/// Re-don announcement fragment asserted in the ordain transcript. Mirror:
/// rbfcb_host.sh `zrbfc_redon_tick` buc_info line — same literal.
const RBTDRV_REDON_ANNOUNCE: &str = "Re-donned the director mantle mid-flight";

/// Debian-base vessel — a DIFFERENT upstream base than busybox, so ensconcing it
/// onto a busybox touchmark trips the collision guard's different-digest branch.
/// Carries the same yoked reliquary as busybox, so host-side tool resolution
/// succeeds and the failure lands cloud-side at the guard, not host-side.
const RBTDRV_DEB_VESSEL_DIR: &str = concat!(crate::rbtd_vessels_dir!(), "/rbev-sentry-deb-tether");

/// Assert a read verb (summon/plumb/augur) exited the vacant band — the named
/// hallmark or Lode is absent from the registry (buc_reject BUBC_band_vacant),
/// the read-side absent-artifact signature rather than a bare death. Shared
/// bookend for the two lifecycle fixtures' post-abjure and post-banish absent
/// moments. No propagation poll (unlike polity-denial's IAM revocation): abjure
/// and banish are synchronous, so the artifact is gone the instant they return.
/// Stamps the stderr for diagnostics; Some(Fail) on any other exit, None on the
/// band.
fn zrbtdrv_expect_vacant(
    result: &rbtdri_InvokeResult,
    label: &str,
    dir: &Path,
    stamp: &str,
) -> Option<rbtdre_Verdict> {
    let _ = std::fs::write(dir.join(stamp), &result.stderr);
    if result.exit_code == RBTDGC_BAND_VACANT {
        None
    } else {
        Some(rbtdre_Verdict::Fail(format!(
            "{}: expected vacant band {} (named artifact absent from registry), got exit {}\nstderr:\n{}",
            label, RBTDGC_BAND_VACANT, result.exit_code, result.stderr
        )))
    }
}

fn rbtdrv_hallmark_lifecycle(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let vessel_dir = RBTDRV_BUSYBOX_VESSEL_DIR;
        if !ctx.project_root().join(vessel_dir).is_dir() {
            return rbtdre_Verdict::Fail(format!("vessel directory not found: {}", vessel_dir));
        }

        // Step 1: baseline audit.
        let _ = std::fs::write(dir.join("01-audit-baseline.txt"), "auditing baseline");
        let baseline_audit = match rbtdri_invoke_global(ctx, RBTDGC_AUDIT_HALLMARKS, &[], &[]) {
            Ok(r) if r.exit_code == 0 => r,
            Ok(r) => return rbtdre_Verdict::Fail(format!("baseline audit failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("baseline audit invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("01-audit-baseline-stdout.txt"), &baseline_audit.stdout);
        let baseline = match rbtdri_read_burv_facts_multi(&baseline_audit, RBTDRV_FACT_EXT_AUDIT_HALLMARK) {
            Ok(v) => v,
            Err(e) => return rbtdre_Verdict::Fail(format!("read baseline audit facts: {}", e)),
        };
        let _ = std::fs::write(dir.join("01-baseline-parsed.txt"), baseline.join("\n"));

        // Step 2: ordain — under the re-don cadence tweak, so this fixture's
        // real short build also exercises the poll's mid-flight re-don
        // (zrbfc_redon_tick; RBS0 rbsk_human_present) on every run, spending
        // no second build on a separate case.
        let hallmark = match rbtdri_ordain_capture(
            ctx,
            dir,
            vessel_dir,
            &[
                (RBTDRI_BURE_TWEAK_NAME_KEY, RBTDGC_TWEAK_REDON_CADENCE),
                (RBTDRI_BURE_TWEAK_VALUE_KEY, RBTDRV_REDON_CADENCE_POLLS),
            ],
            "02-ordain",
        ) {
            Ok(h) => h,
            Err(v) => return v,
        };

        // Step 2b: the re-don announcement must appear in the ordain
        // transcript — the on-cadence observation. BUK dispatch may fold
        // stderr into stdout, so both captured streams are searched.
        let ordain_stdout = std::fs::read_to_string(dir.join("02-ordain-stdout.txt"))
            .unwrap_or_default();
        let ordain_stderr = std::fs::read_to_string(dir.join("02-ordain-stderr.txt"))
            .unwrap_or_default();
        if !ordain_stdout.contains(RBTDRV_REDON_ANNOUNCE)
            && !ordain_stderr.contains(RBTDRV_REDON_ANNOUNCE)
        {
            return rbtdre_Verdict::Fail(format!(
                "re-don cadence: no '{}' announcement in the ordain transcript — the tick never fired under cadence {}",
                RBTDRV_REDON_ANNOUNCE, RBTDRV_REDON_CADENCE_POLLS
            ));
        }

        // Step 3: audit shows new hallmark added.
        let _ = std::fs::write(dir.join("03-audit-after-ordain.txt"), "auditing after ordain");
        let after_ordain_audit = match rbtdri_invoke_global(ctx, RBTDGC_AUDIT_HALLMARKS, &[], &[]) {
            Ok(r) if r.exit_code == 0 => r,
            Ok(r) => return rbtdre_Verdict::Fail(format!("post-ordain audit failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("post-ordain audit invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("03-audit-after-ordain-stdout.txt"), &after_ordain_audit.stdout);
        let after_ordain = match rbtdri_read_burv_facts_multi(&after_ordain_audit, RBTDRV_FACT_EXT_AUDIT_HALLMARK) {
            Ok(v) => v,
            Err(e) => return rbtdre_Verdict::Fail(format!("read post-ordain audit facts: {}", e)),
        };
        let mut expected_after_ordain = baseline.clone();
        expected_after_ordain.push(hallmark.clone());
        expected_after_ordain.sort();
        if after_ordain != expected_after_ordain {
            return rbtdre_Verdict::Fail(format!(
                "post-ordain audit mismatch:\n  expected (baseline + new): {:?}\n  got: {:?}",
                expected_after_ordain, after_ordain
            ));
        }

        // Step 4: rekon shows all five ark basenames present.
        let _ = std::fs::write(dir.join("04-rekon-after-ordain.txt"), "rekoning after ordain");
        let rekon_after_ordain = match rbtdri_invoke_global(ctx, RBTDGC_REKON_HALLMARK, &[&hallmark], &[]) {
            Ok(r) if r.exit_code == 0 => r,
            Ok(r) => return rbtdre_Verdict::Fail(format!("post-ordain rekon failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("post-ordain rekon invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("04-rekon-after-ordain-stdout.txt"), &rekon_after_ordain.stdout);
        for basename in ZRBTDRV_ARK_BASENAMES_ALL {
            if !rbtdrv_rekon_basename_yes(&rekon_after_ordain.stdout, basename) {
                return rbtdre_Verdict::Fail(format!(
                    "post-ordain rekon: basename '{}' not marked yes\nstdout:\n{}",
                    basename, rekon_after_ordain.stdout
                ));
            }
        }

        // Step 5: abjure.
        if let Err(v) = rbtdri_invoke_or_fail(
            ctx,
            "abjure",
            &hallmark,
            RBTDGC_ABJURE_HALLMARK,
            &[&hallmark],
            &[(RBTDRI_BURE_CONFIRM_KEY, RBTDRI_BURE_CONFIRM_SKIP)],
            dir,
            "05-abjure",
        ) {
            return v;
        }

        // Step 6: rekon for the abjured hallmark must exit non-zero — the
        // Unix exit contract is the assertion (rekon's display text is not
        // normative). Stdout captured for diagnostic value only; never read
        // for assertions.
        let _ = std::fs::write(dir.join("06-rekon-after-abjure.txt"), "rekoning after abjure");
        match rbtdri_invoke_global(ctx, RBTDGC_REKON_HALLMARK, &[&hallmark], &[]) {
            Ok(r) if r.exit_code != 0 => {
                let _ = std::fs::write(dir.join("06-rekon-after-abjure-stdout.txt"), &r.stdout);
            }
            Ok(r) => {
                let _ = std::fs::write(dir.join("06-rekon-after-abjure-stdout.txt"), &r.stdout);
                return rbtdre_Verdict::Fail(format!(
                    "post-abjure rekon: expected non-zero exit, got success (exit 0)\nstdout:\n{}",
                    r.stdout
                ));
            }
            Err(e) => return rbtdre_Verdict::Fail(format!("post-abjure rekon invocation: {}", e)),
        }

        // Step 6b: the abjured hallmark is now vacant — summon and plumb must
        // reject with the vacant band (the read-side absent-artifact signature),
        // never a bare death. summon dies at the neither-ark check; plumb at the
        // sole-caller vessel-resolve (no vouch ark), whose band the outer
        // buc_die propagates unchanged through the band membrane. Both are
        // read-only, so they leave the restored-baseline invariant untouched.
        let summon = match rbtdri_invoke_global(ctx, RBTDGC_SUMMON_HALLMARK, &[&hallmark], &[]) {
            Ok(r) => r,
            Err(e) => return rbtdre_Verdict::Fail(format!("post-abjure summon invocation: {}", e)),
        };
        if let Some(v) = zrbtdrv_expect_vacant(&summon, "post-abjure summon", dir, "06b-summon-vacant.txt") {
            return v;
        }
        let plumb = match rbtdri_invoke_global(ctx, RBTDGC_PLUMB_FULL, &[&hallmark], &[]) {
            Ok(r) => r,
            Err(e) => return rbtdre_Verdict::Fail(format!("post-abjure plumb invocation: {}", e)),
        };
        if let Some(v) = zrbtdrv_expect_vacant(&plumb, "post-abjure plumb", dir, "06c-plumb-vacant.txt") {
            return v;
        }

        // Step 7: final audit — registry restored to baseline.
        let _ = std::fs::write(dir.join("07-audit-final.txt"), "auditing final");
        let final_audit = match rbtdri_invoke_global(ctx, RBTDGC_AUDIT_HALLMARKS, &[], &[]) {
            Ok(r) if r.exit_code == 0 => r,
            Ok(r) => return rbtdre_Verdict::Fail(format!("final audit failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("final audit invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("07-audit-final-stdout.txt"), &final_audit.stdout);
        let final_state = match rbtdri_read_burv_facts_multi(&final_audit, RBTDRV_FACT_EXT_AUDIT_HALLMARK) {
            Ok(v) => v,
            Err(e) => return rbtdre_Verdict::Fail(format!("read final audit facts: {}", e)),
        };
        if final_state != baseline {
            return rbtdre_Verdict::Fail(format!(
                "final audit mismatch — abjure did not restore baseline:\n  baseline: {:?}\n  final: {:?}",
                baseline, final_state
            ));
        }

        let _ = std::fs::write(dir.join("08-passed.txt"), "passed");
        rbtdre_Verdict::Pass
    })
}

pub static RBTDRV_CASES_HALLMARK_LIFECYCLE: &[rbtdre_Case] = &[case!(rbtdrv_hallmark_lifecycle)];


// ── Lode round-trip shared blocks ────────────────────────────
// The four Lode round-trip fixtures (lode/reliquary/wsl/podvm-lifecycle) share a
// byte-near-identical capture -> read-touchmark -> divine-contains -> augur ->
// [member-jettison] -> banish -> final-divine skeleton. These helpers home the
// three four-site invariant blocks plus the two-site member-jettison block. The
// six load-bearing per-kind differences stay inline at the call sites by design:
// the capture verb+args, the augur member-tag sets, the trust grade, lode's
// literal-HEAD-commit envelope assertion, podvm's refresh+cohort-count
// sub-sequence and trust-posture prose, and the jettison step's reliquary+podvm-
// only presence.

/// Read the bare Lode touchmark fact from a capture invocation and stamp it to
/// the case scratch dir. The host-side capture handoff is identical across every
/// Lode kind; only the capture result differs. Ok(touchmark) to continue,
/// Err(Fail) to short-circuit on a missing/empty fact.
fn zrbtdrv_read_touchmark(
    result: &rbtdri_InvokeResult,
    dir: &Path,
) -> Result<String, rbtdre_Verdict> {
    let touchmark = rbtdri_read_burv_fact(result, RBTDRV_FACT_LODE_TOUCHMARK)
        .map_err(|e| rbtdre_Verdict::Fail(format!("read touchmark fact: {}", e)))?;
    let _ = std::fs::write(dir.join("02-touchmark.txt"), &touchmark);
    Ok(touchmark)
}

/// Divine-enumerate the Lodes and confirm the just-captured touchmark appears.
/// `verb_label` preserves the per-kind Fail-message diagnostic (ensconce /
/// conclave / underpin / immure). Returns the divine stdout on success so a kind
/// can layer extra inline assertions (podvm's cohort-count) on the same output.
fn zrbtdrv_divine_contains(
    ctx: &mut rbtdri_Context,
    dir: &Path,
    touchmark: &str,
    verb_label: &str,
) -> Result<String, rbtdre_Verdict> {
    let after = match rbtdri_invoke_global(ctx, RBTDGC_DIVINE_LODES, &[], &[]) {
        Ok(r) if r.exit_code == 0 => r,
        Ok(r) => return Err(rbtdre_Verdict::Fail(format!("post-{} divine failed (exit {})\n{}", verb_label, r.exit_code, r.stderr))),
        Err(e) => return Err(rbtdre_Verdict::Fail(format!("post-{} divine invocation: {}", verb_label, e))),
    };
    let _ = std::fs::write(dir.join("03-divine-after.txt"), &after.stdout);
    if !after.stdout.contains(touchmark) {
        return Err(rbtdre_Verdict::Fail(format!(
            "post-{} divine missing touchmark {}\nstdout:\n{}",
            verb_label, touchmark, after.stdout
        )));
    }
    Ok(after.stdout)
}

/// Banish the whole Lode (confirm-skip) and confirm a final divine no longer
/// shows the touchmark — the registry-restored bookend, byte-identical across
/// every Lode kind. Some(Fail) to short-circuit, None to continue.
fn zrbtdrv_banish_and_verify_gone(
    ctx: &mut rbtdri_Context,
    dir: &Path,
    touchmark: &str,
) -> Option<rbtdre_Verdict> {
    let _ = std::fs::write(dir.join("05-banish.txt"), "banishing");
    match rbtdri_invoke_global(
        ctx,
        RBTDGC_BANISH_LODE,
        &[touchmark],
        &[(RBTDRI_BURE_CONFIRM_KEY, RBTDRI_BURE_CONFIRM_SKIP)],
    ) {
        Ok(r) if r.exit_code == 0 => {}
        Ok(r) => return Some(rbtdre_Verdict::Fail(format!("banish failed (exit {})\n{}", r.exit_code, r.stderr))),
        Err(e) => return Some(rbtdre_Verdict::Fail(format!("banish invocation: {}", e))),
    }
    let final_divine = match rbtdri_invoke_global(ctx, RBTDGC_DIVINE_LODES, &[], &[]) {
        Ok(r) if r.exit_code == 0 => r,
        Ok(r) => return Some(rbtdre_Verdict::Fail(format!("final divine failed (exit {})\n{}", r.exit_code, r.stderr))),
        Err(e) => return Some(rbtdre_Verdict::Fail(format!("final divine invocation: {}", e))),
    };
    let _ = std::fs::write(dir.join("06-divine-final.txt"), &final_divine.stdout);
    if final_divine.stdout.contains(touchmark) {
        return Some(rbtdre_Verdict::Fail(format!(
            "final divine still shows banished touchmark {} — banish did not restore baseline\nstdout:\n{}",
            touchmark, final_divine.stdout
        )));
    }
    None
}

/// Member-grain jettison proof for the multi-member Lode kinds (reliquary +
/// podvm): raw-list the cohort and assert both tags present, jettison the victim
/// tag via the type-blind raw verb, then re-list and assert the victim gone while
/// the survivor remains. Emits the 04b/04c/04d scratch files. Some(Fail) to
/// short-circuit, None to continue.
fn zrbtdrv_member_jettison_proof(
    ctx: &mut rbtdri_Context,
    dir: &Path,
    touchmark: &str,
    victim_tag: &str,
    survivor_tag: &str,
) -> Option<rbtdre_Verdict> {
    let lode_path = format!("{}/{}", RBTDRV_LODES_ROOT, touchmark);
    let member_ref = format!("{}:{}", lode_path, victim_tag);

    let pre_list = match rbtdri_invoke_global(ctx, RBTDGC_LIST_IMAGES, &[&lode_path], &[]) {
        Ok(r) if r.exit_code == 0 => r,
        Ok(r) => return Some(rbtdre_Verdict::Fail(format!("pre-jettison list failed (exit {})\n{}", r.exit_code, r.stderr))),
        Err(e) => return Some(rbtdre_Verdict::Fail(format!("pre-jettison list invocation: {}", e))),
    };
    let _ = std::fs::write(dir.join("04b-list-before-jettison.txt"), &pre_list.stdout);
    for member in &[survivor_tag, victim_tag] {
        if !pre_list.stdout.contains(member) {
            return Some(rbtdre_Verdict::Fail(format!(
                "pre-jettison raw list missing member tag '{}'\nstdout:\n{}",
                member, pre_list.stdout
            )));
        }
    }

    let _ = std::fs::write(dir.join("04c-jettison-member.txt"), &member_ref);
    match rbtdri_invoke_global(
        ctx,
        RBTDGC_JETTISON_IMAGE,
        &[&member_ref],
        &[(RBTDRI_BURE_CONFIRM_KEY, RBTDRI_BURE_CONFIRM_SKIP)],
    ) {
        Ok(r) if r.exit_code == 0 => {}
        Ok(r) => return Some(rbtdre_Verdict::Fail(format!("member jettison failed (exit {})\n{}", r.exit_code, r.stderr))),
        Err(e) => return Some(rbtdre_Verdict::Fail(format!("member jettison invocation: {}", e))),
    }

    let post_list = match rbtdri_invoke_global(ctx, RBTDGC_LIST_IMAGES, &[&lode_path], &[]) {
        Ok(r) if r.exit_code == 0 => r,
        Ok(r) => return Some(rbtdre_Verdict::Fail(format!("post-jettison list failed (exit {})\n{}", r.exit_code, r.stderr))),
        Err(e) => return Some(rbtdre_Verdict::Fail(format!("post-jettison list invocation: {}", e))),
    };
    let _ = std::fs::write(dir.join("04d-list-after-jettison.txt"), &post_list.stdout);
    if post_list.stdout.contains(victim_tag) {
        return Some(rbtdre_Verdict::Fail(format!(
            "post-jettison list still shows jettisoned member '{}' — member-grain delete failed\nstdout:\n{}",
            victim_tag, post_list.stdout
        )));
    }
    if !post_list.stdout.contains(survivor_tag) {
        return Some(rbtdre_Verdict::Fail(format!(
            "post-jettison list missing sibling member '{}' — jettison damaged the Lode\nstdout:\n{}",
            survivor_tag, post_list.stdout
        )));
    }
    None
}

// Lode-lifecycle fixture — fetched-side base capture against live GAR. Single
// self-contained round-trip: ensconce the busybox base into a fresh rbi_ld
// Lode, divine-enumerate to confirm it appears, augur to confirm the member
// tags AND the decoded :rbi_vouch envelope rode in, banish the whole Lode, then
// divine-enumerate to confirm the registry is restored. Parallel to hallmark-lifecycle
// on the made side. Requires a reliquary yoked on the busybox vessel (same
// precondition hallmark-lifecycle's ordain carries).
fn rbtdrv_lode_lifecycle(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let vessel_dir = RBTDRV_BUSYBOX_VESSEL_DIR;
        if !ctx.project_root().join(vessel_dir).is_dir() {
            return rbtdre_Verdict::Fail(format!("vessel directory not found: {}", vessel_dir));
        }

        // Step 1: ensconce the busybox base into a fresh Lode.
        let _ = std::fs::write(dir.join("01-ensconce.txt"), "ensconcing busybox base");
        let ensconce = match rbtdri_invoke_global(ctx, RBTDGC_ENSCONCE_BOLE, &[vessel_dir], &[]) {
            Ok(r) if r.exit_code == 0 => r,
            Ok(r) => return rbtdre_Verdict::Fail(format!("ensconce failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("ensconce invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("01-ensconce-stdout.txt"), &ensconce.stdout);

        // The host-side capture handoff is the bare touchmark fact.
        let touchmark = match zrbtdrv_read_touchmark(&ensconce, dir) {
            Ok(t) => t,
            Err(v) => return v,
        };

        // Step 2: divine enumerate shows the new Lode.
        if let Err(v) = zrbtdrv_divine_contains(ctx, dir, &touchmark, "ensconce") {
            return v;
        }

        // Step 3: augur inspects the single Lode — member tags AND the decoded
        // :rbi_vouch envelope. This is the explicit augur-decode case: beyond the
        // member tags (which the retired divine inspect branch also listed), it
        // asserts the envelope's own fields surfaced — the trust grade and a
        // member's verification — proving augur read vouch.json, not merely
        // enumerated tags.
        let augur = match rbtdri_invoke_global(ctx, RBTDGC_AUGUR_LODE, &[&touchmark], &[]) {
            Ok(r) if r.exit_code == 0 => r,
            Ok(r) => return rbtdre_Verdict::Fail(format!("augur failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("augur invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("04-augur.txt"), &augur.stdout);
        for member in &[RBTDRV_LODE_TAG_BOLE, RBTDRV_LODE_TAG_VOUCH, RBTDRV_LODE_TAG_DIGEST_PREFIX] {
            if !augur.stdout.contains(member) {
                return rbtdre_Verdict::Fail(format!(
                    "augur missing member tag '{}'\nstdout:\n{}",
                    member, augur.stdout
                ));
            }
        }
        // Envelope-decode assertions — the new logic. These markers live inside
        // vouch.json (trust_grade, a member's verification), never in a tag list.
        for field in &[RBTDRV_LODE_TRUST_VERIFIED, RBTDRV_LODE_VERIFICATION_OCI] {
            if !augur.stdout.contains(field) {
                return rbtdre_Verdict::Fail(format!(
                    "augur did not decode :rbi_vouch envelope — missing '{}'\nstdout:\n{}",
                    field, augur.stdout
                ));
            }
        }
        // The envelope also carries the dispatching HEAD commit (rblv_git_commit,
        // spine-injected substitution spliced at the shared vouch-push step).
        // Assert the literal hash, not mere field presence — proving the value
        // survived host -> substitution -> splice -> GAR -> augur decode. HEAD
        // cannot have moved since dispatch: ensconce gated a clean tree and this
        // fixture commits nothing.
        let head = match Command::new("git")
            .args(["rev-parse", "HEAD"])
            .current_dir(ctx.project_root())
            .output()
        {
            Ok(out) if out.status.success() => {
                String::from_utf8_lossy(&out.stdout).trim().to_string()
            }
            Ok(out) => {
                return rbtdre_Verdict::Fail(format!(
                    "git rev-parse HEAD failed (exit {}): {}",
                    out.status.code().unwrap_or(-1),
                    String::from_utf8_lossy(&out.stderr).trim()
                ))
            }
            Err(e) => return rbtdre_Verdict::Fail(format!("git rev-parse invocation: {}", e)),
        };
        if !augur.stdout.contains(&head) {
            return rbtdre_Verdict::Fail(format!(
                "augur envelope missing dispatching commit {}\nstdout:\n{}",
                head, augur.stdout
            ));
        }

        // Step 4: banish the whole Lode, then confirm the registry is restored.
        if let Some(v) = zrbtdrv_banish_and_verify_gone(ctx, dir, &touchmark) {
            return v;
        }

        // Step 5: the banished Lode is now vacant — augur must reject with the
        // vacant band (its empty-tags "Lode not present" signal), never a bare
        // death.
        let augur_gone = match rbtdri_invoke_global(ctx, RBTDGC_AUGUR_LODE, &[&touchmark], &[]) {
            Ok(r) => r,
            Err(e) => return rbtdre_Verdict::Fail(format!("post-banish augur invocation: {}", e)),
        };
        if let Some(v) = zrbtdrv_expect_vacant(&augur_gone, "post-banish augur", dir, "06b-augur-vacant.txt") {
            return v;
        }

        let _ = std::fs::write(dir.join("07-passed.txt"), "passed");
        rbtdre_Verdict::Pass
    })
}

// Lode-collision case — exercises the cloud-side touchmark collision guard
// (rbgjl01-ensconce-capture.sh). The guard cannot fire under natural minting:
// each ensconce mints a fresh second-grained stamp, so two CLI captures land on
// distinct touchmarks. We pin the stamp via the buo tweak channel
// (RBTDRV_ENSCONCE_STAMP_TWEAK_NAME) to drive both captures onto ONE touchmark.
//
// Sequence: (1) ensconce busybox naturally -> mint touchmark S, read it back;
// (2) ensconce busybox pinned to S -> identical digest, guard's idempotent
// branch, exit 0; (3) ensconce debian pinned to S -> different digest under the
// same touchmark, guard's collision branch, host exit non-zero; (4) banish S.
//
// The collision verdict rests on the HOST EXIT CODE: the guard's "touchmark
// collision" message lands in Cloud Logging (CLOUD_LOGGING_ONLY), not host
// stdout, but a cloud build FAILURE propagates to a non-zero rbw-lE exit
// (rbfcb_host.sh: status != SUCCESS -> buc_die). The idempotent step (2) is
// the positive control: the identical pipeline on the same pinned touchmark
// SUCCEEDS for the same base, so step (3)'s failure isolates to the differing
// digest — the collision branch — not debian-specific infra. Both vessels carry
// the same yoked reliquary, so host-side tool resolution is identical.
fn rbtdrv_lode_collision(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let busybox_dir = RBTDRV_BUSYBOX_VESSEL_DIR;
        let deb_dir = RBTDRV_DEB_VESSEL_DIR;
        for vd in &[busybox_dir, deb_dir] {
            if !ctx.project_root().join(vd).is_dir() {
                return rbtdre_Verdict::Fail(format!("vessel directory not found: {}", vd));
            }
        }

        // Step 1: ensconce busybox naturally; read back the minted touchmark S.
        let _ = std::fs::write(dir.join("01-ensconce-fresh.txt"), "ensconcing busybox (fresh, natural mint)");
        let fresh = match rbtdri_invoke_global(ctx, RBTDGC_ENSCONCE_BOLE, &[busybox_dir], &[]) {
            Ok(r) if r.exit_code == 0 => r,
            Ok(r) => return rbtdre_Verdict::Fail(format!("fresh ensconce failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("fresh ensconce invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("01-ensconce-fresh-stdout.txt"), &fresh.stdout);
        let touchmark = match rbtdri_read_burv_fact(&fresh, RBTDRV_FACT_LODE_TOUCHMARK) {
            Ok(v) => v,
            Err(e) => return rbtdre_Verdict::Fail(format!("read touchmark fact: {}", e)),
        };
        let _ = std::fs::write(dir.join("02-touchmark.txt"), &touchmark);

        let pin = &[
            ("BURE_TWEAK_NAME", RBTDRV_ENSCONCE_STAMP_TWEAK_NAME),
            ("BURE_TWEAK_VALUE", touchmark.as_str()),
        ];

        // Step 2 (positive control): ensconce busybox pinned to S — identical
        // digest under the same touchmark — guard's idempotent branch — must PASS.
        let _ = std::fs::write(dir.join("03-ensconce-idempotent.txt"), "ensconcing busybox pinned to S (identical digest)");
        let idem = match rbtdri_invoke_global(ctx, RBTDGC_ENSCONCE_BOLE, &[busybox_dir], pin) {
            Ok(r) if r.exit_code == 0 => r,
            Ok(r) => return rbtdre_Verdict::Fail(format!(
                "idempotent ensconce (same base, same touchmark) should pass but failed (exit {})\n{}",
                r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("idempotent ensconce invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("03-ensconce-idempotent-stdout.txt"), &idem.stdout);

        // Step 3: ensconce debian pinned to S — different digest under the same
        // touchmark — guard's collision branch — host exit must be non-zero.
        let _ = std::fs::write(dir.join("04-ensconce-collision.txt"), "ensconcing debian pinned to S (different digest -> collision)");
        let collision = match rbtdri_invoke_global(ctx, RBTDGC_ENSCONCE_BOLE, &[deb_dir], pin) {
            Ok(r) => r,
            Err(e) => return rbtdre_Verdict::Fail(format!("collision ensconce invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("04-ensconce-collision-stdout.txt"), &collision.stdout);
        let _ = std::fs::write(dir.join("04-ensconce-collision-stderr.txt"), &collision.stderr);
        if collision.exit_code == 0 {
            return rbtdre_Verdict::Fail(format!(
                "collision ensconce (different base, same touchmark {}) should fail loud but exited 0\nstdout:\n{}",
                touchmark, collision.stdout));
        }

        // Step 4: banish S — cleanup (removes the busybox Lode steps 1-2 left;
        // the collision step wrote nothing, dying before the GAR copy).
        let _ = std::fs::write(dir.join("05-banish.txt"), "banishing");
        match rbtdri_invoke_global(
            ctx,
            RBTDGC_BANISH_LODE,
            &[&touchmark],
            &[(RBTDRI_BURE_CONFIRM_KEY, RBTDRI_BURE_CONFIRM_SKIP)],
        ) {
            Ok(r) if r.exit_code == 0 => {}
            Ok(r) => return rbtdre_Verdict::Fail(format!("banish failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("banish invocation: {}", e)),
        }

        // Step 5: divine enumerate no longer shows S — registry restored.
        let final_divine = match rbtdri_invoke_global(ctx, RBTDGC_DIVINE_LODES, &[], &[]) {
            Ok(r) if r.exit_code == 0 => r,
            Ok(r) => return rbtdre_Verdict::Fail(format!("final divine failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("final divine invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("06-divine-final.txt"), &final_divine.stdout);
        if final_divine.stdout.contains(&touchmark) {
            return rbtdre_Verdict::Fail(format!(
                "final divine still shows banished touchmark {} — cleanup failed\nstdout:\n{}",
                touchmark, final_divine.stdout));
        }

        let _ = std::fs::write(dir.join("07-passed.txt"), "passed");
        rbtdre_Verdict::Pass
    })
}

pub static RBTDRV_CASES_LODE_LIFECYCLE: &[rbtdre_Case] = &[
    case!(rbtdrv_lode_lifecycle),
    case!(rbtdrv_lode_collision),
];


// Chaining-fact livery fixture — the cloud sibling of the local chaining-fact
// band matrix (rbtdrh_chain.rs). That matrix proves the chain LINKS' rejection
// bands by hand-SEEDING a synthetic touchmark into previous/; it can only
// simulate the producer. This fixture proves the GENUINE producer->consumer
// succession end-to-end: a real bole ensconce captures a base into live GAR and
// hands its touchmark forward as a chaining fact, chain_next_invoke wires that
// capture's BURV root into the following feoff, and the real feoff reads the
// chained fact from previous/ and elects the base anchor. It catches drift the
// synthetic matrix cannot — between what a live ensconce WRITES to current/ and
// what a live feoff READS from previous/.
//
// Distinct from onboarding-sequence's tracked-vessel ensconce->feoff (the same
// chain against a committed forge vessel, gauntlet-tier): this rides PICKET tier
// and feoffs a STAGED TEMP vessel resolved by path, touching no tracked config
// and committing nothing (band-matrix discipline, rbtdrh_chain.rs the model).
// feoff itself makes no GAR call — it composes the locator from the decoded
// touchmark (RBSDF) — so the live ensconce is what makes the chained touchmark
// real; the registry confirmation is conjure's at a later build, not feoff's.
//
// The touchmark is pinned to a fixed bole-shaped value via the ensconce-stamp
// tweak (the lode-collision precedent), giving the reset a stable banish handle:
// a prior crashed run leaves a Lode at exactly this touchmark, which would trip
// the cloud collision guard on the next ensconce. The case OPENS by re-
// establishing the absent-Lode baseline (load-bearing) and CLOSES by banishing
// best-effort regardless of verdict, so a mid-case failure still cleans up and a
// crash is recovered by the next run's opening reset. Both go through one
// divine-then-banish helper, because banish dies on an absent Lode (rbld_banish:
// "nothing to banish"). The reset lives in the case body, not a setup hook: the
// single-case runner reserves a setup hook for crucible charge, and this fixture
// charges no crucible.

/// Fixed bole touchmark this fixture pins via the ensconce-stamp tweak. The shape
/// is the band matrix's synthetic bole-seed shape — RBGC_LODE_KIND_BOLE 'b' + a
/// 12-digit YYMMDDHHMMSS stamp (cf. rbtdrh_chain.rs RBTDRH_BOLE_TOUCHMARK) — but
/// a deterministic value rather than a clock mint, so setup has a stable handle
/// and the elected anchor is predictable. ensconce takes BURE_TWEAK_VALUE
/// verbatim as the stamp (rbldb_bole.sh), so this becomes the captured Lode's
/// touchmark and the chained fact the feoff consumes.
const RBTDRV_LIVERY_TOUCHMARK: &str = "b260623000000";

/// The staged temp vessel's rbrv.env — one populated base ORIGIN slot, which is
/// all feoff needs to locate the slot whose ANCHOR it elects, and NO ANCHOR line,
/// so an RBRV_IMAGE_1_ANCHOR= present after feoff proves the write fired (a no-op
/// would leave the file ORIGIN-only). feoff never reads this origin's value;
/// busybox is the real yoked vessel the live ensconce actually captures from.
const RBTDRV_LIVERY_VESSEL_RBRV: &str = "RBRV_IMAGE_1_ORIGIN=docker.io/library/debian:bookworm\n";

/// Reset the fixture's pinned Lode to absent (idempotent). divine-then-banish:
/// banish dies on an absent Lode, so probe presence first and banish only when
/// the pinned touchmark is live. Shared by setup (load-bearing baseline) and
/// teardown (best-effort cleanup).
fn zrbtdrv_chaining_livery_reset(ctx: &mut rbtdri_Context) -> Result<(), String> {
    let divine = rbtdri_invoke_global(ctx, RBTDGC_DIVINE_LODES, &[], &[])
        .map_err(|e| format!("livery reset divine invocation: {}", e))?;
    if divine.exit_code != 0 {
        return Err(format!(
            "livery reset divine failed (exit {})\n{}",
            divine.exit_code, divine.stderr
        ));
    }
    if !divine.stdout.contains(RBTDRV_LIVERY_TOUCHMARK) {
        // Pinned Lode already absent — clean baseline, nothing to banish.
        return Ok(());
    }
    match rbtdri_invoke_global(
        ctx,
        RBTDGC_BANISH_LODE,
        &[RBTDRV_LIVERY_TOUCHMARK],
        &[(RBTDRI_BURE_CONFIRM_KEY, RBTDRI_BURE_CONFIRM_SKIP)],
    ) {
        Ok(r) if r.exit_code == 0 => Ok(()),
        Ok(r) => Err(format!(
            "livery reset banish failed (exit {})\n{}",
            r.exit_code, r.stderr
        )),
        Err(e) => Err(format!("livery reset banish invocation: {}", e)),
    }
}

/// The case: OPEN by re-establishing the absent-Lode baseline (load-bearing —
/// the cloud collision guard would trip on a leaked prior Lode at the pinned
/// touchmark), run the real ensconce->chain->feoff succession, then CLOSE by
/// banishing best-effort regardless of verdict so a mid-case failure still
/// cleans up. The reset is in the body, not a setup hook, because the single-case
/// runner reserves a setup hook for crucible charge and this fixture charges none.
fn rbtdrv_chaining_livery(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        if let Err(e) = zrbtdrv_chaining_livery_reset(ctx) {
            return rbtdre_Verdict::Fail(format!("baseline reset (banish-if-present): {}", e));
        }
        let verdict = zrbtdrv_chaining_livery_body(ctx, dir);
        // Best-effort cleanup, regardless of verdict — banish the Lode the body
        // captured. A crash that skips this is recovered by the next run's opening
        // reset (the pinned touchmark is the stable handle).
        if let Err(e) = zrbtdrv_chaining_livery_reset(ctx) {
            crate::rbtdrg_error_now!("chaining-livery cleanup banish: {}", e);
        }
        verdict
    })
}

/// The real producer->consumer succession, lifted out of the case wrapper so the
/// reset/cleanup bookend can frame it. Takes ctx directly (the wrapper already
/// holds the thread-local borrow — a nested rbtdrc_with_ctx would double-borrow).
fn zrbtdrv_chaining_livery_body(ctx: &mut rbtdri_Context, dir: &Path) -> rbtdre_Verdict {
    let busybox_dir = RBTDRV_BUSYBOX_VESSEL_DIR;
    if !ctx.project_root().join(busybox_dir).is_dir() {
        return rbtdre_Verdict::Fail(format!("vessel directory not found: {}", busybox_dir));
    }

    // Step 1: real bole ensconce of the busybox base, pinned to the fixed
    // touchmark via the ensconce-stamp tweak. ensconce captures into live GAR
    // and emits the touchmark chaining fact to current/ — the real producer.
    let _ = std::fs::write(dir.join("01-ensconce.txt"), "ensconcing busybox base, pinned");
    let pin = &[
        (RBTDRI_BURE_TWEAK_NAME_KEY, RBTDRV_ENSCONCE_STAMP_TWEAK_NAME),
        (RBTDRI_BURE_TWEAK_VALUE_KEY, RBTDRV_LIVERY_TOUCHMARK),
    ];
    let ensconce = match rbtdri_invoke_global(ctx, RBTDGC_ENSCONCE_BOLE, &[busybox_dir], pin) {
        Ok(r) if r.exit_code == 0 => r,
        Ok(r) => return rbtdre_Verdict::Fail(format!("ensconce failed (exit {})\n{}", r.exit_code, r.stderr)),
        Err(e) => return rbtdre_Verdict::Fail(format!("ensconce invocation: {}", e)),
    };
    let _ = std::fs::write(dir.join("01-ensconce-stdout.txt"), &ensconce.stdout);

    // The producer's handoff is the bare touchmark fact in current/. Read it
    // now, BEFORE the chained feoff promotes current/ into previous/ (where
    // feoff reads it but this read no longer would).
    let touchmark = match rbtdri_read_burv_fact(&ensconce, RBTDRV_FACT_LODE_TOUCHMARK) {
        Ok(v) => v,
        Err(e) => return rbtdre_Verdict::Fail(format!("read touchmark fact: {}", e)),
    };
    let _ = std::fs::write(dir.join("02-touchmark.txt"), &touchmark);

    // The real touchmark must be the pinned value (ensconce honored the stamp
    // and round-tripped it through the fact) AND carry the band matrix's
    // synthetic bole-seed shape: 'b' + 12 digits (cf. rbtdrh_chain.rs
    // RBTDRH_BOLE_TOUCHMARK) — the proof that synthetic seed is faithful to
    // what a live ensconce emits and a live feoff consumes.
    if touchmark != RBTDRV_LIVERY_TOUCHMARK {
        return rbtdre_Verdict::Fail(format!(
            "ensconce emitted touchmark '{}', expected the pinned '{}' (stamp tweak not honored?)",
            touchmark, RBTDRV_LIVERY_TOUCHMARK
        ));
    }
    let shape_ok = touchmark.len() == 13
        && touchmark.starts_with('b')
        && touchmark[1..].chars().all(|c| c.is_ascii_digit());
    if !shape_ok {
        return rbtdre_Verdict::Fail(format!(
            "real ensconce touchmark '{}' is not the bole-seed shape ('b' + 12 digits)",
            touchmark
        ));
    }

    // Step 2: stage a temp vessel and chain feoff off the ensconce. The chain
    // makes feoff reuse the ensconce's BURV root, so bud promotes the touchmark
    // from current/ into feoff's previous/ — the operator's shared ../output-buk
    // flow, restored for exactly this pair (rbtdri chain_next). feoff resolves
    // the vessel by PATH, so its rbrv.env rewrite lands in the case temp dir — no
    // tracked config is touched. No express touchmark is passed, so feoff MUST
    // take the value from the chain or die loud.
    let vessel_dir = dir.join("vessel");
    if let Err(e) = std::fs::create_dir_all(&vessel_dir) {
        return rbtdre_Verdict::Fail(format!("stage vessel dir: {}", e));
    }
    let rbrv = vessel_dir.join(RBTDGC_RBRV_FILE);
    if let Err(e) = std::fs::write(&rbrv, RBTDRV_LIVERY_VESSEL_RBRV) {
        return rbtdre_Verdict::Fail(format!("stage rbrv.env: {}", e));
    }
    let vessel_posix = crate::rbtdrx_platform::rbtdrx_native_to_posix(&vessel_dir);

    ctx.chain_next_invoke();
    let _ = std::fs::write(dir.join("03-feoff.txt"), "feoffing temp vessel off chained touchmark");
    let feoff = match rbtdri_invoke_global(
        ctx,
        RBTDGC_FEOFF_BOLE,
        &[vessel_posix.as_str()],
        &[(RBTDRI_BURE_CONFIRM_KEY, RBTDRI_BURE_CONFIRM_SKIP)],
    ) {
        Ok(r) if r.exit_code == 0 => r,
        Ok(r) => return rbtdre_Verdict::Fail(format!(
            "feoff failed (exit {}) — the ensconce->feoff chain may not have carried the touchmark\n{}",
            r.exit_code, r.stderr
        )),
        Err(e) => return rbtdre_Verdict::Fail(format!("feoff invocation: {}", e)),
    };
    let _ = std::fs::write(dir.join("03-feoff-stdout.txt"), &feoff.stdout);

    // Step 3: the temp vessel's elected anchor must bear the REAL chained
    // touchmark's bole locator. The staged rbrv.env carried no ANCHOR line, so
    // an RBRV_IMAGE_1_ANCHOR= bearing '<touchmark>:rbi_bole' proves both that
    // feoff wrote (no no-op) and that it elected the touchmark the live ensconce
    // handed forward through the chain. Read the config file, never a printout
    // scrape.
    let content = std::fs::read_to_string(&rbrv).unwrap_or_default();
    let _ = std::fs::write(dir.join("04-vessel-rbrv.env"), &content);
    let bole_locator = format!("{}:{}", touchmark, RBTDRV_LODE_TAG_BOLE);
    if content.contains("RBRV_IMAGE_1_ANCHOR=") && content.contains(&bole_locator) {
        let _ = std::fs::write(dir.join("05-passed.txt"), "passed");
        rbtdre_Verdict::Pass
    } else {
        rbtdre_Verdict::Fail(format!(
            "feoff did not elect the chained bole locator '{}' into the temp vessel; rbrv.env:\n{}",
            bole_locator, content
        ))
    }
}

pub static RBTDRV_CASES_CHAINING_LIVERY: &[rbtdre_Case] = &[case!(rbtdrv_chaining_livery)];


// Reliquary-lifecycle fixture — fetched-side cohort capture against live GAR.
// Single self-contained round-trip: conclave the build-tool cohort into a fresh
// rbi_ld Lode, divine-enumerate to confirm it appears, divine-inspect to confirm
// the member tags + vouch envelope rode in, member-grain jettison one member tag
// via the type-blind raw verbs (rbw-il enumerate, rbw-iJ delete) and confirm the
// member is gone while a sibling survives, banish the whole Lode, then divine-
// enumerate to confirm the registry is restored. The reliquary kind's N-member
// cohort analogue of lode-lifecycle's single-image bole round-trip, and the home
// of the per-member-delete assertion the multi-member kinds need (the podvm
// fixture builds on it). Conclave captures a fixed tool cohort, so it needs no
// vessel precondition.
fn rbtdrv_reliquary_lifecycle(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        // Step 1: conclave the build-tool cohort into a fresh Lode.
        let _ = std::fs::write(dir.join("01-conclave.txt"), "conclaving build-tool cohort");
        let conclave = match rbtdri_invoke_global(ctx, RBTDGC_CONCLAVE_RELIQUARY, &[], &[]) {
            Ok(r) if r.exit_code == 0 => r,
            Ok(r) => return rbtdre_Verdict::Fail(format!("conclave failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("conclave invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("01-conclave-stdout.txt"), &conclave.stdout);

        // The host-side capture handoff is the bare touchmark fact.
        let touchmark = match zrbtdrv_read_touchmark(&conclave, dir) {
            Ok(t) => t,
            Err(v) => return v,
        };

        // Step 2: divine enumerate shows the new Lode.
        if let Err(v) = zrbtdrv_divine_contains(ctx, dir, &touchmark, "conclave") {
            return v;
        }

        // Step 3: augur inspects the cohort Lode — member tags AND the decoded
        // :rbi_vouch envelope. The trust-grade assertion proves augur decodes the
        // N-member (cardinality-N) envelope, not just the bole singleton's.
        let augur = match rbtdri_invoke_global(ctx, RBTDGC_AUGUR_LODE, &[&touchmark], &[]) {
            Ok(r) if r.exit_code == 0 => r,
            Ok(r) => return rbtdre_Verdict::Fail(format!("augur failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("augur invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("04-augur.txt"), &augur.stdout);
        for member in &[RBTDRV_RELIQUARY_TAG_GCLOUD, RBTDRV_RELIQUARY_TAG_GCRANE, RBTDRV_LODE_TAG_VOUCH] {
            if !augur.stdout.contains(member) {
                return rbtdre_Verdict::Fail(format!(
                    "augur missing member tag '{}'\nstdout:\n{}",
                    member, augur.stdout
                ));
            }
        }
        if !augur.stdout.contains(RBTDRV_LODE_TRUST_VERIFIED) {
            return rbtdre_Verdict::Fail(format!(
                "augur did not decode cohort :rbi_vouch envelope — missing trust grade '{}'\nstdout:\n{}",
                RBTDRV_LODE_TRUST_VERIFIED, augur.stdout
            ));
        }

        // Step 3.5: member-grain jettison via the type-blind raw verbs — delete
        // one member tag and prove it gone while a sibling survives.
        if let Some(v) = zrbtdrv_member_jettison_proof(
            ctx,
            dir,
            &touchmark,
            RBTDRV_RELIQUARY_TAG_GCRANE,
            RBTDRV_RELIQUARY_TAG_GCLOUD,
        ) {
            return v;
        }

        // Step 4: banish the whole Lode, then confirm the registry is restored.
        if let Some(v) = zrbtdrv_banish_and_verify_gone(ctx, dir, &touchmark) {
            return v;
        }

        let _ = std::fs::write(dir.join("07-passed.txt"), "passed");
        rbtdre_Verdict::Pass
    })
}

pub static RBTDRV_CASES_RELIQUARY_LIFECYCLE: &[rbtdre_Case] = &[case!(rbtdrv_reliquary_lifecycle)];


// Shared payor-credential probe-and-gate preamble for the four credentialed-service
// fixtures below. The probe is identical; the verdict on a non-green probe is
// policy-split:
//   Skip — the terrier pair: auto-suite members, so an absent credential is
//     suite-passenger protection (terse, exit-code-only message).
//   Fail — the foedus pair: operator-invoked only (never a passenger), so an
//     absent credential fails the run and dumps the probe's stdout/stderr verbatim.
// The policy carries the whole per-policy verdict template, not just a Skip|Fail
// flag, precisely because the Fail side's stdout/stderr dump has no Skip analogue.
enum zrbtdrv_PayorGatePolicy {
    Skip,
    Fail,
}

/// Probe the payor credential; return None when green (caller proceeds), or
/// Some(verdict) when the gate trips. `fixture` is interpolated into the message
/// (pass the RBTDRM_FIXTURE_* constant), so each call reproduces its prior
/// open-coded verdict byte-for-byte.
fn zrbtdrv_payor_gate(
    ctx: &mut rbtdri_Context,
    dir: &Path,
    fixture: &str,
    policy: zrbtdrv_PayorGatePolicy,
) -> Option<rbtdre_Verdict> {
    let _ = std::fs::write(dir.join("01-payor-probe.txt"), "probing payor credential");
    match rbtdri_invoke_global(ctx, RBTDGC_CHECK_PAYOR, &[], &[]) {
        Ok(r) if r.exit_code == 0 => None,
        Ok(r) => Some(match policy {
            zrbtdrv_PayorGatePolicy::Skip => rbtdre_Verdict::Skip(format!(
                "payor credential not reachable (exit {}) — {} requires service credentials",
                r.exit_code, fixture
            )),
            zrbtdrv_PayorGatePolicy::Fail => rbtdre_Verdict::Fail(format!(
                "payor credential probe not green (exit {}) — {} is operator-invoked \
                 and requires a live payor credential; this is a failure of the run, not a skip\n\
                 stdout:\n{}\nstderr:\n{}",
                r.exit_code, fixture, r.stdout, r.stderr
            )),
        }),
        Err(e) => Some(match policy {
            zrbtdrv_PayorGatePolicy::Skip => rbtdre_Verdict::Skip(format!(
                "payor credential probe could not run ({}) — {} requires service credentials",
                e, fixture
            )),
            zrbtdrv_PayorGatePolicy::Fail => {
                rbtdre_Verdict::Fail(format!("payor probe invocation: {}", e))
            }
        }),
    }
}


// Foedus-lifecycle fixture — federation IdP-trust round-trip against the live org.
// The reliquary-lifecycle shape (single self-contained case, no charge/quench)
// applied to the affiance→jilt create/destroy round-trip under the one-pool Model
// (RBSMA/RBSMJ): probe the payor credential, affiance a fresh throwaway provider
// under the manor's standing workforce pool, canvass the pool and prove the live
// provider surfaces in the enumeration, jilt the provider to the soft-deleted
// terminal, then re-jilt to prove the idempotent no-op. Codifies the manual proof
// the create-shape fix was found by, and exercises canvass against a real, live
// foedus read from the Manor.
//
// Quota-touching by nature — a genuine create cannot reuse a soft-deleted id, and
// soft-deleted providers linger under the standing pool for ~30 days
// (workforce-pool-constraints memo) — so this fixture is operator-invoked only:
// registered for discovery, a member of no auto-suite.

/// RBRF field the throwaway-provider override targets through the regime-poison seam.
const RBTDRV_RBRF_PROVIDER_VAR: &str = "RBRF_PROVIDER_ID";

/// Drive the affiance→canvass→jilt→re-jilt round-trip on `provider_id`, addressing
/// foedus `foedus` (the folio affiance/jilt take, RBSMA/RBSMJ — its rbrf.env is the
/// base config the poison overrides RBRF_PROVIDER_ID atop), asserting each terminal
/// banner and that canvass enumerates the live provider. Split from the case so the
/// case can run a best-effort cleanup jilt on any failure (the round-trip's own jilt
/// may not have been reached).
fn zrbtdrv_foedus_roundtrip(ctx: &mut rbtdri_Context, dir: &Path, foedus: &str, provider_id: &str) -> rbtdre_Verdict {
    // Payor credential precondition — Fail, not Skip (never a suite passenger).
    if let Some(v) = zrbtdrv_payor_gate(
        ctx, dir, crate::rbtdrm_manifest::RBTDRM_FIXTURE_FOEDUS_LIFECYCLE, zrbtdrv_PayorGatePolicy::Fail,
    ) {
        return v;
    }

    // The throwaway provider id rides the regime-poison seam: RBRF_PROVIDER_ID
    // carries the RBRF_ enroll-scope prefix, so the tweak rewrites that one field
    // at regime kindle and both affiance and jilt target the throwaway provider.
    // Only the provider id is overridden — the provider is seated beneath the
    // manor's standing workforce pool (manor-level RBRW, never created or destroyed
    // here) and removed on jilt.
    let poison = format!("{}={}", RBTDRV_RBRF_PROVIDER_VAR, provider_id);

    // Step 1: affiance a fresh provider under the standing pool; assert the create banners.
    let affiance = match rbtdri_invoke_global(ctx, RBTDGC_AFFIANCE_MANOR, &[foedus], &[
        (RBTDRI_BURE_TWEAK_NAME_KEY, RBTDGC_TWEAK_REGIME_POISON),
        (RBTDRI_BURE_TWEAK_VALUE_KEY, poison.as_str()),
    ]) {
        Ok(r) if r.exit_code == 0 => r,
        Ok(r) => return rbtdre_Verdict::Fail(format!("affiance failed (exit {})\n{}", r.exit_code, r.stderr)),
        Err(e) => return rbtdre_Verdict::Fail(format!("affiance invocation: {}", e)),
    };
    let affiance_out = format!("{}\n{}", affiance.stdout, affiance.stderr);
    let _ = std::fs::write(dir.join("02-affiance.txt"), &affiance_out);
    // The create banner (not the already-present path) proves the seam overrode
    // the regime provider with the throwaway id.
    let created_banner = format!("Provider {} created under pool", provider_id);
    if !affiance_out.contains(&created_banner) {
        return rbtdre_Verdict::Fail(format!(
            "affiance did not create the throwaway provider — missing banner '{}'\n{}",
            created_banner, affiance_out
        ));
    }
    let affianced_banner = format!("Manor affianced: provider={}", provider_id);
    if !affiance_out.contains(&affianced_banner) {
        return rbtdre_Verdict::Fail(format!(
            "affiance did not reach the affianced terminal — missing banner '{}'\n{}",
            affianced_banner, affiance_out
        ));
    }

    // Step 2: canvass the manor's foedera — a read-only live enumeration of every
    // provider under the standing pool. The throwaway provider affiance just seated
    // is live under the pool, so canvass must surface it; it matches no rbef_
    // library foedus, so its fact stem is the bare provider id. Canvass needs no
    // poison — it reads the pool from the Manor directly. Proves canvass reads a
    // real, live foedus from the org, not a fixture-local stub.
    let canvass = match rbtdri_invoke_global(ctx, RBTDGC_CANVASS_FOEDUS, &[], &[]) {
        Ok(r) if r.exit_code == 0 => r,
        Ok(r) => return rbtdre_Verdict::Fail(format!("canvass failed (exit {})\n{}", r.exit_code, r.stderr)),
        Err(e) => return rbtdre_Verdict::Fail(format!("canvass invocation: {}", e)),
    };
    let _ = std::fs::write(
        dir.join("03-canvass.txt"),
        format!("{}\n{}", canvass.stdout, canvass.stderr),
    );
    // The throwaway provider's per-foedus fact file (stem = bare provider id, since
    // the throwaway is not in the rbef_ library) must be among canvass's emissions.
    let stems = match rbtdri_read_burv_facts_multi(&canvass, RBTDGC_FACT_EXT_FOEDUS) {
        Ok(s) => s,
        Err(e) => return rbtdre_Verdict::Fail(format!(
            "canvass wrote no {} facts: {}", RBTDGC_FACT_EXT_FOEDUS, e
        )),
    };
    if !stems.iter().any(|s| s == provider_id) {
        return rbtdre_Verdict::Fail(format!(
            "canvass did not enumerate the live throwaway provider '{}' — {} fact stems: {:?}",
            provider_id, RBTDGC_FACT_EXT_FOEDUS, stems
        ));
    }
    // The fact's provider= line must name the throwaway provider.
    let fact_name = format!("{}.{}", provider_id, RBTDGC_FACT_EXT_FOEDUS);
    let fact_body = match rbtdri_read_burv_fact(&canvass, &fact_name) {
        Ok(s) => s,
        Err(e) => return rbtdre_Verdict::Fail(format!("canvass fact {} unreadable: {}", fact_name, e)),
    };
    let provider_line = format!("provider={}", provider_id);
    if !fact_body.contains(&provider_line) {
        return rbtdre_Verdict::Fail(format!(
            "canvass fact {} does not name the throwaway provider — missing '{}'\n{}",
            fact_name, provider_line, fact_body
        ));
    }

    // Step 3: jilt the provider — live dissolution to the DELETED (soft-delete) terminal.
    let jilt = match rbtdri_invoke_global(ctx, RBTDGC_JILT_MANOR, &[foedus], &[
        (RBTDRI_BURE_TWEAK_NAME_KEY, RBTDGC_TWEAK_REGIME_POISON),
        (RBTDRI_BURE_TWEAK_VALUE_KEY, poison.as_str()),
        (RBTDRI_BURE_CONFIRM_KEY, RBTDRI_BURE_CONFIRM_SKIP),
    ]) {
        Ok(r) if r.exit_code == 0 => r,
        Ok(r) => return rbtdre_Verdict::Fail(format!("jilt failed (exit {})\n{}", r.exit_code, r.stderr)),
        Err(e) => return rbtdre_Verdict::Fail(format!("jilt invocation: {}", e)),
    };
    let jilt_out = format!("{}\n{}", jilt.stdout, jilt.stderr);
    let _ = std::fs::write(dir.join("04-jilt.txt"), &jilt_out);
    let dissolved_banner = format!("Foedus jilted: provider {} dissolved", provider_id);
    if !jilt_out.contains(&dissolved_banner) {
        return rbtdre_Verdict::Fail(format!(
            "jilt did not reach the dissolved terminal — missing banner '{}'\n{}",
            dissolved_banner, jilt_out
        ));
    }

    // Step 4: re-jilt the soft-deleted provider — the idempotent no-op. Either no-op
    // branch (already-soft-deleted or absent) names the provider and tags "(no-op)".
    let rejilt = match rbtdri_invoke_global(ctx, RBTDGC_JILT_MANOR, &[foedus], &[
        (RBTDRI_BURE_TWEAK_NAME_KEY, RBTDGC_TWEAK_REGIME_POISON),
        (RBTDRI_BURE_TWEAK_VALUE_KEY, poison.as_str()),
        (RBTDRI_BURE_CONFIRM_KEY, RBTDRI_BURE_CONFIRM_SKIP),
    ]) {
        Ok(r) if r.exit_code == 0 => r,
        Ok(r) => return rbtdre_Verdict::Fail(format!("re-jilt failed (exit {})\n{}", r.exit_code, r.stderr)),
        Err(e) => return rbtdre_Verdict::Fail(format!("re-jilt invocation: {}", e)),
    };
    let rejilt_out = format!("{}\n{}", rejilt.stdout, rejilt.stderr);
    let _ = std::fs::write(dir.join("05-rejilt.txt"), &rejilt_out);
    if !(rejilt_out.contains(provider_id) && rejilt_out.contains("no-op")) {
        return rbtdre_Verdict::Fail(format!(
            "re-jilt was not the idempotent no-op — expected an 'already … (no-op)' banner naming {}\n{}",
            provider_id, rejilt_out
        ));
    }

    let _ = std::fs::write(dir.join("06-passed.txt"), "passed");
    rbtdre_Verdict::Pass
}

fn rbtdrv_foedus_lifecycle(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        // The foedus folio affiance/jilt address (RBSMA/RBSMJ) — the committed
        // active selector, read rather than hardcoded (matches the reuse leg). Its
        // rbrf.env is the base provider config; the regime-poison seam overrides
        // only RBRF_PROVIDER_ID, so the round-trip seats a throwaway provider under
        // the manor's standing pool and never touches the real provider.
        let root = ctx.project_root().to_path_buf();
        let rbrr = root.join(RBTDGC_RBRR_FILE);
        let foedus = match crate::rbtdrk_freehold::rbtdrk_read_env_value(&rbrr, "RBRR_ACTIVE_FOEDUS") {
            Some(f) if !f.trim().is_empty() => f.trim().to_string(),
            _ => return rbtdre_Verdict::Fail(format!(
                "RBRR_ACTIVE_FOEDUS blank or absent in {} — no foedus to affiance",
                rbrr.display()
            )),
        };

        // A unique throwaway provider id every run: a genuine create cannot reuse a
        // soft-deleted id, and millis-since-epoch stays within the regime's
        // RBRF_PROVIDER_ID [a-z0-9-]{4,32} regex while staying unique across
        // back-to-back runs.
        let provider_id = match std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH) {
            Ok(d) => format!("provider-{}", d.as_millis()),
            Err(e) => return rbtdre_Verdict::Fail(format!("system clock before epoch: {}", e)),
        };
        let _ = std::fs::write(dir.join("00-provider-id.txt"), &provider_id);

        let verdict = zrbtdrv_foedus_roundtrip(ctx, dir, &foedus, &provider_id);

        // Cleanup safety net: if the round-trip failed after affiance seated the
        // provider, a leaked LIVE provider lingers under the standing pool. Jilt is
        // idempotent (no-op on absent/already-deleted), so a best-effort pass
        // soft-deletes any leak. Result ignored — the round-trip verdict stands.
        if matches!(verdict, rbtdre_Verdict::Fail(_)) {
            let poison = format!("{}={}", RBTDRV_RBRF_PROVIDER_VAR, provider_id);
            let _ = rbtdri_invoke_global(ctx, RBTDGC_JILT_MANOR, &[foedus.as_str()], &[
                (RBTDRI_BURE_TWEAK_NAME_KEY, RBTDGC_TWEAK_REGIME_POISON),
                (RBTDRI_BURE_TWEAK_VALUE_KEY, poison.as_str()),
                (RBTDRI_BURE_CONFIRM_KEY, RBTDRI_BURE_CONFIRM_SKIP),
            ]);
        }
        verdict
    })
}

pub static RBTDRV_CASES_FOEDUS_LIFECYCLE: &[rbtdre_Case] = &[case!(rbtdrv_foedus_lifecycle)];


// Foedus-reuse fixture — the standing-freehold REUSE credential leg. Unlike the
// quota-touching lifecycle round-trip above, this reuses the REAL standing foedus
// cap-flat (no regime-poison, no throwaway pool) and is quota-neutral on the reuse
// path. Composes the two new atoms (descry, instate) with the credential heal
// (avow + don), the branch (reuse-if-valid-else-affiance) living here at the
// fixture call site, never folded into a fat verb.

/// The standing-freehold REUSE credential leg: descry the active foedus, reuse it
/// cap-flat when healthy (affiance only on a check failure), re-point the selector
/// (instate), then heal the credentials — avow the sitting, don each mantle. The
/// release ladders (skirmish/dogfight/blockade) assume this readiness step but no
/// fixture established it; operator-invoked (human-present avow, live dons), a
/// member of no suite, the payor gate fails loud (never a passenger).
fn rbtdrv_foedus_reuse(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        // Payor credential precondition — Fail, not Skip (never a suite passenger).
        if let Some(v) = zrbtdrv_payor_gate(
            ctx, dir, crate::rbtdrm_manifest::RBTDRM_FIXTURE_FOEDUS_REUSE, zrbtdrv_PayorGatePolicy::Fail,
        ) {
            return v;
        }

        // The standing foedus the manor authenticates against — the committed
        // active selector, read rather than hardcoded so the leg follows the
        // regime (degenerate today: one standing foedus).
        let root = ctx.project_root().to_path_buf();
        let rbrr = root.join(RBTDGC_RBRR_FILE);
        let foedus = match crate::rbtdrk_freehold::rbtdrk_read_env_value(&rbrr, "RBRR_ACTIVE_FOEDUS") {
            Some(f) if !f.trim().is_empty() => f.trim().to_string(),
            _ => return rbtdre_Verdict::Fail(format!(
                "RBRR_ACTIVE_FOEDUS blank or absent in {} — no standing foedus to reuse",
                rbrr.display()
            )),
        };
        let _ = std::fs::write(dir.join("00-foedus.txt"), &foedus);

        // Descry the standing foedus — probe its provider-grain health (RBSFD:
        // provider presence under the one manor pool). A clean probe exits 0 and
        // reports its verdict via the foedus-health fact; only an unresolvable
        // name or broken read rejects (descry's own band).
        let descry = match rbtdri_invoke_global(ctx, RBTDGC_DESCRY_FOEDUS, &[foedus.as_str()], &[]) {
            Ok(r) if r.exit_code == 0 => r,
            Ok(r) => return rbtdre_Verdict::Fail(format!(
                "descry {} errored (exit {}) — could not determine foedus health\n{}",
                foedus, r.exit_code, r.stderr
            )),
            Err(e) => return rbtdre_Verdict::Fail(format!("descry invocation: {}", e)),
        };
        let _ = std::fs::write(
            dir.join("02-descry.txt"),
            format!("{}\n{}", descry.stdout, descry.stderr),
        );
        let fact_name = format!("{}.{}", foedus, RBTDGC_FACT_EXT_FOEDUS_HEALTH);
        let health = match rbtdri_read_burv_fact(&descry, &fact_name) {
            Ok(s) => s.trim().to_string(),
            Err(e) => {
                return rbtdre_Verdict::Fail(format!("descry wrote no {} health fact: {}", fact_name, e))
            }
        };

        // Reuse-or-establish: the branch lives HERE (the verbs stay atomic). Reuse
        // the standing foedus cap-flat when healthy — no affiance, no provider churn;
        // affiance fires ONLY on a descry deficit (the rebuild-on-check-failure arm).
        // The verdict token "healthy" is descry's (rbof_descry / RBCC_fact_ext_foedus_health).
        if health == "healthy" {
            let _ = std::fs::write(
                dir.join("03-decision.txt"),
                format!("reused {} (healthy, cap-flat)", foedus),
            );
        } else {
            let _ = std::fs::write(
                dir.join("03-decision.txt"),
                format!("affiance {} (descry verdict '{}')", foedus, health),
            );
            match rbtdri_invoke_global(ctx, RBTDGC_AFFIANCE_MANOR, &[foedus.as_str()], &[]) {
                Ok(r) if r.exit_code == 0 => {}
                Ok(r) => return rbtdre_Verdict::Fail(format!(
                    "affiance (on descry deficit '{}') exit {}\n{}",
                    health, r.exit_code, r.stderr
                )),
                Err(e) => return rbtdre_Verdict::Fail(format!("affiance invocation: {}", e)),
            }
        }

        // Instate — re-point the active-foedus selector at the standing foedus.
        // Idempotent on the already-active one (rewrite to the same value, no diff).
        match rbtdri_invoke_global(ctx, RBTDGC_INSTATE_FOEDUS, &[foedus.as_str()], &[]) {
            Ok(r) if r.exit_code == 0 => {}
            Ok(r) => return rbtdre_Verdict::Fail(format!(
                "instate {} exit {}\n{}", foedus, r.exit_code, r.stderr
            )),
            Err(e) => return rbtdre_Verdict::Fail(format!("instate invocation: {}", e)),
        }
        let _ = std::fs::write(dir.join("04-instate.txt"), format!("instated {}", foedus));

        // Credential heal — avow opens or reuses the sitting (one human click at
        // suite head); the mantle dons then ride the cached federated token.
        match rbtdri_invoke_global(ctx, RBTDGC_CHECK_AVOWAL, &[], &[]) {
            Ok(r) if r.exit_code == 0 => {}
            Ok(r) => return rbtdre_Verdict::Fail(format!(
                "avow exit {} — open a sitting with {} (one device-flow click), or launch \
                 from a terminal so the prompt can surface\n{}", r.exit_code, RBTDGC_CHECK_AVOWAL, r.stderr
            )),
            Err(e) => return rbtdre_Verdict::Fail(format!("avow invocation: {}", e)),
        }
        let _ = std::fs::write(dir.join("05-avow.txt"), "avowed");

        // Don each mantle and reach Artifact Registry — proves the
        // standing freehold's mantle credentials are LIVE (the assertion the
        // release ladders previously made in prose). The durable admission (gird/
        // brevet) is freehold-establish's; a don failure here means the freehold is
        // not seated for the subject — run freehold-establish first.
        for mantle in [RBTDGC_MANTLE_GOVERNOR, RBTDGC_MANTLE_DIRECTOR, RBTDGC_MANTLE_RETRIEVER] {
            match rbtdri_invoke_global(ctx, RBTDGC_CHECK_MANTLE, &[mantle], &[]) {
                Ok(r) if r.exit_code == 0 => {}
                Ok(r) => return rbtdre_Verdict::Fail(format!(
                    "don {} exit {} — mantle credential not healed (is the freehold seated for the \
                     subject? run freehold-establish first)\n{}", mantle, r.exit_code, r.stderr
                )),
                Err(e) => return rbtdre_Verdict::Fail(format!("don {} invocation: {}", mantle, e)),
            }
            let _ = std::fs::write(dir.join(format!("06-don-{}.txt", mantle)), "donned");
        }

        let _ = std::fs::write(dir.join("07-passed.txt"), "passed");
        rbtdre_Verdict::Pass
    })
}

pub static RBTDRV_CASES_FOEDUS_REUSE: &[rbtdre_Case] = &[case!(rbtdrv_foedus_reuse)];


// Polity-denial fixture — proves the polity verbs reject with the EXACT precision
// band across their whole failure surface: the IAM admission band when a
// governor-wielded verb's don is refused, and the three terrier bands when a
// muniment sub-op meets an unexpected HTTP code. One credentialed setup, two arcs.
//
// Admission arc — proves BUBC_band_admission / RBTDGC_BAND_ADMISSION is the actual
// exit code a governor-wielded polity verb's don (rbw-am) returns when the wielding
// citizen is NOT brevetted onto the target mantle, AND that admission is per-mantle
// (the leave-one-out isolation matrix). Don retriever (positive baseline) -> unseat
// retriever -> poll don until it exits the admission band EXACTLY (bounded ceiling —
// IAM revocation propagates eventually, never instantly, in either direction) ->
// with retriever withheld, assert the held mantles (governor, director) STILL reach
// AR (isolation — the unseat denied retriever ALONE, not a blanket credential
// failure) -> brevet retriever back -> poll don until positive again (the restore
// proof, so the fixture leaves the freehold exactly as it found it — a leaked
// unseated retriever would fail every downstream picket fixture that dons it). The
// withheld mantle is retriever, never governor: unseating governor would saw off
// the wielding branch every polity verb — including this fixture's own restore
// brevet — rides, so governor is pinned as an always-held mantle.
//
// Terrier-band arc — the regime-poison analogue for HTTP, folded in as the negative
// coverage that superseded the retired interim terrier-atomicity rbw-dT proof (whose
// positive round-trip is already exercised by the real brevet/unseat the admission
// arc and freehold-establish drive). Drive the SAME real verbs under the rbuh
// http-fault seam (RBTDGC_TWEAK_HTTP_FAULT), forcing each muniment sub-op's captured
// code so rbgft rejects: brevet's engross -> engross band, unseat's expunge ->
// expunge band, rehearse's manor-wide list -> the single peruse band. On a SYNTHETIC
// subject, never the freehold subject — the seam overwrites the captured code only
// AFTER the real transport succeeds, so unseat's real DELETE would strike a live
// muniment; a pre-clean and a final sweep leave none behind. No explicit charge: the
// admission arc's restore brevet already engrossed a real muniment, so reaching this
// arc proves the terrier is provisioned.
//
// Payor-credentialed picket fixture; self-skips on an unreachable payor credential,
// like the other credentialed picket fixtures.

/// Don the given (pallium-sprued) mantle token once, logging to `label`, and
/// return its bare exit status (never bare-nonzero downstream — callers compare
/// against the exact code under test).
fn zrbtdrv_mantle_don_status(
    ctx: &mut rbtdri_Context,
    dir: &Path,
    mantle_token: &str,
    label: &str,
) -> Result<i32, rbtdre_Verdict> {
    match crate::rbtdrk_freehold::rbtdrk_invoke_logged(
        ctx, RBTDGC_CHECK_MANTLE, &[mantle_token], &[], dir, label,
    ) {
        Ok(r) => Ok(r.exit_code),
        Err(e) => Err(rbtdre_Verdict::Fail(format!(
            "don {} ({}) invocation: {}", mantle_token, label, e
        ))),
    }
}

/// Poll the retriever don until its exit status equals `want`, bounded by the
/// same propagation-deadline magnitude the bash IAM-grant loops use
/// (RBGC_PROPAGATION_DEADLINE_SEC=420s, rbgc_constants.sh) — IAM admission
/// changes are eventually consistent, never instant, whether revoking or
/// re-granting. Returns Ok on reaching `want`, or a Fail naming the last-seen
/// status once the deadline passes.
fn zrbtdrv_mantle_denial_poll_until(
    ctx: &mut rbtdri_Context,
    dir: &Path,
    label_prefix: &str,
    want: i32,
) -> Result<(), rbtdre_Verdict> {
    const DEADLINE_SECS: u64 = 420;
    const POLL_INTERVAL_SECS: u64 = 10;
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(DEADLINE_SECS);
    let mut attempt = 0u32;
    loop {
        let label = format!("{}-{:02}", label_prefix, attempt);
        let last = zrbtdrv_mantle_don_status(ctx, dir, RBTDGC_MANTLE_RETRIEVER, &label)?;
        if last == want {
            return Ok(());
        }
        if std::time::Instant::now() >= deadline {
            return Err(rbtdre_Verdict::Fail(format!(
                "{}: don retriever did not reach exit {} within {}s — last exit {}",
                label_prefix, want, DEADLINE_SECS, last
            )));
        }
        attempt += 1;
        std::thread::sleep(std::time::Duration::from_secs(POLL_INTERVAL_SECS));
    }
}

// Synthetic subject for the terrier-band poison drives — a throwaway muniment key,
// never the freehold subject: the http-fault seam overwrites the captured code only
// AFTER the real request succeeds, so unseat's real DELETE would strike a live
// muniment. Parallels the terrier proof's rbgft-proof-probe.
const RBTDRV_TERRIER_POISON_SUBJECT: &str = "rbgft-poison-probe";

// http-fault specs (BURE_TWEAK_VALUE "INFIX=CODE") — force each terrier sub-op's
// captured HTTP code to an unexpected 500 so rbgft rejects in the matching band. The
// list infix carries the page suffix zrbgft_list_fetch_emit appends (page 1).
const RBTDRV_TERRIER_FAULT_ENGROSS: &str = "terrier_engross=500";
const RBTDRV_TERRIER_FAULT_EXPUNGE: &str = "terrier_expunge=500";
const RBTDRV_TERRIER_FAULT_PERUSE: &str = "terrier_peruse_manor_list1=500";

/// Best-effort expunge of the synthetic poison muniment via an un-faulted unseat
/// (idempotent — a 404 is "absent"; the tokenCreator revoke is a no-op unless the
/// re-run brevet drive granted it), so a poison drive leaves no muniment behind.
/// Exit ignored: cleanup.
fn zrbtdrv_terrier_poison_sweep(ctx: &mut rbtdri_Context, dir: &Path, label: &str) {
    let _ = crate::rbtdrk_freehold::rbtdrk_invoke_logged(
        ctx,
        RBTDGC_UNSEAT_POLITY,
        &[RBTDRV_TERRIER_POISON_SUBJECT, RBTDGC_ACCOUNT_RETRIEVER],
        &[],
        dir,
        label,
    );
}

/// Drive a real polity verb under the rbuh http-fault seam forcing one terrier
/// sub-op's captured code, asserting the tabtarget exits the EXACT terrier band.
/// Never weaken to bare-nonzero: a harness break or a don failure exits some other
/// code and must fail the drive loud, exactly as the regime-poison band check does.
fn zrbtdrv_terrier_poison_drive(
    ctx: &mut rbtdri_Context,
    dir: &Path,
    colophon: &str,
    args: &[&str],
    fault_spec: &str,
    expected_band: i32,
    label: &str,
) -> Result<(), rbtdre_Verdict> {
    let env = [
        (RBTDRI_BURE_TWEAK_NAME_KEY, RBTDGC_TWEAK_HTTP_FAULT),
        (RBTDRI_BURE_TWEAK_VALUE_KEY, fault_spec),
    ];
    let result = match crate::rbtdrk_freehold::rbtdrk_invoke_logged(ctx, colophon, args, &env, dir, label) {
        Ok(r) => r,
        Err(e) => return Err(rbtdre_Verdict::Fail(format!("{}: {} invocation: {}", label, colophon, e))),
    };
    if result.exit_code != expected_band {
        return Err(rbtdre_Verdict::Fail(format!(
            "{}: {} under http fault '{}' exited {} — expected terrier band {}\nstdout:\n{}\nstderr:\n{}",
            label, colophon, fault_spec, result.exit_code, expected_band, result.stdout, result.stderr
        )));
    }
    Ok(())
}

/// Filter a rehearse roll capture down to muniment rows alone — each is the exact
/// "<depot>\t<mantle>\t<subject>" tab-separated shape rehearse emits
/// (RBSPO depot-attributed emission, two tabs). Strips the invoked tabtarget's own
/// stdout preamble (self-log paths, the sitting-reuse banner) carrying volatile
/// per-invocation content — a temp-dir invoke counter, a ticking runway-seconds
/// countdown — that a raw full-capture comparison would misread as roll drift.
fn zrbtdrv_roll_muniment_lines(roll: &str) -> Vec<&str> {
    roll.lines().filter(|l| l.matches('\t').count() == 2).collect()
}

/// Drive a real (unfaulted) polity verb RE-RUN against an already-mutated synthetic
/// muniment, asserting the clean-disposition idempotency claim the retired rbw-dT
/// proof carried, deliberately dodged by every fault-seam drive above (those force a
/// captured code and assert a rejection band; this issues no fault and asserts the
/// REAL GCS precondition semantics): the sub-op's 412/"present" or 404/"absent" arm
/// (rbgft_terrier.sh) surfaces as a clean exit 0 through the polity verb, and the
/// manor roll — captured before and after via `zrbtdrv_rehearse_roll`, compared at
/// muniment-row grain via `zrbtdrv_roll_muniment_lines` — is unchanged, since the
/// idempotent arm mutates nothing.
fn zrbtdrv_terrier_idempotent_rerun_drive(
    ctx: &mut rbtdri_Context,
    dir: &Path,
    colophon: &str,
    args: &[&str],
    label: &str,
) -> Result<(), rbtdre_Verdict> {
    let roll_before = zrbtdrv_rehearse_roll(ctx, dir, &format!("{}-roll-before", label))?;

    let result = match crate::rbtdrk_freehold::rbtdrk_invoke_logged(ctx, colophon, args, &[], dir, label) {
        Ok(r) => r,
        Err(e) => return Err(rbtdre_Verdict::Fail(format!("{}: {} invocation: {}", label, colophon, e))),
    };
    if result.exit_code != 0 {
        return Err(rbtdre_Verdict::Fail(format!(
            "{}: {} re-run exited {} (expected 0 — the idempotent precondition arm)\nstdout:\n{}\nstderr:\n{}",
            label, colophon, result.exit_code, result.stdout, result.stderr
        )));
    }

    let roll_after = zrbtdrv_rehearse_roll(ctx, dir, &format!("{}-roll-after", label))?;
    if zrbtdrv_roll_muniment_lines(&roll_after) != zrbtdrv_roll_muniment_lines(&roll_before) {
        return Err(rbtdre_Verdict::Fail(format!(
            "{}: manor roll changed across the idempotent re-run — before:\n{}\nafter:\n{}",
            label, roll_before, roll_after
        )));
    }
    Ok(())
}

fn rbtdrv_polity_denial(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        // Self-skip gate: stay green on a machine with no GCP credentials.
        if let Some(v) = zrbtdrv_payor_gate(
            ctx, dir, crate::rbtdrm_manifest::RBTDRM_FIXTURE_POLITY_DENIAL, zrbtdrv_PayorGatePolicy::Skip,
        ) {
            return v;
        }

        // Step 1: positive baseline — the freehold subject is presumed already
        // brevetted onto retriever (freehold-establish's job), so the don must
        // succeed before this fixture touches anything.
        match zrbtdrv_mantle_don_status(ctx, dir, RBTDGC_MANTLE_RETRIEVER, "01-don-baseline") {
            Ok(0) => {}
            Ok(status) => return rbtdre_Verdict::Fail(format!(
                "baseline don retriever exit {} (expected 0) — the freehold subject must be \
                 brevetted onto retriever before this fixture runs (run freehold-establish first)",
                status
            )),
            Err(v) => return v,
        }

        // Step 2: unseat retriever — withdraw the mantle binding.
        let unseat = match crate::rbtdrk_freehold::rbtdrk_invoke_logged(
            ctx, RBTDGC_UNSEAT_POLITY, &[RBTDGC_FREEHOLD_SUBJECT, RBTDGC_ACCOUNT_RETRIEVER], &[], dir,
            "02-unseat",
        ) {
            Ok(r) => r,
            Err(e) => return rbtdre_Verdict::Fail(format!("unseat retriever invocation: {}", e)),
        };
        if unseat.exit_code != 0 {
            return rbtdre_Verdict::Fail(format!(
                "unseat retriever exit {}\n{}", unseat.exit_code, unseat.stderr
            ));
        }

        // Step 3: poll the don until it exits the EXACT admission band — never
        // weaken to bare-nonzero; the whole point of this fixture is proving
        // the specific code, not merely "it failed".
        if let Err(v) = zrbtdrv_mantle_denial_poll_until(ctx, dir, "03-poll-denied", RBTDGC_BAND_ADMISSION) {
            // Best-effort restore before surfacing the failure, so a mid-run
            // failure doesn't leave the freehold subject unseated for the next
            // picket run.
            let _ = crate::rbtdrk_freehold::rbtdrk_invoke_logged(
                ctx, RBTDGC_BREVET_POLITY, &[RBTDGC_FREEHOLD_SUBJECT, RBTDGC_ACCOUNT_RETRIEVER], &[], dir,
                "05-restore-brevet-on-failure",
            );
            return v;
        }

        // Step 3b: isolation — while retriever is withheld and denied, the OTHER
        // mantles must still reach AR. This is the leave-one-out proof: admission is
        // per-mantle, so unseating retriever denies retriever ALONE, never a blanket
        // credential failure. Governor is the wielding mantle (pinned held — unseating
        // it would saw off the restore brevet below), director rides its
        // freehold-establish brevet; both must don clean (exit 0). A non-zero means the
        // unseat bled across mantles (or the freehold is not fully seated). Restore
        // retriever on any breach so it does not leave the subject unseated for the
        // next picket run.
        for held in [RBTDGC_MANTLE_GOVERNOR, RBTDGC_MANTLE_DIRECTOR] {
            let label = format!("03b-isolation-don-{}", held);
            let status = match zrbtdrv_mantle_don_status(ctx, dir, held, &label) {
                Ok(s) => s,
                Err(v) => {
                    let _ = crate::rbtdrk_freehold::rbtdrk_invoke_logged(
                        ctx, RBTDGC_BREVET_POLITY, &[RBTDGC_FREEHOLD_SUBJECT, RBTDGC_ACCOUNT_RETRIEVER], &[], dir,
                        "03b-restore-brevet-on-isolation-error",
                    );
                    return v;
                }
            };
            if status != 0 {
                let _ = crate::rbtdrk_freehold::rbtdrk_invoke_logged(
                    ctx, RBTDGC_BREVET_POLITY, &[RBTDGC_FREEHOLD_SUBJECT, RBTDGC_ACCOUNT_RETRIEVER], &[], dir,
                    "03b-restore-brevet-on-isolation-breach",
                );
                return rbtdre_Verdict::Fail(format!(
                    "isolation breach: with retriever withheld, don {} exit {} (expected 0) — \
                     withholding one mantle must not deny the held mantles; is the freehold fully \
                     seated for the subject? run freehold-establish first",
                    held, status
                ));
            }
        }

        // Step 4: brevet retriever back — the mirror admission.
        let brevet = match crate::rbtdrk_freehold::rbtdrk_invoke_logged(
            ctx, RBTDGC_BREVET_POLITY, &[RBTDGC_FREEHOLD_SUBJECT, RBTDGC_ACCOUNT_RETRIEVER], &[], dir,
            "04-brevet-restore",
        ) {
            Ok(r) => r,
            Err(e) => return rbtdre_Verdict::Fail(format!("brevet retriever (restore) invocation: {}", e)),
        };
        if brevet.exit_code != 0 {
            return rbtdre_Verdict::Fail(format!(
                "brevet retriever (restore) exit {}\n{}", brevet.exit_code, brevet.stderr
            ));
        }

        // Step 5: poll the don until it exits 0 again — the restore proof: the
        // fixture leaves the freehold subject exactly as it found it.
        if let Err(v) = zrbtdrv_mantle_denial_poll_until(ctx, dir, "05-poll-restored", 0) {
            return v;
        }

        // ── Terrier-band arc ─────────────────────────────────────────
        // The admission arc left the freehold subject exactly as found; the terrier
        // drives now work a SYNTHETIC subject so no real muniment is disturbed. Each
        // drives the same real verb under the http-fault seam and asserts the exact
        // terrier band. Pre-clean any muniment a prior failed run left behind, so the
        // engross drive's REAL create is a fresh write, not a 412-present.
        zrbtdrv_terrier_poison_sweep(ctx, dir, "06-terrier-preclean");

        // engross band — brevet's first act is the muniment engross; the fault forces
        // the create's captured code, rejecting before any IAM binding runs.
        if let Err(v) = zrbtdrv_terrier_poison_drive(
            ctx, dir, RBTDGC_BREVET_POLITY,
            &[RBTDRV_TERRIER_POISON_SUBJECT, RBTDGC_ACCOUNT_RETRIEVER],
            RBTDRV_TERRIER_FAULT_ENGROSS, RBTDGC_BAND_ENGROSS, "07-brevet-engross-poison",
        ) {
            zrbtdrv_terrier_poison_sweep(ctx, dir, "07-sweep-on-fail");
            return v;
        }

        // Re-run engross — the muniment the poisoned engross above just wrote for real
        // (only its reported code was forced) now stands PRESENT, so a clean, unfaulted
        // brevet re-run must meet GCS's real 412 precondition and take the "present" arm
        // (rbgft_terrier.sh rbgft_engross): exit 0, manor roll unchanged.
        if let Err(v) = zrbtdrv_terrier_idempotent_rerun_drive(
            ctx, dir, RBTDGC_BREVET_POLITY,
            &[RBTDRV_TERRIER_POISON_SUBJECT, RBTDGC_ACCOUNT_RETRIEVER],
            "07b-brevet-reengross-present",
        ) {
            zrbtdrv_terrier_poison_sweep(ctx, dir, "07b-sweep-on-fail");
            return v;
        }

        // expunge band — unseat's first act is the muniment expunge; the fault forces
        // the delete's captured code. The real DELETE also strikes the muniment the
        // engross drive created.
        if let Err(v) = zrbtdrv_terrier_poison_drive(
            ctx, dir, RBTDGC_UNSEAT_POLITY,
            &[RBTDRV_TERRIER_POISON_SUBJECT, RBTDGC_ACCOUNT_RETRIEVER],
            RBTDRV_TERRIER_FAULT_EXPUNGE, RBTDGC_BAND_EXPUNGE, "08-unseat-expunge-poison",
        ) {
            zrbtdrv_terrier_poison_sweep(ctx, dir, "08-sweep-on-fail");
            return v;
        }

        // Re-run expunge — the muniment the poisoned expunge above just struck for real
        // now stands ABSENT, so a clean, unfaulted unseat re-run must meet GCS's real 404
        // and take the "absent" arm (rbgft_terrier.sh rbgft_expunge): exit 0, manor roll
        // unchanged. The mirror idempotency claim on the withdrawal side.
        if let Err(v) = zrbtdrv_terrier_idempotent_rerun_drive(
            ctx, dir, RBTDGC_UNSEAT_POLITY,
            &[RBTDRV_TERRIER_POISON_SUBJECT, RBTDGC_ACCOUNT_RETRIEVER],
            "08b-unseat-reexpunge-absent",
        ) {
            zrbtdrv_terrier_poison_sweep(ctx, dir, "08b-sweep-on-fail");
            return v;
        }

        // peruse band — rehearse reads manor-wide; the fault forces the first page of
        // the muniment listing. One read gate: list/fetch/missing-fields deficits all
        // reject in this single band. Read-only, so no state to sweep.
        if let Err(v) = zrbtdrv_terrier_poison_drive(
            ctx, dir, RBTDGC_REHEARSE_POLITY, &[],
            RBTDRV_TERRIER_FAULT_PERUSE, RBTDGC_BAND_PERUSE, "09-rehearse-peruse-poison",
        ) {
            return v;
        }

        // Final sweep — leave the terrier exactly as found (no synthetic muniment).
        zrbtdrv_terrier_poison_sweep(ctx, dir, "10-terrier-final-sweep");

        let _ = std::fs::write(dir.join("11-passed.txt"), "passed");
        rbtdre_Verdict::Pass
    })
}

pub static RBTDRV_CASES_POLITY_DENIAL: &[rbtdre_Case] = &[case!(rbtdrv_polity_denial)];


// Parley fixture — the POSITIVE federation admission round-trip. The positive
// mirror of polity-denial (which owns all rejection-band assertion): parley drives
// the REAL polity verbs against the REAL freehold subject and proves the manor roll
// reflects a genuine admission churn — the (retriever, subject) muniment stands at
// baseline, VANISHES after unseat, and STANDS again after the restore brevet — then
// leaves the freehold exactly as found.
//
// The novel content is rehearse's POSITIVE manor-wide roll, asserted nowhere else:
// rehearse dons the governor mantle internally, so its exit 0 through the
// governor-wielded folder-scoped IAM path is proof in itself, and a line in its roll
// names the (retriever, subject) muniment across the create/withdraw/restore arc.
// Every roll assertion is the exact (depot, mantle, subject) line for
// the freehold's own depot (RBSPO depot-attributed emission): the manor roll
// spans every polity slice and identical records co-reside across them, so a
// depot-blind roll cannot attribute an aliasing line at all.
//
// Unseat-first (Cinched): the freehold subject's retriever muniment already stands,
// so a brevet-first shape would ride the 412-idempotent engross; unseating first
// makes the restore brevet a genuinely fresh write. Churns retriever ONLY — governor
// is the pinned wielding mantle every polity verb (including the restore brevet)
// dons, so unseating it would saw off the wielding branch. Denial-band assertion is
// polity-denial's alone: parley makes NO don-denial poll, only the final don-GREEN
// poll proving the restore's tokenCreator binding fully propagated so the freehold
// leaves as found (the muniment restores immediately in the strongly-consistent
// terrier; the IAM binding is eventually consistent, hence the poll).
//
// Payor-credentialed picket fixture; self-skips on an unreachable payor credential
// (suite-passenger posture), like polity-denial.

/// Rehearse the manor-wide muniment roll and return its stdout — one
/// "<depot>\t<mantle>\t<subject>" line per muniment (RBSPO
/// depot-attributed emission). rehearse dons the governor mantle internally, so
/// exit 0 IS the governor-wielded folder-scoped IAM-path proof; a non-zero fails
/// the drive loud (never bare-nonzero-tolerant — a broken read or a refused don
/// must surface, not read as an empty roll). `label` names the log.
fn zrbtdrv_rehearse_roll(
    ctx: &mut rbtdri_Context,
    dir: &Path,
    label: &str,
) -> Result<String, rbtdre_Verdict> {
    match crate::rbtdrk_freehold::rbtdrk_invoke_logged(
        ctx, RBTDGC_REHEARSE_POLITY, &[], &[], dir, label,
    ) {
        Ok(r) if r.exit_code == 0 => Ok(r.stdout),
        Ok(r) => Err(rbtdre_Verdict::Fail(format!(
            "rehearse ({}) exit {} — the manor-roll read failed\n{}", label, r.exit_code, r.stderr
        ))),
        Err(e) => Err(rbtdre_Verdict::Fail(format!("rehearse ({}) invocation: {}", label, e))),
    }
}

/// Compose the freehold's live depot project id from the kindled regime files —
/// RBRD_CLOUD_PREFIX + RBRD_DEPOT_MONIKER, the same derivation as bash
/// RBDC_DEPOT_PROJECT_ID. Parley's roll assertions scope to this depot's slice of
/// the manor roll; the manor-wide roll alone cannot attribute a (mantle, subject)
/// line to a depot once two polities hold the same pair.
fn zrbtdrv_freehold_depot_capture(ctx: &rbtdri_Context) -> Result<String, rbtdre_Verdict> {
    let root = ctx.project_root().to_path_buf();
    let rbrd = root.join(RBTDGC_RBRD_FILE);
    let moniker = match crate::rbtdrk_freehold::rbtdrk_read_env_value(
        &rbrd,
        crate::rbtdrk_freehold::RBTDRK_FIELD_RBRD_DEPOT_MONIKER,
    ) {
        Some(m) if !m.is_empty() => m,
        _ => {
            return Err(rbtdre_Verdict::Fail(format!(
                "RBRD_DEPOT_MONIKER blank or missing in {} — no levied freehold depot to \
                 scope the roll assertions to (run freehold-establish first)",
                rbrd.display()
            )))
        }
    };
    crate::rbtdrk_freehold::rbtdrk_compose_project_id(&root, &moniker)
        .map_err(|e| rbtdre_Verdict::Fail(format!("compose freehold depot project id: {}", e)))
}

/// True when the manor roll holds the freehold subject's retriever muniment in the
/// freehold's own depot — the exact
/// "<depot>\t<mantle>\t<subject>" line rehearse emits
/// (RBTDGC_ACCOUNT_RETRIEVER is the mantle name brevet stores in rbgft_mantle;
/// the tab join mirrors the terrier proof's line). Exact-line, never substring,
/// and depot-attributed: an identical record under another polity's slice (an
/// orphan of an unmade depot, say, since freehold churn never sweeps the
/// payor-grain terrier) must not alias the assertion.
fn zrbtdrv_roll_holds_retriever(roll: &str, depot: &str) -> bool {
    let line = format!(
        "{}\t{}\t{}",
        depot, RBTDGC_ACCOUNT_RETRIEVER, RBTDGC_FREEHOLD_SUBJECT
    );
    roll.lines().any(|l| l == line)
}

fn rbtdrv_parley(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        // Self-skip gate: stay green on a machine with no GCP credentials.
        if let Some(v) = zrbtdrv_payor_gate(
            ctx, dir, crate::rbtdrm_manifest::RBTDRM_FIXTURE_PARLEY, zrbtdrv_PayorGatePolicy::Skip,
        ) {
            return v;
        }

        // The depot the roll assertions scope to — composed once, before any
        // verb runs, so a mis-kindled regime fails here rather than mid-churn.
        let depot = match zrbtdrv_freehold_depot_capture(ctx) {
            Ok(d) => d,
            Err(v) => return v,
        };

        // Step 1: baseline roll — the freehold subject is presumed already brevetted
        // onto retriever (freehold-establish's job), so rehearse must show the
        // muniment before this fixture touches anything. This is parley's positive
        // baseline — the roll analogue of polity-denial's baseline don.
        let baseline = match zrbtdrv_rehearse_roll(ctx, dir, "02-rehearse-baseline") {
            Ok(r) => r,
            Err(v) => return v,
        };
        if !zrbtdrv_roll_holds_retriever(&baseline, &depot) {
            return rbtdre_Verdict::Fail(format!(
                "baseline manor roll lacks the freehold subject's retriever muniment in \
                 depot {} (mantle {}, subject {}) — the subject must be \
                 brevetted onto retriever in this depot before this fixture runs (run \
                 freehold-establish first)\nroll:\n{}",
                depot, RBTDGC_ACCOUNT_RETRIEVER, RBTDGC_FREEHOLD_SUBJECT, baseline
            ));
        }

        // Step 2: unseat retriever — withdraw the muniment (its expunge is immediate
        // in the strongly-consistent terrier, so the vanish below needs no poll).
        let unseat = match crate::rbtdrk_freehold::rbtdrk_invoke_logged(
            ctx, RBTDGC_UNSEAT_POLITY, &[RBTDGC_FREEHOLD_SUBJECT, RBTDGC_ACCOUNT_RETRIEVER], &[], dir,
            "03-unseat",
        ) {
            Ok(r) => r,
            Err(e) => return rbtdre_Verdict::Fail(format!("unseat retriever invocation: {}", e)),
        };
        if unseat.exit_code != 0 {
            return rbtdre_Verdict::Fail(format!(
                "unseat retriever exit {}\n{}", unseat.exit_code, unseat.stderr
            ));
        }

        // Step 3: roll after unseat — the muniment must be GONE. Any failure here
        // leaves the subject unseated (which would fail every downstream picket
        // fixture that dons retriever), so best-effort restore before surfacing. This
        // is the sole window between the unseat and the restore brevet.
        let after_unseat = match zrbtdrv_rehearse_roll(ctx, dir, "04-rehearse-unseated") {
            Ok(r) => r,
            Err(v) => {
                let _ = crate::rbtdrk_freehold::rbtdrk_invoke_logged(
                    ctx, RBTDGC_BREVET_POLITY, &[RBTDGC_FREEHOLD_SUBJECT, RBTDGC_ACCOUNT_RETRIEVER], &[], dir,
                    "04-restore-brevet-on-failure",
                );
                return v;
            }
        };
        if zrbtdrv_roll_holds_retriever(&after_unseat, &depot) {
            let _ = crate::rbtdrk_freehold::rbtdrk_invoke_logged(
                ctx, RBTDGC_BREVET_POLITY, &[RBTDGC_FREEHOLD_SUBJECT, RBTDGC_ACCOUNT_RETRIEVER], &[], dir,
                "04-restore-brevet-on-breach",
            );
            return rbtdre_Verdict::Fail(format!(
                "manor roll still holds the retriever muniment in depot {} \
                 after unseat — expunge did not withdraw it\nroll:\n{}",
                depot, after_unseat
            ));
        }

        // Step 4: restore-brevet retriever — a genuinely fresh engross (unseat-first).
        let brevet = match crate::rbtdrk_freehold::rbtdrk_invoke_logged(
            ctx, RBTDGC_BREVET_POLITY, &[RBTDGC_FREEHOLD_SUBJECT, RBTDGC_ACCOUNT_RETRIEVER], &[], dir,
            "05-brevet-restore",
        ) {
            Ok(r) => r,
            Err(e) => return rbtdre_Verdict::Fail(format!("brevet retriever (restore) invocation: {}", e)),
        };
        if brevet.exit_code != 0 {
            return rbtdre_Verdict::Fail(format!(
                "brevet retriever (restore) exit {}\n{}", brevet.exit_code, brevet.stderr
            ));
        }

        // Step 5: roll after restore — the muniment STANDS again (engross is immediate
        // in the terrier). The subject is brevetted from step 4, so no restore needed
        // on failure past here.
        let after_restore = match zrbtdrv_rehearse_roll(ctx, dir, "06-rehearse-restored") {
            Ok(r) => r,
            Err(v) => return v,
        };
        if !zrbtdrv_roll_holds_retriever(&after_restore, &depot) {
            return rbtdre_Verdict::Fail(format!(
                "manor roll lacks the retriever muniment in depot {} \
                 after the restore brevet — the fresh engross did not land\nroll:\n{}",
                depot, after_restore
            ));
        }

        // Step 6: don-green poll — the muniment restored immediately, but the
        // tokenCreator IAM binding is eventually consistent; poll the retriever don to
        // exit 0 so the freehold leaves exactly as found. NOT a denial poll —
        // polity-denial owns all denial-band assertion.
        if let Err(v) = zrbtdrv_mantle_denial_poll_until(ctx, dir, "07-poll-restored", 0) {
            return v;
        }

        let _ = std::fs::write(dir.join("08-passed.txt"), "passed");
        rbtdre_Verdict::Pass
    })
}

pub static RBTDRV_CASES_PARLEY: &[rbtdre_Case] = &[case!(rbtdrv_parley)];


// Wsl-lifecycle fixture — fetched-side rootfs capture against live GAR. Single
// self-contained round-trip: underpin a vendor-published Ubuntu rootfs into a
// fresh rbi_ld Lode, divine-enumerate to confirm it appears, divine-inspect to
// confirm the opaque-rootfs member tag + vouch envelope rode in, banish the whole
// Lode, then divine-enumerate to confirm the registry is restored. The wsl kind's
// structural-outlier analogue of lode-lifecycle: its capture is curl + GPG-verify
// + opaque-blob wrap, not a registry pull. Underpin takes the substrate version
// as arguments (release point), so it needs no vessel precondition. Consumption
// (wsl --import) is deferred — this stops at the registry, no host in the loop.
fn rbtdrv_wsl_lifecycle(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        // Step 1: underpin the pinned Ubuntu rootfs version into a fresh Lode.
        let _ = std::fs::write(dir.join("01-underpin.txt"), "underpinning wsl rootfs");
        let underpin = match rbtdri_invoke_global(
            ctx,
            RBTDGC_UNDERPIN_WSL,
            &[RBTDRV_WSL_RELEASE, RBTDRV_WSL_POINT],
            &[],
        ) {
            Ok(r) if r.exit_code == 0 => r,
            Ok(r) => return rbtdre_Verdict::Fail(format!("underpin failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("underpin invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("01-underpin-stdout.txt"), &underpin.stdout);

        // The host-side capture handoff is the bare touchmark fact.
        let touchmark = match zrbtdrv_read_touchmark(&underpin, dir) {
            Ok(t) => t,
            Err(v) => return v,
        };

        // Step 2: divine enumerate shows the new Lode.
        if let Err(v) = zrbtdrv_divine_contains(ctx, dir, &touchmark, "underpin") {
            return v;
        }

        // Step 3: augur inspects the rootfs Lode — member tags AND the decoded
        // :rbi_vouch envelope (the rootfs singleton).
        let augur = match rbtdri_invoke_global(ctx, RBTDGC_AUGUR_LODE, &[&touchmark], &[]) {
            Ok(r) if r.exit_code == 0 => r,
            Ok(r) => return rbtdre_Verdict::Fail(format!("augur failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("augur invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("04-augur.txt"), &augur.stdout);
        for member in &[RBTDRV_LODE_TAG_ROOTFS, RBTDRV_LODE_TAG_VOUCH] {
            if !augur.stdout.contains(member) {
                return rbtdre_Verdict::Fail(format!(
                    "augur missing member tag '{}'\nstdout:\n{}",
                    member, augur.stdout
                ));
            }
        }

        // Step 4: banish the whole Lode, then confirm the registry is restored.
        if let Some(v) = zrbtdrv_banish_and_verify_gone(ctx, dir, &touchmark) {
            return v;
        }

        let _ = std::fs::write(dir.join("07-passed.txt"), "passed");
        rbtdre_Verdict::Pass
    })
}

pub static RBTDRV_CASES_WSL_LIFECYCLE: &[rbtdre_Case] = &[case!(rbtdrv_wsl_lifecycle)];


// Podvm-lifecycle fixture — fetched-side podvm disk-leaf capture against live GAR. Single
// self-contained round-trip: immure a quay.io/podman/machine-os-wsl family into a fresh
// rbi_ld Lode, divine-enumerate to confirm it appears as a cohort, augur to confirm the
// two member tags (rbi_wsl-x86_64, rbi_wsl-aarch64) + decoded :rbi_vouch envelope rode
// in at recorded-at-acquisition grade, jettison one member tag via the type-blind raw
// image verb proving per-member delete, banish the whole Lode, then divine-enumerate to
// confirm the registry is restored. Structural analogue of both reliquary-lifecycle
// (multi-member cohort + member-jettison case) and wsl-lifecycle (opaque-blob capture).

/// Podvm-wsl kind argument — family brand passed to immure.
const RBTDRV_PODVM_FAMILY: &str = "podvm-wsl";
/// Podvm version tag — the quay.io family index version to capture.
const RBTDRV_PODVM_VERSION: &str = "5.6";

/// Podvm-wsl member tags asserted by augur. Compose RBGC_LODE_TAG_SPRUE ("rbi_")
/// with the selection leaf names from rbgc_constants.sh RBGC_LODE_PODVM_WSL_SELECTION.
const RBTDRV_PODVM_TAG_WSL_X86: &str = "rbi_wsl-x86_64";
const RBTDRV_PODVM_TAG_WSL_AARCH: &str = "rbi_wsl-aarch64";

/// Trust grade for the recorded-at-acquisition envelope — mirrors rbgc_constants.sh
/// RBGC_LODE_TRUST_RECORDED. The podvm upstream offers no durable checksum, so RB
/// attests only the digest observed at capture.
const RBTDRV_LODE_TRUST_RECORDED: &str = "recorded-at-acquisition";

/// Honest-posture text fragment emitted by augur for recorded-at-acquisition grade
/// (rbldl_lifecycle.sh RBGC_LODE_TRUST_RECORDED branch). Proves augur rendered the
/// trust-posture section, not just the envelope header. Matches a stable substring
/// of the fixed prose rather than the full multi-line block.
const RBTDRV_PODVM_TRUST_POSTURE_FRAGMENT: &str = "attests only the digest observed at capture";

fn rbtdrv_podvm_lifecycle(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        // Step 1: immure the podvm-wsl family + version into a fresh Lode.
        let _ = std::fs::write(dir.join("01-immure.txt"), "immuring podvm-wsl disk leaves");
        let immure = match rbtdri_invoke_global(
            ctx,
            RBTDGC_IMMURE_PODVM,
            &[RBTDRV_PODVM_FAMILY, RBTDRV_PODVM_VERSION],
            &[],
        ) {
            Ok(r) if r.exit_code == 0 => r,
            Ok(r) => return rbtdre_Verdict::Fail(format!("immure failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("immure invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("01-immure-stdout.txt"), &immure.stdout);

        // The host-side capture handoff is the bare touchmark fact.
        let touchmark = match zrbtdrv_read_touchmark(&immure, dir) {
            Ok(t) => t,
            Err(v) => return v,
        };

        // Step 2: divine enumerate shows the new Lode as a cohort.
        let after = match zrbtdrv_divine_contains(ctx, dir, &touchmark, "immure") {
            Ok(s) => s,
            Err(v) => return v,
        };
        // Cohort display asserts the member count column, not a specific digest.
        if !after.contains("cohort: 2 members") {
            return rbtdre_Verdict::Fail(format!(
                "post-immure divine row for {} missing '(cohort: 2 members)'\nstdout:\n{}",
                touchmark, after
            ));
        }

        // Step 2.5: REFRESH the same Lode at its locked version. The wsl family's
        // production curation IS the full 2-leaf set, so this refresh adds no new
        // member — it is the all-preserved / convergent path, and that is what the
        // recurring suite proves: refresh reuses the existing touchmark (no new Lode),
        // derives the locked version from the envelope (it takes no version argument),
        // re-reads the GAR member tags as the source of truth, preserves both originals
        // verbatim, and re-authors :rbi_vouch. The widen-adds-a-member path is not
        // exercised here.
        let _ = std::fs::write(dir.join("03b-refresh.txt"), "refreshing podvm-wsl Lode (all-preserved)");
        match rbtdri_invoke_global(
            ctx,
            RBTDGC_IMMURE_PODVM,
            &[RBTDRV_PODVM_FAMILY, "--refresh", &touchmark],
            &[],
        ) {
            Ok(r) if r.exit_code == 0 => {}
            Ok(r) => return rbtdre_Verdict::Fail(format!("refresh immure failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("refresh immure invocation: {}", e)),
        }
        // Post-refresh divine: the SAME touchmark, still a 2-member cohort — refresh
        // reused the Lode and preserved both originals (no new Lode, no membership drift).
        let after_refresh = match rbtdri_invoke_global(ctx, RBTDGC_DIVINE_LODES, &[], &[]) {
            Ok(r) if r.exit_code == 0 => r,
            Ok(r) => return rbtdre_Verdict::Fail(format!("post-refresh divine failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("post-refresh divine invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("03c-divine-after-refresh.txt"), &after_refresh.stdout);
        if !after_refresh.stdout.contains(&touchmark) {
            return rbtdre_Verdict::Fail(format!(
                "post-refresh divine missing touchmark {} — refresh lost the Lode\nstdout:\n{}",
                touchmark, after_refresh.stdout
            ));
        }
        if !after_refresh.stdout.contains("cohort: 2 members") {
            return rbtdre_Verdict::Fail(format!(
                "post-refresh divine row for {} not '(cohort: 2 members)' — refresh changed membership\nstdout:\n{}",
                touchmark, after_refresh.stdout
            ));
        }

        // Step 3: augur inspects the podvm Lode — member tags AND the decoded
        // (this augur now also validates the refresh PRESERVED both original members)
        // :rbi_vouch envelope. The trust-grade assertion proves augur decoded the
        // recorded-at-acquisition envelope (distinct from the verified grade the bole
        // and reliquary kinds carry); the posture-fragment assertion proves the honest-
        // posture prose block was rendered (struct proof, not digest assertion).
        let augur = match rbtdri_invoke_global(ctx, RBTDGC_AUGUR_LODE, &[&touchmark], &[]) {
            Ok(r) if r.exit_code == 0 => r,
            Ok(r) => return rbtdre_Verdict::Fail(format!("augur failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("augur invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("04-augur.txt"), &augur.stdout);
        // Member-tag presence (structural: these are the two WSL disk-leaf kinds).
        for member in &[RBTDRV_PODVM_TAG_WSL_X86, RBTDRV_PODVM_TAG_WSL_AARCH, RBTDRV_LODE_TAG_VOUCH] {
            if !augur.stdout.contains(member) {
                return rbtdre_Verdict::Fail(format!(
                    "augur missing member tag '{}'\nstdout:\n{}",
                    member, augur.stdout
                ));
            }
        }
        // Trust-grade assertion — recorded-at-acquisition, not verified-against-published.
        // Never assert specific digest hex: the upstream rotates and the digest changes.
        if !augur.stdout.contains(RBTDRV_LODE_TRUST_RECORDED) {
            return rbtdre_Verdict::Fail(format!(
                "augur did not decode podvm :rbi_vouch envelope — missing trust grade '{}'\nstdout:\n{}",
                RBTDRV_LODE_TRUST_RECORDED, augur.stdout
            ));
        }
        // Kind field assertion — proves the envelope names the podvm-wsl kind.
        if !augur.stdout.contains(RBTDRV_PODVM_FAMILY) {
            return rbtdre_Verdict::Fail(format!(
                "augur envelope missing kind '{}'\nstdout:\n{}",
                RBTDRV_PODVM_FAMILY, augur.stdout
            ));
        }
        // Honest-posture prose block — proves the recorded-at-acquisition branch ran.
        if !augur.stdout.contains(RBTDRV_PODVM_TRUST_POSTURE_FRAGMENT) {
            return rbtdre_Verdict::Fail(format!(
                "augur trust-posture prose missing expected fragment '{}'\nstdout:\n{}",
                RBTDRV_PODVM_TRUST_POSTURE_FRAGMENT, augur.stdout
            ));
        }

        // Step 3.5: per-member jettison via the type-blind raw verbs — delete one
        // member tag and prove it gone while a sibling survives.
        if let Some(v) = zrbtdrv_member_jettison_proof(
            ctx,
            dir,
            &touchmark,
            RBTDRV_PODVM_TAG_WSL_AARCH,
            RBTDRV_PODVM_TAG_WSL_X86,
        ) {
            return v;
        }

        // Step 4: banish the whole Lode, then confirm the registry is restored.
        if let Some(v) = zrbtdrv_banish_and_verify_gone(ctx, dir, &touchmark) {
            return v;
        }

        let _ = std::fs::write(dir.join("07-passed.txt"), "passed");
        rbtdre_Verdict::Pass
    })
}

pub static RBTDRV_CASES_PODVM_LIFECYCLE: &[rbtdre_Case] = &[case!(rbtdrv_podvm_lifecycle)];


// Batch-vouch fixture — exercises rbfv_batch_vouch's two-pass pending→vouched
// transition. Single self-contained lifecycle: ordain conjure, jettison the
// vouch ark to plant a pending hallmark, tally to confirm pending, batch_vouch
// to fill the gap, tally to confirm vouched, abjure.

/// Locate a hallmark's row in tally stdout and return its health column.
/// Tally rows have shape `  <hallmark>  <health>  <basenames...>`.
fn rbtdrv_tally_health(stdout: &str, hallmark: &str) -> Option<String> {
    for line in stdout.lines() {
        let mut fields = line.split_whitespace();
        if fields.next() == Some(hallmark) {
            return fields.next().map(str::to_string);
        }
    }
    None
}

fn rbtdrv_batch_vouch_lifecycle(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let vessel_dir = RBTDRV_BUSYBOX_VESSEL_DIR;
        if !ctx.project_root().join(vessel_dir).is_dir() {
            return rbtdre_Verdict::Fail(format!("vessel directory not found: {}", vessel_dir));
        }

        let hallmark = match rbtdri_ordain_capture(ctx, dir, vessel_dir, &[], "01-ordain") {
            Ok(h) => h,
            Err(v) => return v,
        };

        // Plant pending state: jettison the vouch ark, leaving image+about.
        let _ = std::fs::write(dir.join("02-plant-jettison.txt"), "jettisoning vouch");
        let jettison_locator = rbtdri_gar_ref_categorical(
            RBTDRV_GAR_CATEGORY_HALLMARKS,
            RBTDRV_ARK_BASENAME_VOUCH,
            &hallmark,
        );
        match rbtdri_invoke_global(ctx, RBTDGC_JETTISON_HALLMARK_IMAGE, &[&jettison_locator], &[(RBTDRI_BURE_CONFIRM_KEY, RBTDRI_BURE_CONFIRM_SKIP)]) {
            Ok(r) if r.exit_code == 0 => {}
            Ok(r) => return rbtdre_Verdict::Fail(format!("plant jettison failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("plant jettison invocation: {}", e)),
        }

        // Tally — expect pending classification on our hallmark.
        let _ = std::fs::write(dir.join("03-tally-pending.txt"), "tallying for pending");
        let tally_pending = match rbtdri_invoke_global(ctx, RBTDGC_TALLY_HALLMARKS, &[], &[]) {
            Ok(r) if r.exit_code == 0 => r,
            Ok(r) => return rbtdre_Verdict::Fail(format!("tally (pending) failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("tally (pending) invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("03-tally-pending-stdout.txt"), &tally_pending.stdout);
        match rbtdrv_tally_health(&tally_pending.stdout, &hallmark) {
            Some(h) if h == "pending" => {}
            Some(h) => return rbtdre_Verdict::Fail(format!(
                "tally: expected health 'pending' for {}, got '{}'\nstdout:\n{}",
                hallmark, h, tally_pending.stdout
            )),
            None => return rbtdre_Verdict::Fail(format!(
                "tally: hallmark {} not found in tally output\nstdout:\n{}",
                hallmark, tally_pending.stdout
            )),
        }

        // Batch vouch — should detect the pending hallmark and re-create vouch.
        let _ = std::fs::write(dir.join("04-batch-vouch.txt"), "running batch vouch");
        match rbtdri_invoke_global(ctx, RBTDGC_VOUCH_HALLMARKS, &[], &[]) {
            Ok(r) if r.exit_code == 0 => {}
            Ok(r) => return rbtdre_Verdict::Fail(format!("batch_vouch failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("batch_vouch invocation: {}", e)),
        }

        // Tally — expect vouched after batch_vouch.
        let _ = std::fs::write(dir.join("05-tally-vouched.txt"), "tallying for vouched");
        let tally_vouched = match rbtdri_invoke_global(ctx, RBTDGC_TALLY_HALLMARKS, &[], &[]) {
            Ok(r) if r.exit_code == 0 => r,
            Ok(r) => return rbtdre_Verdict::Fail(format!("tally (vouched) failed (exit {})\n{}", r.exit_code, r.stderr)),
            Err(e) => return rbtdre_Verdict::Fail(format!("tally (vouched) invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("05-tally-vouched-stdout.txt"), &tally_vouched.stdout);
        match rbtdrv_tally_health(&tally_vouched.stdout, &hallmark) {
            Some(h) if h == "vouched" => {}
            Some(h) => return rbtdre_Verdict::Fail(format!(
                "tally: expected health 'vouched' for {}, got '{}'\nstdout:\n{}",
                hallmark, h, tally_vouched.stdout
            )),
            None => return rbtdre_Verdict::Fail(format!(
                "tally: hallmark {} not found in tally output\nstdout:\n{}",
                hallmark, tally_vouched.stdout
            )),
        }

        if let Err(v) = rbtdri_invoke_or_fail(
            ctx,
            "abjure",
            &hallmark,
            RBTDGC_ABJURE_HALLMARK,
            &[&hallmark],
            &[(RBTDRI_BURE_CONFIRM_KEY, RBTDRI_BURE_CONFIRM_SKIP)],
            dir,
            "06-abjure",
        ) {
            return v;
        }

        let _ = std::fs::write(dir.join("07-passed.txt"), "passed");
        rbtdre_Verdict::Pass
    })
}

pub static RBTDRV_CASES_BATCH_VOUCH: &[rbtdre_Case] = &[case!(rbtdrv_batch_vouch_lifecycle)];

// ── Access probe cases (bare fixture, imprint-scoped) ────────

/// Invoke a credential access-probe tabtarget by role, check exit code.
fn rbtdrv_access_probe_role(ctx: &mut rbtdri_Context, role: &str, dir: &Path) -> rbtdre_Verdict {
    let colophon = match rbtdrm_credential_check_colophon(role) {
        Some(c) => c,
        None => return rbtdre_Verdict::Fail(format!("unknown credential role: {}", role)),
    };
    let result = match rbtdri_invoke_global(ctx, colophon, &[], &[]) {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("{} probe invocation: {}", role, e)),
    };
    let _ = std::fs::write(dir.join("probe-stdout.txt"), &result.stdout);
    let _ = std::fs::write(dir.join("probe-stderr.txt"), &result.stderr);

    if result.exit_code != 0 {
        return rbtdre_Verdict::Fail(format!(
            "{} probe exited {}\n{}",
            role, result.exit_code, result.stderr
        ));
    }
    rbtdre_Verdict::Pass
}

fn rbtdrv_oauth_payor(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrv_access_probe_role(ctx, RBTDGC_ACCOUNT_PAYOR, dir))
}

// ── Sitting-runway gate and novate round-trip ────────────────

/// Impossible runway demand — above the 12h workforce-session ceiling (43200s),
/// so ANY live sitting's remaining runway falls short and the avow reuse gate
/// must reject. Keeps the negative deterministic without forging cache state:
/// the demand rides rba_avow's parameterized required-runway seam (the designed
/// per-operation channel), never a test-only back door.
const RBTDRV_RUNWAY_IMPOSSIBLE_SEC: &str = "999999";

/// The shared sitting-ready leader: espy the sitting read-only and fail fast
/// when none is live — never prompts, never waits on a device window
/// (operator ruling 260704: no interactive act may live inside a theurge
/// fixture) — then a promptless baseline avow (reuse by construction: espy
/// just proved a live sitting, so a short one band-rejects deterministically
/// at the runway gate with the novate advisory, never opening a device
/// window). Consumed by the access-probe gate case (which adds the
/// impossible-runway negative) and by the credential-readiness leader
/// (which adds the mantle dons).
///
/// Stream note: the launcher's self-logging merges the spawned tabtarget's
/// stderr into stdout (surveyed 260704 — captured stderr arrives empty), so
/// the advisory is asserted against BOTH streams and forensics print both.
fn zrbtdrv_sitting_ready_arc(ctx: &mut rbtdri_Context, dir: &Path) -> Result<(), rbtdre_Verdict> {
    // Fail-fast: the read-only espy replaces the blind device-window poll the
    // operator hit (260704) — a dead sitting is reported in seconds with the
    // open-a-sitting instruction, never waited out to the device-code expiry.
    let espy = match rbtdri_invoke_global(ctx, RBTDGC_ESPY_SITTING, &[], &[]) {
        Ok(r) if r.exit_code == 0 => r,
        Ok(r) => return Err(rbtdre_Verdict::Fail(format!(
            "sitting espy exited {} — the probe reports verdicts and should never reject\nstdout:\n{}\nstderr:\n{}",
            r.exit_code, r.stdout, r.stderr
        ))),
        Err(e) => return Err(rbtdre_Verdict::Fail(format!("sitting espy invocation: {}", e))),
    };
    let _ = std::fs::write(dir.join("00-espy-stdout.txt"), &espy.stdout);
    let _ = std::fs::write(dir.join("00-espy-stderr.txt"), &espy.stderr);

    let roots = match rbtdri_read_burv_facts_multi(&espy, RBTDGC_FACT_EXT_SITTING) {
        Ok(r) => r,
        Err(e) => return Err(rbtdre_Verdict::Fail(format!("espy wrote no sitting fact: {}", e))),
    };
    let root = match roots.as_slice() {
        [one] => one.clone(),
        other => return Err(rbtdre_Verdict::Fail(format!(
            "expected exactly one {} fact from espy, got {:?}",
            RBTDGC_FACT_EXT_SITTING, other
        ))),
    };
    let fact = match rbtdri_read_burv_fact(&espy, &format!("{}.{}", root, RBTDGC_FACT_EXT_SITTING)) {
        Ok(f) => f,
        Err(e) => return Err(rbtdre_Verdict::Fail(format!("sitting fact unreadable: {}", e))),
    };
    // The verdict token "live" is espy's (rba_espy_sitting / RBCC_fact_ext_sitting).
    if !fact.lines().any(|l| l.trim() == "verdict=live") {
        return Err(rbtdre_Verdict::Fail(format!(
            "no live sitting ({}) — open one from a terminal with {} (one device-flow \
             sign-in) or {} (fresh full window), then re-run",
            fact.replace('\n', ", "), RBTDGC_CHECK_AVOWAL, RBTDGC_NOVATE_SITTING
        )));
    }

    // Baseline avow — promptless by construction: espy just proved a live
    // sitting, so this rides the reuse path (a short sitting band-rejects
    // deterministically at the runway gate; it never opens a device window).
    match rbtdri_invoke_global(ctx, RBTDGC_CHECK_AVOWAL, &[], &[]) {
        Ok(r) if r.exit_code == 0 => {}
        Ok(r) => return Err(rbtdre_Verdict::Fail(format!(
            "baseline avow exit {} — open a sitting with {} (one device-flow click), \
             or novate ({}) if the gate turned a short sitting away\nstdout:\n{}\nstderr:\n{}",
            r.exit_code, RBTDGC_CHECK_AVOWAL, RBTDGC_NOVATE_SITTING, r.stdout, r.stderr
        ))),
        Err(e) => return Err(rbtdre_Verdict::Fail(format!("baseline avow invocation: {}", e))),
    }
    let _ = std::fs::write(dir.join("01-avow-baseline.txt"), "avowed");
    Ok(())
}

/// The deterministic gate arc: the shared sitting-ready leader, then demand
/// an impossible runway and assert the EXACT runway band plus the novate
/// advisory (the rejection must name the remedy's colophon). Never weakened
/// to bare-nonzero, per band doctrine.
fn zrbtdrv_runway_gate_arc(ctx: &mut rbtdri_Context, dir: &Path) -> Result<(), rbtdre_Verdict> {
    zrbtdrv_sitting_ready_arc(ctx, dir)?;

    let short = match rbtdri_invoke_global(
        ctx, RBTDGC_CHECK_AVOWAL, &[RBTDRV_RUNWAY_IMPOSSIBLE_SEC], &[],
    ) {
        Ok(r) => r,
        Err(e) => return Err(rbtdre_Verdict::Fail(format!("runway-demand invocation: {}", e))),
    };
    let _ = std::fs::write(dir.join("02-runway-demand-stdout.txt"), &short.stdout);
    let _ = std::fs::write(dir.join("02-runway-demand-stderr.txt"), &short.stderr);
    if short.exit_code != RBTDGC_BAND_RUNWAY {
        return Err(rbtdre_Verdict::Fail(format!(
            "avow under impossible runway demand {}s exited {} — expected runway band {}\nstdout:\n{}\nstderr:\n{}",
            RBTDRV_RUNWAY_IMPOSSIBLE_SEC, short.exit_code, RBTDGC_BAND_RUNWAY, short.stdout, short.stderr
        )));
    }
    if !short.stdout.contains(RBTDGC_NOVATE_SITTING) && !short.stderr.contains(RBTDGC_NOVATE_SITTING) {
        return Err(rbtdre_Verdict::Fail(format!(
            "runway rejection carried no novate advisory — expected '{}' on either stream\nstdout:\n{}\nstderr:\n{}",
            RBTDGC_NOVATE_SITTING, short.stdout, short.stderr
        )));
    }
    Ok(())
}

/// Picket-tier gate case: the deterministic negative alone. No novate step —
/// novation always forces a fresh sign-in under the interactive mechanism, and
/// theurge captures the streams the prompt rides, so NO interactive act may
/// live inside a fixture (operator ruling 260704 — the retired sitting-novate
/// fixture is the cautionary precedent). Novate's positive proof is the
/// operator ceremony: rbw-aN from a terminal, then a promptless plain avow.
fn rbtdrv_sitting_runway_gate(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        if let Err(v) = zrbtdrv_runway_gate_arc(ctx, dir) {
            return v;
        }
        let _ = std::fs::write(dir.join("03-passed.txt"), "passed");
        rbtdre_Verdict::Pass
    })
}

pub static RBTDRV_CASES_ACCESS_PROBE: &[rbtdre_Case] = &[
    case!(rbtdrv_oauth_payor),
    case!(rbtdrv_sitting_runway_gate),
];

// ── Credential-readiness leader ──────────────────────────────

/// The standing-freehold credential-readiness leader — the up-front step the
/// release ladders lost with the keyfile re-enrobe preamble: the shared
/// sitting-ready arc (espy fail-fast + promptless baseline avow through the
/// runway gate), then don the two mantles the ladders' inner bodies wield —
/// director (ordain/conjure) and retriever (summon/charge). Governor is
/// deliberately not donned: no release-ladder body wields it, and its
/// readiness is proven where it IS wielded (the polity fixtures). A deficit
/// rejects in seconds with the remedy named — open a sitting (rbw-aa),
/// novate a short one (rbw-aN), or seat the freehold (freehold-establish).
fn rbtdrv_credential_readiness(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        if let Err(v) = zrbtdrv_sitting_ready_arc(ctx, dir) {
            return v;
        }
        for mantle in [RBTDGC_MANTLE_DIRECTOR, RBTDGC_MANTLE_RETRIEVER] {
            match rbtdri_invoke_global(ctx, RBTDGC_CHECK_MANTLE, &[mantle], &[]) {
                Ok(r) if r.exit_code == 0 => {}
                Ok(r) => return rbtdre_Verdict::Fail(format!(
                    "don {} exit {} — mantle not donnable for the freehold subject \
                     (is the freehold seated? run freehold-establish first)\nstdout:\n{}\nstderr:\n{}",
                    mantle, r.exit_code, r.stdout, r.stderr
                )),
                Err(e) => return rbtdre_Verdict::Fail(format!("don {} invocation: {}", mantle, e)),
            }
            let _ = std::fs::write(dir.join(format!("02-don-{}.txt", mantle)), "donned");
        }
        let _ = std::fs::write(dir.join("03-passed.txt"), "passed");
        rbtdre_Verdict::Pass
    })
}

pub static RBTDRV_CASES_CREDENTIAL_READINESS: &[rbtdre_Case] =
    &[case!(rbtdrv_credential_readiness)];
