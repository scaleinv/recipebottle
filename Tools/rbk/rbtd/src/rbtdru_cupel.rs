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
// RBTDRU — cupel: BCG command-dependency static-analysis fixture.
//
// A cupel is the assay vessel in which base metals are driven off and the
// noble metal remains. This fixture drives off command-position tokens that
// violate the Bash Console Guide's Command Dependency Discipline, leaving a
// corpus whose external-command surface is exactly the declared dependency
// floor.
//
// This module is the fixture frame: the BCG allowlists that are the single
// source of truth (POSIX floor, RBS0 declared deps, the curated GCB
// container-tool list, the python stdlib import floor, the eviction table),
// the shared finding/result types, the corpus walk, the trace-file reporting,
// and the case/fixture wiring. The per-language scanning lives in two sibling
// modules:
//   - rbtdru_bash   — the command-position lexer and the kit-bash / GCB-bash
//                     classification (two-pass, function-aware).
//   - rbtdru_python — the python cloud-step conformance scan (import floor,
//                     dynamic-import ban, subprocess argv[0] tool floor).
//
// Corpus scope — only the release-relevant kit roots (Tools/buk, Tools/rbk) are
// linted. These are the kits that ship in the recipe-bottle consumer release and
// are authored under BCG; other kits under Tools/ are separate products never
// written to the discipline, and holding them to it would surface noise, not
// defects. A kit adopts the discipline by being added to ZRBTDRU_KIT_ROOTS —
// opt-in, never by default. Within the lint target, ABANDONED* and FUTURE*
// directories are excluded (dead / not-yet-live); the pass-1 function universe
// excludes only ABANDONED* (FUTURE* code is present and sourceable, so its
// definitions stay visible).
//
// Three cases, one per scan surface: kit-bash and GCB-bash (rbtdru_bash) and
// the python cloud steps (rbtdru_python).

use std::collections::BTreeSet;
use std::path::{
    Path,
    PathBuf,
};

use crate::case;
use crate::rbtdre_engine::{
    rbtdre_Tariff,
    rbtdre_Case,
    rbtdre_Disposition,
    rbtdre_Fixture,
    rbtdre_Verdict,
};
use crate::rbtdrm_manifest::RBTDRM_FIXTURE_CUPEL;
use crate::rbtdru_bash::zrbtdru_scan_domain;
use crate::rbtdru_python::zrbtdru_scan_python;

// ── Corpus location ─────────────────────────────────────────

/// Repo-relative directory holding all kit trees, walked per release kit root.
pub(crate) const ZRBTDRU_TOOLS_SUBDIR: &str = "Tools";

/// Release-relevant kit roots under Tools/, each walked recursively. Only these
/// kits ship in the recipe-bottle consumer release and are authored under BCG,
/// so only these are held to the discipline. Names are directory basenames under
/// Tools/; adding one opts that kit into the lint deliberately.
pub(crate) const ZRBTDRU_KIT_ROOTS: &[&str] = &["buk", "rbk"];

/// Extension (no dot) selecting bash files from the corpus walk.
pub(crate) const ZRBTDRU_SH_EXT: &str = "sh";

/// Extension (no dot) selecting python cloud-step files. Python is scanned
/// only under the GCB job directories (rbgj*) — other python in the kit roots
/// (e.g. in-bottle attack scripts) is not cloud-step surface.
pub(crate) const ZRBTDRU_PY_EXT: &str = "py";

/// Directory-name prefix marking the Google Cloud Build job family. Any bash
/// under a `Tools/rbk/rbgj*` directory is GCB-bash. Partitioning by this prefix
/// — rather than a hardcoded directory list — keeps the partition drift-proof
/// as new rbgj* job groups are added.
pub(crate) const ZRBTDRU_GCB_DIR_PREFIX: &str = "rbgj";

/// Dead-code directory prefixes excluded from the function-visibility universe.
/// `ABANDONED*` is retained for reference but unbuilt and unsourceable, so its
/// definitions must NOT clear a live command-position token — a live reference
/// to a dead function is a defect the lint should still surface.
pub(crate) const ZRBTDRU_UNIVERSE_EXCLUDED_DIR_PREFIXES: &[&str] = &["ABANDONED"];

/// Lint-target directory prefixes — additionally exclude `FUTURE*`. Not-yet-live
/// code is present on disk (so its functions stay visible for pass-1 collection,
/// resolving live code that sources it) but is not itself held to the discipline.
pub(crate) const ZRBTDRU_LINT_EXCLUDED_DIR_PREFIXES: &[&str] = &["ABANDONED", "FUTURE"];

/// Filename affixes for the per-domain trace files written into the case dir:
/// `cupel-<label>-findings.txt` (violations) and `cupel-<label>-inventory.txt`
/// (the full external-command surface — every command-position token that is
/// neither a bash builtin nor a local function, allowed or not). The inventory
/// is the empirical basis for curating an allowlist; it is always emitted,
/// independent of pass/fail.
pub(crate) const ZRBTDRU_TRACE_PREFIX: &str = "cupel-";
pub(crate) const ZRBTDRU_FINDINGS_SUFFIX: &str = "-findings.txt";
pub(crate) const ZRBTDRU_INVENTORY_SUFFIX: &str = "-inventory.txt";

/// Domain labels — name the findings trace and the verdict message per domain.
pub(crate) const ZRBTDRU_LABEL_KIT: &str = "kit";
pub(crate) const ZRBTDRU_LABEL_GCB: &str = "gcb";
pub(crate) const ZRBTDRU_LABEL_PY: &str = "py";

// ── BCG allowlists (source of truth: BCG + RBS0 Dependency Inventory) ──

/// POSIX Utility Allowlist — the irreducible external-command floor. No bash
/// 3.2 builtin replacement; mandated by POSIX wherever bash runs.
pub(crate) const ZRBTDRU_POSIX_FLOOR: &[&str] = &[
    "chmod", "cp", "date", "find", "mkdir", "mktemp", "mv", "rm", "sed",
    "sleep", "sort", "stty",
];

/// Declared dependencies — the RBS0 Dependency Inventory (consumer + developer
/// + specialized). A cost accepted by every consumer; each appears in RBS0 with
/// its justification.
pub(crate) const ZRBTDRU_DECLARED_DEPS: &[&str] = &[
    "bash", "cargo", "curl", "docker", "git", "jq", "openssl", "podman", "scp",
    "shellcheck", "ssh", "ssh-keygen", "stat", "tar", "tee", "timeout",
    // Optional probe-and-skip clipboard tier (one RBS0 inventory row): probed
    // by buc_clipboard_copy_predicate, never required on any host.
    "clip.exe", "pbcopy", "wl-copy", "xclip",
];

/// Curated GCB container-tool allowlist — the external commands present in the
/// controlled builder images (alpine/docker→busybox, gcloud→Debian,
/// gcrane:debug→busybox, the wsl-underpin fetch step→Debian) that GCB-bash
/// legitimately uses, enumerated empirically via the cupel inventory over
/// Tools/rbk/rbgj*. GCB-allowed = POSIX floor (universal in every container) ∪
/// this list. It deliberately does NOT inherit the kit declared deps: membership
/// is per-container-presence, not portability. Each entry is empirically present
/// in the controlled builder that uses it — openssl/gpg/apt-get on the Debian
/// wsl-underpin fetch builder, gcrane/tar in gcrane:debug busybox — while jq is
/// still absent everywhere and the rbgj* scripts avoid it by hand ("no jq
/// dependency — use grep+cut"), so a GCB script reaching for a tool outside its
/// controlled container still fails — a supply-chain conformance check, not
/// merely a portability one.
///
/// This list is the single tool floor for BOTH step languages: bash
/// command-position tokens and python `subprocess` argv[0] literals are
/// classified against the same membership (one floor, two languages).
pub(crate) const ZRBTDRU_GCB_ALLOWED: &[&str] = &[
    "apt-get", "awk", "cat", "curl", "cut", "docker",
    // gcloud: rbgjv02's SLSA provenance describe subprocess-runs it in the
    // cloud-sdk builder, where it is native.
    "gcloud",
    "gcrane", "gpg",
    "grep", "head", "ls", "openssl", "sha256sum", "shasum",
    "tar", "tr", "wget",
];

/// Python stdlib import floor — the module roots a python cloud step may
/// import, enumerated empirically as the union over Tools/rbk/rbgj*/*.py.
/// This constant is the floor's authoritative home (CBG CBp_102 points here,
/// never restates the list). Stdlib-only is the criterion: a third-party
/// import binds a step to the floating builder's unpinned pip set — the same
/// drift class the bash allowlist exists to stop. `subprocess` is sanctioned
/// only because its argv[0] literals are scanned against the GCB tool floor;
/// dynamic-import surface (importlib / __import__ / exec / eval) is banned
/// outright in the scan, never via this list.
pub(crate) const ZRBTDRU_PY_IMPORT_ALLOWED: &[&str] = &[
    "base64", "datetime", "io", "json", "os", "re", "socket", "subprocess",
    "sys", "tarfile", "time", "urllib",
];

/// Bash builtins and command-position keywords that name no external command —
/// never flagged. Keywords with control-flow semantics ([[, ]], the loop/branch
/// words) are handled structurally in the lexer; the rest live here so that a
/// builtin reaching classification (echo, printf, read, local, …) is cleared.
pub(crate) const ZRBTDRU_BUILTINS: &[&str] = &[
    ":", ".", "[", "[[", "]", "]]", "alias", "bg", "bind", "break", "builtin",
    "caller", "cd", "command", "compgen", "complete", "compopt", "continue",
    "coproc", "declare", "dirs", "disown", "echo", "enable", "eval", "exec",
    "exit", "export", "false", "fc", "fg", "getopts", "hash", "help", "history",
    "jobs", "kill", "let", "local", "logout", "mapfile", "popd", "printf",
    "pushd", "pwd", "read", "readarray", "readonly", "return", "set", "shift",
    "shopt", "source", "suspend", "test", "times", "trap", "true", "type",
    "typeset", "ulimit", "umask", "unalias", "unset", "wait",
];

/// One evicted command and the BCG-prescribed replacement reported in its
/// stead. Verbatim from BCG's "Evicted Utilities" table.
pub(crate) struct zrbtdru_Eviction {
    pub(crate) command: &'static str,
    pub(crate) replacement: &'static str,
}

/// The enforced eviction table. In kit-bash these fail with the replacement; in
/// GCB-bash they are tolerated (the cloud-sdk image carries them and the
/// portability concern is moot).
pub(crate) const ZRBTDRU_EVICTIONS: &[zrbtdru_Eviction] = &[
    zrbtdru_Eviction { command: "awk", replacement: "read with IFS + parameter expansion" },
    zrbtdru_Eviction { command: "base64", replacement: "openssl enc -base64" },
    zrbtdru_Eviction { command: "cut", replacement: "read with IFS + parameter expansion" },
    zrbtdru_Eviction { command: "grep", replacement: "case / test / [[ =~ ]]" },
    zrbtdru_Eviction { command: "head", replacement: "read -r" },
    zrbtdru_Eviction { command: "ls", replacement: "glob expansion (for f in dir/*)" },
    zrbtdru_Eviction { command: "sha256sum", replacement: "openssl dgst -sha256 -r" },
    zrbtdru_Eviction { command: "shasum", replacement: "openssl dgst -sha256 -r" },
    zrbtdru_Eviction { command: "tr", replacement: "${var//old/new} parameter expansion" },
    zrbtdru_Eviction { command: "wc", replacement: "${#var} / ${#arr[@]}" },
];

// ── Domain and findings ─────────────────────────────────────

/// Execution-environment partition controlling allowlist strictness.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub(crate) enum zrbtdru_Domain {
    Kit,
    Gcb,
}

/// A single command-discipline violation: where it is and why it failed.
#[derive(Clone, Debug)]
pub(crate) struct zrbtdru_Finding {
    pub(crate) file: String,
    pub(crate) line: usize,
    pub(crate) command: String,
    pub(crate) detail: String,
}

/// One scan's result: violations, plus the full external-command inventory
/// (base command names, deduplicated and sorted) — the empirical basis for
/// curating an allowlist.
pub(crate) struct zrbtdru_ScanResult {
    pub(crate) findings: Vec<zrbtdru_Finding>,
    pub(crate) inventory: BTreeSet<String>,
}

// ── Corpus walk ─────────────────────────────────────────────

/// Recursively collect every file with extension `ext` under `dir` into
/// `out`, skipping any subdirectory whose basename begins with one of
/// `excluded_prefixes`.
pub(crate) fn zrbtdru_walk_ext(dir: &Path, ext: &str, excluded_prefixes: &[&str], out: &mut Vec<PathBuf>) {
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            let excluded = path
                .file_name()
                .and_then(|s| s.to_str())
                .map(|name| {
                    excluded_prefixes
                        .iter()
                        .any(|prefix| name.starts_with(prefix))
                })
                .unwrap_or(false);
            if excluded {
                continue;
            }
            zrbtdru_walk_ext(&path, ext, excluded_prefixes, out);
        } else if path.extension().and_then(|e| e.to_str()) == Some(ext) {
            out.push(path);
        }
    }
}

/// True when `path` lies under a Google Cloud Build job directory (any path
/// component beginning with the rbgj prefix).
pub(crate) fn zrbtdru_is_gcb(path: &Path) -> bool {
    path.components().any(|comp| {
        comp.as_os_str()
            .to_str()
            .map(|s| s.starts_with(ZRBTDRU_GCB_DIR_PREFIX))
            .unwrap_or(false)
    })
}

// ── Reporting ───────────────────────────────────────────────

/// Render findings as a stable one-per-line report.
fn zrbtdru_render(findings: &[zrbtdru_Finding]) -> String {
    let mut report = String::new();
    for f in findings {
        report.push_str(&format!("{}:{}: {} — {}\n", f.file, f.line, f.command, f.detail));
    }
    report
}

/// Persist a scan's findings and inventory traces into the case dir and turn
/// the result into a verdict. `what` names the violation class in the fail
/// message (e.g. "BCG command-discipline violation(s) in kit-bash").
fn zrbtdru_report(dir: &Path, label: &str, scan: &zrbtdru_ScanResult, what: &str) -> rbtdre_Verdict {
    let findings = &scan.findings;
    let report = zrbtdru_render(findings);
    let findings_name = format!("{}{}{}", ZRBTDRU_TRACE_PREFIX, label, ZRBTDRU_FINDINGS_SUFFIX);
    let _ = std::fs::write(dir.join(findings_name), &report);

    let mut inventory_report = String::new();
    for cmd in &scan.inventory {
        inventory_report.push_str(cmd);
        inventory_report.push('\n');
    }
    let inventory_name = format!("{}{}{}", ZRBTDRU_TRACE_PREFIX, label, ZRBTDRU_INVENTORY_SUFFIX);
    let _ = std::fs::write(dir.join(inventory_name), &inventory_report);

    if findings.is_empty() {
        rbtdre_Verdict::Pass
    } else {
        rbtdre_Verdict::Fail(format!("{} {}:\n{}", findings.len(), what, report))
    }
}

/// Drive one bash domain's scan, persist its traces, and fail the verdict
/// when any violation remains.
fn zrbtdru_run_domain(dir: &Path, domain: zrbtdru_Domain, label: &str) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };
    let tools = root.join(ZRBTDRU_TOOLS_SUBDIR);
    let scan = match zrbtdru_scan_domain(&tools, domain) {
        Ok(s) => s,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };
    let what = format!("BCG command-discipline violation(s) in {}-bash", label);
    zrbtdru_report(dir, label, &scan, &what)
}

/// Drive the python cloud-step scan, persist its traces, and fail the verdict
/// when any violation remains.
fn zrbtdru_run_python(dir: &Path) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };
    let tools = root.join(ZRBTDRU_TOOLS_SUBDIR);
    let scan = match zrbtdru_scan_python(&tools) {
        Ok(s) => s,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };
    zrbtdru_report(
        dir,
        ZRBTDRU_LABEL_PY,
        &scan,
        "python step-conformance violation(s)",
    )
}

// ── Cases and fixture ───────────────────────────────────────

fn rbtdru_kit_bash(dir: &Path) -> rbtdre_Verdict {
    zrbtdru_run_domain(dir, zrbtdru_Domain::Kit, ZRBTDRU_LABEL_KIT)
}

fn rbtdru_gcb_bash(dir: &Path) -> rbtdre_Verdict {
    zrbtdru_run_domain(dir, zrbtdru_Domain::Gcb, ZRBTDRU_LABEL_GCB)
}

fn rbtdru_gcb_python(dir: &Path) -> rbtdre_Verdict {
    zrbtdru_run_python(dir)
}

pub static RBTDRU_CASES_CUPEL: &[rbtdre_Case] = &[
    case!(rbtdru_kit_bash),
    case!(rbtdru_gcb_bash),
    case!(rbtdru_gcb_python),
];

pub static RBTDRU_FIXTURE_CUPEL: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_CUPEL,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRU_CASES_CUPEL,
    credless: true,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: None, invocations: Some(0) },
};
