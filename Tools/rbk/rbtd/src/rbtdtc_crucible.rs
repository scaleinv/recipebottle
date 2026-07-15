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
// RBTDTC — suite-composition oracle: the theurge wrapper(inner) membership matrix
//
// A runnable suite is, in the theurge model, one inner-body set run under one
// wrapper. That product is spelled by hand in RBTDRA_SUITES — the literal,
// compile-checked membership lists ARE the source of truth and stay literal.
// This module is the independent regression oracle proving those literal lists
// remain expressible as wrapper(inner) compositions: it classifies every suite
// under a first-class wrapper and asserts the structural laws the product
// implies — the REUSE product completeness (complete = service ∪ crucible) and
// the standing/lifecycle ladder containment (blockade ⊆ skirmish ⊆ gauntlet).
//
// Credless membrane: a wrapper classification never alters a fixture's
// `credless` arming. Suite membership is a set of WHOLE fixtures, each retaining
// the credless flag it was registered with; the wrapper selects the substrate
// the inner bodies run against, not their credential posture. There is no
// composition that merges two credless values, so none "wins".

use std::collections::BTreeSet;

use crate::rbtdra_almanac::{
    RBTDRA_SUITES,
    RBTDRA_SUITE_NAME_CALIBRANT,
    rbtdra_lookup_suite,
};

// Canonical suite names. The production source of truth is the `name` literal on
// each RBTDRA_SUITES entry; these test-side consts are the single spelling the
// oracle shares across its model table and law assertions (a renamed suite makes
// the lookup panic loudly rather than silently skipping a law).
const ZRBTDTC_REVEILLE: &str = "reveille";
const ZRBTDTC_PICKET: &str = "picket";
const ZRBTDTC_BIVOUAC: &str = "bivouac";
const ZRBTDTC_ECHELON: &str = "echelon";
const ZRBTDTC_GAUNTLET: &str = "gauntlet";
const ZRBTDTC_SKIRMISH: &str = "skirmish";
const ZRBTDTC_DOGFIGHT: &str = "dogfight";
const ZRBTDTC_SIEGE: &str = "siege";
const ZRBTDTC_BLOCKADE: &str = "blockade";
const ZRBTDTC_PARLEY: &str = "parley";

/// First-class wrapper classification — the theurge cosmology's two wrappers,
/// plus the two non-product suite shapes. A suite runs its inner bodies under
/// exactly one of these.
#[derive(Clone, Copy, PartialEq, Eq)]
enum rbtdtc_Wrapper {
    /// Substrate-independent — no freehold (reveille; also the calibrant
    /// abort-subject suite, whose deliberately-failing inner bodies touch no
    /// substrate at all).
    Base,
    /// Inner bodies run against a standing freehold; no create, no destroy.
    Reuse,
    /// Create the substrate, run, then destroy it — the release ladder.
    Lifecycle,
    /// Fully-local crucible with no freehold product.
    Local,
}

/// The wrapper(inner) model: every suite paired with the wrapper it runs under.
/// The exhaustiveness test pins this against RBTDRA_SUITES, so a new suite cannot
/// enter the registry without being classified under a wrapper here.
const ZRBTDTC_MODEL: &[(&str, rbtdtc_Wrapper)] = &[
    (ZRBTDTC_REVEILLE, rbtdtc_Wrapper::Base),
    (ZRBTDTC_PICKET, rbtdtc_Wrapper::Reuse),
    (ZRBTDTC_BIVOUAC, rbtdtc_Wrapper::Reuse),
    (ZRBTDTC_ECHELON, rbtdtc_Wrapper::Reuse),
    (ZRBTDTC_GAUNTLET, rbtdtc_Wrapper::Lifecycle),
    (ZRBTDTC_SKIRMISH, rbtdtc_Wrapper::Reuse),
    (ZRBTDTC_DOGFIGHT, rbtdtc_Wrapper::Reuse),
    (ZRBTDTC_SIEGE, rbtdtc_Wrapper::Local),
    (ZRBTDTC_BLOCKADE, rbtdtc_Wrapper::Reuse),
    (ZRBTDTC_PARLEY, rbtdtc_Wrapper::Reuse),
    (RBTDRA_SUITE_NAME_CALIBRANT, rbtdtc_Wrapper::Base),
];

/// Resolve a suite's membership as a set of fixture names, read live from
/// RBTDRA_SUITES. Panics if the suite is not registered — a stale suite name in
/// the model is a loud failure, not a silent skip.
fn zrbtdtc_members(suite: &str) -> BTreeSet<&'static str> {
    rbtdra_lookup_suite(suite)
        .unwrap_or_else(|| panic!("suite '{}' not registered in RBTDRA_SUITES", suite))
        .fixtures
        .iter()
        .map(|f| f.name)
        .collect()
}

#[test]
fn rbtdtc_model_classifies_every_suite() {
    // Every registered suite carries exactly one wrapper classification, and
    // every classified name is a registered suite — the model covers reality,
    // neither missing a suite nor naming a phantom.
    let registered: BTreeSet<&str> = RBTDRA_SUITES.iter().map(|s| s.name).collect();
    let modeled: BTreeSet<&str> = ZRBTDTC_MODEL.iter().map(|(n, _)| *n).collect();
    assert_eq!(
        registered, modeled,
        "wrapper model and RBTDRA_SUITES disagree on the suite set"
    );
    assert_eq!(
        ZRBTDTC_MODEL.len(),
        modeled.len(),
        "a suite is classified more than once in the wrapper model"
    );
}

#[test]
fn rbtdtc_reuse_product_completeness() {
    // complete (echelon) = service (picket) ∪ crucible (bivouac): the REUSE
    // product law. The union of the two facet suites reconstructs the complete
    // suite exactly — neither facet contributes a member the union omits, and
    // the complete suite adds nothing beyond the two facets.
    let picket = zrbtdtc_members(ZRBTDTC_PICKET);
    let bivouac = zrbtdtc_members(ZRBTDTC_BIVOUAC);
    let echelon = zrbtdtc_members(ZRBTDTC_ECHELON);
    let union: BTreeSet<&str> = picket.union(&bivouac).copied().collect();
    assert_eq!(union, echelon, "echelon must equal picket ∪ bivouac");
}

#[test]
fn rbtdtc_reuse_tier_containment() {
    let picket = zrbtdtc_members(ZRBTDTC_PICKET);
    let bivouac = zrbtdtc_members(ZRBTDTC_BIVOUAC);
    let echelon = zrbtdtc_members(ZRBTDTC_ECHELON);
    assert!(picket.is_subset(&echelon), "picket must be a subset of echelon");
    assert!(bivouac.is_subset(&echelon), "bivouac must be a subset of echelon");
}

#[test]
fn rbtdtc_ladder_containment() {
    // blockade ⊆ skirmish ⊆ gauntlet — the standing/lifecycle ladder. Each rung
    // adds wrapper machinery or inner bodies over the one below and never drops a
    // member: the airgap probe rides inside the standing-reuse mini-ladder, which
    // rides inside the lifecycle release ladder.
    let blockade = zrbtdtc_members(ZRBTDTC_BLOCKADE);
    let skirmish = zrbtdtc_members(ZRBTDTC_SKIRMISH);
    let gauntlet = zrbtdtc_members(ZRBTDTC_GAUNTLET);
    assert!(
        blockade.is_subset(&skirmish),
        "blockade must be a subset of skirmish"
    );
    assert!(
        skirmish.is_subset(&gauntlet),
        "skirmish must be a subset of gauntlet"
    );
}

#[test]
fn rbtdtc_lifecycle_builds_on_reuse() {
    // Each Lifecycle suite (create→destroy) is a superset of at least one Reuse
    // suite: the release ladder stands the same inner bodies up under a
    // create→destroy wrapper that the standing-reuse suites run against an
    // already-standing freehold. Reads the wrapper classification — the model's
    // load-bearing claim about how the two wrappers relate.
    let reuse: Vec<BTreeSet<&str>> = ZRBTDTC_MODEL
        .iter()
        .filter(|(_, w)| *w == rbtdtc_Wrapper::Reuse)
        .map(|(n, _)| zrbtdtc_members(n))
        .collect();
    for (name, wrapper) in ZRBTDTC_MODEL {
        if *wrapper == rbtdtc_Wrapper::Lifecycle {
            let members = zrbtdtc_members(name);
            assert!(
                reuse.iter().any(|r| r.is_subset(&members)),
                "lifecycle suite '{}' must be a superset of some reuse suite",
                name
            );
        }
    }
}
