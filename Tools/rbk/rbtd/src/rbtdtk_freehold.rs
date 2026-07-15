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
// Tests for rbtdrk_freehold — the shared freehold-scheme machinery and the
// keyless freehold-establish / freehold-churn fixtures.

use std::path::PathBuf;

use crate::rbtdrk_freehold::{
    rbtdrk_family_stem, rbtdrk_freehold_cloud_prefix, rbtdrk_freehold_runtime_prefix,
    rbtdrk_install_freehold_prefixes, RBTDRK_FREEHOLD_CLOUD_BASE, RBTDRK_FREEHOLD_RUNTIME_BASE,
    RBTDRK_FREEHOLD_STEM_BASE,
};
use crate::rbtdth_helpers::rbtdth_scratch_root;

/// Freehold-prefix base shape: lowercase letters, distinct cloud/runtime
/// pair, no trailing hyphen (the composer adds it). The cases rely on the
/// composed form for state detection in rbrr.env.
#[test]
fn rbtdtk_freehold_base_shape() {
    assert_ne!(RBTDRK_FREEHOLD_CLOUD_BASE, RBTDRK_FREEHOLD_RUNTIME_BASE);
    assert!(!RBTDRK_FREEHOLD_CLOUD_BASE.ends_with('-'));
    assert!(!RBTDRK_FREEHOLD_RUNTIME_BASE.ends_with('-'));
    assert!(RBTDRK_FREEHOLD_CLOUD_BASE
        .chars()
        .all(|c| c.is_ascii_lowercase()));
    assert!(RBTDRK_FREEHOLD_RUNTIME_BASE
        .chars()
        .all(|c| c.is_ascii_lowercase()));
}

/// Composed freehold prefix shape: tinctured base ends with a hyphen and
/// stays disjoint between cloud and runtime.
#[test]
fn rbtdtk_freehold_prefix_compose() {
    let cloud = rbtdrk_freehold_cloud_prefix("xyz");
    let runtime = rbtdrk_freehold_runtime_prefix("xyz");
    assert!(cloud.ends_with('-'));
    assert!(runtime.ends_with('-'));
    assert_ne!(cloud, runtime);
    assert!(cloud.starts_with(RBTDRK_FREEHOLD_CLOUD_BASE));
    assert!(runtime.starts_with(RBTDRK_FREEHOLD_RUNTIME_BASE));
    assert!(cloud.contains("xyz"));
    assert!(runtime.contains("xyz"));
}

/// Composed family stems are the base stem followed verbatim by the tincture.
/// Tied to RBTDRK_FREEHOLD_STEM_BASE rather than a literal so an era-bump of the
/// base (canest -> canest2 -> canest3 ...) can't silently desync this test.
#[test]
fn rbtdtk_family_stem_value() {
    assert_eq!(
        rbtdrk_family_stem("xyz"),
        format!("{}xyz", RBTDRK_FREEHOLD_STEM_BASE)
    );
}

/// Distinct tinctures yield disjoint composed names (prefixes and family
/// stems) — the load-bearing disjointness property for parallel-station
/// runs on a shared payor manor.
#[test]
fn rbtdtk_freehold_disjoint_per_tincture() {
    assert_ne!(
        rbtdrk_freehold_cloud_prefix("aa"),
        rbtdrk_freehold_cloud_prefix("bb")
    );
    assert_ne!(
        rbtdrk_freehold_runtime_prefix("aa"),
        rbtdrk_freehold_runtime_prefix("bb")
    );
    assert_ne!(rbtdrk_family_stem("aa"), rbtdrk_family_stem("bb"));
}

/// Dual-station dry-run for the freehold scheme: two distinct tinctures
/// produce disjoint depot project IDs, GAR repos, and SA
/// emails. Mirrors RBDC composition rules (rbdc_derived.sh) without invoking GCP.
#[test]
fn rbtdtk_freehold_dual_station_disjoint() {
    let (a, b) = ("aaa", "bbb");
    let cloud_a = rbtdrk_freehold_cloud_prefix(a);
    let cloud_b = rbtdrk_freehold_cloud_prefix(b);
    let moniker_a = format!("{}100000", rbtdrk_family_stem(a));
    let moniker_b = format!("{}100000", rbtdrk_family_stem(b));

    let project_a = format!("{}d-{}", cloud_a, moniker_a);
    let project_b = format!("{}d-{}", cloud_b, moniker_b);
    assert_ne!(project_a, project_b);
    assert!(project_a.len() <= 30, "project_a {} > 30", project_a);
    assert!(project_b.len() <= 30, "project_b {} > 30", project_b);

    assert_ne!(
        format!("{}{}-gar", cloud_a, moniker_a),
        format!("{}{}-gar", cloud_b, moniker_b)
    );

    assert_ne!(
        format!("{}b-{}", cloud_a, moniker_a),
        format!("{}b-{}", cloud_b, moniker_b)
    );

    assert_ne!(
        format!("canest-ret@{}.iam.gserviceaccount.com", project_a),
        format!("canest-ret@{}.iam.gserviceaccount.com", project_b)
    );
}

/// install_freehold_prefixes refuses cleanly when rbrr.env is absent — the
/// helper does not silently succeed against a missing regime file.
#[test]
fn rbtdtk_install_freehold_prefixes_rejects_missing_rbrr() {
    let tmp: PathBuf = rbtdth_scratch_root().join("rbtdtk-nonexistent-root-xyz");
    let _ = std::fs::remove_dir_all(&tmp);
    std::fs::create_dir_all(&tmp).expect("create tempdir");
    let result = rbtdrk_install_freehold_prefixes(&tmp);
    let _ = std::fs::remove_dir_all(&tmp);
    assert!(result.is_err(), "expected Err when {}/rbrr.env is absent", crate::rbtdgc_consts::RBTDGC_MOORINGS_DIR);
}
