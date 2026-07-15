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
// RBTDTE — tests for case execution engine

use std::path::Path;

use super::rbtdre_engine::*;
use super::rbtdth_helpers::rbtdth_make_scratch;

fn rbtdte_pass(_dir: &Path) -> rbtdre_Verdict {
    rbtdre_Verdict::Pass
}

fn rbtdte_fail(_dir: &Path) -> rbtdre_Verdict {
    rbtdre_Verdict::Fail("boom".to_string())
}

fn rbtdte_skip(_dir: &Path) -> rbtdre_Verdict {
    rbtdre_Verdict::Skip("nope".to_string())
}

const RBTDTE_COLORS: rbtdre_Colors = rbtdre_Colors {
    green: "",
    red: "",
    yellow: "",
    reset: "",
};

#[test]
fn rbtdte_counts_all_verdict_types() {
    static CASES: &[rbtdre_Case] = &[
        rbtdre_Case { name: "p1", func: rbtdte_pass },
        rbtdre_Case { name: "p2", func: rbtdte_pass },
        rbtdre_Case { name: "s1", func: rbtdte_skip },
        rbtdre_Case { name: "f1", func: rbtdte_fail },
    ];

    let tmp = rbtdth_make_scratch("counts");
    let result = rbtdre_run_cases(CASES, &RBTDTE_COLORS, false, &tmp).unwrap();
    assert_eq!(result.passed, 2);
    assert_eq!(result.failed, 1);
    assert_eq!(result.skipped, 1);
    let _ = std::fs::remove_dir_all(&tmp);
}

#[test]
fn rbtdte_fail_fast_stops_after_first_failure() {
    static CASES: &[rbtdre_Case] = &[
        rbtdre_Case { name: "ff-f1", func: rbtdte_fail },
        rbtdre_Case { name: "ff-p1", func: rbtdte_pass },
    ];

    let tmp = rbtdth_make_scratch("failfast");
    let result = rbtdre_run_cases(CASES, &RBTDTE_COLORS, true, &tmp).unwrap();
    assert_eq!(result.failed, 1);
    assert_eq!(result.passed, 0);
    let _ = std::fs::remove_dir_all(&tmp);
}

#[test]
fn rbtdte_trace_files_written() {
    static CASES: &[rbtdre_Case] = &[
        rbtdre_Case {
            name: "traced-pass",
            func: rbtdte_pass,
        },
        rbtdre_Case {
            name: "traced-fail",
            func: rbtdte_fail,
        },
    ];

    let tmp = rbtdth_make_scratch("trace");
    let _ = rbtdre_run_cases(CASES, &RBTDTE_COLORS, false, &tmp).unwrap();

    let pass_trace =
        std::fs::read_to_string(tmp.join("traced-pass").join("trace.txt")).unwrap();
    assert!(pass_trace.contains("PASSED"));

    let fail_trace =
        std::fs::read_to_string(tmp.join("traced-fail").join("trace.txt")).unwrap();
    assert!(fail_trace.contains("FAILED"));
    assert!(fail_trace.contains("boom"));

    let _ = std::fs::remove_dir_all(&tmp);
}

#[test]
fn rbtdte_cases_run_in_declaration_order() {
    static CASES: &[rbtdre_Case] = &[
        rbtdre_Case { name: "ord-a", func: rbtdte_pass },
        rbtdre_Case { name: "ord-b", func: rbtdte_pass },
        rbtdre_Case { name: "ord-c", func: rbtdte_skip },
    ];

    let tmp = rbtdth_make_scratch("order");
    let result = rbtdre_run_cases(CASES, &RBTDTE_COLORS, false, &tmp).unwrap();
    assert_eq!(result.passed, 2);
    assert_eq!(result.skipped, 1);
    assert_eq!(result.failed, 0);
    let _ = std::fs::remove_dir_all(&tmp);
}

// ── Edge cases ───────────────────────────────────────────────

#[test]
fn rbtdte_zero_cases() {
    static CASES: &[rbtdre_Case] = &[];
    let tmp = rbtdth_make_scratch("zerocases");
    let result = rbtdre_run_cases(CASES, &RBTDTE_COLORS, false, &tmp).unwrap();
    assert_eq!(result.passed, 0);
    assert_eq!(result.failed, 0);
    assert_eq!(result.skipped, 0);
    let _ = std::fs::remove_dir_all(&tmp);
}

#[test]
fn rbtdte_all_skip() {
    static CASES: &[rbtdre_Case] = &[
        rbtdre_Case { name: "sk1", func: rbtdte_skip },
        rbtdre_Case { name: "sk2", func: rbtdte_skip },
        rbtdre_Case { name: "sk3", func: rbtdte_skip },
    ];

    let tmp = rbtdth_make_scratch("allskip");
    let result = rbtdre_run_cases(CASES, &RBTDTE_COLORS, false, &tmp).unwrap();
    assert_eq!(result.passed, 0);
    assert_eq!(result.failed, 0);
    assert_eq!(result.skipped, 3);
    let _ = std::fs::remove_dir_all(&tmp);
}

#[test]
fn rbtdte_single_case_pass() {
    static CASES: &[rbtdre_Case] = &[rbtdre_Case {
        name: "solo-pass",
        func: rbtdte_pass,
    }];

    let tmp = rbtdth_make_scratch("solopass");
    let result = rbtdre_run_cases(CASES, &RBTDTE_COLORS, false, &tmp).unwrap();
    assert_eq!(result.passed, 1);
    assert_eq!(result.failed, 0);
    assert_eq!(result.skipped, 0);
    let _ = std::fs::remove_dir_all(&tmp);
}

#[test]
fn rbtdte_single_case_fail() {
    static CASES: &[rbtdre_Case] = &[rbtdre_Case {
        name: "solo-fail",
        func: rbtdte_fail,
    }];

    let tmp = rbtdth_make_scratch("solofail");
    let result = rbtdre_run_cases(CASES, &RBTDTE_COLORS, false, &tmp).unwrap();
    assert_eq!(result.passed, 0);
    assert_eq!(result.failed, 1);
    assert_eq!(result.skipped, 0);
    let _ = std::fs::remove_dir_all(&tmp);
}

// ── Run-all despite failures ─────────────────────────────────

#[test]
fn rbtdte_run_all_executes_every_case_despite_failures() {
    static CASES: &[rbtdre_Case] = &[
        rbtdre_Case { name: "ra-f1", func: rbtdte_fail },
        rbtdre_Case { name: "ra-p1", func: rbtdte_pass },
        rbtdre_Case { name: "ra-f2", func: rbtdte_fail },
        rbtdre_Case { name: "ra-p2", func: rbtdte_pass },
    ];

    let tmp = rbtdth_make_scratch("runall");
    let result = rbtdre_run_cases(CASES, &RBTDTE_COLORS, false, &tmp).unwrap();
    assert_eq!(result.passed, 2);
    assert_eq!(result.failed, 2);
    // All four case dirs were created — every case ran
    assert!(tmp.join("ra-f1").exists());
    assert!(tmp.join("ra-p1").exists());
    assert!(tmp.join("ra-f2").exists());
    assert!(tmp.join("ra-p2").exists());
    let _ = std::fs::remove_dir_all(&tmp);
}

// ── Temp dir isolation ───────────────────────────────────────

fn rbtdte_write_marker(dir: &Path) -> rbtdre_Verdict {
    let _ = std::fs::write(dir.join("marker.txt"), dir.to_string_lossy().as_bytes());
    rbtdre_Verdict::Pass
}

#[test]
fn rbtdte_temp_dirs_are_distinct_and_isolated() {
    static CASES: &[rbtdre_Case] = &[
        rbtdre_Case { name: "iso-a", func: rbtdte_write_marker },
        rbtdre_Case { name: "iso-b", func: rbtdte_write_marker },
    ];

    let tmp = rbtdth_make_scratch("isolation");
    let _ = rbtdre_run_cases(CASES, &RBTDTE_COLORS, false, &tmp).unwrap();

    let dir_a = tmp.join("iso-a");
    let dir_b = tmp.join("iso-b");

    // Dirs are distinct paths
    assert_ne!(dir_a, dir_b);

    // Each has its own marker
    let marker_a = std::fs::read_to_string(dir_a.join("marker.txt")).unwrap();
    let marker_b = std::fs::read_to_string(dir_b.join("marker.txt")).unwrap();
    assert!(marker_a.contains("iso-a"));
    assert!(marker_b.contains("iso-b"));

    // No cross-contamination: each dir has exactly 2 files (marker.txt + trace.txt)
    let entries_a: Vec<_> = std::fs::read_dir(&dir_a).unwrap().collect();
    let entries_b: Vec<_> = std::fs::read_dir(&dir_b).unwrap().collect();
    assert_eq!(entries_a.len(), 2);
    assert_eq!(entries_b.len(), 2);

    // Trace content references only its own case
    let trace_a = std::fs::read_to_string(dir_a.join("trace.txt")).unwrap();
    let trace_b = std::fs::read_to_string(dir_b.join("trace.txt")).unwrap();
    assert!(trace_a.contains("iso-a"));
    assert!(trace_b.contains("iso-b"));
    assert!(!trace_a.contains("iso-b"));
    assert!(!trace_b.contains("iso-a"));

    let _ = std::fs::remove_dir_all(&tmp);
}

// ── Disposition policy gate ──────────────────────────────────

#[test]
fn rbtdte_resolve_fail_fast_independent_default_is_fail_fast() {
    let r = rbtdre_resolve_fail_fast(rbtdre_Disposition::Independent, false).unwrap();
    assert!(r);
}

#[test]
fn rbtdte_resolve_fail_fast_independent_keep_going_permitted() {
    let r = rbtdre_resolve_fail_fast(rbtdre_Disposition::Independent, true).unwrap();
    assert!(!r);
}

#[test]
fn rbtdte_resolve_fail_fast_state_progressing_default_is_fail_fast() {
    let r = rbtdre_resolve_fail_fast(rbtdre_Disposition::StateProgressing, false).unwrap();
    assert!(r);
}

#[test]
fn rbtdte_resolve_fail_fast_state_progressing_keep_going_refused() {
    let err = rbtdre_resolve_fail_fast(rbtdre_Disposition::StateProgressing, true).unwrap_err();
    assert!(err.contains("StateProgressing"));
    assert!(err.contains("keep-going"));
}

// ── Runner CLI arg parsing ───────────────────────────────────

fn rbtdte_args(raw: &[&str]) -> Vec<String> {
    raw.iter().map(|s| s.to_string()).collect()
}

#[test]
fn rbtdte_parse_keep_going_absent() {
    let (pos, kg) = rbtdre_parse_keep_going(&rbtdte_args(&["tadmor"])).unwrap();
    assert_eq!(pos, vec!["tadmor".to_string()]);
    assert!(!kg);
}

#[test]
fn rbtdte_parse_keep_going_trailing() {
    let (pos, kg) =
        rbtdre_parse_keep_going(&rbtdte_args(&["tadmor", RBTDRE_FLAG_KEEP_GOING])).unwrap();
    assert_eq!(pos, vec!["tadmor".to_string()]);
    assert!(kg);
}

#[test]
fn rbtdte_parse_keep_going_position_independent() {
    let (pos, kg) =
        rbtdre_parse_keep_going(&rbtdte_args(&[RBTDRE_FLAG_KEEP_GOING, "tadmor"])).unwrap();
    assert_eq!(pos, vec!["tadmor".to_string()]);
    assert!(kg);
}

#[test]
fn rbtdte_parse_keep_going_unknown_flag_rejected() {
    let err = rbtdre_parse_keep_going(&rbtdte_args(&["tadmor", "--keep-goign"])).unwrap_err();
    assert!(err.contains("--keep-goign"));
    assert!(err.contains(RBTDRE_FLAG_KEEP_GOING));
}

// ── Trace file content detail ────────────────────────────────

#[test]
fn rbtdte_trace_file_skip_contains_reason() {
    static CASES: &[rbtdre_Case] = &[rbtdre_Case {
        name: "traced-skip",
        func: rbtdte_skip,
    }];

    let tmp = rbtdth_make_scratch("skiptrace");
    let _ = rbtdre_run_cases(CASES, &RBTDTE_COLORS, false, &tmp).unwrap();

    let trace = std::fs::read_to_string(tmp.join("traced-skip").join("trace.txt")).unwrap();
    assert!(trace.contains("SKIPPED"));
    assert!(trace.contains("traced-skip"));
    assert!(trace.contains("nope"));

    let _ = std::fs::remove_dir_all(&tmp);
}

#[test]
fn rbtdte_case_output_files_survive_in_trace_dir() {
    fn write_output(dir: &Path) -> rbtdre_Verdict {
        let _ = std::fs::write(dir.join("output.txt"), "custom output data\n");
        rbtdre_Verdict::Pass
    }

    static CASES: &[rbtdre_Case] = &[rbtdre_Case {
        name: "output-case",
        func: write_output,
    }];

    let tmp = rbtdth_make_scratch("caseoutput");
    let _ = rbtdre_run_cases(CASES, &RBTDTE_COLORS, false, &tmp).unwrap();

    let output = std::fs::read_to_string(tmp.join("output-case").join("output.txt")).unwrap();
    assert!(output.contains("custom output data"));

    // Trace also exists alongside the case output
    let trace = std::fs::read_to_string(tmp.join("output-case").join("trace.txt")).unwrap();
    assert!(trace.contains("PASSED"));

    let _ = std::fs::remove_dir_all(&tmp);
}

// ── Config-evolution console ─────────────────────────────────

fn rbtdte_git(args: &[&str], root: &Path) -> std::process::Output {
    std::process::Command::new("git")
        .args(args)
        .current_dir(root)
        .output()
        .expect("git invocation")
}

#[test]
fn rbtdte_config_set_field_replaces_value_preserving_other_lines() {
    let tmp = rbtdth_make_scratch("setfield");
    let file = tmp.join(crate::rbtdgc_consts::RBTDGC_RBRV_FILE);
    std::fs::write(&file, "KEEP_BEFORE=1\nRBRV_ANCHOR=old\nKEEP_AFTER=2\n").unwrap();

    rbtdre_config_set_field(&file, "RBRV_ANCHOR", "new").unwrap();

    let body = std::fs::read_to_string(&file).unwrap();
    assert!(body.contains("RBRV_ANCHOR=new"));
    assert!(body.contains("KEEP_BEFORE=1"));
    assert!(body.contains("KEEP_AFTER=2"));
    assert!(!body.contains("RBRV_ANCHOR=old"));
    let _ = std::fs::remove_dir_all(&tmp);
}

#[test]
fn rbtdte_config_zero_blanks_named_field_only() {
    let tmp = rbtdth_make_scratch("zerofield");
    let file = tmp.join("rbrd.env");
    std::fs::write(&file, "RBRD_DEPOT_MONIKER=canest3-000007\nRBRD_CLOUD_PREFIX=canc\n").unwrap();

    rbtdre_config_zero(&file, "RBRD_DEPOT_MONIKER").unwrap();

    let body = std::fs::read_to_string(&file).unwrap();
    assert!(body.contains("RBRD_DEPOT_MONIKER=\n"));
    // The sibling field is untouched — zeroing is field-scoped.
    assert!(body.contains("RBRD_CLOUD_PREFIX=canc"));
    let _ = std::fs::remove_dir_all(&tmp);
}

#[test]
fn rbtdte_config_zero_absent_field_fails_loud() {
    let tmp = rbtdth_make_scratch("zeroabsent");
    let file = tmp.join("rbrd.env");
    std::fs::write(&file, "RBRD_CLOUD_PREFIX=canc\n").unwrap();

    // The schema-drift catch: zeroing a field that is not present errs rather
    // than silently no-op'ing (which would mask a renamed or removed field).
    let err = rbtdre_config_zero(&file, "RBRD_RENAMED_AWAY").unwrap_err();
    assert!(err.contains("RBRD_RENAMED_AWAY"));
    assert!(err.contains("not found"));
    let _ = std::fs::remove_dir_all(&tmp);
}

#[test]
fn rbtdte_commit_nameplates_scopes_to_named_class_only() {
    let tmp = rbtdth_make_scratch("commit-scope");
    assert!(rbtdte_git(&["init", "-q"], &tmp).status.success());
    rbtdte_git(&["config", "user.email", "theurge@test"], &tmp);
    rbtdte_git(&["config", "user.name", "theurge test"], &tmp);

    // Baseline: a nameplate rbrn.env plus an unrelated tracked file, committed clean.
    let np_dir = tmp
        .join(crate::rbtdgc_consts::RBTDGC_MOORINGS_DIR)
        .join("testnp");
    std::fs::create_dir_all(&np_dir).unwrap();
    let rbrn = np_dir.join(crate::rbtdgc_consts::RBTDGC_RBRN_FILE);
    std::fs::write(&rbrn, "RBRN_SENTRY_HALLMARK=\n").unwrap();
    let surprise = tmp.join("surprise.txt");
    std::fs::write(&surprise, "baseline\n").unwrap();
    rbtdte_git(&["add", "-A"], &tmp);
    assert!(rbtdte_git(&["commit", "-q", "-m", "baseline"], &tmp).status.success());

    // Dirty BOTH the owned nameplate file and an unrelated file — the exact
    // wrap-sweeps-everything hazard the scoped verb exists to prevent.
    std::fs::write(&rbrn, "RBRN_SENTRY_HALLMARK=kabc123\n").unwrap();
    std::fs::write(&surprise, "SURPRISE EDIT — must not be swept\n").unwrap();

    rbtdre_commit_nameplates(&tmp, &["testnp"], "test: nameplate hallmark").unwrap();

    let status = rbtdte_git(&["status", "--porcelain"], &tmp);
    let out = String::from_utf8_lossy(&status.stdout);
    // The nameplate file is committed (no longer dirty)...
    assert!(
        !out.contains("rbrn.env"),
        "nameplate file must be committed; status: {:?}",
        out
    );
    // ...and the surprise edit survives uncommitted — never swept into the commit.
    assert!(
        out.contains("surprise.txt"),
        "surprise edit must survive uncommitted; status: {:?}",
        out
    );
    let _ = std::fs::remove_dir_all(&tmp);
}

// ── Tariff evaluation seam ─────────────────────────────────────
//
// The pure seam is the tariff feature's testable heart: given a declared tariff
// and an observed (elapsed, invocations), it must flag exactly the violated
// bounds and nothing else. No spawning, no timing — deliberate violation of each
// kind asserts its flag, and every unchecked bound stays silent.

#[test]
fn rbtdte_tariff_unchecked_never_flags() {
    // UNCHECKED (all bounds None) must report all-clear no matter how extreme
    // the observation — this is what "undeclared fixtures run exactly as before"
    // rests on.
    let r = rbtdre_evaluate_tariff(&rbtdre_Tariff::UNCHECKED, 0, 0);
    assert!(!r.too_fast && !r.too_slow && !r.count_drift);
    let r = rbtdre_evaluate_tariff(&rbtdre_Tariff::UNCHECKED, 99_999, 9_999);
    assert!(!r.too_fast && !r.too_slow && !r.count_drift);
}

#[test]
fn rbtdte_tariff_min_is_a_strict_floor() {
    let t = rbtdre_Tariff { min_secs: Some(10), max_secs: None, invocations: None };
    // Strictly below → too_fast (the vacuity catch).
    assert!(rbtdre_evaluate_tariff(&t, 9, 0).too_fast);
    // Exactly at, and above → clear (a boundary green is not vacuous).
    assert!(!rbtdre_evaluate_tariff(&t, 10, 0).too_fast);
    assert!(!rbtdre_evaluate_tariff(&t, 11, 0).too_fast);
    // The floor never trips the drift warnings.
    let r = rbtdre_evaluate_tariff(&t, 9, 0);
    assert!(!r.too_slow && !r.count_drift);
}

#[test]
fn rbtdte_tariff_max_is_a_strict_ceiling_warning() {
    let t = rbtdre_Tariff { min_secs: None, max_secs: Some(60), invocations: None };
    assert!(rbtdre_evaluate_tariff(&t, 61, 0).too_slow);
    assert!(!rbtdre_evaluate_tariff(&t, 60, 0).too_slow);
    assert!(!rbtdre_evaluate_tariff(&t, 59, 0).too_slow);
    // A too-slow observation is never also a failure.
    assert!(!rbtdre_evaluate_tariff(&t, 61, 0).too_fast);
}

#[test]
fn rbtdte_tariff_count_drift_is_exact_mismatch() {
    let t = rbtdre_Tariff { min_secs: None, max_secs: None, invocations: Some(23) };
    assert!(rbtdre_evaluate_tariff(&t, 0, 22).count_drift);
    assert!(rbtdre_evaluate_tariff(&t, 0, 24).count_drift);
    assert!(!rbtdre_evaluate_tariff(&t, 0, 23).count_drift);
}

#[test]
fn rbtdte_tariff_bounds_are_independent() {
    // All three declared: a clean observation flags nothing; a mixed violation
    // (too-fast AND count-drift) flags exactly those two, leaving too-slow off.
    let t = rbtdre_Tariff { min_secs: Some(5), max_secs: Some(50), invocations: Some(3) };
    let clean = rbtdre_evaluate_tariff(&t, 20, 3);
    assert!(!clean.too_fast && !clean.too_slow && !clean.count_drift);
    let mixed = rbtdre_evaluate_tariff(&t, 2, 4);
    assert!(mixed.too_fast && mixed.count_drift && !mixed.too_slow);
    // The report echoes the observation for the declared-vs-observed print.
    assert_eq!(mixed.elapsed_secs, 2);
    assert_eq!(mixed.invocations, 4);
}

// ── Colophon census wired into rbtdre_run_fixture ────────────────
//
// Mirrors the real Context::new -> rbtdrc_set_context -> rbtdre_run_fixture
// -> rbtdrc_take_context sequence main.rs drives, so the negative check
// (declared-but-unused fails a fully-green fixture), its skip suppression,
// and the single-case exemption (rbtdre_run_single_case never consults it)
// are proven against the real wiring, not a reimplementation of it. The case
// reaches ctx through rbtdrc_with_ctx — the same channel a real fixture's
// case uses.
//
// Arm order: rbtdrc_set_context derives the census from the MANIFEST, and
// these synthetic fixture names have no manifest entry — so set_context arms
// None, and each test overrides with its synthetic declared set AFTER
// set_context. rbtdrc_take_context disarms, leaving the worker thread clean.

const ZRBTDTE_CENSUS_COL_USED: &str = "zrbtdte-col-used";
const ZRBTDTE_CENSUS_COL_UNUSED: &str = "zrbtdte-col-unused";

fn zrbtdte_census_invoke_used(_dir: &Path) -> rbtdre_Verdict {
    crate::rbtdrc_crucible::rbtdrc_with_ctx(|ctx| {
        match crate::rbtdri_invocation::rbtdri_invoke_global(ctx, ZRBTDTE_CENSUS_COL_USED, &[], &[]) {
            Ok(r) if r.exit_code == 0 => rbtdre_Verdict::Pass,
            Ok(r) => rbtdre_Verdict::Fail(format!("exit {}", r.exit_code)),
            Err(e) => rbtdre_Verdict::Fail(e),
        }
    })
}

static ZRBTDTE_CENSUS_CASES: &[rbtdre_Case] = &[crate::case!(zrbtdte_census_invoke_used)];

static ZRBTDTE_CENSUS_FIXTURE: rbtdre_Fixture = rbtdre_Fixture {
    name: "zrbtdte-census-fixture",
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: ZRBTDTE_CENSUS_CASES,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};

/// Scratch project root with a tt/ script satisfying ZRBTDTE_CENSUS_COL_USED
/// via the global-tabtarget shape (`{colophon}.<frontispiece>.sh`).
fn zrbtdte_census_scratch(label: &str) -> std::path::PathBuf {
    let tmp = rbtdth_make_scratch(label);
    let tt = tmp.join("tt");
    std::fs::create_dir_all(&tt).unwrap();
    let script = tt.join(format!("{}.Foo.sh", ZRBTDTE_CENSUS_COL_USED));
    std::fs::write(&script, "#!/bin/bash\nexit 0\n").unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
    }
    tmp
}

#[test]
fn rbtdte_run_fixture_passes_when_declared_colophons_all_used() {
    let tmp = zrbtdte_census_scratch("census-fixture-pass");
    let burv_temp_root = tmp.join("burv-temp");
    let burv_output_root = tmp.join("burv-output");
    let ctx = crate::rbtdri_invocation::rbtdri_Context::new(
        &tmp, ZRBTDTE_CENSUS_FIXTURE.name, &burv_temp_root, &burv_output_root,
    );
    crate::rbtdrc_crucible::rbtdrc_set_context(ctx);
    crate::rbtdri_invocation::rbtdri_census_arm(Some(&[ZRBTDTE_CENSUS_COL_USED]), &[]);

    let result = rbtdre_run_fixture(&ZRBTDTE_CENSUS_FIXTURE, &RBTDTE_COLORS, &tmp, false).unwrap();

    let _ = crate::rbtdrc_crucible::rbtdrc_take_context();

    assert_eq!(result.failed, 0, "every declared colophon was invoked — must not fail");

    let _ = std::fs::remove_dir_all(&tmp);
}

#[test]
fn rbtdte_run_fixture_fails_on_declared_but_unused_colophon() {
    let tmp = zrbtdte_census_scratch("census-fixture-fail");
    let burv_temp_root = tmp.join("burv-temp");
    let burv_output_root = tmp.join("burv-output");
    let ctx = crate::rbtdri_invocation::rbtdri_Context::new(
        &tmp, ZRBTDTE_CENSUS_FIXTURE.name, &burv_temp_root, &burv_output_root,
    );
    crate::rbtdrc_crucible::rbtdrc_set_context(ctx);
    // Declares a SECOND colophon the case never invokes.
    crate::rbtdri_invocation::rbtdri_census_arm(Some(&[
        ZRBTDTE_CENSUS_COL_USED,
        ZRBTDTE_CENSUS_COL_UNUSED,
    ]), &[]);

    let result = rbtdre_run_fixture(&ZRBTDTE_CENSUS_FIXTURE, &RBTDTE_COLORS, &tmp, false).unwrap();

    let _ = crate::rbtdrc_crucible::rbtdrc_take_context();

    assert!(result.failed > 0, "a declared-but-never-invoked colophon must fail the fixture");

    let _ = std::fs::remove_dir_all(&tmp);
}

#[test]
fn rbtdte_run_single_case_ignores_unused_declared_colophons() {
    // Single-case runs enforce positive only: rbtdre_run_single_case never
    // calls rbtdre_check_census, so the same armed declared-but-unused
    // colophon that fails a full fixture run above must NOT fail a
    // single-case run of the identical case.
    let tmp = zrbtdte_census_scratch("census-single-case-exempt");
    let burv_temp_root = tmp.join("burv-temp");
    let burv_output_root = tmp.join("burv-output");
    let ctx = crate::rbtdri_invocation::rbtdri_Context::new(
        &tmp, ZRBTDTE_CENSUS_FIXTURE.name, &burv_temp_root, &burv_output_root,
    );
    crate::rbtdrc_crucible::rbtdrc_set_context(ctx);
    crate::rbtdri_invocation::rbtdri_census_arm(Some(&[
        ZRBTDTE_CENSUS_COL_USED,
        ZRBTDTE_CENSUS_COL_UNUSED,
    ]), &[]);

    let result = rbtdre_run_single_case(&ZRBTDTE_CENSUS_CASES[0], &RBTDTE_COLORS, &tmp).unwrap();

    let _ = crate::rbtdrc_crucible::rbtdrc_take_context();

    assert_eq!(result.failed, 0, "single-case run must not enforce the negative census direction");

    let _ = std::fs::remove_dir_all(&tmp);
}

#[test]
fn rbtdte_run_fixture_permitted_colophon_invocation_not_refused() {
    // Positive-only tier, proven through the real set_context/run_fixture
    // wiring: the required set is deliberately empty (so an unmediated
    // invoke would refuse, exactly as it does when a fixture declares zero
    // required colophons), but the invoked colophon IS permitted — so the
    // invoke must succeed and the fixture must pass.
    let tmp = zrbtdte_census_scratch("census-fixture-permitted-invoked");
    let burv_temp_root = tmp.join("burv-temp");
    let burv_output_root = tmp.join("burv-output");
    let ctx = crate::rbtdri_invocation::rbtdri_Context::new(
        &tmp, ZRBTDTE_CENSUS_FIXTURE.name, &burv_temp_root, &burv_output_root,
    );
    crate::rbtdrc_crucible::rbtdrc_set_context(ctx);
    crate::rbtdri_invocation::rbtdri_census_arm(Some(&[]), &[ZRBTDTE_CENSUS_COL_USED]);

    let result = rbtdre_run_fixture(&ZRBTDTE_CENSUS_FIXTURE, &RBTDTE_COLORS, &tmp, false).unwrap();

    let _ = crate::rbtdrc_crucible::rbtdrc_take_context();

    assert_eq!(result.passed, 1, "a permitted colophon's invoke must not be refused");
    assert_eq!(result.failed, 0, "a permitted colophon's invoke must not be refused");

    let _ = std::fs::remove_dir_all(&tmp);
}

static ZRBTDTE_CENSUS_NOINVOKE_CASES: &[rbtdre_Case] = &[crate::case!(rbtdte_pass)];

static ZRBTDTE_CENSUS_NOINVOKE_FIXTURE: rbtdre_Fixture = rbtdre_Fixture {
    name: "zrbtdte-census-noinvoke-fixture",
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: ZRBTDTE_CENSUS_NOINVOKE_CASES,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};

#[test]
fn rbtdte_run_fixture_permitted_colophon_unused_does_not_fail() {
    // Negative check ignores the permitted tier entirely: a permitted
    // colophon declared but never invoked must not fail an otherwise-green
    // fixture, unlike the required-tier sibling above
    // (rbtdte_run_fixture_fails_on_declared_but_unused_colophon) where the
    // identical non-invocation DOES fail the fixture.
    let tmp = rbtdth_make_scratch("census-fixture-permitted-unused");
    let burv_temp_root = tmp.join("burv-temp");
    let burv_output_root = tmp.join("burv-output");
    let ctx = crate::rbtdri_invocation::rbtdri_Context::new(
        &tmp, ZRBTDTE_CENSUS_NOINVOKE_FIXTURE.name, &burv_temp_root, &burv_output_root,
    );
    crate::rbtdrc_crucible::rbtdrc_set_context(ctx);
    crate::rbtdri_invocation::rbtdri_census_arm(Some(&[]), &[ZRBTDTE_CENSUS_COL_UNUSED]);

    let result =
        rbtdre_run_fixture(&ZRBTDTE_CENSUS_NOINVOKE_FIXTURE, &RBTDTE_COLORS, &tmp, false).unwrap();

    let _ = crate::rbtdrc_crucible::rbtdrc_take_context();

    assert_eq!(result.passed, 1);
    assert_eq!(result.failed, 0, "an unused permitted colophon must not fail the fixture");

    let _ = std::fs::remove_dir_all(&tmp);
}

fn zrbtdte_census_skip(_dir: &Path) -> rbtdre_Verdict {
    rbtdre_Verdict::Skip("credential unavailable".to_string())
}

static ZRBTDTE_CENSUS_SKIP_CASES: &[rbtdre_Case] = &[crate::case!(zrbtdte_census_skip)];

static ZRBTDTE_CENSUS_SKIP_FIXTURE: rbtdre_Fixture = rbtdre_Fixture {
    name: "zrbtdte-census-skip-fixture",
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: ZRBTDTE_CENSUS_SKIP_CASES,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};

#[test]
fn rbtdte_run_fixture_skip_suppresses_negative_census() {
    // Suite-passenger protection: a self-skipping fixture's run is not
    // exhaustive, so a declared colophon its skipped cases never invoked must
    // not fail it — the same declared-but-unused set that fails a fully-run
    // fixture above is suppressed here by the skip.
    let tmp = rbtdth_make_scratch("census-skip-suppress");
    let burv_temp_root = tmp.join("burv-temp");
    let burv_output_root = tmp.join("burv-output");
    let ctx = crate::rbtdri_invocation::rbtdri_Context::new(
        &tmp, ZRBTDTE_CENSUS_SKIP_FIXTURE.name, &burv_temp_root, &burv_output_root,
    );
    crate::rbtdrc_crucible::rbtdrc_set_context(ctx);
    crate::rbtdri_invocation::rbtdri_census_arm(Some(&[ZRBTDTE_CENSUS_COL_UNUSED]), &[]);

    let result =
        rbtdre_run_fixture(&ZRBTDTE_CENSUS_SKIP_FIXTURE, &RBTDTE_COLORS, &tmp, false).unwrap();

    let _ = crate::rbtdrc_crucible::rbtdrc_take_context();

    assert_eq!(result.skipped, 1);
    assert_eq!(result.failed, 0, "a skipped run must suppress the negative census check");

    let _ = std::fs::remove_dir_all(&tmp);
}
