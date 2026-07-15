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
// RBTDRL — calibrant fixtures: synthetic test inputs with deterministic
// verdicts that exercise the operator-facing surface of the theurge engine.
// Internal framework-test plumbing; not end-user-facing.
//
// Seven fixtures registered through rbtdrm_manifest.rs and dispatched via
// rbtdrc_crucible.rs:
//
//   calibrant-verdicts             Independent  4 cases  verdict-path coverage
//   calibrant-fail-fast            Independent  3 cases  fail-fast halts subsequent cases
//   calibrant-progressing  StateProgressing     2 cases  probe Ok/Err dispatch
//   calibrant-sentinel             Independent  1 case   suite-fail-fast pivot
//   calibrant-coverage-aligned     Independent  1 case   declared+invoked census colophon
//   calibrant-coverage-undeclared  Independent  1 case   invoked-but-undeclared -> positive-check FAIL
//   calibrant-coverage-unused      Independent  1 case   declared-but-unused -> negative-check FAIL
//
// The first four declare empty rbtdrm_required_colophons — their cases never
// shell out to bash tabtargets, so the manifest-coupling check is vacuous.
// The three coverage fixtures invoke (or deliberately don't invoke) the
// synthetic RBTDGC_THEURGE_NIHIL colophon to exercise the census enforcement
// itself; their manifest declarations are what differ between them.
//
// The touchstone surface fixture (rbtdrj_touchstone.rs) consumes these
// fixtures as child rbtd runs through the real tabtarget chain and asserts
// engine-output contracts (exit codes, diagnostic format, fail-fast
// semantics, disposition × keep-going policy gate, census diagnostics).
// calibrant-fail-fast and calibrant-sentinel additionally compose the
// registered `calibrant` suite — touchstone's suite-abort subject; the rest
// stay roster-only.

use std::path::Path;

use crate::case;
use crate::rbtdgc_consts::RBTDGC_THEURGE_NIHIL;
use crate::rbtdrb_probe::{rbtdrb_assert, rbtdrb_Probe};
use crate::rbtdrc_crucible::rbtdrc_with_ctx;
use crate::rbtdre_engine::{rbtdre_Case, rbtdre_Disposition, rbtdre_Fixture, rbtdre_Tariff, rbtdre_Verdict};
use crate::rbtdri_invocation::rbtdri_invoke_global;
use crate::rbtdrm_manifest::{
    RBTDRM_FIXTURE_CALIBRANT_COVERAGE_ALIGNED, RBTDRM_FIXTURE_CALIBRANT_COVERAGE_UNDECLARED,
    RBTDRM_FIXTURE_CALIBRANT_COVERAGE_UNUSED, RBTDRM_FIXTURE_CALIBRANT_FAIL_FAST,
    RBTDRM_FIXTURE_CALIBRANT_PROGRESSING, RBTDRM_FIXTURE_CALIBRANT_SENTINEL,
    RBTDRM_FIXTURE_CALIBRANT_VERDICTS,
};

/// Sentinel filename written into a case's temp dir to mark execution. The
/// touchstone fixture asserts presence/absence under the BURV_TEMP_ROOT_DIR
/// it set for the child rbtd invocation. I/O failure during sentinel write
/// fails the case visibly — silent failure would hide bugs in the engine's
/// case-dir contract.
pub(crate) const RBTDRL_SENTINEL_FILE: &str = "ran.sentinel";

/// Case-written output filename. Distinct from the engine's auto-written
/// trace.txt so the touchstone fixture can verify both the engine's per-case
/// trace contract and the case's own write contract.
pub(crate) const RBTDRL_OUTPUT_FILE: &str = "output.txt";

fn rbtdrl_write_sentinel(dir: &Path) -> Result<(), rbtdre_Verdict> {
    std::fs::write(dir.join(RBTDRL_SENTINEL_FILE), "")
        .map_err(|e| rbtdre_Verdict::Fail(format!("sentinel write failed: {}", e)))
}

// ── calibrant-verdicts ──────────────────────────────────────

fn rbtdrl_verdicts_pass(_dir: &Path) -> rbtdre_Verdict {
    rbtdre_Verdict::Pass
}

fn rbtdrl_verdicts_fail(_dir: &Path) -> rbtdre_Verdict {
    rbtdre_Verdict::Fail("calibrant deterministic fail verdict".to_string())
}

fn rbtdrl_verdicts_skip(_dir: &Path) -> rbtdre_Verdict {
    rbtdre_Verdict::Skip("calibrant deterministic skip verdict".to_string())
}

fn rbtdrl_verdicts_pass_with_output(dir: &Path) -> rbtdre_Verdict {
    if let Err(e) = std::fs::write(
        dir.join(RBTDRL_OUTPUT_FILE),
        "calibrant case-written output\n",
    ) {
        return rbtdre_Verdict::Fail(format!("output write failed: {}", e));
    }
    rbtdre_Verdict::Pass
}

pub static RBTDRL_CASES_VERDICTS: &[rbtdre_Case] = &[
    case!(rbtdrl_verdicts_pass),
    case!(rbtdrl_verdicts_fail),
    case!(rbtdrl_verdicts_skip),
    case!(rbtdrl_verdicts_pass_with_output),
];

// ── calibrant-fail-fast ─────────────────────────────────────

fn rbtdrl_failfast_pass(_dir: &Path) -> rbtdre_Verdict {
    rbtdre_Verdict::Pass
}

fn rbtdrl_failfast_fail(_dir: &Path) -> rbtdre_Verdict {
    rbtdre_Verdict::Fail("calibrant fail-fast fail trigger".to_string())
}

/// Trailing case after the deterministic fail. Under default fail-fast it
/// never runs and its sentinel must be absent; under keep-going it runs and
/// writes the sentinel.
fn rbtdrl_failfast_not_reached(dir: &Path) -> rbtdre_Verdict {
    if let Err(v) = rbtdrl_write_sentinel(dir) {
        return v;
    }
    rbtdre_Verdict::Pass
}

pub static RBTDRL_CASES_FAIL_FAST: &[rbtdre_Case] = &[
    case!(rbtdrl_failfast_pass),
    case!(rbtdrl_failfast_fail),
    case!(rbtdrl_failfast_not_reached),
];

// ── calibrant-progressing ───────────────────────────────────

/// Probe-Ok mechanism: deterministic Ok return. No env-var or file coupling
/// — a single fixture run exercises the case-body-runs-after-Probe-Ok path.
fn rbtdrl_probe_ok() -> Result<(), String> {
    Ok(())
}

/// Probe-Err mechanism: deterministic Err return. Case body never runs, so a
/// single fixture run exercises the Fail-via-Probe-Err path. Required by the
/// touchstone fixture to verify rbtdrb_assert's "precondition '%s' not met:" +
/// "remediation:" diagnostic format.
fn rbtdrl_probe_err() -> Result<(), String> {
    Err("calibrant deterministic probe failure".to_string())
}

fn rbtdrl_progressing_probe_ok(_dir: &Path) -> rbtdre_Verdict {
    let probe = rbtdrb_Probe {
        name: "calibrant deterministic ok",
        check: rbtdrl_probe_ok,
        remediation: "n/a — deterministic probe always Ok",
    };
    if let Err(v) = rbtdrb_assert(&probe) {
        return v;
    }
    rbtdre_Verdict::Pass
}

fn rbtdrl_progressing_probe_err(_dir: &Path) -> rbtdre_Verdict {
    let probe = rbtdrb_Probe {
        name: "calibrant deterministic err",
        check: rbtdrl_probe_err,
        remediation: "n/a — deterministic probe always Err for engine surface verification",
    };
    if let Err(v) = rbtdrb_assert(&probe) {
        return v;
    }
    rbtdre_Verdict::Fail("calibrant probe-err case body executed unexpectedly".to_string())
}

pub static RBTDRL_CASES_PROGRESSING: &[rbtdre_Case] = &[
    case!(rbtdrl_progressing_probe_ok),
    case!(rbtdrl_progressing_probe_err),
];

// ── calibrant-sentinel ──────────────────────────────────────

/// Single-case Independent fixture used as a suite-level fail-fast pivot:
/// place this fixture after a failing fixture in the calibrant suite and
/// assert the sentinel is absent.
fn rbtdrl_sentinel_marks(dir: &Path) -> rbtdre_Verdict {
    if let Err(v) = rbtdrl_write_sentinel(dir) {
        return v;
    }
    rbtdre_Verdict::Pass
}

pub static RBTDRL_CASES_SENTINEL: &[rbtdre_Case] = &[case!(rbtdrl_sentinel_marks)];

// ── calibrant-coverage-aligned / -undeclared / -unused ───────
//
// Three single-case Independent fixtures proving the RBTDRI colophon census
// enforcement lands its diagnostics against the synthetic RBTDGC_THEURGE_NIHIL
// colophon — zero cloud/filesystem side effects. Manifest declaration
// (rbtdrm_required_colophons) is the only difference between the three; the
// touchstone surface fixture spawns each as a child rbtd run and asserts the
// resulting exit code and diagnostic text (coverage section of its case
// catalog). Roster-only: a member of no suite.

/// Invoke the nihil tabtarget through the real invocation chokepoint
/// (rbtdri_invoke_global). Shared body for the aligned and undeclared cases —
/// their fixtures' manifest declarations are what differ.
fn zrbtdrl_invoke_nihil() -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| match rbtdri_invoke_global(ctx, RBTDGC_THEURGE_NIHIL, &[], &[]) {
        Ok(result) if result.exit_code == 0 => rbtdre_Verdict::Pass,
        Ok(result) => rbtdre_Verdict::Fail(format!("nihil tabtarget exited {}", result.exit_code)),
        Err(e) => rbtdre_Verdict::Fail(e),
    })
}

/// Declared and invoked: the census positive check has nothing to refuse, and
/// the negative check finds the declared colophon in the used-set — Pass.
fn rbtdrl_coverage_aligned_invokes(_dir: &Path) -> rbtdre_Verdict {
    zrbtdrl_invoke_nihil()
}

/// Invoked but never declared (this fixture's manifest entry is `Some(&[])`):
/// the census positive check in rbtdri_invoke_impl refuses the invoke before
/// the tabtarget ever launches, failing the fixture.
fn rbtdrl_coverage_undeclared_invokes(_dir: &Path) -> rbtdre_Verdict {
    zrbtdrl_invoke_nihil()
}

/// Declared but never invoked: this case passes clean, and the engine's
/// negative census check fails the fixture afterward for the unused
/// declaration.
fn rbtdrl_coverage_unused_no_invoke(_dir: &Path) -> rbtdre_Verdict {
    rbtdre_Verdict::Pass
}

pub static RBTDRL_CASES_COVERAGE_ALIGNED: &[rbtdre_Case] = &[case!(rbtdrl_coverage_aligned_invokes)];
pub static RBTDRL_CASES_COVERAGE_UNDECLARED: &[rbtdre_Case] =
    &[case!(rbtdrl_coverage_undeclared_invokes)];
pub static RBTDRL_CASES_COVERAGE_UNUSED: &[rbtdre_Case] = &[case!(rbtdrl_coverage_unused_no_invoke)];

// ── Fixture statics ──────────────────────────────────────────

pub static RBTDRL_FIXTURE_VERDICTS: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_CALIBRANT_VERDICTS,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRL_CASES_VERDICTS,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};
const _: () = assert!(RBTDRL_FIXTURE_VERDICTS.cases.len() == 4);

pub static RBTDRL_FIXTURE_FAIL_FAST: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_CALIBRANT_FAIL_FAST,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRL_CASES_FAIL_FAST,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};
const _: () = assert!(RBTDRL_FIXTURE_FAIL_FAST.cases.len() == 3);

pub static RBTDRL_FIXTURE_PROGRESSING: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_CALIBRANT_PROGRESSING,
    disposition: rbtdre_Disposition::StateProgressing,
    setup: None,
    teardown: None,
    cases: RBTDRL_CASES_PROGRESSING,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};
const _: () = assert!(RBTDRL_FIXTURE_PROGRESSING.cases.len() == 2);

pub static RBTDRL_FIXTURE_SENTINEL: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_CALIBRANT_SENTINEL,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRL_CASES_SENTINEL,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};
const _: () = assert!(RBTDRL_FIXTURE_SENTINEL.cases.len() == 1);

pub static RBTDRL_FIXTURE_COVERAGE_ALIGNED: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_CALIBRANT_COVERAGE_ALIGNED,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRL_CASES_COVERAGE_ALIGNED,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};
const _: () = assert!(RBTDRL_FIXTURE_COVERAGE_ALIGNED.cases.len() == 1);

pub static RBTDRL_FIXTURE_COVERAGE_UNDECLARED: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_CALIBRANT_COVERAGE_UNDECLARED,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRL_CASES_COVERAGE_UNDECLARED,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};
const _: () = assert!(RBTDRL_FIXTURE_COVERAGE_UNDECLARED.cases.len() == 1);

pub static RBTDRL_FIXTURE_COVERAGE_UNUSED: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_CALIBRANT_COVERAGE_UNUSED,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRL_CASES_COVERAGE_UNUSED,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};
const _: () = assert!(RBTDRL_FIXTURE_COVERAGE_UNUSED.cases.len() == 1);
