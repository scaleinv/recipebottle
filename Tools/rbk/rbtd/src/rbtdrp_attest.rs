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
// RBTDRP — marshal-zero attestation gate (case 1 of the depot-lifecycle fixture)
//
// The entry gate for the gauntlet suite. It asserts that the working tree was
// just zeroed by `rbw-MZ` (rblm_zero): four violation classes are checked and
// ALL surfaced in one aggregated diagnostic. Failure short-circuits the rest of
// the depot-lifecycle arc (rbtdrp_lifecycle) via the per-fixture fail_fast switch.
//
// Carved out of the lifecycle arc as its own responsibility: attesting a clean
// blank-slate regime is independent of standing a depot up and tearing it down.

use std::path::Path;

use crate::rbtdre_engine::{rbtdre_tree_clean, rbtdre_Verdict};
use crate::rbtdgc_consts::{
    RBTDGC_MOORINGS_DIR, RBTDGC_RBRD_FILE, RBTDGC_RBRN_FILE, RBTDGC_RBRR_FILE, RBTDGC_RBRV_FILE,
};
use crate::rbtdrk_freehold::{
    rbtdrk_read_env_value, rbtdrk_resolve, RBTDRK_FIELD_RBRD_CLOUD_PREFIX,
    RBTDRK_FIELD_RBRD_DEPOT_MONIKER, RBTDRK_FIELD_RBRR_RUNTIME_PREFIX,
};

/// Site-specific RBRR field rblm_zero blanks. Currently just the runtime
/// prefix — depot identity (CLOUD_PREFIX, DEPOT_MONIKER) moved to RBRD.
const RBTDRP_RBRR_BLANK_FIELDS: &[&str] = &[
    RBTDRK_FIELD_RBRR_RUNTIME_PREFIX,
];

/// Site-specific RBRD fields rblm_zero blanks. Both define the depot-bound
/// site identity (project ID, GAR repo, and pool stem derive from
/// CLOUD_PREFIX + DEPOT_MONIKER at kindle); an empty value is the post-
/// marshal-zero invariant.
const RBTDRP_RBRD_BLANK_FIELDS: &[&str] = &[
    RBTDRK_FIELD_RBRD_CLOUD_PREFIX,
    RBTDRK_FIELD_RBRD_DEPOT_MONIKER,
];

/// Nameplate hallmark fields rblm_zero blanks.
const RBTDRP_RBRN_BLANK_FIELDS: &[&str] = &["RBRN_SENTRY_HALLMARK", "RBRN_BOTTLE_HALLMARK"];

// ── Violation-class checks ───────────────────────────────────

/// Class A — working tree clean (`git status --porcelain` empty). Delegates to
/// the shared engine check so the run-start guard and this fixture gate stay in
/// lockstep.
fn rbtdrp_check_tree_clean(root: &Path, violations: &mut Vec<String>) {
    if let Err(msg) = rbtdre_tree_clean(root) {
        violations.push(msg);
    }
}

/// Class B — site-specific RBRR/RBRD fields are blank.
fn rbtdrp_check_rbrr_fields(rbrr: &Path, violations: &mut Vec<String>) {
    for field in RBTDRP_RBRR_BLANK_FIELDS {
        if let Some(value) = rbtdrk_read_env_value(rbrr, field) {
            if !value.is_empty() {
                violations.push(format!(
                    "RBRR field non-blank: {}={} (in {})",
                    field,
                    value,
                    rbrr.display()
                ));
            }
        }
    }
}

fn rbtdrp_check_rbrd_fields(rbrd: &Path, violations: &mut Vec<String>) {
    for field in RBTDRP_RBRD_BLANK_FIELDS {
        if let Some(value) = rbtdrk_read_env_value(rbrd, field) {
            if !value.is_empty() {
                violations.push(format!(
                    "RBRD field non-blank: {}={} (in {})",
                    field,
                    value,
                    rbrd.display()
                ));
            }
        }
    }
}

/// Class C — every nameplate's RBRN_SENTRY_HALLMARK and RBRN_BOTTLE_HALLMARK
/// is blank.
fn rbtdrp_check_nameplate_hallmarks(root: &Path, violations: &mut Vec<String>) {
    let dot_dir = root.join(RBTDGC_MOORINGS_DIR);
    let entries = match std::fs::read_dir(&dot_dir) {
        Ok(e) => e,
        Err(e) => {
            violations.push(format!("cannot read {}: {}", dot_dir.display(), e));
            return;
        }
    };
    for entry in entries.flatten() {
        let np_dir = entry.path();
        if !np_dir.is_dir() {
            continue;
        }
        let rbrn = np_dir.join(RBTDGC_RBRN_FILE);
        if !rbrn.exists() {
            continue;
        }
        for field in RBTDRP_RBRN_BLANK_FIELDS {
            if let Some(value) = rbtdrk_read_env_value(&rbrn, field) {
                if !value.is_empty() {
                    violations.push(format!(
                        "nameplate hallmark non-blank: {}={} (in {})",
                        field,
                        value,
                        rbrn.display()
                    ));
                }
            }
        }
    }
}

/// Class D — every vessel rbrv.env has RBRV_RELIQUARY blank and every
/// RBRV_IMAGE_*_ANCHOR field blank.
fn rbtdrp_check_vessel_depot_fields(
    root: &Path,
    vessel_dir: &str,
    violations: &mut Vec<String>,
) {
    if vessel_dir.is_empty() {
        violations.push("RBRR_VESSEL_DIR is blank — cannot scan vessels".to_string());
        return;
    }
    let vroot = rbtdrk_resolve(root, vessel_dir);
    let entries = match std::fs::read_dir(&vroot) {
        Ok(e) => e,
        Err(e) => {
            violations.push(format!("cannot read {}: {}", vroot.display(), e));
            return;
        }
    };
    for entry in entries.flatten() {
        let v_dir = entry.path();
        if !v_dir.is_dir() {
            continue;
        }
        let rbrv = v_dir.join(RBTDGC_RBRV_FILE);
        if !rbrv.exists() {
            continue;
        }
        rbtdrp_scan_rbrv_file(&rbrv, violations);
    }
}

/// Scan a single rbrv.env for non-blank RBRV_RELIQUARY and RBRV_IMAGE_*_ANCHOR
/// fields.
fn rbtdrp_scan_rbrv_file(rbrv: &Path, violations: &mut Vec<String>) {
    let content = match std::fs::read_to_string(rbrv) {
        Ok(c) => c,
        Err(e) => {
            violations.push(format!("cannot read {}: {}", rbrv.display(), e));
            return;
        }
    };
    for line in content.lines() {
        let trimmed = line.trim_start();
        if trimmed.starts_with('#') {
            continue;
        }
        let (key, value) = match trimmed.split_once('=') {
            Some(kv) => kv,
            None => continue,
        };
        let is_reliquary = key == "RBRV_RELIQUARY";
        let is_anchor = key.starts_with("RBRV_IMAGE_") && key.ends_with("_ANCHOR");
        if (is_reliquary || is_anchor) && !value.is_empty() {
            violations.push(format!(
                "vessel depot-scoped field non-blank: {}={} (in {})",
                key,
                value,
                rbrv.display()
            ));
        }
    }
}

// ── Case 1: marshal-zero attestation ─────────────────────────

/// Case 1 — marshal-zero attestation. Aggregates all four violation classes
/// into a single diagnostic. A passing run is the proof that `rbw-MZ` was
/// just executed and committed.
pub(crate) fn rbtdrp_marshal_zero_attestation(_dir: &Path) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot resolve project root: {}", e)),
    };

    let rbrr = root.join(RBTDGC_RBRR_FILE);
    if !rbrr.exists() {
        return rbtdre_Verdict::Fail(format!("RBRR file not found: {}", rbrr.display()));
    }
    let rbrd = root.join(RBTDGC_RBRD_FILE);
    if !rbrd.exists() {
        return rbtdre_Verdict::Fail(format!("RBRD file not found: {}", rbrd.display()));
    }

    let vessel_dir = rbtdrk_read_env_value(&rbrr, "RBRR_VESSEL_DIR").unwrap_or_default();

    let mut violations: Vec<String> = Vec::new();

    rbtdrp_check_tree_clean(&root, &mut violations);
    rbtdrp_check_rbrr_fields(&rbrr, &mut violations);
    rbtdrp_check_rbrd_fields(&rbrd, &mut violations);
    rbtdrp_check_nameplate_hallmarks(&root, &mut violations);
    rbtdrp_check_vessel_depot_fields(&root, &vessel_dir, &mut violations);

    if violations.is_empty() {
        return rbtdre_Verdict::Pass;
    }

    let body = violations
        .iter()
        .map(|v| format!("  - {}", v))
        .collect::<Vec<_>>()
        .join("\n");
    rbtdre_Verdict::Fail(format!(
        "marshal-zero attestation failed — {} violation(s):\n{}\n\n\
         remedy: tt/rbw-MZ.MarshalZeroes.sh, then commit and rerun.",
        violations.len(),
        body
    ))
}
