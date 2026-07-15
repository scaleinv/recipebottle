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
// RBTDRW — dowse: observed-tariff census over the station's logs-buk history
//
// Read-only report verb, never a fixture: fixtures assert, and suite verdicts
// stay functions of the tree — host log history informs the operator only.
// Dowse parses the per-fixture tariff lines rbtdre_print_tariff emits into the
// BUK self-logs and prints observed cost history per suite and per fixture,
// the observed complement to the declared-cost ETA listing.
//
// Parse contract: the per-fixture line
//   `tariff <name>: elapsed=<N>s invocations=<N> [declared ...]`
// appears exactly once per fixture per run. The suite-end drift-table rows
// carry no colon after the fixture name and the advisory/FAILED lines put a
// non-name token after `tariff`, so both are deliberate non-matches — one run
// is never double-counted. Hist lines may or may not carry the dispatch
// timestamp prefix (interactive tee is uncurated), so the scan keys on the
// `tariff` token, never on column position.

use std::collections::BTreeMap;
use std::path::Path;

use crate::rbtdre_engine::RBTDRE_TARIFF_TOKEN;

/// One observed fixture footprint parsed from a per-fixture tariff line.
#[derive(Debug, PartialEq)]
pub struct rbtdrw_Observation {
    pub fixture: String,
    pub elapsed_secs: u64,
    pub invocations: u32,
}

/// Which theurge launch a hist log records — a named suite run, or a
/// single-fixture run whose log name carries no fixture (the tariff lines
/// inside identify it).
#[derive(Debug, PartialEq)]
pub enum rbtdrw_LogKind {
    Suite(String),
    FixtureRun,
}

/// Parse one self-log line as a per-fixture tariff line. None for every other
/// line shape, including the drift-table header/rows and the advisory lines
/// (see the module header for why those must not match).
pub fn rbtdrw_parse_tariff_line(line: &str) -> Option<rbtdrw_Observation> {
    let mut toks = line
        .split_whitespace()
        .skip_while(|t| *t != RBTDRE_TARIFF_TOKEN)
        .skip(1);
    let fixture = toks.next()?.strip_suffix(':')?;
    if fixture.is_empty() {
        return None;
    }
    let elapsed_secs = toks
        .next()?
        .strip_prefix("elapsed=")?
        .strip_suffix('s')?
        .parse()
        .ok()?;
    let invocations = toks
        .next()?
        .strip_prefix("invocations=")?
        .parse()
        .ok()?;
    Some(rbtdrw_Observation {
        fixture: fixture.to_string(),
        elapsed_secs,
        invocations,
    })
}

/// Classify a logs-buk filename as a theurge history log, yielding its kind
/// and dispatch stamp (YYYYMMDD-HHMMSS). Only `hist-*` files count — `last.txt`
/// and `same-*` duplicate the newest hist and would double-count. The hist
/// shape is `hist-<tag>-<YYYYMMDD>-<HHMMSS>-<pid>-<n>.txt` where the tag is
/// BUK's `<colophon>-<token3>`: `rbw-ts-<suite>` for suite runs, `rbw-tf-sh`
/// for fixture runs (param1-channel folios never reach the filename).
pub fn rbtdrw_parse_log_name(name: &str) -> Option<(rbtdrw_LogKind, String)> {
    let stem = name.strip_prefix("hist-")?.strip_suffix(".txt")?;
    let segs: Vec<&str> = stem.split('-').collect();
    let all_digits = |s: &str| !s.is_empty() && s.chars().all(|c| c.is_ascii_digit());
    let i = segs
        .iter()
        .position(|s| s.len() == 8 && all_digits(s))?;
    if i == 0 {
        return None;
    }
    let time = segs.get(i + 1).filter(|s| s.len() == 6 && all_digits(s))?;
    let tag = segs[..i].join("-");
    let stamp = format!("{}-{}", segs[i], time);
    let kind = if let Some(suite) = tag.strip_prefix("rbw-ts-") {
        rbtdrw_LogKind::Suite(suite.to_string())
    } else if tag == "rbw-tf-sh" {
        rbtdrw_LogKind::FixtureRun
    } else {
        return None;
    };
    Some((kind, stamp))
}

/// Scan the station's log dir and print the observed-tariff census: per suite,
/// each run with its fixture count and summed elapsed; per fixture, an
/// elapsed min/max/last summary then every observation with its source. All
/// history, no truncation — this is a census, and its own output self-logs.
pub fn rbtdrw_dowse(log_dir: &Path) -> Result<(), String> {
    let entries = std::fs::read_dir(log_dir)
        .map_err(|e| format!("dowse: cannot read log dir '{}': {}", log_dir.display(), e))?;

    let mut scanned = 0usize;
    let mut carrying = 0usize;
    // suite → runs of (stamp, fixtures observed, elapsed sum)
    let mut suites: BTreeMap<String, Vec<(String, usize, u64)>> = BTreeMap::new();
    // fixture → observations of (stamp, elapsed, invocations, source label)
    let mut fixtures: BTreeMap<String, Vec<(String, u64, u32, String)>> = BTreeMap::new();

    for entry in entries {
        let entry = entry.map_err(|e| format!("dowse: cannot walk '{}': {}", log_dir.display(), e))?;
        let name = entry.file_name();
        let Some((kind, stamp)) = rbtdrw_parse_log_name(&name.to_string_lossy()) else {
            continue;
        };
        scanned += 1;
        // Lossy read: self-logs can carry non-UTF8 bytes from container output.
        let bytes = std::fs::read(entry.path())
            .map_err(|e| format!("dowse: cannot read '{}': {}", entry.path().display(), e))?;
        let content = String::from_utf8_lossy(&bytes);
        let obs: Vec<rbtdrw_Observation> =
            content.lines().filter_map(rbtdrw_parse_tariff_line).collect();
        if obs.is_empty() {
            continue;
        }
        carrying += 1;
        let label = match &kind {
            rbtdrw_LogKind::Suite(s) => format!("suite {}", s),
            rbtdrw_LogKind::FixtureRun => "fixture-run".to_string(),
        };
        if let rbtdrw_LogKind::Suite(s) = &kind {
            suites.entry(s.clone()).or_default().push((
                stamp.clone(),
                obs.len(),
                obs.iter().map(|o| o.elapsed_secs).sum(),
            ));
        }
        for o in obs {
            fixtures
                .entry(o.fixture)
                .or_default()
                .push((stamp.clone(), o.elapsed_secs, o.invocations, label.clone()));
        }
    }

    crate::rbtdrg_info_now!(
        "dowse: {} theurge log(s) under '{}', {} carrying tariff observations",
        scanned,
        log_dir.display(),
        carrying
    );
    if carrying == 0 {
        crate::rbtdrg_info_now!(
            "dowse: no observations yet — suite and fixture runs write them on every green"
        );
        return Ok(());
    }

    for (suite, mut runs) in suites {
        runs.sort();
        crate::rbtdrg_info_now!("dowse suite {} — {} run(s):", suite, runs.len());
        for (stamp, count, sum) in runs {
            crate::rbtdrg_info_now!(
                "dowse   {}  fixtures={:>2}  elapsed-sum={:>4}s",
                stamp, count, sum
            );
        }
    }

    for (fixture, mut obs) in fixtures {
        obs.sort();
        let min = obs.iter().map(|o| o.1).min().unwrap_or(0);
        let max = obs.iter().map(|o| o.1).max().unwrap_or(0);
        let last = obs.last().map(|o| o.1).unwrap_or(0);
        crate::rbtdrg_info_now!(
            "dowse fixture {} — {} observation(s), elapsed min={}s max={}s last={}s:",
            fixture,
            obs.len(),
            min,
            max,
            last
        );
        for (stamp, elapsed, inv, label) in obs {
            crate::rbtdrg_info_now!(
                "dowse   {}  elapsed={:>4}s  inv={:>3}  [{}]",
                stamp, elapsed, inv, label
            );
        }
    }

    Ok(())
}
