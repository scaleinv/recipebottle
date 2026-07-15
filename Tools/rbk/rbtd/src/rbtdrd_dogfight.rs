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
// RBTDRD — dogfight cloud-build viability fixture
//
// Proves the cloud-depot build-and-retrieve path yields a *runnable*
// artifact, with no crucible apparatus. Standing-depot scenario fixture in
// the operator-precondition family: it reuses a depot the operator has levied
// by hand (no levy, no unmake) and assumes director + retriever credentials
// already in place. It differs from the skirmish chain
// on the crucible axis — dogfight charges NO crucible. It proves only
// build → summon → run viability, not containment (the crucible's orthogonal
// concern).
//
// Single case, ordain → summon → resolved-base check → run → abjure, threaded
// through one body. The busybox vessel is consumerless — no nameplate holds its
// hallmark, so there is no committed regime file to carry the ephemeral hallmark
// across a case boundary. The hallmark therefore lives as a local across the
// steps, the same structural choice rbtdrv_hallmark_lifecycle makes for the same
// reason. This fixture IS hallmark_lifecycle with the registry-inventory
// middle (audit/rekon) swapped for summon + a bare container-runtime run.
//
// The resolved-base check reads the rbi_resolved_base_1 label off the summoned
// image and fails loud if it diverges from the vessel's committed base — the
// regression guard for the conjure resolved-base provenance feature (RBSAC /
// RBr_b4e). It reuses this fixture's existing ordain rather than spending a
// second cloud build on a separate case.

use std::path::Path;
use std::process::Command;

use crate::case;
use crate::rbtdrc_crucible::rbtdrc_with_ctx;
use crate::rbtdrv_patrol::{
    rbtdrv_docker_config_label, rbtdrv_docker_inspect, RBTDRV_ARK_BASENAME_IMAGE,
    RBTDRV_BUSYBOX_VESSEL_DIR,
};
use crate::rbtdre_engine::{rbtdre_Case, rbtdre_Disposition, rbtdre_Fixture, rbtdre_Tariff, rbtdre_Verdict};
use crate::rbtdri_invocation::{
    rbtdri_gar_ref_fact, rbtdri_invoke_or_fail, rbtdri_ordain_capture_full, rbtdri_Context,
    RBTDRI_BURE_CONFIRM_KEY, RBTDRI_BURE_CONFIRM_SKIP,
};
use crate::rbtdgc_consts::{RBTDGC_ABJURE_HALLMARK, RBTDGC_RBRV_FILE, RBTDGC_SUMMON_HALLMARK};

/// Container runtime for the bare executability proof. Hardcoded to docker;
/// podman is deferred to the Director-governed runtime-regime decision that
/// rides with ₣BS. This single named site is the future swap point — do NOT
/// add a regime field here now.
const RBTDRD_RUNTIME: &str = "docker";

/// Degenerate command proving the summoned image is runnable. busybox's
/// default cmd is `sh`; passing an explicit `true` yields a clean exit-0
/// executability proof without spawning an interactive shell.
const RBTDRD_PROOF_CMD: &str = "true";

// ── Runtime run helper ───────────────────────────────────────

/// Run `<runtime> run --rm <image_ref> <cmd>` and return Ok on exit 0. The
/// single site naming the container runtime — see RBTDRD_RUNTIME.
fn rbtdrd_runtime_run(image_ref: &str, cmd: &str, dir: &Path) -> Result<(), String> {
    let output = Command::new(RBTDRD_RUNTIME)
        .args(["run", "--rm", image_ref, cmd])
        .output()
        .map_err(|e| format!("{} run exec failed: {}", RBTDRD_RUNTIME, e))?;
    let _ = std::fs::write(dir.join("run-stdout.txt"), &output.stdout);
    let _ = std::fs::write(dir.join("run-stderr.txt"), &output.stderr);
    if !output.status.success() {
        return Err(format!(
            "{} run --rm {} {} exited {}: {}",
            RBTDRD_RUNTIME,
            image_ref,
            cmd,
            output.status.code().unwrap_or(-1),
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    Ok(())
}

// ── Committed-config reader ──────────────────────────────────

/// Read one shell-assignment field from a vessel's rbrv.env, value with
/// surrounding double-quotes stripped. The committed-config source the
/// resolved-base divergence check compares the emitted label against.
fn rbtdrd_vessel_field(
    ctx: &rbtdri_Context,
    vessel_dir: &str,
    key: &str,
) -> Result<String, String> {
    let path = ctx.project_root().join(vessel_dir).join(RBTDGC_RBRV_FILE);
    let body = std::fs::read_to_string(&path)
        .map_err(|e| format!("read {}: {}", path.display(), e))?;
    let prefix = format!("{}=", key);
    for line in body.lines() {
        if let Some(value) = line.trim().strip_prefix(&prefix) {
            return Ok(value.trim().trim_matches('"').to_owned());
        }
    }
    Err(format!("{} not found in {}", key, path.display()))
}

// ── Case ─────────────────────────────────────────────────────

fn rbtdrd_build_run_lifecycle(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrd_build_run_lifecycle_impl(ctx, dir))
}

fn rbtdrd_build_run_lifecycle_impl(ctx: &mut rbtdri_Context, dir: &Path) -> rbtdre_Verdict {
    let vessel_dir = RBTDRV_BUSYBOX_VESSEL_DIR;
    if !ctx.project_root().join(vessel_dir).is_dir() {
        return rbtdre_Verdict::Fail(format!("vessel directory not found: {}", vessel_dir));
    }

    // Ordain (conjure-mode): build busybox into the standing depot, capturing
    // the hallmark plus the gar_root/ark_stem facts needed to name the
    // locally-pulled image after summon.
    let (hallmark, gar_root, ark_stem) =
        match rbtdri_ordain_capture_full(ctx, dir, vessel_dir, &[], "01-ordain") {
            Ok(facts) => facts,
            Err(v) => return v,
        };

    // The image ref summon pulls locally: <gar_root>/<ark_stem>/image:<hallmark>.
    // Same construction onboarding's conjure verification tail uses.
    let image_ref = rbtdri_gar_ref_fact(&gar_root, &ark_stem, RBTDRV_ARK_BASENAME_IMAGE, &hallmark);
    let _ = std::fs::write(dir.join("02-image-ref.txt"), &image_ref);

    // Summon: retriever pulls the hallmark's arks locally. Confirm the image
    // ark is resolvable before attempting to run it.
    let _ = std::fs::write(dir.join("03-summon.txt"), "summoning");
    if let Err(v) = rbtdri_invoke_or_fail(
        ctx,
        "summon",
        &hallmark,
        RBTDGC_SUMMON_HALLMARK,
        &[&hallmark],
        &[],
        dir,
        "03-summon",
    ) {
        return v;
    }
    if !rbtdrv_docker_inspect(&image_ref) {
        return rbtdre_Verdict::Fail(format!(
            "summon: image ark not local after pull: {}",
            image_ref
        ));
    }

    // Resolved-base provenance regression: the summoned image must carry the
    // rbi_resolved_base_1 label naming the vessel's committed base (busybox is a
    // pass-through, slot-1 vessel), pinned by a well-formed sha256. The label
    // rides the consumer image config byte-identically into the signed attest
    // image (RBr_b4e), so reading it off the locally summoned consumer image is
    // the same value without a registry round-trip.
    let _ = std::fs::write(dir.join("03-resolved-base.txt"), "checking rbi_resolved_base_1");
    let label = match rbtdrv_docker_config_label(&image_ref, "rbi_resolved_base_1") {
        Ok(v) => v,
        Err(e) => {
            return rbtdre_Verdict::Fail(format!(
                "resolved-base: docker inspect label failed: {}",
                e
            ))
        }
    };
    let _ = std::fs::write(dir.join("03-resolved-base-label.txt"), &label);
    if label.is_empty() {
        return rbtdre_Verdict::Fail(format!(
            "resolved-base: rbi_resolved_base_1 absent on {} — write-side (rbgjb03/rbgjb04) regression",
            image_ref
        ));
    }
    let (ref_portion, digest) = match label.split_once("@sha256:") {
        Some(pair) => pair,
        None => {
            return rbtdre_Verdict::Fail(format!(
                "resolved-base: label not @sha256:-pinned: {}",
                label
            ))
        }
    };
    if digest.len() != 64 || !digest.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f')) {
        return rbtdre_Verdict::Fail(format!(
            "resolved-base: malformed sha256 digest in label: {}",
            label
        ));
    }
    // The ref-portion must equal the committed RBRV_IMAGE_1_ORIGIN with its tag
    // stripped — the exact transform rbgjb03 applies (${origin%:*}). A mismatch is
    // a provenance lie: the label names a base the vessel never committed.
    let committed_origin = match rbtdrd_vessel_field(ctx, vessel_dir, "RBRV_IMAGE_1_ORIGIN") {
        Ok(v) => v,
        Err(e) => return rbtdre_Verdict::Fail(format!("resolved-base: {}", e)),
    };
    let expected_ref = committed_origin
        .rsplit_once(':')
        .map(|(base, _)| base)
        .unwrap_or(committed_origin.as_str());
    if ref_portion != expected_ref {
        return rbtdre_Verdict::Fail(format!(
            "resolved-base DIVERGENCE: label base '{}' != committed '{}' (RBRV_IMAGE_1_ORIGIN='{}')",
            ref_portion, expected_ref, committed_origin
        ));
    }

    // Bare run — the executability proof. No crucible: a plain
    // `<runtime> run --rm <ref> true` exiting 0 proves the summoned artifact
    // is runnable.
    let _ = std::fs::write(dir.join("04-run.txt"), "running degenerate command");
    if let Err(e) = rbtdrd_runtime_run(&image_ref, RBTDRD_PROOF_CMD, dir) {
        return rbtdre_Verdict::Fail(format!("bare run executability proof: {}", e));
    }

    // Abjure — remove the hallmark's arks, restoring the standing depot to its
    // pre-run inventory. BURE_CONFIRM skipped for non-interactive teardown.
    let _ = std::fs::write(dir.join("05-abjure.txt"), "abjuring");
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

    let _ = std::fs::write(dir.join("06-passed.txt"), "passed");
    rbtdre_Verdict::Pass
}

// ── Section registry ─────────────────────────────────────────

pub static RBTDRD_CASES_DOGFIGHT: &[rbtdre_Case] = &[case!(rbtdrd_build_run_lifecycle)];

pub static RBTDRD_FIXTURE_DOGFIGHT: rbtdre_Fixture = rbtdre_Fixture {
    name: crate::rbtdrm_manifest::RBTDRM_FIXTURE_DOGFIGHT,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRD_CASES_DOGFIGHT,
    credless: false,
    tariff: rbtdre_Tariff { min_secs: Some(60), max_secs: Some(1800), invocations: None },
};
