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
// RBTDRJ — touchstone: theurge certifying its own operator surface.
//
// A green, credless reveille member whose cases spawn child rbtd runs through
// the real tabtarget chain (tabtarget → launcher → workbench → rbte_engine →
// binary) against the deliberately-failing calibrant fixtures, asserting the
// child's exit code, its diagnostic shape on the operator-visible stream, and
// sentinel/trace files. The watcher passes; the watched calibrant fixtures
// stay out of every green suite. In the assay asterism: the calibrant needles
// are streaked on this touchstone and compared against known verdicts.
//
// Assertion surfaces: BUK dispatch folds the coordinator's stderr into stdout
// (2>&1 through its logging loop), so a child rbtd's diagnostics — which the
// RBTDRG discipline routes entirely to stderr — arrive on the PARENT'S
// captured stdout; captured stderr carries only pre-coordinator chain
// failures. Cases therefore assert on captured stdout, except the one
// stream-placement case, which runs its child under BURD_NO_LOG (streams
// unmerged, station/logging sublayer skipped) to prove diagnostics land on
// stderr rather than stdout.
//
// Child hygiene: every logged child carries a BURV_LOG_DIR override into the
// case dir, so a deliberately-failing child never truncates the station's
// shared last-log mid-suite nor seeds the logs-buk hist census the tariff
// dowse reads; TERM=dumb keeps the whole child chain colorless so text
// assertions are exact. Self-hosting note: a child run re-enters
// zrbte_build_binary (write-on-change codegen + cargo) while the parent
// binary executes — on the clean, freshly-built tree every run starts from,
// that is a fingerprint no-op, which is what keeps a Windows relink over the
// running binary out of reach.

use std::path::{Path, PathBuf};

use crate::case;
use crate::rbtdgc_consts::{
    RBTDGC_THEURGE_CASE,
    RBTDGC_THEURGE_FIXTURE,
    RBTDGC_THEURGE_NIHIL,
    RBTDGC_THEURGE_SUITE,
};
use crate::rbtdra_almanac::RBTDRA_SUITE_NAME_CALIBRANT;
use crate::rbtdrc_crucible::rbtdrc_with_ctx;
use crate::rbtdre_engine::{
    RBTDRE_FLAG_KEEP_GOING,
    RBTDRE_TRACE_FILE,
    RBTDRE_WORD_FAILED,
    RBTDRE_WORD_PASSED,
    RBTDRE_WORD_SKIPPED,
    rbtdre_Case,
    rbtdre_Disposition,
    rbtdre_Fixture,
    rbtdre_Tariff,
    rbtdre_Verdict,
};
use crate::rbtdri_invocation::{
    rbtdri_InvokeResult,
    rbtdri_invoke_global,
    rbtdri_invoke_imprint_env,
};
use crate::rbtdrl_calibrant::{
    RBTDRL_CASES_COVERAGE_UNDECLARED,
    RBTDRL_CASES_COVERAGE_UNUSED,
    RBTDRL_CASES_FAIL_FAST,
    RBTDRL_CASES_PROGRESSING,
    RBTDRL_CASES_SENTINEL,
    RBTDRL_CASES_VERDICTS,
    RBTDRL_OUTPUT_FILE,
    RBTDRL_SENTINEL_FILE,
};
use crate::rbtdrm_manifest::{
    RBTDRM_FIXTURE_CALIBRANT_COVERAGE_ALIGNED,
    RBTDRM_FIXTURE_CALIBRANT_COVERAGE_UNDECLARED,
    RBTDRM_FIXTURE_CALIBRANT_COVERAGE_UNUSED,
    RBTDRM_FIXTURE_CALIBRANT_FAIL_FAST,
    RBTDRM_FIXTURE_CALIBRANT_PROGRESSING,
    RBTDRM_FIXTURE_CALIBRANT_VERDICTS,
    RBTDRM_FIXTURE_TOUCHSTONE,
};
use crate::rbtdrx_platform::rbtdrx_native_to_posix;

/// Child dispatch's trace-tree subdir under its BURD_TEMP_DIR — pinned to the
/// literal in rbtdb_allocate_roots (main.rs). A layout change there fails
/// these assertions loudly rather than letting them pass vacuously.
const ZRBTDRJ_CHILD_TRACE_SUBDIR: &str = "rbtd";

// ── Child runner ─────────────────────────────────────────────

/// One observed child run: the captured streams and exit code, plus the two
/// roots the parent handed the child — the BURV temp root (under which the
/// child's dispatch minted its temp-<stamp>/ generation, holding the child
/// rbtd trace tree) and the BURV_LOG_DIR override (None for a BURD_NO_LOG
/// child, which writes no logs at all).
struct zrbtdrj_Child {
    exit_code: i32,
    stdout: String,
    stderr: String,
    burv_temp: PathBuf,
    log_dir: Option<PathBuf>,
}

/// Spawn one child theurge run through the real tabtarget chain and capture
/// its observable surface. `imprint` Some resolves the imprinted form (the
/// rbw-ts suite tabtargets); None resolves the global form (rbw-tf / rbw-tc).
fn zrbtdrj_child(
    dir: &Path,
    label: &str,
    colophon: &str,
    imprint: Option<&str>,
    args: &[&str],
    no_log: bool,
) -> Result<zrbtdrj_Child, rbtdre_Verdict> {
    let mut env: Vec<(String, String)> = vec![("TERM".to_string(), "dumb".to_string())];
    let log_dir = if no_log {
        env.push(("BURD_NO_LOG".to_string(), "1".to_string()));
        None
    } else {
        let d = dir.join(format!("{}-logs", label));
        std::fs::create_dir_all(&d).map_err(|e| {
            rbtdre_Verdict::Fail(format!("{}: create child log dir: {}", label, e))
        })?;
        env.push(("BURV_LOG_DIR".to_string(), rbtdrx_native_to_posix(&d)));
        Some(d)
    };
    let env_refs: Vec<(&str, &str)> =
        env.iter().map(|(k, v)| (k.as_str(), v.as_str())).collect();

    let mut captured: Option<(rbtdri_InvokeResult, PathBuf)> = None;
    let invoke_verdict = rbtdrc_with_ctx(|ctx| {
        let invoked = match imprint {
            Some(imp) => rbtdri_invoke_imprint_env(ctx, colophon, imp, args, &env_refs),
            None => rbtdri_invoke_global(ctx, colophon, args, &env_refs),
        };
        match invoked {
            Ok(result) => {
                let invoke_dir = match result.burv_output.file_name() {
                    Some(n) => n.to_os_string(),
                    None => {
                        return rbtdre_Verdict::Fail(format!(
                            "{}: burv_output has no dir name: {}",
                            label,
                            result.burv_output.display()
                        ))
                    }
                };
                let burv_temp = ctx.burv_temp_root.join(invoke_dir);
                captured = Some((result, burv_temp));
                rbtdre_Verdict::Pass
            }
            Err(e) => rbtdre_Verdict::Fail(format!("{}: {}", label, e)),
        }
    });
    if !matches!(invoke_verdict, rbtdre_Verdict::Pass) {
        return Err(invoke_verdict);
    }
    let (result, burv_temp) = captured.expect("captured set on Pass verdict");

    let _ = std::fs::write(dir.join(format!("{}-stdout.txt", label)), &result.stdout);
    let _ = std::fs::write(dir.join(format!("{}-stderr.txt", label)), &result.stderr);

    Ok(zrbtdrj_Child {
        exit_code: result.exit_code,
        stdout: result.stdout,
        stderr: result.stderr,
        burv_temp,
        log_dir,
    })
}

// ── Assertion helpers ────────────────────────────────────────

fn zrbtdrj_expect(cond: bool, detail: String) -> Result<(), rbtdre_Verdict> {
    if cond {
        Ok(())
    } else {
        Err(rbtdre_Verdict::Fail(detail))
    }
}

/// Tail excerpt for failure messages — the whole child output would drown the
/// verdict; the tail usually carries the summary and the miss.
fn zrbtdrj_tail(s: &str) -> String {
    const KEEP: usize = 800;
    if s.len() <= KEEP {
        return s.to_string();
    }
    let mut start = s.len() - KEEP;
    while !s.is_char_boundary(start) {
        start += 1;
    }
    format!("…{}", &s[start..])
}

fn zrbtdrj_expect_contains(hay: &str, needle: &str, what: &str) -> Result<(), rbtdre_Verdict> {
    zrbtdrj_expect(
        hay.contains(needle),
        format!(
            "{}: expected to contain '{}'\n--- observed tail ---\n{}",
            what,
            needle,
            zrbtdrj_tail(hay)
        ),
    )
}

fn zrbtdrj_expect_lacks(hay: &str, needle: &str, what: &str) -> Result<(), rbtdre_Verdict> {
    zrbtdrj_expect(
        !hay.contains(needle),
        format!(
            "{}: expected NOT to contain '{}'\n--- observed tail ---\n{}",
            what,
            needle,
            zrbtdrj_tail(hay)
        ),
    )
}

fn zrbtdrj_expect_nonzero(child: &zrbtdrj_Child, what: &str) -> Result<(), rbtdre_Verdict> {
    zrbtdrj_expect(
        child.exit_code != 0,
        format!(
            "{}: expected nonzero child exit, got 0\n--- stdout tail ---\n{}",
            what,
            zrbtdrj_tail(&child.stdout)
        ),
    )
}

fn zrbtdrj_expect_zero(child: &zrbtdrj_Child, what: &str) -> Result<(), rbtdre_Verdict> {
    zrbtdrj_expect(
        child.exit_code == 0,
        format!(
            "{}: child exited {}\n--- stdout tail ---\n{}\n--- stderr tail ---\n{}",
            what,
            child.exit_code,
            zrbtdrj_tail(&child.stdout),
            zrbtdrj_tail(&child.stderr)
        ),
    )
}

/// Resolve the single temp-<stamp>/ generation the child's dispatch minted
/// under the BURV temp root this fixture handed it. Exactly one is expected —
/// one dispatch per invoke; zero means the chain never reached dispatch.
fn zrbtdrj_child_temp_gen(
    child: &zrbtdrj_Child,
    label: &str,
) -> Result<PathBuf, rbtdre_Verdict> {
    let entries = std::fs::read_dir(&child.burv_temp).map_err(|e| {
        rbtdre_Verdict::Fail(format!(
            "{}: read child temp root {}: {}",
            label,
            child.burv_temp.display(),
            e
        ))
    })?;
    let gens: Vec<PathBuf> = entries
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.is_dir()
                && p.file_name()
                    .and_then(|n| n.to_str())
                    .is_some_and(|n| n.starts_with("temp-"))
        })
        .collect();
    match gens.len() {
        1 => Ok(gens.into_iter().next().unwrap()),
        n => Err(rbtdre_Verdict::Fail(format!(
            "{}: expected exactly one temp-* generation under {}, found {}",
            label,
            child.burv_temp.display(),
            n
        ))),
    }
}

/// One case's directory in the child rbtd's trace tree:
/// temp-<stamp>/rbtd/<case fn name>/.
fn zrbtdrj_child_case_dir(
    child: &zrbtdrj_Child,
    label: &str,
    case_name: &str,
) -> Result<PathBuf, rbtdre_Verdict> {
    Ok(zrbtdrj_child_temp_gen(child, label)?
        .join(ZRBTDRJ_CHILD_TRACE_SUBDIR)
        .join(case_name))
}

fn zrbtdrj_read(path: &Path, what: &str) -> Result<String, rbtdre_Verdict> {
    std::fs::read_to_string(path)
        .map_err(|e| rbtdre_Verdict::Fail(format!("{}: read {}: {}", what, path.display(), e)))
}

/// Fold a Result-style case body into the engine's Verdict shape.
fn zrbtdrj_run(body: impl FnOnce() -> Result<(), rbtdre_Verdict>) -> rbtdre_Verdict {
    match body() {
        Ok(()) => rbtdre_Verdict::Pass,
        Err(v) => v,
    }
}

// ── verdict-propagation ─────────────────────────────────────
//
// Calibrant-verdicts case order is pinned by the RBTDRL const asserts:
// [0] pass, [1] fail, [2] skip, [3] pass_with_output. Names are taken from
// the case arrays (stringify!'d fn names), so a calibrant rename tracks here
// automatically.

/// Single-case child running the deterministic pass case: exit 0, PASSED on
/// the operator stream, trace file recording the verdict.
fn rbtdrj_verdict_pass_exits_zero(dir: &Path) -> rbtdre_Verdict {
    zrbtdrj_run(|| {
        let label = "single-pass";
        let pass_case = RBTDRL_CASES_VERDICTS[0].name;
        let child = zrbtdrj_child(
            dir,
            label,
            RBTDGC_THEURGE_CASE,
            None,
            &[RBTDRM_FIXTURE_CALIBRANT_VERDICTS, pass_case],
            false,
        )?;
        zrbtdrj_expect_zero(&child, label)?;
        zrbtdrj_expect_contains(&child.stdout, RBTDRE_WORD_PASSED, "single-pass stdout")?;
        zrbtdrj_expect_contains(&child.stdout, pass_case, "single-pass stdout")?;
        let trace = zrbtdrj_child_case_dir(&child, label, pass_case)?.join(RBTDRE_TRACE_FILE);
        let content = zrbtdrj_read(&trace, "single-pass trace")?;
        zrbtdrj_expect_contains(&content, RBTDRE_WORD_PASSED, "single-pass trace content")
    })
}

/// Single-case child running the deterministic skip case: a skip is not a
/// failure, so the child exits 0 with SKIPPED on the operator stream.
fn rbtdrj_verdict_skip_exits_zero(dir: &Path) -> rbtdre_Verdict {
    zrbtdrj_run(|| {
        let label = "single-skip";
        let skip_case = RBTDRL_CASES_VERDICTS[2].name;
        let child = zrbtdrj_child(
            dir,
            label,
            RBTDGC_THEURGE_CASE,
            None,
            &[RBTDRM_FIXTURE_CALIBRANT_VERDICTS, skip_case],
            false,
        )?;
        zrbtdrj_expect_zero(&child, label)?;
        zrbtdrj_expect_contains(&child.stdout, RBTDRE_WORD_SKIPPED, "single-skip stdout")?;
        let trace = zrbtdrj_child_case_dir(&child, label, skip_case)?.join(RBTDRE_TRACE_FILE);
        let content = zrbtdrj_read(&trace, "single-skip trace")?;
        zrbtdrj_expect_contains(&content, RBTDRE_WORD_SKIPPED, "single-skip trace content")
    })
}

/// Full-fixture child (default fail-fast): the deterministic fail yields a
/// nonzero exit carrying the fail detail, and the cases after the failure
/// never run — their trace dirs are never created.
fn rbtdrj_verdict_fail_exits_nonzero(dir: &Path) -> rbtdre_Verdict {
    zrbtdrj_run(|| {
        let label = "verdicts-default";
        let pass_case = RBTDRL_CASES_VERDICTS[0].name;
        let fail_case = RBTDRL_CASES_VERDICTS[1].name;
        let skip_case = RBTDRL_CASES_VERDICTS[2].name;
        let child = zrbtdrj_child(
            dir,
            label,
            RBTDGC_THEURGE_FIXTURE,
            None,
            &[RBTDRM_FIXTURE_CALIBRANT_VERDICTS],
            false,
        )?;
        zrbtdrj_expect_nonzero(&child, label)?;
        zrbtdrj_expect_contains(&child.stdout, RBTDRE_WORD_PASSED, "verdicts-default stdout")?;
        zrbtdrj_expect_contains(&child.stdout, pass_case, "verdicts-default stdout")?;
        zrbtdrj_expect_contains(&child.stdout, RBTDRE_WORD_FAILED, "verdicts-default stdout")?;
        zrbtdrj_expect_contains(&child.stdout, fail_case, "verdicts-default stdout")?;
        zrbtdrj_expect_contains(
            &child.stdout,
            "calibrant deterministic fail verdict",
            "verdicts-default stdout",
        )?;
        let skip_dir = zrbtdrj_child_case_dir(&child, label, skip_case)?;
        zrbtdrj_expect(
            !skip_dir.exists(),
            format!(
                "verdicts-default: case after the failure ran under default fail-fast — {} exists",
                skip_dir.display()
            ),
        )
    })
}

/// Full-fixture child under --keep-going: all four verdict cases run — the
/// skip surfaces, the case-written output file lands, every case has a trace
/// file, and the summary counts all four.
fn rbtdrj_verdict_keep_going_runs_all(dir: &Path) -> rbtdre_Verdict {
    zrbtdrj_run(|| {
        let label = "verdicts-keep-going";
        let output_case = RBTDRL_CASES_VERDICTS[3].name;
        let child = zrbtdrj_child(
            dir,
            label,
            RBTDGC_THEURGE_FIXTURE,
            None,
            &[RBTDRM_FIXTURE_CALIBRANT_VERDICTS, RBTDRE_FLAG_KEEP_GOING],
            false,
        )?;
        zrbtdrj_expect_nonzero(&child, label)?;
        zrbtdrj_expect_contains(&child.stdout, RBTDRE_WORD_SKIPPED, "verdicts-keep-going stdout")?;
        zrbtdrj_expect_contains(
            &child.stdout,
            "2 passed, 1 failed, 1 skipped (4 total)",
            "verdicts-keep-going stdout",
        )?;
        for case in RBTDRL_CASES_VERDICTS {
            let trace =
                zrbtdrj_child_case_dir(&child, label, case.name)?.join(RBTDRE_TRACE_FILE);
            zrbtdrj_expect(
                trace.is_file(),
                format!("verdicts-keep-going: missing trace {}", trace.display()),
            )?;
        }
        let output =
            zrbtdrj_child_case_dir(&child, label, output_case)?.join(RBTDRL_OUTPUT_FILE);
        let content = zrbtdrj_read(&output, "verdicts-keep-going case output")?;
        zrbtdrj_expect_contains(
            &content,
            "calibrant case-written output",
            "verdicts-keep-going case output",
        )
    })
}

// ── fixture-fail-fast ───────────────────────────────────────

/// Default run of the fail-fast calibrant: the trailing case after the
/// deterministic fail never runs — its sentinel is absent.
fn rbtdrj_failfast_default_halts_trailing(dir: &Path) -> rbtdre_Verdict {
    zrbtdrj_run(|| {
        let label = "failfast-default";
        let trailing = RBTDRL_CASES_FAIL_FAST.last().expect("fail-fast has cases").name;
        let child = zrbtdrj_child(
            dir,
            label,
            RBTDGC_THEURGE_FIXTURE,
            None,
            &[RBTDRM_FIXTURE_CALIBRANT_FAIL_FAST],
            false,
        )?;
        zrbtdrj_expect_nonzero(&child, label)?;
        let sentinel =
            zrbtdrj_child_case_dir(&child, label, trailing)?.join(RBTDRL_SENTINEL_FILE);
        zrbtdrj_expect(
            !sentinel.exists(),
            format!(
                "failfast-default: trailing case ran under fail-fast — sentinel {} exists",
                sentinel.display()
            ),
        )
    })
}

/// Keep-going run of the fail-fast calibrant: the trailing case DOES run —
/// its sentinel is present — while the fail still yields a nonzero exit.
fn rbtdrj_failfast_keep_going_reaches_trailing(dir: &Path) -> rbtdre_Verdict {
    zrbtdrj_run(|| {
        let label = "failfast-keep-going";
        let trailing = RBTDRL_CASES_FAIL_FAST.last().expect("fail-fast has cases").name;
        let child = zrbtdrj_child(
            dir,
            label,
            RBTDGC_THEURGE_FIXTURE,
            None,
            &[RBTDRM_FIXTURE_CALIBRANT_FAIL_FAST, RBTDRE_FLAG_KEEP_GOING],
            false,
        )?;
        zrbtdrj_expect_nonzero(&child, label)?;
        let sentinel =
            zrbtdrj_child_case_dir(&child, label, trailing)?.join(RBTDRL_SENTINEL_FILE);
        zrbtdrj_expect(
            sentinel.is_file(),
            format!(
                "failfast-keep-going: trailing case did not run — sentinel {} absent",
                sentinel.display()
            ),
        )
    })
}

// ── disposition-policy ──────────────────────────────────────

/// StateProgressing fixture under the default: fail-fast is forced, both
/// probe cases run (Ok passes, Err fails), nonzero exit.
fn rbtdrj_progressing_default_runs_fail_fast(dir: &Path) -> rbtdre_Verdict {
    zrbtdrj_run(|| {
        let label = "progressing-default";
        let ok_case = RBTDRL_CASES_PROGRESSING[0].name;
        let err_case = RBTDRL_CASES_PROGRESSING[1].name;
        let child = zrbtdrj_child(
            dir,
            label,
            RBTDGC_THEURGE_FIXTURE,
            None,
            &[RBTDRM_FIXTURE_CALIBRANT_PROGRESSING],
            false,
        )?;
        zrbtdrj_expect_nonzero(&child, label)?;
        zrbtdrj_expect_contains(&child.stdout, RBTDRE_WORD_PASSED, "progressing-default stdout")?;
        zrbtdrj_expect_contains(&child.stdout, ok_case, "progressing-default stdout")?;
        zrbtdrj_expect_contains(&child.stdout, RBTDRE_WORD_FAILED, "progressing-default stdout")?;
        zrbtdrj_expect_contains(&child.stdout, err_case, "progressing-default stdout")
    })
}

/// StateProgressing + --keep-going is refused with the policy diagnostic
/// BEFORE any case work: nonzero exit, the refusal text on the operator
/// stream, and neither case's trace dir ever created.
fn rbtdrj_progressing_keep_going_refused(dir: &Path) -> rbtdre_Verdict {
    zrbtdrj_run(|| {
        let label = "progressing-refused";
        let child = zrbtdrj_child(
            dir,
            label,
            RBTDGC_THEURGE_FIXTURE,
            None,
            &[RBTDRM_FIXTURE_CALIBRANT_PROGRESSING, RBTDRE_FLAG_KEEP_GOING],
            false,
        )?;
        zrbtdrj_expect_nonzero(&child, label)?;
        zrbtdrj_expect_contains(
            &child.stdout,
            "keep-going mode refused for StateProgressing",
            "progressing-refused stdout",
        )?;
        for case in RBTDRL_CASES_PROGRESSING {
            let case_dir = zrbtdrj_child_case_dir(&child, label, case.name)?;
            zrbtdrj_expect(
                !case_dir.exists(),
                format!(
                    "progressing-refused: case ran despite policy refusal — {} exists",
                    case_dir.display()
                ),
            )?;
        }
        Ok(())
    })
}

// ── probe-diagnostics ───────────────────────────────────────

/// The unmet-probe diagnostic carries the precondition name and the
/// remediation line, in rbtdrb_assert's exact format. The probe label is
/// pinned to rbtdrl_progressing_probe_err's rbtdrb_Probe literal.
fn rbtdrj_probe_diagnostic_shape(dir: &Path) -> rbtdre_Verdict {
    zrbtdrj_run(|| {
        let label = "probe-shape";
        let child = zrbtdrj_child(
            dir,
            label,
            RBTDGC_THEURGE_FIXTURE,
            None,
            &[RBTDRM_FIXTURE_CALIBRANT_PROGRESSING],
            false,
        )?;
        zrbtdrj_expect_nonzero(&child, label)?;
        zrbtdrj_expect_contains(
            &child.stdout,
            "precondition 'calibrant deterministic err' not met:",
            "probe-shape stdout",
        )?;
        zrbtdrj_expect_contains(&child.stdout, "remediation:", "probe-shape stdout")
    })
}

// ── suite-abort ─────────────────────────────────────────────

/// The registered calibrant suite proves suite-level abort: its failing
/// fixture halts the run, so the sentinel fixture ordered after it never
/// runs — one fixture reported, the sentinel's trace dir absent.
fn rbtdrj_suite_abort_halts_sentinel(dir: &Path) -> rbtdre_Verdict {
    zrbtdrj_run(|| {
        let label = "suite-abort";
        let fail_case = RBTDRL_CASES_FAIL_FAST[1].name;
        let sentinel_case = RBTDRL_CASES_SENTINEL[0].name;
        let child = zrbtdrj_child(
            dir,
            label,
            RBTDGC_THEURGE_SUITE,
            Some(RBTDRA_SUITE_NAME_CALIBRANT),
            &[],
            false,
        )?;
        zrbtdrj_expect_nonzero(&child, label)?;
        zrbtdrj_expect_contains(&child.stdout, RBTDRE_WORD_FAILED, "suite-abort stdout")?;
        zrbtdrj_expect_contains(&child.stdout, fail_case, "suite-abort stdout")?;
        zrbtdrj_expect_contains(
            &child.stdout,
            &format!("Suite '{}': 1 fixture(s) run", RBTDRA_SUITE_NAME_CALIBRANT),
            "suite-abort stdout",
        )?;
        let sentinel_dir = zrbtdrj_child_case_dir(&child, label, sentinel_case)?;
        zrbtdrj_expect(
            !sentinel_dir.exists(),
            format!(
                "suite-abort: sentinel fixture ran after the aborting failure — {} exists",
                sentinel_dir.display()
            ),
        )
    })
}

// ── cli-surface ─────────────────────────────────────────────

/// An unknown fixture name errors clearly, naming the fixture.
fn rbtdrj_cli_unknown_fixture_errors(dir: &Path) -> rbtdre_Verdict {
    zrbtdrj_run(|| {
        let label = "cli-unknown";
        let child = zrbtdrj_child(
            dir,
            label,
            RBTDGC_THEURGE_FIXTURE,
            None,
            &["touchstone-nonesuch"],
            false,
        )?;
        zrbtdrj_expect_nonzero(&child, label)?;
        zrbtdrj_expect_contains(&child.stdout, "touchstone-nonesuch", "cli-unknown stdout")?;
        zrbtdrj_expect_contains(&child.stdout, "has no registered Fixture", "cli-unknown stdout")
    })
}

/// A fixture run with no folio dies at the bash usage gate.
fn rbtdrj_cli_missing_fixture_usage(dir: &Path) -> rbtdre_Verdict {
    zrbtdrj_run(|| {
        let label = "cli-no-folio";
        let child = zrbtdrj_child(dir, label, RBTDGC_THEURGE_FIXTURE, None, &[], false)?;
        zrbtdrj_expect_nonzero(&child, label)?;
        zrbtdrj_expect_contains(&child.stdout, "No fixture", "cli-no-folio stdout")
    })
}

/// The single-case runner with a fixture but no case lists that fixture's
/// cases and its declared tariff, exiting 0.
fn rbtdrj_cli_case_listing(dir: &Path) -> rbtdre_Verdict {
    zrbtdrj_run(|| {
        let label = "cli-case-list";
        let child = zrbtdrj_child(
            dir,
            label,
            RBTDGC_THEURGE_CASE,
            None,
            &[RBTDRM_FIXTURE_CALIBRANT_VERDICTS],
            false,
        )?;
        zrbtdrj_expect_zero(&child, label)?;
        zrbtdrj_expect_contains(&child.stdout, "declared tariff", "cli-case-list stdout")?;
        for case in RBTDRL_CASES_VERDICTS {
            zrbtdrj_expect_contains(&child.stdout, case.name, "cli-case-list stdout")?;
        }
        Ok(())
    })
}

/// The single-case runner with no arguments yields usage plus the fixture
/// listing, exiting nonzero.
fn rbtdrj_cli_single_usage_lists_fixtures(dir: &Path) -> rbtdre_Verdict {
    zrbtdrj_run(|| {
        let label = "cli-single-usage";
        let child = zrbtdrj_child(dir, label, RBTDGC_THEURGE_CASE, None, &[], false)?;
        zrbtdrj_expect_nonzero(&child, label)?;
        zrbtdrj_expect_contains(&child.stdout, "usage: rbtd single", "cli-single-usage stdout")?;
        zrbtdrj_expect_contains(&child.stdout, "available fixtures:", "cli-single-usage stdout")
    })
}

// ── coverage ─────────────────────────────────────────────────
//
// Black-box proof that the RBTDRI colophon census enforcement (the
// calibrant-coverage-* fixtures, rbtdrm_manifest) surfaces both directions
// from outside a child run: exit code and diagnostic text naming the
// offending colophon. The fourth case exercises the engine's documented
// single-case exemption (rbtdre_run_single_case never calls
// rbtdre_check_census) directly through the real rbw-tc chokepoint.

/// Declared and invoked: both census directions are satisfied — zero exit,
/// and the per-colophon usage report names the colophon as used.
fn rbtdrj_coverage_aligned_exits_zero(dir: &Path) -> rbtdre_Verdict {
    zrbtdrj_run(|| {
        let label = "coverage-aligned";
        let child = zrbtdrj_child(
            dir,
            label,
            RBTDGC_THEURGE_FIXTURE,
            None,
            &[RBTDRM_FIXTURE_CALIBRANT_COVERAGE_ALIGNED],
            false,
        )?;
        zrbtdrj_expect_zero(&child, label)?;
        zrbtdrj_expect_contains(&child.stdout, RBTDRE_WORD_PASSED, "coverage-aligned stdout")?;
        zrbtdrj_expect_contains(
            &child.stdout,
            &format!("colophon '{}' used", RBTDGC_THEURGE_NIHIL),
            "coverage-aligned stdout",
        )
    })
}

/// Invoked but never declared: the positive census check refuses the invoke
/// at the chokepoint, failing the fixture and naming the colophon.
fn rbtdrj_coverage_undeclared_fails_naming_colophon(dir: &Path) -> rbtdre_Verdict {
    zrbtdrj_run(|| {
        let label = "coverage-undeclared";
        let case_name = RBTDRL_CASES_COVERAGE_UNDECLARED[0].name;
        let child = zrbtdrj_child(
            dir,
            label,
            RBTDGC_THEURGE_FIXTURE,
            None,
            &[RBTDRM_FIXTURE_CALIBRANT_COVERAGE_UNDECLARED],
            false,
        )?;
        zrbtdrj_expect_nonzero(&child, label)?;
        zrbtdrj_expect_contains(&child.stdout, RBTDRE_WORD_FAILED, "coverage-undeclared stdout")?;
        zrbtdrj_expect_contains(&child.stdout, case_name, "coverage-undeclared stdout")?;
        zrbtdrj_expect_contains(
            &child.stdout,
            &format!(
                "invoked colophon '{}' which is not declared in its required-colophons census",
                RBTDGC_THEURGE_NIHIL
            ),
            "coverage-undeclared stdout",
        )
    })
}

/// Declared but never invoked: the case passes clean, but the engine's
/// negative census check fails the fixture afterward, naming the colophon.
fn rbtdrj_coverage_unused_fails_naming_colophon(dir: &Path) -> rbtdre_Verdict {
    zrbtdrj_run(|| {
        let label = "coverage-unused";
        let case_name = RBTDRL_CASES_COVERAGE_UNUSED[0].name;
        let child = zrbtdrj_child(
            dir,
            label,
            RBTDGC_THEURGE_FIXTURE,
            None,
            &[RBTDRM_FIXTURE_CALIBRANT_COVERAGE_UNUSED],
            false,
        )?;
        zrbtdrj_expect_nonzero(&child, label)?;
        zrbtdrj_expect_contains(&child.stdout, RBTDRE_WORD_PASSED, "coverage-unused stdout")?;
        zrbtdrj_expect_contains(&child.stdout, case_name, "coverage-unused stdout")?;
        zrbtdrj_expect_contains(
            &child.stdout,
            &format!(
                "census — colophon '{}' declared but never invoked",
                RBTDGC_THEURGE_NIHIL
            ),
            "coverage-unused stdout",
        )
    })
}

/// The unused fixture's one case, invoked directly through the single-case
/// runner: exempt from the negative census check, so it exits 0 despite the
/// fixture-level declaration going unused.
fn rbtdrj_coverage_unused_single_case_exempt(dir: &Path) -> rbtdre_Verdict {
    zrbtdrj_run(|| {
        let label = "coverage-unused-single";
        let case_name = RBTDRL_CASES_COVERAGE_UNUSED[0].name;
        let child = zrbtdrj_child(
            dir,
            label,
            RBTDGC_THEURGE_CASE,
            None,
            &[RBTDRM_FIXTURE_CALIBRANT_COVERAGE_UNUSED, case_name],
            false,
        )?;
        zrbtdrj_expect_zero(&child, label)?;
        zrbtdrj_expect_contains(
            &child.stdout,
            RBTDRE_WORD_PASSED,
            "coverage-unused-single stdout",
        )?;
        zrbtdrj_expect_contains(&child.stdout, case_name, "coverage-unused-single stdout")?;
        zrbtdrj_expect_lacks(
            &child.stdout,
            "declared but never invoked",
            "coverage-unused-single stdout",
        )
    })
}

// ── stream-placement ────────────────────────────────────────

/// Under BURD_NO_LOG the dispatch leaves the coordinator's streams unmerged,
/// so this is where the placement contract itself is provable: rbtd's
/// diagnostics land on stderr, not stdout. Every other case reads the folded
/// stdout the logged chain produces.
fn rbtdrj_stream_placement_diags_on_stderr(dir: &Path) -> rbtdre_Verdict {
    zrbtdrj_run(|| {
        let label = "stream-placement";
        let child = zrbtdrj_child(
            dir,
            label,
            RBTDGC_THEURGE_FIXTURE,
            None,
            &[RBTDRM_FIXTURE_CALIBRANT_VERDICTS],
            true,
        )?;
        zrbtdrj_expect_nonzero(&child, label)?;
        zrbtdrj_expect_contains(&child.stderr, RBTDRE_WORD_FAILED, "stream-placement stderr")?;
        zrbtdrj_expect_contains(
            &child.stderr,
            "calibrant deterministic fail verdict",
            "stream-placement stderr",
        )?;
        zrbtdrj_expect_lacks(&child.stdout, RBTDRE_WORD_FAILED, "stream-placement stdout")
    })
}

// ── log-isolation ───────────────────────────────────────────

/// The BURV_LOG_DIR override redirects the child's self-logs into the case
/// dir: the launcher spine's override slots are thereby regression-guarded,
/// and a deliberately-failing child can never write the station's logs-buk.
fn rbtdrj_log_override_isolates(dir: &Path) -> rbtdre_Verdict {
    zrbtdrj_run(|| {
        let label = "log-isolation";
        let pass_case = RBTDRL_CASES_VERDICTS[0].name;
        let child = zrbtdrj_child(
            dir,
            label,
            RBTDGC_THEURGE_CASE,
            None,
            &[RBTDRM_FIXTURE_CALIBRANT_VERDICTS, pass_case],
            false,
        )?;
        zrbtdrj_expect_zero(&child, label)?;
        let log_dir = child.log_dir.clone().expect("logged child carries a log dir");
        zrbtdrj_expect_contains(
            &child.stdout,
            &rbtdrx_native_to_posix(&log_dir),
            "log-isolation stdout (log-files preamble)",
        )?;
        let names: Vec<String> = std::fs::read_dir(&log_dir)
            .map_err(|e| {
                rbtdre_Verdict::Fail(format!(
                    "log-isolation: read override log dir {}: {}",
                    log_dir.display(),
                    e
                ))
            })?
            .filter_map(|e| e.ok())
            .filter_map(|e| e.file_name().into_string().ok())
            .collect();
        zrbtdrj_expect(
            names.iter().any(|n| n.starts_with("hist-")),
            format!("log-isolation: no hist-* self-log in override dir (found: {:?})", names),
        )?;
        zrbtdrj_expect(
            names.iter().any(|n| n.starts_with("same-")),
            format!("log-isolation: no same-* self-log in override dir (found: {:?})", names),
        )?;
        zrbtdrj_expect(
            names.len() >= 3,
            format!("log-isolation: expected ≥3 self-logs in override dir, found {:?}", names),
        )
    })
}

// ── Case array and fixture static ───────────────────────────

pub static RBTDRJ_CASES_TOUCHSTONE: &[rbtdre_Case] = &[
    // verdict-propagation
    case!(rbtdrj_verdict_pass_exits_zero),
    case!(rbtdrj_verdict_skip_exits_zero),
    case!(rbtdrj_verdict_fail_exits_nonzero),
    case!(rbtdrj_verdict_keep_going_runs_all),
    // fixture-fail-fast
    case!(rbtdrj_failfast_default_halts_trailing),
    case!(rbtdrj_failfast_keep_going_reaches_trailing),
    // disposition-policy
    case!(rbtdrj_progressing_default_runs_fail_fast),
    case!(rbtdrj_progressing_keep_going_refused),
    // probe-diagnostics
    case!(rbtdrj_probe_diagnostic_shape),
    // suite-abort
    case!(rbtdrj_suite_abort_halts_sentinel),
    // cli-surface
    case!(rbtdrj_cli_unknown_fixture_errors),
    case!(rbtdrj_cli_missing_fixture_usage),
    case!(rbtdrj_cli_case_listing),
    case!(rbtdrj_cli_single_usage_lists_fixtures),
    // coverage
    case!(rbtdrj_coverage_aligned_exits_zero),
    case!(rbtdrj_coverage_undeclared_fails_naming_colophon),
    case!(rbtdrj_coverage_unused_fails_naming_colophon),
    case!(rbtdrj_coverage_unused_single_case_exempt),
    // stream-placement
    case!(rbtdrj_stream_placement_diags_on_stderr),
    // log-isolation
    case!(rbtdrj_log_override_isolates),
];

/// credless: touchstone is a reveille member, so the guard rides every child
/// launch (BURE_TWEAK_NAME = credless guard) — inert on the rbw-t* chain,
/// which mints no tokens, and required by the reveille slot-reservation rule.
pub static RBTDRJ_FIXTURE_TOUCHSTONE: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_TOUCHSTONE,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRJ_CASES_TOUCHSTONE,
    credless: true,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: None, invocations: Some(20) },
};
const _: () = assert!(RBTDRJ_FIXTURE_TOUCHSTONE.cases.len() == 20);
