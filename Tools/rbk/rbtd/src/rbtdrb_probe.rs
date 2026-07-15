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
// RBTDRB — precondition-probe helper for StateProgressing fixtures
//
// Each case in a StateProgressing fixture probes its precondition at entry.
// If the observed state matches the expected state the case body proceeds;
// otherwise the case returns a Fail verdict naming the expected state and
// the closest fixture that establishes it. The probe encapsulates state
// verification at the case level, so the engine does not need to track
// case history to support safe a-la-carte single-case rerun.

use crate::rbtdre_engine::rbtdre_Verdict;

/// A precondition probe attached to a StateProgressing case.
pub struct rbtdrb_Probe {
    /// Human-readable label for the precondition (e.g., "depot levied").
    pub name: &'static str,
    /// Check fn. Returns Ok(()) when the precondition holds; Err carries a
    /// diagnostic describing the observed state.
    pub check: fn() -> Result<(), String>,
    /// Operator-actionable next step naming the closest fixture or tabtarget
    /// that establishes the precondition.
    pub remediation: &'static str,
}

/// Assert a probe at case entry.
///
/// On Ok(()) the precondition holds and the case body should proceed. On
/// Err(verdict) the case should return the verdict immediately — the verdict
/// names the unmet precondition and the remediation step.
pub fn rbtdrb_assert(probe: &rbtdrb_Probe) -> Result<(), rbtdre_Verdict> {
    match (probe.check)() {
        Ok(()) => Ok(()),
        Err(observed) => Err(rbtdre_Verdict::Fail(format!(
            "precondition '{}' not met: {}\nremediation: {}",
            probe.name, observed, probe.remediation
        ))),
    }
}
