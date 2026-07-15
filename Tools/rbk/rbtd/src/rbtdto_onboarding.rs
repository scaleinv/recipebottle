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
// Tests for rbtdro_onboarding — gauntlet onboarding-sequence fixture.

use crate::rbtdra_almanac::rbtdra_lookup_fixture;
use crate::rbtdrm_manifest::RBTDRM_FIXTURE_ONBOARDING_SEQUENCE;

/// Case order is load-bearing for StateProgressing — conclave must precede
/// all reliquary-consuming cases (kludge, conjure, srjcl, airgap, bind).
#[test]
fn rbtdto_conclave_precedes_reliquary_consumers() {
    let fix = rbtdra_lookup_fixture(RBTDRM_FIXTURE_ONBOARDING_SEQUENCE)
        .expect("onboarding-sequence is registered");
    let names: Vec<&str> = fix.cases.iter().map(|c| c.name).collect();
    let conclave_idx = names
        .iter()
        .position(|n| n.contains("rbtdro_onboarding_conclave_reliquary"))
        .expect("conclave case present");
    let kludge_tadmor_idx = names
        .iter()
        .position(|n| n.contains("rbtdro_onboarding_kludge_tadmor"))
        .expect("kludge-tadmor case present");
    let kludge_ccyolo_idx = names
        .iter()
        .position(|n| n.contains("rbtdro_onboarding_kludge_ccyolo"))
        .expect("kludge-ccyolo case present");
    let conjure_idx = names
        .iter()
        .position(|n| n.contains("rbtdro_onboarding_ordain_conjure_sentry"))
        .expect("ordain-conjure case present");
    let srjcl_idx = names
        .iter()
        .position(|n| n.contains("rbtdro_onboarding_ordain_conjure_jupyter"))
        .expect("conjure-srjcl case present");
    let airgap_idx = names
        .iter()
        .position(|n| n.contains("rbtdro_onboarding_ordain_airgap_chain"))
        .expect("airgap case present");
    let bind_idx = names
        .iter()
        .position(|n| n.contains("rbtdro_onboarding_ordain_bind_plantuml"))
        .expect("ordain-bind case present");
    assert!(conclave_idx < kludge_tadmor_idx);
    assert!(conclave_idx < kludge_ccyolo_idx);
    assert!(conclave_idx < conjure_idx);
    assert!(conclave_idx < srjcl_idx);
    assert!(conclave_idx < airgap_idx);
    assert!(conclave_idx < bind_idx);
}
