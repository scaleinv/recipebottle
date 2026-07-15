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
// RBTDTW — dowse parse-seam tests: the per-fixture tariff line is the one
// matching shape; every sibling emission under the same grep token (drift
// table, advisories, declared listing) must be a non-match, and the hist
// filename classifier must reject everything but theurge suite/fixture logs.

use super::rbtdrw_dowse::{
    rbtdrw_parse_log_name, rbtdrw_parse_tariff_line, rbtdrw_LogKind, rbtdrw_Observation,
};

#[test]
fn rbtdtw_parses_bare_per_fixture_line() {
    let line = "[INFO] [src/rbtdre_engine.rs:498] tariff regime-smoke: elapsed=7s invocations=47 [declared min=2s max=60s invocations=47]";
    assert_eq!(
        rbtdrw_parse_tariff_line(line),
        Some(rbtdrw_Observation {
            fixture: "regime-smoke".to_string(),
            elapsed_secs: 7,
            invocations: 47,
        })
    );
}

#[test]
fn rbtdtw_parses_hist_curated_line() {
    // Non-interactive dispatch prepends the wall-clock stamp; the parse keys
    // on the tariff token, never on column position.
    let line = "[2026-07-09 21:21:30] [INFO] [src/rbtdre_engine.rs:498] tariff podvm-resolve: elapsed=0s invocations=2 [declared min=— max=— invocations=2]";
    assert_eq!(
        rbtdrw_parse_tariff_line(line),
        Some(rbtdrw_Observation {
            fixture: "podvm-resolve".to_string(),
            elapsed_secs: 0,
            invocations: 2,
        })
    );
}

#[test]
fn rbtdtw_rejects_drift_table_row() {
    // Table rows carry no colon after the name — the double-count guard.
    let line = "[INFO] [src/rbtdre_engine.rs:555] tariff  regime-smoke                 elapsed=   7s inv= 47  decl[min=2s max=60s inv=47]";
    assert_eq!(rbtdrw_parse_tariff_line(line), None);
}

#[test]
fn rbtdtw_rejects_drift_table_header() {
    let line = "[INFO] [src/rbtdre_engine.rs:543] tariff drift table (observed vs declared):";
    assert_eq!(rbtdrw_parse_tariff_line(line), None);
}

#[test]
fn rbtdtw_rejects_declared_listing_line() {
    let line = "[INFO] [src/main.rs:368] fixture 'regime-smoke' declared tariff: [min=2s max=60s inv=47]";
    assert_eq!(rbtdrw_parse_tariff_line(line), None);
}

#[test]
fn rbtdtw_rejects_advisory_lines() {
    let too_fast = "[INFO] FAILED: regime-smoke tariff too-fast — elapsed 1s below declared min 2s (vacuous green)";
    let too_slow = "[INFO] WARNING: regime-smoke tariff too-slow — elapsed 99s above declared max 60s (advisory)";
    let drift = "[INFO] WARNING: regime-smoke tariff count-drift — 3 invocations vs declared 47 (advisory)";
    assert_eq!(rbtdrw_parse_tariff_line(too_fast), None);
    assert_eq!(rbtdrw_parse_tariff_line(too_slow), None);
    assert_eq!(rbtdrw_parse_tariff_line(drift), None);
}

#[test]
fn rbtdtw_rejects_tokenless_line() {
    assert_eq!(rbtdrw_parse_tariff_line("Suite 'reveille': 12 fixture(s) run"), None);
    assert_eq!(rbtdrw_parse_tariff_line(""), None);
}

#[test]
fn rbtdtw_classifies_suite_log_name() {
    assert_eq!(
        rbtdrw_parse_log_name("hist-rbw-ts-reveille-20260709-212119-1862763-785.txt"),
        Some((
            rbtdrw_LogKind::Suite("reveille".to_string()),
            "20260709-212119".to_string()
        ))
    );
}

#[test]
fn rbtdtw_classifies_fixture_run_log_name() {
    assert_eq!(
        rbtdrw_parse_log_name("hist-rbw-tf-sh-20260605-073148-55814-34.txt"),
        Some((rbtdrw_LogKind::FixtureRun, "20260605-073148".to_string()))
    );
}

#[test]
fn rbtdtw_rejects_foreign_log_names() {
    // Non-theurge tabtargets, the same/last duplicates of the newest hist,
    // and the single-case runner (which emits no per-fixture tariff line).
    assert_eq!(rbtdrw_parse_log_name("hist-rbw-cC-tadmor-20260709-212119-1-1.txt"), None);
    assert_eq!(rbtdrw_parse_log_name("same-rbw-ts-reveille.txt"), None);
    assert_eq!(rbtdrw_parse_log_name("last.txt"), None);
    assert_eq!(rbtdrw_parse_log_name("hist-rbw-tc-sh-20260709-212119-1-1.txt"), None);
}
