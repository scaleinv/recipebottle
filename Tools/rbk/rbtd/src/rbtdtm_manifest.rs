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
// RBTDTM — manifest-module tests: pin the generated-const path literal

use super::rbtdgc_consts::*;
use crate::rbtdra_almanac::RBTDRA_FIXTURES;
use crate::rbtdrm_manifest::{rbtdrm_permitted_colophons, rbtdrm_required_colophons};

/// Pin the one surviving compile-time path literal (the `rbtd_vessels_dir!`
/// macro in lib.rs) to the generated source of truth. The macro must equal
/// `<RBTDGC_MOORINGS_DIR>/<RBTDGC_VESSELS_SUBDIR>`; if rbcc_constants.sh changes
/// either, codegen updates the consts and this test fails until the macro
/// literal is corrected — drift caught at test time, no new dependency.
#[test]
fn rbtdtm_vessels_dir_matches_generated() {
    assert_eq!(
        crate::rbtd_vessels_dir!(),
        format!("{}/{}", RBTDGC_MOORINGS_DIR, RBTDGC_VESSELS_SUBDIR)
    );
}

/// A permitted declaration is inert unless the fixture also carries a required
/// entry: `rbtdrm_required_colophons` returning `None` disables the census
/// outright, and the positive check reads the permitted set only from inside
/// that `Some` arm. So a fixture declaring permitted colophons with no required
/// entry would silently get no census at all — the permitted list reading as
/// coverage while enforcing nothing. Pin the invariant across the whole roster
/// so that pairing cannot land unnoticed.
#[test]
fn rbtdtm_permitted_declaration_requires_a_required_entry() {
    for fixture in RBTDRA_FIXTURES {
        let permitted = rbtdrm_permitted_colophons(fixture.name);
        assert!(
            permitted.is_empty() || rbtdrm_required_colophons(fixture.name).is_some(),
            "fixture '{}' declares permitted colophons {:?} but no required-colophons entry — \
             None disables the census entirely, so the permitted tier would be inert",
            fixture.name,
            permitted
        );
    }
}
