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
// RBTDRF — handbook-render reveille-tier fixture for theurge
//
// Exercises every handbook display tabtarget and reports per-case pass/fail.
// Each case invokes a handbook colophon with no arguments and asserts exit 0.

use std::path::Path;

use crate::case;
use crate::rbtdre_engine::{rbtdre_Case, rbtdre_Disposition, rbtdre_Fixture, rbtdre_Tariff, rbtdre_Verdict};
use crate::rbtdri_invocation::{rbtdri_find_tabtarget_global, rbtdri_tabtarget_command};
use crate::rbtdgc_consts::{
    RBTDGC_ONBOARD_CRASH_COURSE, RBTDGC_ONBOARD_DIR_FIRST_BUILD,
    RBTDGC_ONBOARD_FIRST_CRUCIBLE,
    RBTDGC_ONBOARD_PAYOR_HB, RBTDGC_ONBOARD_START_HERE,
    RBTDGC_PAYOR_ESTABLISH,
    RBTDGC_QUOTA_BUILD,
};
use crate::rbtdrm_manifest::RBTDRM_FIXTURE_HANDBOOK_RENDER;

// ── Helper ───────────────────────────────────────────────────

/// Invoke a handbook tabtarget with no arguments and return Pass iff exit 0.
/// Writes stdout/stderr traces to the per-case directory for diagnostic review.
fn rbtdrf_hb_render(dir: &Path, colophon: &str, label: &str) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };

    let tt = match rbtdri_find_tabtarget_global(&root, colophon) {
        Ok(p) => p,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };

    let output = match rbtdri_tabtarget_command(&tt).current_dir(&root).output() {
        Ok(o) => o,
        Err(e) => {
            return rbtdre_Verdict::Fail(format!(
                "{}: failed to run {}: {}",
                label,
                tt.display(),
                e
            ));
        }
    };

    let code = output.status.code().unwrap_or(-1);
    let _ = std::fs::write(dir.join(format!("{}-stdout.txt", label)), &output.stdout);
    let _ = std::fs::write(dir.join(format!("{}-stderr.txt", label)), &output.stderr);

    if code != 0 {
        return rbtdre_Verdict::Fail(format!(
            "{}: {} exited {} — {}",
            label,
            colophon,
            code,
            String::from_utf8_lossy(&output.stderr),
        ));
    }
    rbtdre_Verdict::Pass
}

// ── Onboarding cases (8) ────────────────────────────────────

fn rbtdrf_hb_onboard_start_here(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_hb_render(dir, RBTDGC_ONBOARD_START_HERE, "onboard-start-here")
}

fn rbtdrf_hb_onboard_crash_course(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_hb_render(dir, RBTDGC_ONBOARD_CRASH_COURSE, "onboard-crash-course")
}

fn rbtdrf_hb_onboard_first_crucible(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_hb_render(dir, RBTDGC_ONBOARD_FIRST_CRUCIBLE, "onboard-first-crucible")
}

fn rbtdrf_hb_onboard_dir_first_build(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_hb_render(dir, RBTDGC_ONBOARD_DIR_FIRST_BUILD, "onboard-dir-first-build")
}

fn rbtdrf_hb_onboard_payor_hb(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_hb_render(dir, RBTDGC_ONBOARD_PAYOR_HB, "onboard-payor-hb")
}

// ── Payor cases (2) ─────────────────────────────────────────

fn rbtdrf_hb_payor_establish(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_hb_render(dir, RBTDGC_PAYOR_ESTABLISH, "payor-establish")
}

fn rbtdrf_hb_quota_build(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_hb_render(dir, RBTDGC_QUOTA_BUILD, "quota-build")
}

// ── Case array ──────────────────────────────────────────────

pub static RBTDRF_CASES_HANDBOOK_RENDER: &[rbtdre_Case] = &[
    case!(rbtdrf_hb_onboard_start_here),
    case!(rbtdrf_hb_onboard_crash_course),
    case!(rbtdrf_hb_onboard_first_crucible),
    case!(rbtdrf_hb_onboard_dir_first_build),
    case!(rbtdrf_hb_onboard_payor_hb),
    case!(rbtdrf_hb_payor_establish),
    case!(rbtdrf_hb_quota_build),
];

// ── Fixture static ───────────────────────────────────────────

pub static RBTDRF_FIXTURE_HANDBOOK_RENDER: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_HANDBOOK_RENDER,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRF_CASES_HANDBOOK_RENDER,
    credless: true,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: None, invocations: Some(7) },
};
