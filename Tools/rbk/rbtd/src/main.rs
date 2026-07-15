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
// RBTD Theurge — test orchestrator entry point
//
// Subcommands:
//   rbtd <fixture> [--keep-going]
//     Single-fixture runner — charge, run all cases, quench. --keep-going
//     requests keep-going mode, resolved against the fixture's disposition
//     (refused for StateProgressing) by rbtdre_resolve_fail_fast.
//   rbtd suite <suite> [--keep-going]
//     Suite runner — resolve the suite's fixtures (composition owned here, not
//     in bash) and run each in sequence, fail-fast, with one aggregate summary.
//     --keep-going applies per fixture; the cross-fixture break-on-failure is
//     unchanged.
//   rbtd single <fixture> [case]
//     Single-case runner — no charge/quench. List cases or run one.
//   rbtd dowse <log-dir>
//     Observed-tariff census — read-only report over the station's logs-buk
//     history; no tree guard, no roots, no context.

// RCG output discipline: all emission via rbtdrg_*! — no direct println!/eprintln!

#![allow(non_camel_case_types)]
#![allow(private_interfaces)]
#![deny(warnings)]

use std::path::PathBuf;
use std::process::ExitCode;

use rbtd::rbtdra_almanac::{
    rbtdra_lookup_fixture, rbtdra_lookup_suite, RBTDRA_FIXTURES, RBTDRA_SUITES,
};
use rbtd::rbtdrc_crucible::{rbtdrc_set_context, rbtdrc_take_context};
use rbtd::rbtdre_engine::{
    RBTDRE_FLAG_KEEP_GOING,
    rbtdre_TariffRow,
    rbtdre_detect_colors,
    rbtdre_find_case,
    rbtdre_list_cases,
    rbtdre_parse_keep_going,
    rbtdre_print_summary,
    rbtdre_print_tariff_table,
    rbtdre_run_fixture,
    rbtdre_run_single_case,
    rbtdre_tariff_declared,
    rbtdre_tree_clean,
};
use rbtd::rbtdri_invocation::{
    rbtdri_Context, rbtdri_invoke_global,
    RBTDRI_BURD_TEMP_DIR_KEY,
};
use rbtd::rbtdrw_dowse::rbtdrw_dowse;
use rbtd::rbtdgc_consts::RBTDGC_CRUCIBLE_ACTIVE;
use rbtd::rbtdrx_platform::rbtdrx_path_from_env;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().collect();

    match args.get(1).map(|s| s.as_str()) {
        Some("single") => rbtdb_run_single(&args[2..]),
        Some("suite") => rbtdb_run_suite(&args[2..]),
        Some("dowse") => rbtdb_run_dowse(&args[2..]),
        _ => rbtdb_run_fixture(&args[1..]),
    }
}

// ── Dowse (observed-tariff census) ───────────────────────────

fn rbtdb_run_dowse(args: &[String]) -> ExitCode {
    let log_dir = match args.first() {
        Some(d) => PathBuf::from(d),
        None => rbtd::rbtdrg_fatal_now!(
            "rbtd dowse: usage: rbtd dowse <log-dir>\n\
             launch via tabtarget: tt/rbw-td.TariffDowse.sh"
        ),
    };
    match rbtdrw_dowse(&log_dir) {
        Ok(()) => ExitCode::SUCCESS,
        Err(msg) => rbtd::rbtdrg_fatal_now!("rbtd: {}", msg),
    }
}

struct rbtdb_Roots {
    trace_root: PathBuf,
    burv_temp_root: PathBuf,
    burv_output_root: PathBuf,
}

fn rbtdb_allocate_roots() -> Result<rbtdb_Roots, String> {
    let burd_temp = rbtdrx_path_from_env(RBTDRI_BURD_TEMP_DIR_KEY)?;

    // Both BURV roots are anchored under the per-run trace dir
    // (BURD_TEMP_DIR/rbtd), which is stable for the life of the run. The output
    // root deliberately does NOT live under BURD_OUTPUT_DIR (output-buk/current):
    // that dir is cleared at the start of every BUK dispatch, so a fact captured
    // there can be deleted out from under a still-running invocation by any
    // default-root dispatch — leaving the durable temp copy as the only survivor
    // (the failure that made rbgp_fact_governor_sa_email unreadable mid-suite).
    let trace_root = burd_temp.join("rbtd");
    let burv_temp_root = trace_root.join("burv-temp");
    let burv_output_root = trace_root.join("burv-output");

    std::fs::create_dir_all(&trace_root)
        .map_err(|e| format!("rbtd: failed to create trace root '{}': {}", trace_root.display(), e))?;
    std::fs::create_dir_all(&burv_temp_root)
        .map_err(|e| format!("rbtd: failed to create burv temp root '{}': {}", burv_temp_root.display(), e))?;
    std::fs::create_dir_all(&burv_output_root)
        .map_err(|e| format!("rbtd: failed to create burv output root '{}': {}", burv_output_root.display(), e))?;

    Ok(rbtdb_Roots { trace_root, burv_temp_root, burv_output_root })
}

// ── Single-fixture runner ────────────────────────────────────

fn rbtdb_run_fixture(args: &[String]) -> ExitCode {
    let (positionals, keep_going) = match rbtdre_parse_keep_going(args) {
        Ok(v) => v,
        Err(msg) => rbtd::rbtdrg_fatal_now!("rbtd: {}", msg),
    };
    let fixture = match positionals.first() {
        Some(n) => n,
        None => rbtd::rbtdrg_fatal_now!(
            "rbtd: usage: rbtd <fixture> [{}]\n\
             theurge must be launched via tabtarget (e.g. tt/rbw-tf.FixtureRun.sh tadmor)",
            RBTDRE_FLAG_KEEP_GOING
        ),
    };
    if positionals.len() > 1 {
        rbtd::rbtdrg_fatal_now!(
            "rbtd: unexpected argument '{}' — usage: rbtd <fixture> [{}]",
            positionals[1], RBTDRE_FLAG_KEEP_GOING
        );
    }

    let project_root = match std::env::current_dir() {
        Ok(p) => p,
        Err(e) => rbtd::rbtdrg_fatal_now!("rbtd: cannot determine working directory: {}", e),
    };

    // Run-start hygiene guard (suite only). A suite run commits a sequence of
    // hallmark/yoke changes; starting on a dirty tree would interleave the
    // operator's uncommitted edits with those commits. Single-case mode is the
    // crucible-debug loop and is intentionally left unguarded.
    if let Err(msg) = rbtdre_tree_clean(&project_root) {
        rbtd::rbtdrg_fatal_now!(
            "rbtd: refusing to start a suite run on a dirty working tree — \
             commit or stash first.\n{}",
            msg
        );
    }

    let roots = match rbtdb_allocate_roots() {
        Ok(r) => r,
        Err(msg) => rbtd::rbtdrg_fatal_now!("{}", msg),
    };

    let ctx = rbtdri_Context::new(
        &project_root,
        fixture,
        &roots.burv_temp_root,
        &roots.burv_output_root,
    );

    let fixture_def = match rbtdra_lookup_fixture(fixture) {
        Some(f) => f,
        None => rbtd::rbtdrg_fatal_now!(
            "rbtd: fixture '{}' has no registered Fixture — \
             no Fixture static is bound. \
             Update rbtdra_lookup_fixture in rbtdrc_crucible.rs.",
            fixture
        ),
    };

    rbtdrc_set_context(ctx);

    let colors = rbtdre_detect_colors();
    let run_result = rbtdre_run_fixture(fixture_def, &colors, &roots.trace_root, keep_going);

    let _ctx = rbtdrc_take_context();

    let result = match run_result {
        Ok(r) => r,
        Err(msg) => rbtd::rbtdrg_fatal_now!("rbtd: {}", msg),
    };

    rbtdre_print_summary(&result, &colors);

    if result.failed > 0 {
        rbtd::rbtdrg_error_now!("rbtd: {} case(s) failed", result.failed);
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}

// ── Suite runner ─────────────────────────────────────────────

fn rbtdb_run_suite(args: &[String]) -> ExitCode {
    let (positionals, keep_going) = match rbtdre_parse_keep_going(args) {
        Ok(v) => v,
        Err(msg) => rbtd::rbtdrg_fatal_now!("rbtd suite: {}", msg),
    };
    let suite = match positionals.first() {
        Some(name) => match rbtdra_lookup_suite(name) {
            Some(s) => s,
            None => {
                rbtd::rbtdrg_error_now!("rbtd suite: unknown suite '{}'", name);
                rbtdb_list_suites();
                return ExitCode::FAILURE;
            }
        },
        None => {
            rbtd::rbtdrg_error_now!("rbtd suite: no suite argument");
            rbtdb_list_suites();
            return ExitCode::FAILURE;
        }
    };
    if positionals.len() > 1 {
        rbtd::rbtdrg_fatal_now!(
            "rbtd suite: unexpected argument '{}' — usage: rbtd suite <suite> [{}]",
            positionals[1], RBTDRE_FLAG_KEEP_GOING
        );
    }

    let project_root = match std::env::current_dir() {
        Ok(p) => p,
        Err(e) => rbtd::rbtdrg_fatal_now!("rbtd: cannot determine working directory: {}", e),
    };

    // Run-start hygiene guard, once per suite (under the bash loop it ran once
    // per fixture). A suite commits a sequence of hallmark/yoke changes; a dirty
    // tree at the start would interleave the operator's uncommitted edits.
    if let Err(msg) = rbtdre_tree_clean(&project_root) {
        rbtd::rbtdrg_fatal_now!(
            "rbtd: refusing to start a suite run on a dirty working tree — \
             commit or stash first.\n{}",
            msg
        );
    }

    // Roots allocated once per suite; all fixtures share the trace/burv roots.
    // This matches the bash loop, where every per-fixture process inherited the
    // same BURD_TEMP_DIR and thus the same trace root.
    let roots = match rbtdb_allocate_roots() {
        Ok(r) => r,
        Err(msg) => rbtd::rbtdrg_fatal_now!("{}", msg),
    };

    let colors = rbtdre_detect_colors();

    let mut total_passed = 0usize;
    let mut total_failed = 0usize;
    let mut total_skipped = 0usize;
    let mut ran = 0usize;
    // Collected per-fixture tariff footprints for the suite-end drift table.
    let mut tariff_rows: Vec<rbtdre_TariffRow> = Vec::new();

    // Sequential, fail-fast across fixtures — matches the bash for-loop under
    // `set -e`. A fixture whose cases fail (or whose setup errors) stops the
    // suite; fixtures already run have charged-and-quenched cleanly.
    //
    // Note: a case that *panics* (rather than returning a Fail verdict) unwinds
    // past its fixture's quench and aborts the whole suite process with that
    // fixture's crucible left charged — the same leak the per-process bash loop
    // had. Routine failure is always a Fail verdict, which quenches normally
    // (teardown is finally-shaped in rbtdre_run_fixture).
    let mut next_invoke_count = 0u32;
    for fixture in suite.fixtures {
        let mut ctx = rbtdri_Context::new(
            &project_root,
            fixture.name,
            &roots.burv_temp_root,
            &roots.burv_output_root,
        );
        // Carry the BURV invoke counter across fixtures so per-invoke dir names
        // never collide between fixtures. A fresh Context starts at 0, so without
        // this every fixture's first invoke reuses invoke-00000 — and bud's
        // start-of-dispatch current/->previous/ promotion then leaks the prior
        // fixture's chaining facts into a non-chained invoke's previous/.
        // Suite-monotonic numbering gives each invoke its own dir, closing that.
        ctx.set_invoke_count(next_invoke_count);
        rbtdrc_set_context(ctx);

        let run_result = rbtdre_run_fixture(fixture, &colors, &roots.trace_root, keep_going);

        next_invoke_count = rbtdrc_take_context().invoke_count();

        match run_result {
            Ok(result) => {
                rbtdre_print_summary(&result, &colors);
                tariff_rows.push(rbtdre_TariffRow {
                    name: fixture.name.to_string(),
                    tariff: fixture.tariff,
                    elapsed_secs: result.elapsed_secs,
                    invocations: result.invocations,
                });
                total_passed += result.passed;
                total_failed += result.failed;
                total_skipped += result.skipped;
                ran += 1;
                if result.failed > 0 {
                    break;
                }
            }
            Err(msg) => {
                rbtd::rbtdrg_error_now!("rbtd: fixture '{}': {}", fixture.name, msg);
                total_failed += 1;
                ran += 1;
                break;
            }
        }
    }

    rbtdre_print_tariff_table(&tariff_rows);

    rbtd::rbtdrg_info_now!(
        "Suite '{}': {} fixture(s) run, {} passed, {} failed, {} skipped",
        suite.name, ran, total_passed, total_failed, total_skipped
    );

    if total_failed > 0 {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}

fn rbtdb_list_suites() {
    rbtd::rbtdrg_info_now!("available suites:");
    for s in RBTDRA_SUITES {
        rbtd::rbtdrg_info_now!("  {}", s.name);
    }
}

// ── Single-case runner ───────────────────────────────────────

fn rbtdb_run_single(args: &[String]) -> ExitCode {
    let fixture = match args.first() {
        Some(f) => f,
        None => {
            rbtd::rbtdrg_error_now!(
                "rbtd single: usage: rbtd single <fixture> [case]\n\
                 omit case to list all cases for the fixture"
            );
            rbtdb_list_fixtures();
            return ExitCode::FAILURE;
        }
    };

    if !RBTDRA_FIXTURES.iter().any(|f| f.name == *fixture) {
        rbtd::rbtdrg_error_now!("rbtd single: unknown fixture '{}'", fixture);
        rbtdb_list_fixtures();
        return ExitCode::FAILURE;
    }

    // Set up execution context early — needed for charge check and case execution
    let project_root = match std::env::current_dir() {
        Ok(p) => p,
        Err(e) => rbtd::rbtdrg_fatal_now!("rbtd: cannot determine working directory: {}", e),
    };

    let roots = match rbtdb_allocate_roots() {
        Ok(r) => r,
        Err(msg) => rbtd::rbtdrg_fatal_now!("{}", msg),
    };

    // Context is required for every case execution path (rbtdrc_with_ctx).
    // Fixtures with a setup hook (crucible charge) additionally verify their
    // crucible is charged externally — single-case mode never charges. The
    // charge probe below runs BEFORE rbtdrc_set_context, so it is deliberately
    // outside the fixture's census: it is harness machinery, not fixture
    // behavior.
    let mut ctx = rbtdri_Context::new(
        &project_root,
        fixture,
        &roots.burv_temp_root,
        &roots.burv_output_root,
    );

    let fixture_def = match rbtdra_lookup_fixture(fixture) {
        Some(f) => f,
        None => rbtd::rbtdrg_fatal_now!(
            "rbtd single: fixture '{}' has no registered Fixture",
            fixture
        ),
    };

    if fixture_def.setup.is_some() {
        match rbtdri_invoke_global(
            &mut ctx,
            RBTDGC_CRUCIBLE_ACTIVE,
            &[fixture],
            &[],
        ) {
            Ok(r) if r.exit_code == 0 => {}
            _ => rbtd::rbtdrg_fatal_now!(
                "rbtd single: crucible not charged for '{}'\n\
                 charge first: tt/rbw-cC.Charge.{}.sh",
                fixture, fixture
            ),
        }
    }

    rbtdrc_set_context(ctx);

    let cases = fixture_def.cases;

    // No case argument — list all cases
    let case_name = match args.get(1) {
        None => {
            rbtd::rbtdrg_info_now!(
                "fixture '{}' declared tariff: [{}]",
                fixture, rbtdre_tariff_declared(&fixture_def.tariff)
            );
            rbtdre_list_cases(cases);
            return ExitCode::SUCCESS;
        }
        Some(n) => n,
    };

    // Find the case
    let case = match rbtdre_find_case(cases, case_name) {
        Some(c) => c,
        None => {
            rbtd::rbtdrg_error_now!(
                "rbtd single: case '{}' not found in fixture '{}'",
                case_name, fixture
            );
            rbtdre_list_cases(cases);
            return ExitCode::FAILURE;
        }
    };

    let colors = rbtdre_detect_colors();
    let result = match rbtdre_run_single_case(case, &colors, &roots.trace_root) {
        Ok(r) => r,
        Err(msg) => rbtd::rbtdrg_fatal_now!("rbtd: case execution error: {}", msg),
    };

    rbtdre_print_summary(&result, &colors);

    if result.failed > 0 {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}

fn rbtdb_list_fixtures() {
    rbtd::rbtdrg_info_now!("available fixtures:");
    let mut eta_min = 0u64;
    let mut eta_max = 0u64;
    for f in RBTDRA_FIXTURES {
        rbtd::rbtdrg_info_now!("  {:<28} [{}]", f.name, rbtdre_tariff_declared(&f.tariff));
        eta_min += f.tariff.min_secs.unwrap_or(0);
        eta_max += f.tariff.max_secs.unwrap_or(0);
    }
    // Declared-cost ETA envelope: the sum of declared min/max wall-clock across
    // the roster. Undeclared bounds contribute zero, so this is a lower bound on
    // the envelope, not a promise — it grows as declarations are seeded.
    rbtd::rbtdrg_info_now!(
        "declared-cost ETA envelope (sum of declared bounds): min {}s, max {}s",
        eta_min, eta_max
    );
}
