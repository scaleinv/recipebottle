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
// RBTDRQ — loupe: the veil-leak fixture.
//
// A loupe is the jeweler's glass held to a coin still in the mint — the veiled
// trees haven't been cut away yet. This case used to ride inside pyx (the Trial
// of the Pyx), which the release ceremony re-runs on the STRIPPED candidate for
// its other checks. But the veil case harvests its needle set from the veiled
// trees themselves: post-strip those trees are gone, the census is empty, and an
// empty census used to be tolerated whenever no veiled tree stood — exactly the
// condition the stripped tree satisfies. The case reported green while asserting
// nothing, and the ceremony recorded that degradation in prose instead of fixing
// it.
//
// Loupe is the fix: a fixture of its own, SOURCE-TREE ONLY, a member of no suite,
// invoked by name pre-strip. Pyx keeps its other four cases, which are honest
// invariants on both trees.
//
// A member of no suite, and damnatio's mirror: loupe assays the tree BEFORE the
// cut, damnatio the tree after, and each is red in the other's seat. Loupe first
// landed inside reveille on the reasoning that the ceremony never re-runs it
// post-strip — true of the ceremony, false of the product. The reveille suite
// SHIPS: the delivered tree carries the theurge crate and the suite tabtarget, so
// a consumer's own reveille run IS a post-strip run, and loupe would redden there
// forever, asserting the absence of documents that consumer was never given.
// Suite membership and source-tree-only cannot both hold; the by-name invocation
// is what makes source-tree-only true.
//
// The one behavioral change from the case's time inside pyx: an empty census is
// now a finding UNCONDITIONALLY, not only when a veiled tree happens to still
// stand. The old guard existed solely so the case could survive being re-run
// post-strip; now that it never is, the guard is dead weight that would only
// mask the same extractor-stopped-extracting failure the readme-anchor case
// already guards against by the same means.
//
// The scan machinery (constants, census walk, matcher, self-proof, walker,
// report, finding type) stays in rbtdrq_pyx.rs and is reached from here —
// zrbtdrq_veil_tree_exists also backs damnatio's strip-landed check, so it and
// its neighbors are shared, not loupe's alone.

use std::collections::BTreeSet;
use std::path::Path;

use crate::case;
use crate::rbtdre_engine::{
    rbtdre_Tariff,
    rbtdre_Case,
    rbtdre_Disposition,
    rbtdre_Fixture,
    rbtdre_Verdict,
};
use crate::rbtdrm_manifest::RBTDRM_FIXTURE_LOUPE;
use crate::rbtdrq_pyx::{
    zrbtdrq_census_walk,
    zrbtdrq_report,
    zrbtdrq_root,
    zrbtdrq_veil_scan_text,
    zrbtdrq_veil_self_proof,
    zrbtdrq_walk,
    zrbtdrq_Finding,
    ZRBTDRQ_VEIL_CENSUS_ROOT,
    ZRBTDRQ_VEIL_EXEMPT,
    ZRBTDRQ_VEIL_FILES,
    ZRBTDRQ_VEIL_ROOTS,
    ZRBTDRQ_VEIL_SKIP_DIRS,
};

// ── Case: veil leak ─────────────────────────────────────────

/// No shipping file may name what the distribution withholds — not the veiled
/// tree by path, and not a withheld document by basename. The census is harvested
/// from the tree rather than hand-listed, so a document veiled tomorrow is
/// protected tomorrow, with no table to remember to update.
///
/// This fixture is source-tree only — the release ceremony never re-runs it on
/// the stripped candidate, where the veiled trees are gone and the census would
/// be empty by construction. That is why an empty census is a FINDING outright:
/// there is no stripped-tree re-run left to tolerate it for, so an empty result
/// here can only mean the extractor has quietly stopped extracting.
fn rbtdrq_veil_leak(dir: &Path) -> rbtdre_Verdict {
    let root = match zrbtdrq_root() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };

    let mut findings = zrbtdrq_veil_self_proof();
    let mut inventory = BTreeSet::new();

    for (path, reason) in ZRBTDRQ_VEIL_EXEMPT {
        inventory.insert(format!("{}\texempt: {}", path, reason));
    }

    let census_root = root.join(ZRBTDRQ_VEIL_CENSUS_ROOT);
    let mut census = BTreeSet::new();
    zrbtdrq_census_walk(&census_root, false, &mut census);
    if census.is_empty() {
        findings.push(zrbtdrq_Finding {
            file: ZRBTDRQ_VEIL_CENSUS_ROOT.to_string(),
            line: 0,
            detail: "the census matched no documents — the extractor stopped extracting"
                .to_string(),
        });
    }

    let mut files = Vec::new();
    for sub in ZRBTDRQ_VEIL_ROOTS {
        let path = root.join(sub);
        if path.is_dir() {
            zrbtdrq_walk(&path, ZRBTDRQ_VEIL_SKIP_DIRS, &mut files);
        }
    }

    // A basename naming BOTH a withheld document and a shipping file is not
    // evidence of a leak — it is an ambiguity, and reading it as a leak would
    // redden every honest mention of the shipping file. Drop it from the census.
    for path in &files {
        if let Some(name) = path.file_name().and_then(|s| s.to_str()) {
            census.remove(name);
        }
    }
    for doc in &census {
        inventory.insert(format!("{}\twithheld document", doc));
    }

    for sub in ZRBTDRQ_VEIL_FILES {
        let path = root.join(sub);
        if path.is_file() {
            files.push(path);
        }
    }

    for path in files {
        let rel = crate::rbtdrx_platform::rbtdrx_repo_rel(&root, &path);
        if ZRBTDRQ_VEIL_EXEMPT.iter().any(|(exempt, _)| *exempt == rel) {
            continue;
        }
        inventory.insert(rel.clone());
        let bytes = match std::fs::read(&path) {
            Ok(b) => b,
            Err(_) => continue,
        };
        let text = String::from_utf8_lossy(&bytes);
        zrbtdrq_veil_scan_text(&rel, &text, &census, &mut findings);
    }

    zrbtdrq_report(dir, "veil", &findings, &inventory, "veil-leak violation(s)")
}

// ── Case: hostname leak ─────────────────────────────────────

/// Repo-relative root of the BURN node registry — one subdirectory per operator
/// test machine (the investiture dirname), each carrying a `burn.env` with a
/// `BURN_HOST=` value. Withheld by the perambulation, so it never reaches a
/// candidate; like the veil census, this harvest can only mean anything in the
/// working repository, pre-cut.
const ZRBTDRQ_HOST_CENSUS_ROOT: &str = "rbmm_moorings/rbmn_nodes";

/// Basenames the census walk ignores — the registry's own README, never a node
/// identity.
const ZRBTDRQ_HOST_CENSUS_SKIP_FILES: &[&str] = &["README.md"];

/// Directories skipped while scanning shipping files for a hostname leak. The
/// registry directories themselves carry the very identities the census is
/// harvested from — scanning them would match the census against its own source,
/// not against a leak.
const ZRBTDRQ_HOST_SCAN_SKIP_DIRS: &[&str] =
    &["target", "vov_veiled", "rbmn_nodes", "rbmu_users"];

/// Tokens exempt from the hostname census — an exact string that happens to also
/// be ordinary vocabulary, so treating it as a needle would flag every honest
/// use. Exact token, operator act, same doctrine as `ZRBTDRQ_VEIL_EXEMPT`.
const ZRBTDRQ_HOST_EXEMPT: &[&str] = &[];

/// Harvest operator machine identity from the BURN node registry: every
/// investiture dirname and every `BURN_HOST=` value beneath it. Both name a
/// specific machine.
fn zrbtdrq_host_census_walk(dir: &Path, out: &mut BTreeSet<String>) {
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let name = match path.file_name().and_then(|s| s.to_str()) {
            Some(n) => n.to_string(),
            None => continue,
        };
        if path.is_dir() {
            out.insert(name.clone());
            zrbtdrq_host_census_walk(&path, out);
            continue;
        }
        if ZRBTDRQ_HOST_CENSUS_SKIP_FILES.contains(&name.as_str()) {
            continue;
        }
        let bytes = match std::fs::read(&path) {
            Ok(b) => b,
            Err(_) => continue,
        };
        let text = String::from_utf8_lossy(&bytes);
        for line in text.lines() {
            if let Some(value) = line.strip_prefix("BURN_HOST=") {
                let value = value.trim();
                if !value.is_empty() {
                    out.insert(value.to_string());
                }
            }
        }
    }
}

/// True when `token` appears in `line` on a word boundary — not merely as a
/// substring of a longer, unrelated identifier.
fn zrbtdrq_names_token(line: &str, token: &str) -> bool {
    fn word_char(c: char) -> bool {
        c.is_alphanumeric() || c == '_' || c == '-'
    }

    let bytes = line.as_bytes();
    let mut start = 0;
    while let Some(pos) = line[start..].find(token) {
        let idx = start + pos;
        let before_ok = idx == 0 || !word_char(bytes[idx - 1] as char);
        let after = idx + token.len();
        let after_ok = after >= bytes.len() || !word_char(bytes[after] as char);
        if before_ok && after_ok {
            return true;
        }
        start = idx + 1;
    }
    false
}

/// No shipping file may name an operator's own test machine. The needle set is
/// harvested live from the BURN node registry rather than hand-listed, so a node
/// enrolled tomorrow is protected tomorrow, with no list to remember to update.
///
/// Source-tree only, same as veil leak: the registry is stripped whole at
/// release (Step 10b), so the census is empty on the delivered tree by
/// construction, and an empty census here is a FINDING outright — there is no
/// stripped-tree re-run to tolerate it for.
fn rbtdrq_hostname_leak(dir: &Path) -> rbtdre_Verdict {
    let root = match zrbtdrq_root() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };

    let mut findings = Vec::new();
    let mut inventory = BTreeSet::new();

    let census_root = root.join(ZRBTDRQ_HOST_CENSUS_ROOT);
    let mut census = BTreeSet::new();
    zrbtdrq_host_census_walk(&census_root, &mut census);
    if census.is_empty() {
        findings.push(zrbtdrq_Finding {
            file: ZRBTDRQ_HOST_CENSUS_ROOT.to_string(),
            line: 0,
            detail: "the census matched no operator machine names — the extractor stopped extracting"
                .to_string(),
        });
    }
    for name in ZRBTDRQ_HOST_EXEMPT {
        census.remove(*name);
    }
    for tok in &census {
        inventory.insert(tok.clone());
    }

    let mut files = Vec::new();
    for sub in ZRBTDRQ_VEIL_ROOTS {
        let path = root.join(sub);
        if path.is_dir() {
            zrbtdrq_walk(&path, ZRBTDRQ_HOST_SCAN_SKIP_DIRS, &mut files);
        }
    }
    for sub in ZRBTDRQ_VEIL_FILES {
        let path = root.join(sub);
        if path.is_file() {
            files.push(path);
        }
    }

    for path in files {
        let rel = crate::rbtdrx_platform::rbtdrx_repo_rel(&root, &path);
        let bytes = match std::fs::read(&path) {
            Ok(b) => b,
            Err(_) => continue,
        };
        let text = String::from_utf8_lossy(&bytes);
        for (index, line) in text.lines().enumerate() {
            for tok in &census {
                if zrbtdrq_names_token(line, tok) {
                    findings.push(zrbtdrq_Finding {
                        file: rel.clone(),
                        line: index + 1,
                        detail: format!("names operator machine {}", tok),
                    });
                }
            }
        }
    }

    zrbtdrq_report(dir, "hostname", &findings, &inventory, "operator-hostname leak(s)")
}

// ── Cases and fixture ───────────────────────────────────────

pub static RBTDRQ_CASES_LOUPE: &[rbtdre_Case] = &[
    case!(rbtdrq_veil_leak),
    case!(rbtdrq_hostname_leak),
];

pub static RBTDRQ_FIXTURE_LOUPE: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_LOUPE,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRQ_CASES_LOUPE,
    credless: true,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: None, invocations: Some(0) },
};
