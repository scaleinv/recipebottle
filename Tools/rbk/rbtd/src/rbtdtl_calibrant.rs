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
// Tests for rbtdrl_calibrant — calibrant fixture foundation. Tests pin the
// case-registration ground truth that the touchstone surface fixture depends
// on: disposition tags, sections registered, each fixture's manifest census
// declaration, per-case verdicts, sentinel write/non-write contracts.
//
// Tests look up cases through the public registry (rbtdra_lookup_fixture)
// rather than calling case fns directly — exercising the same dispatch path the
// engine uses, so a registration-without-implementation regression is caught.

use std::path::PathBuf;

use crate::rbtdgc_consts::RBTDGC_THEURGE_NIHIL;
use crate::rbtdra_almanac::rbtdra_lookup_fixture;
use crate::rbtdre_engine::{rbtdre_find_case, rbtdre_Disposition, rbtdre_Verdict};
use crate::rbtdrl_calibrant::{RBTDRL_OUTPUT_FILE, RBTDRL_SENTINEL_FILE};
use crate::rbtdrm_manifest::{
    rbtdrm_required_colophons, RBTDRM_FIXTURE_CALIBRANT_COVERAGE_ALIGNED,
    RBTDRM_FIXTURE_CALIBRANT_COVERAGE_UNDECLARED, RBTDRM_FIXTURE_CALIBRANT_COVERAGE_UNUSED,
    RBTDRM_FIXTURE_CALIBRANT_FAIL_FAST, RBTDRM_FIXTURE_CALIBRANT_PROGRESSING,
    RBTDRM_FIXTURE_CALIBRANT_SENTINEL, RBTDRM_FIXTURE_CALIBRANT_VERDICTS,
};
use crate::rbtdth_helpers::rbtdth_make_scratch;

fn rbtdtl_run_case(fixture: &'static str, case_name: &str) -> (rbtdre_Verdict, PathBuf) {
    let fix = rbtdra_lookup_fixture(fixture)
        .unwrap_or_else(|| panic!("fixture '{}' not registered", fixture));
    let case = rbtdre_find_case(fix.cases, case_name)
        .unwrap_or_else(|| panic!("case '{}' not found in fixture '{}'", case_name, fixture));
    let dir = rbtdth_make_scratch(case_name);
    let verdict = (case.func)(&dir);
    (verdict, dir)
}

fn rbtdtl_assert_pass(verdict: &rbtdre_Verdict, label: &str) {
    match verdict {
        rbtdre_Verdict::Pass => (),
        rbtdre_Verdict::Fail(d) => panic!("{}: expected Pass, got Fail({})", label, d),
        rbtdre_Verdict::Skip(d) => panic!("{}: expected Pass, got Skip({})", label, d),
    }
}

fn rbtdtl_assert_fail_with(verdict: &rbtdre_Verdict, needle: &str, label: &str) {
    match verdict {
        rbtdre_Verdict::Fail(d) => assert!(
            d.contains(needle),
            "{}: Fail detail did not contain '{}': {}",
            label,
            needle,
            d
        ),
        other => panic!("{}: expected Fail, got {:?}", label, fmt_other(other)),
    }
}

fn rbtdtl_assert_skip(verdict: &rbtdre_Verdict, label: &str) {
    if !matches!(verdict, rbtdre_Verdict::Skip(_)) {
        panic!("{}: expected Skip, got {:?}", label, fmt_other(verdict));
    }
}

fn fmt_other(v: &rbtdre_Verdict) -> &'static str {
    match v {
        rbtdre_Verdict::Pass => "Pass",
        rbtdre_Verdict::Fail(_) => "Fail",
        rbtdre_Verdict::Skip(_) => "Skip",
    }
}

// ── manifest entries ────────────────────────────────────────

/// The four verdict-family calibrants shell out to nothing, so their census
/// declarations are empty. Deliberately NOT a family-wide sweep: the coverage
/// calibrants below declare (and mis-declare) the nihil colophon on purpose,
/// and are pinned by their own tests.
#[test]
fn rbtdtl_verdict_family_declares_no_colophons() {
    for fixture in [
        RBTDRM_FIXTURE_CALIBRANT_VERDICTS,
        RBTDRM_FIXTURE_CALIBRANT_FAIL_FAST,
        RBTDRM_FIXTURE_CALIBRANT_PROGRESSING,
        RBTDRM_FIXTURE_CALIBRANT_SENTINEL,
    ] {
        let req = rbtdrm_required_colophons(fixture)
            .unwrap_or_else(|| panic!("fixture '{}' not registered in manifest", fixture));
        assert!(
            req.is_empty(),
            "fixture '{}' must declare empty required-colophons (no shell-outs); got {:?}",
            fixture,
            req
        );
    }
}

// ── per-case verdicts ───────────────────────────────────────

#[test]
fn rbtdtl_verdicts_pass_returns_pass() {
    let (verdict, dir) = rbtdtl_run_case(RBTDRM_FIXTURE_CALIBRANT_VERDICTS, "rbtdrl_verdicts_pass");
    rbtdtl_assert_pass(&verdict, "verdicts_pass");
    assert!(
        !dir.join(RBTDRL_OUTPUT_FILE).exists(),
        "pass case must not write output.txt"
    );
    assert!(
        !dir.join(RBTDRL_SENTINEL_FILE).exists(),
        "pass case must not write sentinel"
    );
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn rbtdtl_verdicts_fail_returns_fail() {
    let (verdict, dir) = rbtdtl_run_case(RBTDRM_FIXTURE_CALIBRANT_VERDICTS, "rbtdrl_verdicts_fail");
    rbtdtl_assert_fail_with(&verdict, "calibrant", "verdicts_fail");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn rbtdtl_verdicts_skip_returns_skip() {
    let (verdict, dir) = rbtdtl_run_case(RBTDRM_FIXTURE_CALIBRANT_VERDICTS, "rbtdrl_verdicts_skip");
    rbtdtl_assert_skip(&verdict, "verdicts_skip");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn rbtdtl_verdicts_pass_with_output_writes_output_file() {
    let (verdict, dir) = rbtdtl_run_case(
        RBTDRM_FIXTURE_CALIBRANT_VERDICTS,
        "rbtdrl_verdicts_pass_with_output",
    );
    rbtdtl_assert_pass(&verdict, "verdicts_pass_with_output");
    let output = dir.join(RBTDRL_OUTPUT_FILE);
    assert!(
        output.exists(),
        "pass_with_output must write {}",
        RBTDRL_OUTPUT_FILE
    );
    let body = std::fs::read_to_string(&output).expect("read output.txt");
    assert!(!body.is_empty(), "output.txt must be non-empty");
    let _ = std::fs::remove_dir_all(&dir);
}

// ── sentinel write/non-write ────────────────────────────────

#[test]
fn rbtdtl_failfast_pass_writes_no_sentinel() {
    let (verdict, dir) =
        rbtdtl_run_case(RBTDRM_FIXTURE_CALIBRANT_FAIL_FAST, "rbtdrl_failfast_pass");
    rbtdtl_assert_pass(&verdict, "failfast_pass");
    assert!(
        !dir.join(RBTDRL_SENTINEL_FILE).exists(),
        "failfast_pass must not write sentinel"
    );
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn rbtdtl_failfast_fail_returns_fail() {
    let (verdict, dir) =
        rbtdtl_run_case(RBTDRM_FIXTURE_CALIBRANT_FAIL_FAST, "rbtdrl_failfast_fail");
    rbtdtl_assert_fail_with(&verdict, "fail trigger", "failfast_fail");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn rbtdtl_failfast_not_reached_writes_sentinel_when_run() {
    let (verdict, dir) = rbtdtl_run_case(
        RBTDRM_FIXTURE_CALIBRANT_FAIL_FAST,
        "rbtdrl_failfast_not_reached",
    );
    rbtdtl_assert_pass(&verdict, "not_reached");
    assert!(
        dir.join(RBTDRL_SENTINEL_FILE).exists(),
        "not_reached must write sentinel when run"
    );
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn rbtdtl_sentinel_marks_writes_sentinel() {
    let (verdict, dir) =
        rbtdtl_run_case(RBTDRM_FIXTURE_CALIBRANT_SENTINEL, "rbtdrl_sentinel_marks");
    rbtdtl_assert_pass(&verdict, "sentinel_marks");
    assert!(
        dir.join(RBTDRL_SENTINEL_FILE).exists(),
        "calibrant-sentinel must write sentinel"
    );
    let _ = std::fs::remove_dir_all(&dir);
}

// ── progressing probe paths ─────────────────────────────────

#[test]
fn rbtdtl_progressing_probe_ok_passes() {
    let (verdict, dir) = rbtdtl_run_case(
        RBTDRM_FIXTURE_CALIBRANT_PROGRESSING,
        "rbtdrl_progressing_probe_ok",
    );
    rbtdtl_assert_pass(&verdict, "progressing_probe_ok");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn rbtdtl_progressing_probe_err_fails_with_diagnostic() {
    let (verdict, dir) = rbtdtl_run_case(
        RBTDRM_FIXTURE_CALIBRANT_PROGRESSING,
        "rbtdrl_progressing_probe_err",
    );
    rbtdtl_assert_fail_with(&verdict, "precondition", "progressing_probe_err");
    rbtdtl_assert_fail_with(&verdict, "remediation:", "progressing_probe_err");
    let _ = std::fs::remove_dir_all(&dir);
}

// ── coverage fixtures: registration shape only ───────────────
//
// The coverage cases call rbtdrc_with_ctx to reach the real invocation
// chokepoint, which panics without an installed rbtdrc context (see
// rbtdrc_crucible::rbtdrc_with_ctx). Unlike the case bodies above — pure
// functions the engine can run standalone — these need a real fixture run
// (installed context, armed census) to execute meaningfully; that exercise is
// the touchstone surface fixture's job (child rbtd runs, exit-code/stderr
// assertions). These tests pin the registration ground truth only: each
// fixture is registered, Independent, single-case, with the manifest
// declaration the coverage story depends on.

fn rbtdtl_assert_registered_single_case(fixture: &'static str, case_name: &str) {
    let fix = rbtdra_lookup_fixture(fixture)
        .unwrap_or_else(|| panic!("fixture '{}' not registered", fixture));
    assert!(
        matches!(fix.disposition, rbtdre_Disposition::Independent),
        "fixture '{}' must be Independent",
        fixture
    );
    assert_eq!(
        fix.cases.len(),
        1,
        "fixture '{}' must register exactly one case",
        fixture
    );
    assert!(
        rbtdre_find_case(fix.cases, case_name).is_some(),
        "fixture '{}' must register case '{}'",
        fixture,
        case_name
    );
}

#[test]
fn rbtdtl_coverage_aligned_declares_and_registers_nihil() {
    rbtdtl_assert_registered_single_case(
        RBTDRM_FIXTURE_CALIBRANT_COVERAGE_ALIGNED,
        "rbtdrl_coverage_aligned_invokes",
    );
    let req = rbtdrm_required_colophons(RBTDRM_FIXTURE_CALIBRANT_COVERAGE_ALIGNED)
        .expect("coverage-aligned must carry a manifest entry");
    assert_eq!(
        req,
        &[RBTDGC_THEURGE_NIHIL],
        "coverage-aligned must declare exactly the nihil colophon"
    );
}

#[test]
fn rbtdtl_coverage_undeclared_declares_empty_and_registers() {
    rbtdtl_assert_registered_single_case(
        RBTDRM_FIXTURE_CALIBRANT_COVERAGE_UNDECLARED,
        "rbtdrl_coverage_undeclared_invokes",
    );
    let req = rbtdrm_required_colophons(RBTDRM_FIXTURE_CALIBRANT_COVERAGE_UNDECLARED)
        .expect("coverage-undeclared must carry a manifest entry");
    assert!(
        req.is_empty(),
        "coverage-undeclared must declare no colophons; got {:?}",
        req
    );
}

#[test]
fn rbtdtl_coverage_unused_declares_and_registers_nihil() {
    rbtdtl_assert_registered_single_case(
        RBTDRM_FIXTURE_CALIBRANT_COVERAGE_UNUSED,
        "rbtdrl_coverage_unused_no_invoke",
    );
    let req = rbtdrm_required_colophons(RBTDRM_FIXTURE_CALIBRANT_COVERAGE_UNUSED)
        .expect("coverage-unused must carry a manifest entry");
    assert_eq!(
        req,
        &[RBTDGC_THEURGE_NIHIL],
        "coverage-unused must declare exactly the nihil colophon"
    );
}

#[test]
fn rbtdtl_coverage_unused_case_passes_without_invoking() {
    // The one case pure-passes with no ctx/tabtarget interaction — the
    // negative census check that fails this fixture lives in the engine,
    // exercised only by a real fixture run (touchstone's sibling pace).
    let (verdict, dir) = rbtdtl_run_case(
        RBTDRM_FIXTURE_CALIBRANT_COVERAGE_UNUSED,
        "rbtdrl_coverage_unused_no_invoke",
    );
    rbtdtl_assert_pass(&verdict, "coverage_unused_no_invoke");
    let _ = std::fs::remove_dir_all(&dir);
}
