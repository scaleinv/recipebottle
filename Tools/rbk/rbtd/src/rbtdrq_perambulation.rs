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
// RBTDRQ — perambulation: the ship/withhold judgment is TOTAL over the tracked tree.
//
// Damnatio proves the delivered tree carries none of the operator's identity.
// This fixture proves something one rung earlier and more basic: that the project
// has RULED on every file it tracks. Not that the ruling is right — that is the
// operator's judgment, and no fixture can hold it — but that the ruling EXISTS,
// for every path, before a candidate is cut from it.
//
// The perambulation (Tools/rbk/rblm_perambulation.sh) is the table. This is its completeness
// case, and it is damnatio's completeness case generalized from fields to paths:
//
//   UNJUDGED  a tracked path no perambulation row rules on. Red. No default in
//             either direction — a new file may not ship because nobody said not
//             to, and it may not vanish because nobody said to keep it. It is red
//             until someone rules, and the ruling is a line in the table.
//
//   DEAD      a perambulation row that wins for no tracked path. Red. Two failures
//             this face and both mean the table is lying about the tree: a STALE
//             row judging a path long deleted, and a SHADOWED row outranked
//             everywhere by a longer one, so its judgment never lands. The
//             ceremony's prose strip lists carried three stale entries for months
//             and nothing could see them; this case saw them on its first run.
//
// A MEMBER OF NO SUITE, for exactly the reason loupe is. Reveille SHIPS — the
// delivered tree carries the theurge crate and the suite tabtarget — and in the
// consumer's tree `git ls-files` returns only the shipped paths, so every withhold
// row wins nothing and goes dead. A reveille membership would hand every consumer
// a fixture that is red by construction, asserting the staleness of rows about
// files they were never given. It is the maintainer's assay of the maintainer's
// tree, invoked by name and — where it actually bites — by expede, which refuses
// to cut a candidate from a tree holding an unjudged path.
//
// NO SECOND MATCHER. The table, the longest-prefix rule, and the sweep all live in
// bash, in the perambulation module, and this fixture reaches them the way damnatio
// reaches the proscription: it shells in and reads the verdicts back. Expede cuts
// from the same matcher these cases prove. A Rust reimplementation would be a
// second copy of the one judgment that must never have two.

use std::collections::BTreeSet;
use std::path::Path;

use crate::case;
use crate::rbtdre_engine::{
    rbtdre_Case,
    rbtdre_Disposition,
    rbtdre_Fixture,
    rbtdre_Tariff,
    rbtdre_Verdict,
};
use crate::rbtdrf_fast::{
    rbtdrf_run_bash,
    RBTDRF_RBK_ROOT,
};
use crate::rbtdrm_manifest::RBTDRM_FIXTURE_PERAMBULATION;
use crate::rbtdrq_pyx::{
    zrbtdrq_report,
    zrbtdrq_root,
    zrbtdrq_Finding,
};

/// The perambulation module — the home of the judgment, and the file every finding here
/// names, because a finding here is always answered by a line in that table.
const ZRBTDRQ_PERAMBULATION_HOME: &str = "Tools/rbk/rblm_perambulation.sh";

const ZRBTDRQ_MARK_VERDICTS: &str = "##VERDICTS";
const ZRBTDRQ_MARK_DEAD: &str = "##DEAD";
const ZRBTDRQ_MARK_LEAKS: &str = "##LEAKS";

/// The disposition the perambulation emits for a path no row rules on.
const ZRBTDRQ_UNJUDGED: &str = "unjudged";

/// Reach into bash for the perambulation's verdict over the live tracked tree.
///
/// The tracked set is derived from git inside the reach, never passed in: the
/// judgment is against what the repository actually carries at this commit, and
/// any other source of truth is a second copy waiting to drift.
///
/// Returns (verdicts, dead rows). A verdict is (disposition, path); a dead row is
/// (prefix, disposition).
fn zrbtdrq_reach_perambulation(
    root: &Path,
    dir: &Path,
) -> Result<(Vec<(String, String)>, Vec<(String, String)>), String> {
    let rbk = crate::rbtdrx_platform::rbtdrx_native_to_posix(&root.join(RBTDRF_RBK_ROOT));

    let script = format!(
        "set -euo pipefail\n\
         export BURD_TEMP_DIR='{dir}'\n\
         source '{rbk}/rblm_perambulation.sh'\n\
         echo '{mark_verdicts}'\n\
         rblm_emit_verdicts\n\
         echo '{mark_dead}'\n\
         rblm_emit_dead_rows\n",
        dir = crate::rbtdrx_platform::rbtdrx_native_to_posix(dir),
        rbk = rbk,
        mark_verdicts = ZRBTDRQ_MARK_VERDICTS,
        mark_dead = ZRBTDRQ_MARK_DEAD,
    );

    let stdout = match rbtdrf_run_bash(root, &script, dir, "perambulation-reach")? {
        (0, stdout, _) => stdout,
        (code, _, stderr) => {
            return Err(format!("perambulation reach failed (exit {}): {}", code, stderr.trim()));
        }
    };

    let mut verdicts: Vec<(String, String)> = Vec::new();
    let mut dead: Vec<(String, String)> = Vec::new();
    let mut section = "";

    for line in stdout.lines() {
        match line {
            ZRBTDRQ_MARK_VERDICTS | ZRBTDRQ_MARK_DEAD => {
                section = line;
                continue;
            }
            _ => {}
        }
        if line.is_empty() {
            continue;
        }
        let fields: Vec<&str> = line.split('\t').collect();
        if fields.len() < 2 {
            continue;
        }
        match section {
            ZRBTDRQ_MARK_VERDICTS => {
                verdicts.push((fields[0].to_string(), fields[1].to_string()));
            }
            ZRBTDRQ_MARK_DEAD => {
                dead.push((fields[0].to_string(), fields[1].to_string()));
            }
            _ => {}
        }
    }

    if verdicts.is_empty() {
        return Err("the perambulation came back empty — the reach tracked nothing".to_string());
    }

    Ok((verdicts, dead))
}

// ── Case: the judgment is total ─────────────────────────────

/// Every tracked path is ruled ship or withhold, and every perambulation row rules on
/// something. The completeness case: it does not ask whether the ruling is right,
/// only that it was made.
fn rbtdrq_perambulation_total(dir: &Path) -> rbtdre_Verdict {
    let root = match zrbtdrq_root() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };
    let (verdicts, dead) = match zrbtdrq_reach_perambulation(&root, dir) {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };

    let mut findings: Vec<zrbtdrq_Finding> = Vec::new();
    let mut inventory: BTreeSet<String> = BTreeSet::new();

    let mut shipped = 0usize;
    let mut withheld = 0usize;

    for (disposition, path) in &verdicts {
        if disposition == ZRBTDRQ_UNJUDGED {
            findings.push(zrbtdrq_Finding {
                file: ZRBTDRQ_PERAMBULATION_HOME.to_string(),
                line: 0,
                detail: format!(
                    "{} is tracked but unjudged — rule it ship or withhold",
                    path
                ),
            });
            continue;
        }
        if disposition == "ship" {
            shipped += 1;
            inventory.insert(format!("ship\t{}", path));
        } else {
            withheld += 1;
        }
    }

    for (prefix, disposition) in &dead {
        findings.push(zrbtdrq_Finding {
            file: ZRBTDRQ_PERAMBULATION_HOME.to_string(),
            line: 0,
            detail: format!(
                "row '{}|{}' judges no tracked path — it is stale, or shadowed by a longer row",
                prefix, disposition
            ),
        });
    }

    inventory.insert(format!("== {} shipped, {} withheld", shipped, withheld));

    zrbtdrq_report(dir, "perambulation", &findings, &inventory, "unjudged path(s) or dead row(s)")
}

// ── Case: the sweep catches a planted leak ──────────────────

/// The sweep is what stands between a withheld file and the upstream, and it is
/// the assertion the 2026-07-13 candidate had no version of. That candidate's TIP
/// was clean — every strip had landed, and every assay this project owned read the
/// tip and passed it — while its HISTORY carried the whole pre-strip repository to
/// the remote at 292 MiB. Expede sweeps the candidate's entire object graph, so a
/// withheld path is caught wherever it is reachable from the branch, at any depth.
///
/// This case proves the sweep the way damnatio's matcher proves itself before its
/// verdict is trusted: it plants leaks in a synthetic path list and demands they be
/// caught, then feeds a clean list and demands silence. Synthetic, and pure over
/// its input — the sweep is a function of the perambulation and a list of paths, so
/// proving it needs no clone, no network, and no candidate. A sweep that cannot
/// catch a planted leak cannot be trusted to catch a real one, and a sweep that
/// reddens on a clean list would be worked around within a week.
fn rbtdrq_perambulation_sweep(dir: &Path) -> rbtdre_Verdict {
    let root = match zrbtdrq_root() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };
    let rbk = crate::rbtdrx_platform::rbtdrx_native_to_posix(&root.join(RBTDRF_RBK_ROOT));

    // The planted paths, and the clean ones. Both are ordinary repo paths named
    // structurally — a veiled spec, a memo, the operator's own kit, a withheld
    // tabtarget — against a delivered face that must pass untouched.
    //
    // The veiled-spec datum carries a SYNTHETIC basename. What it must exercise is
    // the longest-wins override — a veiled half inside a shipping kit — and that is
    // a property of the directory, not of any document sitting in it. Naming a real
    // withheld document here would print its title in delivered source, which is the
    // very citation form the veil law forbids.
    let planted = [
        "Tools/rbk/vov_veiled/planted-spec.adoc",
        "Memos/memo-20260713-the-one-that-got-out.md",
        "Tools/jjk/jjw_workbench.sh",
        "tt/rbw-MZ.MarshalZeroes.sh",
        "rbmm_moorings/fdkyclk/fdkyclk-proof.sh",
    ];
    let clean = [
        "README.md",
        "LICENSE",
        "Tools/rbk/rba_auth.sh",
        "Tools/buk/buc_command.sh",
        "tt/rbw-cC.Charge.tadmor.sh",
        "rbmm_moorings/fdkyclk/fdkyclk-asserter-key.pem",
    ];

    // The two graphs the sweep is asked to judge, written where the sweep takes
    // them: a file. A dirty graph carrying every planted path among the clean ones,
    // and a graph that is nothing but the delivered face.
    let mut dirty_body = String::new();
    for path in planted.iter().chain(clean.iter()) {
        dirty_body.push_str(path);
        dirty_body.push('\n');
    }
    let mut clean_body = String::new();
    for path in &clean {
        clean_body.push_str(path);
        clean_body.push('\n');
    }

    let dirty_list = dir.join("graph-dirty.txt");
    let clean_list = dir.join("graph-clean.txt");
    if let Err(e) = std::fs::write(&dirty_list, dirty_body) {
        return rbtdre_Verdict::Fail(format!("cannot write planted graph: {}", e));
    }
    if let Err(e) = std::fs::write(&clean_list, clean_body) {
        return rbtdre_Verdict::Fail(format!("cannot write clean graph: {}", e));
    }

    let script = format!(
        "set -euo pipefail\n\
         export BURD_TEMP_DIR='{dir}'\n\
         source '{rbk}/rblm_perambulation.sh'\n\
         echo '{mark_leaks}'\n\
         rblm_perambulation_sweep_capture '{dirty}'\n\
         printf '%s\\n' \"${{ZRBLM_LEAKS[@]:-}}\"\n\
         echo '{mark_dead}'\n\
         rblm_perambulation_sweep_capture '{clean_list}'\n\
         printf '%s\\n' \"${{ZRBLM_LEAKS[@]:-}}\"\n",
        dir = crate::rbtdrx_platform::rbtdrx_native_to_posix(dir),
        rbk = rbk,
        mark_leaks = ZRBTDRQ_MARK_LEAKS,
        mark_dead = ZRBTDRQ_MARK_DEAD,
        dirty = crate::rbtdrx_platform::rbtdrx_native_to_posix(&dirty_list),
        clean_list = crate::rbtdrx_platform::rbtdrx_native_to_posix(&clean_list),
    );

    let stdout = match rbtdrf_run_bash(&root, &script, dir, "perambulation-sweep") {
        Ok((0, stdout, _)) => stdout,
        Ok((code, _, stderr)) => {
            return rbtdre_Verdict::Fail(format!(
                "sweep reach failed (exit {}): {}",
                code,
                stderr.trim()
            ));
        }
        Err(e) => return rbtdre_Verdict::Fail(e),
    };

    let mut caught: BTreeSet<String> = BTreeSet::new();
    let mut clean_leaks: BTreeSet<String> = BTreeSet::new();
    let mut section = "";

    for line in stdout.lines() {
        match line {
            ZRBTDRQ_MARK_LEAKS | ZRBTDRQ_MARK_DEAD => {
                section = line;
                continue;
            }
            _ => {}
        }
        if line.is_empty() {
            continue;
        }
        match section {
            ZRBTDRQ_MARK_LEAKS => {
                caught.insert(line.to_string());
            }
            ZRBTDRQ_MARK_DEAD => {
                clean_leaks.insert(line.to_string());
            }
            _ => {}
        }
    }

    let mut findings: Vec<zrbtdrq_Finding> = Vec::new();
    let mut inventory: BTreeSet<String> = BTreeSet::new();

    for path in &planted {
        if caught.contains(*path) {
            inventory.insert(format!("caught\t{}", path));
        } else {
            findings.push(zrbtdrq_Finding {
                file: ZRBTDRQ_PERAMBULATION_HOME.to_string(),
                line: 0,
                detail: format!(
                    "the sweep did not catch planted withheld path {} — it would ride a candidate",
                    path
                ),
            });
        }
    }

    for path in &clean {
        if caught.contains(*path) || clean_leaks.contains(*path) {
            findings.push(zrbtdrq_Finding {
                file: ZRBTDRQ_PERAMBULATION_HOME.to_string(),
                line: 0,
                detail: format!(
                    "the sweep reddened on shipped path {} — a sweep that cries wolf gets disabled",
                    path
                ),
            });
        } else {
            inventory.insert(format!("passed\t{}", path));
        }
    }

    zrbtdrq_report(dir, "sweep", &findings, &inventory, "sweep self-proof failure(s)")
}

// ── The fixture ─────────────────────────────────────────────

pub static RBTDRQ_CASES_PERAMBULATION: &[rbtdre_Case] = &[
    case!(rbtdrq_perambulation_total),
    case!(rbtdrq_perambulation_sweep),
];

pub static RBTDRQ_FIXTURE_PERAMBULATION: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_PERAMBULATION,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRQ_CASES_PERAMBULATION,
    credless: true,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: None, invocations: Some(0) },
};
