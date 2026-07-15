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
// RBTDRQ — pyx: the release-hygiene tree-invariant fixture.
//
// The Trial of the Pyx is the ceremonial assay in which sample coins are drawn
// from a sealed box and tested for purity before the coinage is let out. This
// fixture is that trial for a release candidate: the checks a maintainer would
// otherwise perform by hand before letting a tree out to the upstream, run as
// standing reveille cases so the tree is continuously fit to cut. Sibling of the
// cupel fixture in both asterism and method — cupellation is the assay performed
// in the trial itself — and in the pattern of a hand-curated allowlist as the
// single source of truth.
//
// Every case here is a DETERMINISTIC TREE-INVARIANT: same tree, same verdict.
// The fixture reads committed files only. It runs no tool, opens no socket,
// consults no live service. That is what admits it to reveille (credless, no
// external dependency) and what lets the release ceremony re-run it on the
// STRIPPED candidate tree, where the veiled specs and the non-shipping kits are
// gone. Every corpus root below is therefore existence-tolerant: a root absent
// from the stripped tree is skipped, not failed.
//
// The veil-leak case that once lived here is evicted to its own fixture, loupe
// (rbtdrq_loupe.rs): it reads the tree in two roles at once, assaying the
// SHIPPING files while harvesting its needle set from the WITHHELD ones, and
// that needs a still-standing veiled tree to mean anything — a stripped-tree
// re-run would go vacuously green. The scan machinery it reaches (constants,
// census walk, matcher, self-proof) stays here because zrbtdrq_veil_tree_exists
// also backs damnatio's strip-landed check.
//
// The known-vulnerability advisory audit is deliberately NOT here. Its verdict
// moves with a live advisory database while the tree stands still, so it is not
// a tree-invariant and cannot be a fixture without making reveille's greenness a
// function of the network. It remains a ceremony step, owned by the operator at
// cut time.
//
// The crate-license case reads Cargo.lock, NOT `cargo metadata`. Resolving the
// dependency graph pulls manifests for every target platform, including the
// Windows- and Redox-only crates a macOS or Linux build never fetches; offline
// it fails outright, and `--filter-platform` makes the verdict a function of the
// host rather than the tree. Cargo.lock is a committed file naming the exact
// resolved graph on every platform at once, so the check becomes a pure
// tree-invariant reading with no external tool at all.
//
// Checker proves itself (ACG move discipline; the rbtdrn_conformance precedent).
// The secret-shape matcher is exercised against known in-memory positives and
// negatives before its verdict on the live tree is trusted, and the license
// allowlist is proved internally consistent — every vetted expression drawn from
// the approved set — so a typo in the table cannot quietly widen it. No case
// plants a real violation in the repo.

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
use crate::rbtdrm_manifest::RBTDRM_FIXTURE_PYX;

// ── Crate-license allowlist ─────────────────────────────────

/// Repo-relative lockfile naming the exact resolved dependency graph of the one
/// Rust crate that ships in the consumer release. The other crates under Tools/
/// are stripped from the candidate, so their graphs are not release surface.
pub(crate) const ZRBTDRQ_LOCKFILE: &str = "Tools/rbk/rbtd/Cargo.lock";

/// The root package named by ZRBTDRQ_LOCKFILE — this project's own crate, which
/// declares no `license` field and is covered by the repo-root LICENSE. Skipped
/// when the lock's package set is checked against the vendored allowlist.
pub(crate) const ZRBTDRQ_ROOT_CRATE: &str = "rbtd";

/// SPDX expressions vetted as acceptable for a dependency of an Apache-2.0
/// release. Every expression admits at least one permissive license under which
/// the dependency may be taken; none is copyleft, and none imposes a term the
/// Apache-2.0 distribution cannot satisfy. An expression absent from this set is
/// a deliberate rejection: adding one is an operator act, not a maintenance
/// chore, because it widens what may enter the release.
///
/// Exact-string membership, not SPDX parsing. Two expressions naming the same
/// disjunction in different order ("MIT OR Apache-2.0" versus "Apache-2.0 OR
/// MIT") are distinct entries here on purpose — a parser would be a second
/// source of truth about license meaning, and its bugs would silently admit what
/// this set exists to gate. The cost is a few near-duplicate rows.
pub(crate) const ZRBTDRQ_ALLOWED_LICENSES: &[&str] = &[
    "(MIT OR Apache-2.0) AND Unicode-3.0",
    "0BSD OR MIT OR Apache-2.0",
    "Apache-2.0",
    "Apache-2.0 OR MIT",
    "Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT",
    "BSD-2-Clause OR Apache-2.0 OR MIT",
    "BSD-3-Clause OR Apache-2.0",
    "BSL-1.0",
    "MIT",
    "MIT OR Apache-2.0",
    "MIT OR Apache-2.0 OR Zlib",
    "MIT OR Zlib OR Apache-2.0",
    "MIT/Apache-2.0",
    "Unlicense OR MIT",
    "Zlib OR Apache-2.0 OR MIT",
];

/// Every crate the lockfile may name, with the SPDX expression vetted for it.
/// The lock's package set must be a subset of these names: a crate absent here
/// has never been license-vetted, and the case fails until an operator vets it
/// and adds the row.
///
/// Keyed by crate NAME, not name+version. A version bump does not redden the
/// fixture; only a NEW dependency does. The residual risk this accepts is
/// relicensing — an existing crate changing its terms under a version bump —
/// judged rare against the certainty that a version-keyed table would redden on
/// every routine bump and be rubber-stamped, which is worse than not having it.
/// The vetted expression on each row is the license as declared by that crate's
/// manifest at vetting time.
pub(crate) const ZRBTDRQ_CRATE_LICENSES: &[(&str, &str)] = &[
    ("adler2", "0BSD OR MIT OR Apache-2.0"),
    ("arboard", "MIT OR Apache-2.0"),
    ("autocfg", "Apache-2.0 OR MIT"),
    ("bitflags", "MIT OR Apache-2.0"),
    ("block-buffer", "MIT OR Apache-2.0"),
    ("bytemuck", "Zlib OR Apache-2.0 OR MIT"),
    ("byteorder", "Unlicense OR MIT"),
    ("byteorder-lite", "Unlicense OR MIT"),
    ("bytes", "MIT"),
    ("cfg-if", "MIT OR Apache-2.0"),
    ("clipboard-win", "BSL-1.0"),
    ("cpufeatures", "MIT OR Apache-2.0"),
    ("crc32fast", "MIT OR Apache-2.0"),
    ("crunchy", "MIT"),
    ("crypto-common", "MIT OR Apache-2.0"),
    ("data-encoding", "MIT"),
    ("digest", "MIT OR Apache-2.0"),
    ("dispatch2", "Zlib OR Apache-2.0 OR MIT"),
    ("errno", "MIT OR Apache-2.0"),
    ("error-code", "BSL-1.0"),
    ("fax", "MIT"),
    ("fdeflate", "MIT OR Apache-2.0"),
    ("flate2", "MIT OR Apache-2.0"),
    ("generic-array", "MIT"),
    ("gethostname", "Apache-2.0"),
    ("getrandom", "MIT OR Apache-2.0"),
    ("half", "MIT OR Apache-2.0"),
    ("http", "MIT OR Apache-2.0"),
    ("httparse", "MIT OR Apache-2.0"),
    ("image", "MIT OR Apache-2.0"),
    ("itoa", "MIT OR Apache-2.0"),
    ("libc", "MIT OR Apache-2.0"),
    ("linux-raw-sys", "Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT"),
    ("lock_api", "MIT OR Apache-2.0"),
    ("log", "MIT OR Apache-2.0"),
    ("miniz_oxide", "MIT OR Zlib OR Apache-2.0"),
    ("moxcms", "BSD-3-Clause OR Apache-2.0"),
    ("num-traits", "MIT OR Apache-2.0"),
    ("objc2", "MIT"),
    ("objc2-app-kit", "Zlib OR Apache-2.0 OR MIT"),
    ("objc2-core-foundation", "Zlib OR Apache-2.0 OR MIT"),
    ("objc2-core-graphics", "Zlib OR Apache-2.0 OR MIT"),
    ("objc2-encode", "MIT"),
    ("objc2-foundation", "MIT"),
    ("objc2-io-surface", "Zlib OR Apache-2.0 OR MIT"),
    ("parking_lot", "MIT OR Apache-2.0"),
    ("parking_lot_core", "MIT OR Apache-2.0"),
    ("percent-encoding", "MIT OR Apache-2.0"),
    ("png", "MIT OR Apache-2.0"),
    ("ppv-lite86", "MIT OR Apache-2.0"),
    ("proc-macro2", "MIT OR Apache-2.0"),
    ("pxfm", "BSD-3-Clause OR Apache-2.0"),
    ("quick-error", "MIT/Apache-2.0"),
    ("quote", "MIT OR Apache-2.0"),
    ("rand", "MIT OR Apache-2.0"),
    ("rand_chacha", "MIT OR Apache-2.0"),
    ("rand_core", "MIT OR Apache-2.0"),
    ("redox_syscall", "MIT"),
    ("rustix", "Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT"),
    ("scopeguard", "MIT OR Apache-2.0"),
    ("sha1", "MIT OR Apache-2.0"),
    ("simd-adler32", "MIT"),
    ("smallvec", "MIT OR Apache-2.0"),
    ("syn", "MIT OR Apache-2.0"),
    ("thiserror", "MIT OR Apache-2.0"),
    ("thiserror-impl", "MIT OR Apache-2.0"),
    ("tiff", "MIT"),
    ("tungstenite", "MIT OR Apache-2.0"),
    ("typenum", "MIT OR Apache-2.0"),
    ("unicode-ident", "(MIT OR Apache-2.0) AND Unicode-3.0"),
    ("utf-8", "MIT OR Apache-2.0"),
    ("version_check", "MIT/Apache-2.0"),
    ("wasi", "Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT"),
    ("weezl", "MIT OR Apache-2.0"),
    ("windows-link", "MIT OR Apache-2.0"),
    ("windows-sys", "MIT OR Apache-2.0"),
    ("windows-targets", "MIT OR Apache-2.0"),
    ("windows_aarch64_gnullvm", "MIT OR Apache-2.0"),
    ("windows_aarch64_msvc", "MIT OR Apache-2.0"),
    ("windows_i686_gnu", "MIT OR Apache-2.0"),
    ("windows_i686_gnullvm", "MIT OR Apache-2.0"),
    ("windows_i686_msvc", "MIT OR Apache-2.0"),
    ("windows_x86_64_gnu", "MIT OR Apache-2.0"),
    ("windows_x86_64_gnullvm", "MIT OR Apache-2.0"),
    ("windows_x86_64_msvc", "MIT OR Apache-2.0"),
    ("x11rb", "MIT OR Apache-2.0"),
    ("x11rb-protocol", "MIT OR Apache-2.0"),
    ("zerocopy", "BSD-2-Clause OR Apache-2.0 OR MIT"),
    ("zerocopy-derive", "BSD-2-Clause OR Apache-2.0 OR MIT"),
    ("zune-core", "MIT OR Apache-2.0 OR Zlib"),
    ("zune-jpeg", "MIT OR Apache-2.0 OR Zlib"),
];

// ── Root LICENSE ────────────────────────────────────────────

/// Repo-relative path of the license the distribution is made under.
pub(crate) const ZRBTDRQ_LICENSE_FILE: &str = "LICENSE";

/// Phrases the root LICENSE must carry. A LICENSE file that exists but names
/// some other license is the failure this looks for — an empty or truncated file
/// passes a mere existence check and ships a distribution with no terms.
pub(crate) const ZRBTDRQ_LICENSE_PHRASES: &[&str] = &["Apache License", "Version 2.0"];

// ── Secret-shape scan ───────────────────────────────────────

/// Repo-relative roots walked for secret shapes — the trees that ship to a
/// consumer. Each is existence-tolerant: `Study/` and `Memos/` are not here
/// because they never ship, and `rbmm_moorings/` is here because the operator's
/// regime and vessel context files are exactly where a credential would land by
/// accident.
pub(crate) const ZRBTDRQ_SECRET_ROOTS: &[&str] = &["Tools/buk", "Tools/rbk", "tt", "rbmm_moorings"];

/// Repo-relative single files added to the secret-scan corpus alongside the
/// roots above — the consumer-facing documents at the repo root.
pub(crate) const ZRBTDRQ_SECRET_FILES: &[&str] = &["README.md", "RELEASE.md"];

/// This module's own source. Named as a constant because it is both an exempt
/// path below and the file a table-consistency finding points at.
pub(crate) const ZRBTDRQ_SELF_EXEMPT: &str = "Tools/rbk/rbtd/src/rbtdrq_pyx.rs";

/// Repo-relative paths exempt from the secret-shape scan, each with the reason
/// it is exempt. An exemption is an OPERATOR ACT, not a maintenance chore: every
/// row here is a place the scan has been told to stay silent, so a row added to
/// quiet a finding rather than to record a judgment is how this check dies. The
/// list is exact-path, never a prefix — a directory exemption would silently
/// cover files that do not yet exist.
pub(crate) const ZRBTDRQ_EXEMPT: &[(&str, &str)] = &[
    // The shape table necessarily spells the prefixes it hunts for, and the PEM
    // shape is a bare literal that matches itself. Safe precisely because the
    // matcher is proved against in-memory positives and negatives in its own
    // case: the live-tree verdict rests on a matcher checked elsewhere, not on a
    // file that excuses itself.
    (ZRBTDRQ_SELF_EXEMPT, "the shape table spells the shapes it hunts"),
    // Caged test scaffolding, committed deliberately (993985c91). This key signs
    // RFC 7523 assertions to the fdkyclk Keycloak realm, whose baked
    // publicKeySignatureVerifier is this key's public half. It grants authority
    // over nothing but an ephemeral local container, and the realm cannot be
    // exercised without it. A real credential never belongs beside it.
    (
        "rbmm_moorings/fdkyclk/fdkyclk-asserter-key.pem",
        "caged asserter key for the local Keycloak test realm; no live authority",
    ),
];

/// Directory basenames skipped by the secret-shape walk. Build output is
/// untracked, never ships, and holds enough compiled bytes that walking it turns
/// a sub-second fixture into a multi-minute one.
pub(crate) const ZRBTDRQ_SKIP_DIRS: &[&str] = &["target"];

/// File extensions skipped by the secret-shape walk — compiled, compressed, or
/// raster payloads in which a token shape cannot be authored by hand and a
/// byte-coincidence would be a false positive.
pub(crate) const ZRBTDRQ_SKIP_EXTS: &[&str] = &[
    "gz", "ico", "jpg", "jpeg", "lock", "png", "tar", "tgz", "webp", "zip",
];

/// Per-file byte cap for the secret-shape walk. A file above this size is not a
/// hand-authored source or config and reading it whole would make a fast fixture
/// slow.
pub(crate) const ZRBTDRQ_SIZE_CAP: u64 = 1_048_576;

/// The character class of a credential body: what may follow a shape's prefix
/// and still be part of the same token.
#[derive(Copy, Clone, PartialEq, Eq, Debug)]
pub(crate) enum zrbtdrq_Body {
    /// No body requirement — the prefix literal alone is the finding.
    Literal,
    /// Base64url-ish: the alphabet of nearly every bearer token in circulation.
    Token,
    /// Uppercase letters and digits.
    Shout,
}

/// One credential shape: a literal prefix, the class its body must be drawn
/// from, and how long that body must run before the match is credited. The
/// body-length floor is what keeps a shape from firing on prose that merely
/// mentions the prefix.
pub(crate) struct zrbtdrq_Shape {
    pub(crate) label: &'static str,
    pub(crate) prefix: &'static str,
    pub(crate) body: zrbtdrq_Body,
    pub(crate) body_min: usize,
}

/// The hunted shapes. Deliberately NOT a gitleaks reimplementation: this is a
/// short, curated set of high-signal token forms whose presence in a shipping
/// tree is never innocent. Entropy heuristics and generic `password =` matching
/// are excluded on purpose — they are the false-positive engine that trains an
/// operator to wave a scanner through, which is worse than not scanning.
///
/// The PEM shape matches the closing half of the armor line, so it fires on both
/// the BEGIN and END markers of any private-key block while a PUBLIC key block —
/// which is not a secret — goes untouched.
pub(crate) const ZRBTDRQ_SHAPES: &[zrbtdrq_Shape] = &[
    zrbtdrq_Shape { label: "PEM private key block",      prefix: "PRIVATE KEY-----", body: zrbtdrq_Body::Literal, body_min: 0  },
    zrbtdrq_Shape { label: "service-account private key", prefix: "\"private_key\":", body: zrbtdrq_Body::Literal, body_min: 0  },
    zrbtdrq_Shape { label: "Google API key",             prefix: "AIza",             body: zrbtdrq_Body::Token,   body_min: 35 },
    zrbtdrq_Shape { label: "Google OAuth client secret", prefix: "GOCSPX-",          body: zrbtdrq_Body::Token,   body_min: 20 },
    zrbtdrq_Shape { label: "Google OAuth access token",  prefix: "ya29.",            body: zrbtdrq_Body::Token,   body_min: 20 },
    zrbtdrq_Shape { label: "AWS access key id",          prefix: "AKIA",             body: zrbtdrq_Body::Shout,   body_min: 16 },
    zrbtdrq_Shape { label: "GitHub personal token",      prefix: "ghp_",             body: zrbtdrq_Body::Token,   body_min: 36 },
    zrbtdrq_Shape { label: "GitHub fine-grained token",  prefix: "github_pat_",      body: zrbtdrq_Body::Token,   body_min: 20 },
    zrbtdrq_Shape { label: "Slack bot token",            prefix: "xoxb-",            body: zrbtdrq_Body::Token,   body_min: 10 },
    zrbtdrq_Shape { label: "Anthropic API key",          prefix: "sk-ant-",          body: zrbtdrq_Body::Token,   body_min: 20 },
];

// ── Veil scan ───────────────────────────────────────────────

/// The directory basename that marks a tree as withheld from the distribution.
/// It is both the needle the scan hunts in shipping files and the directory the
/// scan refuses to walk.
pub(crate) const ZRBTDRQ_VEIL_DIR: &str = "vov_veiled";

/// Directories the veil walk never descends: build output, and the veiled trees
/// themselves — a veiled file may name its veiled siblings freely, that is what
/// being veiled means.
pub(crate) const ZRBTDRQ_VEIL_SKIP_DIRS: &[&str] = &["target", ZRBTDRQ_VEIL_DIR];

/// Repo-relative roots walked by the veil scan — the shipping tree. `diagrams/`
/// rides here and not in the secret roots because a rendered diagram displays its
/// source text to a reader: a withheld name in a `.puml` title is baked into the
/// committed `.svg` and is read by a consumer who never greps anything.
pub(crate) const ZRBTDRQ_VEIL_ROOTS: &[&str] =
    &["Tools/buk", "Tools/rbk", "tt", "rbmm_moorings", "diagrams"];

/// Repo-relative single files added to the veil corpus.
///
/// The repo-root `CLAUDE.md` is deliberately ABSENT — this scan's census is
/// harvested from the veiled trees, so it only runs where they still stand (the
/// maintainer tree), and there root CLAUDE.md is the maintainer's own context,
/// naming withheld material on purpose. In the candidate, root CLAUDE.md carries
/// the consumer template's bytes: expede transposes them from the path named
/// below onto it, byte-asserted, between materialization and the commit — never
/// a copy this ceremony performs. Scanning the template at its veiled home here
/// covers that content pre-cut; damnatio's rbtdrq_veil_stripped covers the
/// candidate's actual root CLAUDE.md directly, once no veiled tree stands to
/// census from.
pub(crate) const ZRBTDRQ_VEIL_FILES: &[&str] =
    &["README.md", "Tools/rbk/vov_veiled/CLAUDE.consumer.md"];

/// Repo-relative root under which veiled trees are hunted to build the census.
pub(crate) const ZRBTDRQ_VEIL_CENSUS_ROOT: &str = "Tools";

/// Extensions of the withheld documents whose BASENAMES may not be named by a
/// shipping file. Documents only: a withheld `.sh` is reachable in prose only by
/// its path, which the veil-directory needle already catches, while a bare
/// document basename (`SOMEDOC-Topic.adoc`) is the citation form that slips past
/// a path check.
pub(crate) const ZRBTDRQ_VEIL_DOC_EXTS: &[&str] = &["adoc", "md"];

/// Substrings a line must carry before it can possibly name a withheld document.
/// A pure speed gate over the census loop, and exactly the extensions above.
pub(crate) const ZRBTDRQ_VEIL_DOC_MARKS: &[&str] = &[".adoc", ".md"];

/// Repo-relative paths exempt from the veil scan, each with the reason. Same
/// doctrine as the secret-scan exemptions: an exemption is an OPERATOR ACT, exact
/// path, never a prefix. Every row must address the veiled tree to do its work —
/// a scan spelling its own needles, a table naming what it hunts, the census whose
/// charter is to judge every withheld tree by name, or the delivery tool that
/// transposes a withheld template onto the candidate.
pub(crate) const ZRBTDRQ_VEIL_EXEMPT: &[(&str, &str)] = &[
    (ZRBTDRQ_SELF_EXEMPT, "the veil scan spells the token and the corpus paths it hunts"),
    (
        "Tools/rbk/rbtd/src/rbtdrn_conformance.rs",
        "its curl-scan exemption table addresses a withheld tree by path; dead in the stripped tree, where that tree is gone",
    ),
    (
        "Tools/rbk/rbtd/src/rbtdrq_loupe.rs",
        "the hostname-leak case's scan skip-dir list spells the veiled-dir literal it must not descend into",
    ),
    (
        "Tools/rbk/rblm_perambulation.sh",
        "the census names every withheld tree by charter, and is itself withheld — no candidate carries it",
    ),
    (
        "Tools/rbk/rbtd/src/rbtdrq_perambulation.rs",
        "its planted-leak table addresses a withheld tree by path to prove the sweep catches one; dead in the stripped tree, where that tree is gone",
    ),
    (
        "Tools/rbk/rblm_expede.sh",
        "expede must name the withheld consumer CLAUDE.md template it transposes onto the candidate's root, and is itself withheld — no candidate carries it",
    ),
];

/// One line may name a withheld thing two ways. Reported distinctly so a finding
/// says which law it broke.
pub(crate) const ZRBTDRQ_VEIL_PATH_DETAIL: &str = "names the withheld tree";
pub(crate) const ZRBTDRQ_VEIL_DOC_DETAIL: &str = "names withheld document";

/// True when `basename` is a withheld document — one of the extensions above.
fn zrbtdrq_is_veil_doc(basename: &str) -> bool {
    ZRBTDRQ_VEIL_DOC_EXTS
        .iter()
        .any(|ext| basename.ends_with(&format!(".{}", ext)))
}

/// Collect the basenames of every withheld document beneath `dir`, descending
/// into it whole once a veiled tree is entered.
pub(crate) fn zrbtdrq_census_walk(dir: &Path, inside: bool, out: &mut BTreeSet<String>) {
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
            if ZRBTDRQ_SKIP_DIRS.contains(&name.as_str()) {
                continue;
            }
            zrbtdrq_census_walk(&path, inside || name == ZRBTDRQ_VEIL_DIR, out);
            continue;
        }
        if inside && zrbtdrq_is_veil_doc(&name) {
            out.insert(name);
        }
    }
}

/// True when any veiled tree exists beneath `dir` — the test that tells the
/// maintainer's tree from the stripped candidate.
pub(crate) fn zrbtdrq_veil_tree_exists(dir: &Path) -> bool {
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return false,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let name = match path.file_name().and_then(|s| s.to_str()) {
            Some(n) => n.to_string(),
            None => continue,
        };
        if name == ZRBTDRQ_VEIL_DIR {
            return true;
        }
        if ZRBTDRQ_SKIP_DIRS.contains(&name.as_str()) {
            continue;
        }
        if zrbtdrq_veil_tree_exists(&path) {
            return true;
        }
    }
    false
}

/// Scan one shipping file's text for both veil needles, appending findings.
pub(crate) fn zrbtdrq_veil_scan_text(
    rel: &str,
    text: &str,
    census: &BTreeSet<String>,
    findings: &mut Vec<zrbtdrq_Finding>,
) {
    for (index, line) in text.lines().enumerate() {
        if line.contains(ZRBTDRQ_VEIL_DIR) {
            findings.push(zrbtdrq_Finding {
                file: rel.to_string(),
                line: index + 1,
                detail: ZRBTDRQ_VEIL_PATH_DETAIL.to_string(),
            });
        }
        if !ZRBTDRQ_VEIL_DOC_MARKS.iter().any(|mark| line.contains(mark)) {
            continue;
        }
        for doc in census {
            if line.contains(doc.as_str()) {
                findings.push(zrbtdrq_Finding {
                    file: rel.to_string(),
                    line: index + 1,
                    detail: format!("{} {}", ZRBTDRQ_VEIL_DOC_DETAIL, doc),
                });
            }
        }
    }
}

/// The veil matcher's self-proof, run before its live-tree verdict is trusted.
/// The census it proves against is synthetic, so the proof holds in a tree whose
/// veiled documents have all been stripped away.
pub(crate) fn zrbtdrq_veil_self_proof() -> Vec<zrbtdrq_Finding> {
    let mut findings = Vec::new();
    let census: BTreeSet<String> = ["ZZQ-Example.adoc".to_string()].into_iter().collect();

    let positives: &[&str] = &[
        "  - see Tools/rbk/vov_veiled/whatever.sh for the rule",
        "# Contract: ZZQ-Example.adoc.",
        "- **ZZQ**  → `zzk/vov_veiled/ZZQ-Example.adoc` (a maintainer-context acronym row)",
    ];
    for probe in positives {
        let mut hits = Vec::new();
        zrbtdrq_veil_scan_text("self-proof", probe, &census, &mut hits);
        if hits.is_empty() {
            findings.push(zrbtdrq_Finding {
                file: ZRBTDRQ_SELF_EXEMPT.to_string(),
                line: 0,
                detail: format!("veil matcher missed a known leak: {:?}", probe),
            });
        }
    }

    let negatives: &[&str] = &[
        "start with the README.md at the project root",
        "the terrier records which citizens hold which mantles",
        "ZZQ-Example.txt is not a withheld document",
    ];
    for probe in negatives {
        let mut hits = Vec::new();
        zrbtdrq_veil_scan_text("self-proof", probe, &census, &mut hits);
        if !hits.is_empty() {
            findings.push(zrbtdrq_Finding {
                file: ZRBTDRQ_SELF_EXEMPT.to_string(),
                line: 0,
                detail: format!("veil matcher fired on a benign line: {:?}", probe),
            });
        }
    }

    findings
}

// The veil-leak CASE (rbtdrq_veil_leak) lives in rbtdrq_loupe.rs now — evicted
// into its own source-tree-only fixture so it cannot go vacuously green on the
// stripped candidate. The scan machinery above (constants, census walk, matcher,
// self-proof) stays here because zrbtdrq_veil_tree_exists is also damnatio's
// strip-landed check, and the walker/report/finding types below are pyx's own
// shared helpers reached from both loupe and damnatio.

// ── README anchor check ─────────────────────────────────────

/// Repo-relative source of the linked-term anchors the handbook yelps point at.
pub(crate) const ZRBTDRQ_ANCHOR_SOURCE: &str = "Tools/rbk/rbyc_common.sh";

/// Repo-relative document that must define every anchor pointed at. It is also
/// the second consumer: its own internal cross-references must land on its own
/// anchors.
pub(crate) const ZRBTDRQ_ANCHOR_TARGET: &str = "README.md";

/// The call whose third argument names an anchor in the target document.
pub(crate) const ZRBTDRQ_ANCHOR_CALL: &str = "zrbyc_yk";

/// How an anchor is declared in the target document. The consumer-facing README
/// carries explicit `<a id="…">` anchors rather than relying on a renderer's
/// heading-slug derivation, so the anchor a handbook link resolves is a literal
/// present in the source and checkable without a Markdown parser.
pub(crate) const ZRBTDRQ_ANCHOR_DECL: &str = "<a id=\"";

/// How the target document references its own anchors: the tail of a Markdown
/// inline link whose destination is a same-page fragment.
pub(crate) const ZRBTDRQ_ANCHOR_REF_OPEN: &str = "](#";

/// Names the consumed set a dangling anchor was reached from, so a finding says
/// where to go and fix it.
pub(crate) const ZRBTDRQ_CONSUMER_YELP: &str = "handbook linked term";
pub(crate) const ZRBTDRQ_CONSUMER_README: &str = "README internal reference";

// ── Findings ────────────────────────────────────────────────

/// One hygiene violation: where it is and what it is. `line` is 0 for a
/// whole-file finding that names no line.
#[derive(Clone, Debug)]
pub(crate) struct zrbtdrq_Finding {
    pub(crate) file: String,
    pub(crate) line: usize,
    pub(crate) detail: String,
}

/// Filename affixes for the traces written into the case dir.
pub(crate) const ZRBTDRQ_TRACE_PREFIX: &str = "pyx-";
pub(crate) const ZRBTDRQ_FINDINGS_SUFFIX: &str = "-findings.txt";
pub(crate) const ZRBTDRQ_INVENTORY_SUFFIX: &str = "-inventory.txt";

/// Render findings as a stable one-per-line report. A zero line number names a
/// whole file rather than a position within it.
fn zrbtdrq_render(findings: &[zrbtdrq_Finding]) -> String {
    let mut report = String::new();
    for f in findings {
        if f.line == 0 {
            report.push_str(&format!("{}: {}\n", f.file, f.detail));
        } else {
            report.push_str(&format!("{}:{}: {}\n", f.file, f.line, f.detail));
        }
    }
    report
}

/// Persist a case's findings and inventory traces into the case dir and turn the
/// findings into a verdict. `what` names the violation class in the fail message.
pub(crate) fn zrbtdrq_report(
    dir: &Path,
    label: &str,
    findings: &[zrbtdrq_Finding],
    inventory: &BTreeSet<String>,
    what: &str,
) -> rbtdre_Verdict {
    let report = zrbtdrq_render(findings);
    let findings_name = format!("{}{}{}", ZRBTDRQ_TRACE_PREFIX, label, ZRBTDRQ_FINDINGS_SUFFIX);
    let _ = std::fs::write(dir.join(findings_name), &report);

    let mut inventory_report = String::new();
    for entry in inventory {
        inventory_report.push_str(entry);
        inventory_report.push('\n');
    }
    let inventory_name = format!("{}{}{}", ZRBTDRQ_TRACE_PREFIX, label, ZRBTDRQ_INVENTORY_SUFFIX);
    let _ = std::fs::write(dir.join(inventory_name), &inventory_report);

    if findings.is_empty() {
        rbtdre_Verdict::Pass
    } else {
        rbtdre_Verdict::Fail(format!("{} {}:\n{}", findings.len(), what, report))
    }
}

/// The tree the fixture assays — the working directory, which every theurge run
/// anchors at the repo root.
pub(crate) fn zrbtdrq_root() -> Result<PathBuf, String> {
    std::env::current_dir().map_err(|e| format!("cannot get cwd: {}", e))
}

// ── Case: crate licenses ────────────────────────────────────

/// Extract the package names declared in a Cargo.lock body. Each `[[package]]`
/// table opens with its `name = "…"` key, so the names are read positionally
/// without a TOML parser: the first `name` line after each table header.
pub(crate) fn zrbtdrq_lock_crates(lock: &str) -> BTreeSet<String> {
    let mut crates = BTreeSet::new();
    let mut in_package = false;
    for line in lock.lines() {
        let trimmed = line.trim();
        if trimmed == "[[package]]" {
            in_package = true;
            continue;
        }
        if !in_package {
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix("name = \"") {
            if let Some(name) = rest.strip_suffix('"') {
                crates.insert(name.to_string());
            }
            in_package = false;
        }
    }
    crates
}

/// The lockfile's crate set must be covered by the vetted allowlist, and every
/// vetted expression must be drawn from the approved set. The first assertion
/// gates what enters the release; the second proves the table itself was not
/// widened by a typo.
fn rbtdrq_crate_licenses(dir: &Path) -> rbtdre_Verdict {
    let root = match zrbtdrq_root() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };
    let lock_path = root.join(ZRBTDRQ_LOCKFILE);
    let lock = match std::fs::read_to_string(&lock_path) {
        Ok(s) => s,
        Err(e) => {
            return rbtdre_Verdict::Fail(format!("cannot read {}: {}", ZRBTDRQ_LOCKFILE, e));
        }
    };

    let mut findings = Vec::new();
    let mut inventory = BTreeSet::new();

    for (name, license) in ZRBTDRQ_CRATE_LICENSES {
        inventory.insert(format!("{}\t{}", name, license));
        if !ZRBTDRQ_ALLOWED_LICENSES.contains(license) {
            findings.push(zrbtdrq_Finding {
                file: ZRBTDRQ_SELF_EXEMPT.to_string(),
                line: 0,
                detail: format!(
                    "vetted crate {} carries license {:?}, which is not in the approved set",
                    name, license
                ),
            });
        }
    }

    for name in zrbtdrq_lock_crates(&lock) {
        if name == ZRBTDRQ_ROOT_CRATE {
            continue;
        }
        if !ZRBTDRQ_CRATE_LICENSES.iter().any(|(vetted, _)| *vetted == name) {
            findings.push(zrbtdrq_Finding {
                file: ZRBTDRQ_LOCKFILE.to_string(),
                line: 0,
                detail: format!(
                    "crate {} is not license-vetted — vet it and add its row to ZRBTDRQ_CRATE_LICENSES",
                    name
                ),
            });
        }
    }

    zrbtdrq_report(dir, "license", &findings, &inventory, "crate-license violation(s)")
}

// ── Case: root LICENSE ──────────────────────────────────────

/// The distribution must carry its own terms at the root, and those terms must
/// be the ones the source headers claim.
fn rbtdrq_license_file(dir: &Path) -> rbtdre_Verdict {
    let root = match zrbtdrq_root() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };
    let path = root.join(ZRBTDRQ_LICENSE_FILE);

    let mut findings = Vec::new();
    match std::fs::read_to_string(&path) {
        Err(e) => findings.push(zrbtdrq_Finding {
            file: ZRBTDRQ_LICENSE_FILE.to_string(),
            line: 0,
            detail: format!("absent or unreadable: {}", e),
        }),
        Ok(body) => {
            for phrase in ZRBTDRQ_LICENSE_PHRASES {
                if !body.contains(phrase) {
                    findings.push(zrbtdrq_Finding {
                        file: ZRBTDRQ_LICENSE_FILE.to_string(),
                        line: 0,
                        detail: format!("does not carry the phrase {:?}", phrase),
                    });
                }
            }
        }
    }

    let inventory = BTreeSet::new();
    zrbtdrq_report(dir, "licensefile", &findings, &inventory, "root-LICENSE violation(s)")
}

// ── Case: secret shapes ─────────────────────────────────────

/// True when `byte` belongs to the body class.
fn zrbtdrq_in_body(body: zrbtdrq_Body, byte: u8) -> bool {
    match body {
        zrbtdrq_Body::Literal => false,
        zrbtdrq_Body::Token => {
            byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_' || byte == b'.'
        }
        zrbtdrq_Body::Shout => byte.is_ascii_uppercase() || byte.is_ascii_digit(),
    }
}

/// True when `line` carries a match for `shape`: the prefix appears, and the run
/// of body-class characters immediately after it is at least `body_min` long.
pub(crate) fn zrbtdrq_shape_hit(line: &str, shape: &zrbtdrq_Shape) -> bool {
    let bytes = line.as_bytes();
    let prefix = shape.prefix.as_bytes();
    if prefix.is_empty() || bytes.len() < prefix.len() {
        return false;
    }
    for start in 0..=(bytes.len() - prefix.len()) {
        if &bytes[start..start + prefix.len()] != prefix {
            continue;
        }
        if shape.body_min == 0 {
            return true;
        }
        let mut run = 0;
        let mut cursor = start + prefix.len();
        while cursor < bytes.len() && zrbtdrq_in_body(shape.body, bytes[cursor]) {
            run += 1;
            cursor += 1;
        }
        if run >= shape.body_min {
            return true;
        }
    }
    false
}

/// Scan one file's text for every shape, appending findings.
pub(crate) fn zrbtdrq_scan_text(rel: &str, text: &str, findings: &mut Vec<zrbtdrq_Finding>) {
    for (index, line) in text.lines().enumerate() {
        for shape in ZRBTDRQ_SHAPES {
            if zrbtdrq_shape_hit(line, shape) {
                findings.push(zrbtdrq_Finding {
                    file: rel.to_string(),
                    line: index + 1,
                    detail: format!("{} shape present", shape.label),
                });
            }
        }
    }
}

/// Recursively collect scannable files under `dir` into `out`, skipping the
/// extensions and oversize payloads that cannot hold a hand-authored token.
/// `skip_dirs` is per-scan: the secret scan reads the veiled trees (a credential
/// committed there is still a maintainer's problem), while the veil scan must not
/// (see ZRBTDRQ_VEIL_SKIP_DIRS).
pub(crate) fn zrbtdrq_walk(dir: &Path, skip_dirs: &[&str], out: &mut Vec<PathBuf>) {
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            let skipped = path
                .file_name()
                .and_then(|s| s.to_str())
                .map(|name| skip_dirs.contains(&name))
                .unwrap_or(false);
            if !skipped {
                zrbtdrq_walk(&path, skip_dirs, out);
            }
            continue;
        }
        let skipped = path
            .extension()
            .and_then(|e| e.to_str())
            .map(|ext| ZRBTDRQ_SKIP_EXTS.contains(&ext))
            .unwrap_or(false);
        if skipped {
            continue;
        }
        if let Ok(meta) = std::fs::metadata(&path) {
            if meta.len() > ZRBTDRQ_SIZE_CAP {
                continue;
            }
        }
        out.push(path);
    }
}

/// The matcher's self-proof, run before its live-tree verdict is trusted. Each
/// positive is assembled at runtime from fragments so the whole token never
/// appears as a literal in this source, and each negative is a form that a
/// coarser scanner would flag — the prose mention of a prefix, and the public
/// half of a PEM armor line.
fn zrbtdrq_matcher_self_proof() -> Vec<zrbtdrq_Finding> {
    let mut findings = Vec::new();

    let google_key = format!("{}{}", "AIza", "a".repeat(35));
    let pem = format!("-----BEGIN RSA {}", "PRIVATE KEY-----");
    let positives: &[&str] = &[&google_key, &pem];
    for probe in positives {
        let mut hits = Vec::new();
        zrbtdrq_scan_text("self-proof", probe, &mut hits);
        if hits.is_empty() {
            findings.push(zrbtdrq_Finding {
                file: ZRBTDRQ_SELF_EXEMPT.to_string(),
                line: 0,
                detail: "matcher missed a known secret shape".to_string(),
            });
        }
    }

    let short_key = format!("{}{}", "AIza", "a".repeat(4));
    let negatives: &[&str] = &[
        "a Google API key begins AIza — see the vendor docs",
        &short_key,
        "-----BEGIN PUBLIC KEY-----",
    ];
    for probe in negatives {
        let mut hits = Vec::new();
        zrbtdrq_scan_text("self-proof", probe, &mut hits);
        if !hits.is_empty() {
            findings.push(zrbtdrq_Finding {
                file: ZRBTDRQ_SELF_EXEMPT.to_string(),
                line: 0,
                detail: format!("matcher fired on a benign line: {:?}", probe),
            });
        }
    }

    findings
}

/// No shipping file may carry a credential shape. The matcher proves itself
/// first; a matcher failure and a tree failure are both findings, so a broken
/// checker can never report a clean tree.
fn rbtdrq_secret_shapes(dir: &Path) -> rbtdre_Verdict {
    let root = match zrbtdrq_root() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };

    let mut findings = zrbtdrq_matcher_self_proof();
    let mut inventory = BTreeSet::new();

    // The exemptions ride the inventory trace: a reader of the scan's record
    // sees what was NOT scanned and why, without reading this source.
    for (path, reason) in ZRBTDRQ_EXEMPT {
        inventory.insert(format!("{}\texempt: {}", path, reason));
    }

    let mut files = Vec::new();
    for sub in ZRBTDRQ_SECRET_ROOTS {
        let path = root.join(sub);
        if path.is_dir() {
            zrbtdrq_walk(&path, ZRBTDRQ_SKIP_DIRS, &mut files);
        }
    }
    for sub in ZRBTDRQ_SECRET_FILES {
        let path = root.join(sub);
        if path.is_file() {
            files.push(path);
        }
    }

    for path in files {
        let rel = crate::rbtdrx_platform::rbtdrx_repo_rel(&root, &path);
        if ZRBTDRQ_EXEMPT.iter().any(|(path, _)| *path == rel) {
            continue;
        }
        inventory.insert(rel.clone());
        let bytes = match std::fs::read(&path) {
            Ok(b) => b,
            Err(_) => continue,
        };
        let text = String::from_utf8_lossy(&bytes);
        zrbtdrq_scan_text(&rel, &text, &mut findings);
    }

    zrbtdrq_report(dir, "secret", &findings, &inventory, "secret-shape violation(s)")
}

// ── Case: README anchors ────────────────────────────────────

/// Extract the anchor named by each linked-term declaration in the yelp source:
/// the third whitespace-separated argument of a `zrbyc_yk` call, stripped of its
/// surrounding quotes.
pub(crate) fn zrbtdrq_declared_anchors(source: &str) -> BTreeSet<String> {
    let mut anchors = BTreeSet::new();
    for line in source.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('#') || !trimmed.starts_with(ZRBTDRQ_ANCHOR_CALL) {
            continue;
        }
        let fields: Vec<&str> = trimmed.split_whitespace().collect();
        if fields.len() < 4 {
            continue;
        }
        let anchor = fields[3].trim_matches('"');
        if !anchor.is_empty() {
            anchors.insert(anchor.to_string());
        }
    }
    anchors
}

/// Extract every anchor the target document defines.
pub(crate) fn zrbtdrq_defined_anchors(target: &str) -> BTreeSet<String> {
    let mut anchors = BTreeSet::new();
    for line in target.lines() {
        let mut rest = line;
        while let Some(at) = rest.find(ZRBTDRQ_ANCHOR_DECL) {
            rest = &rest[at + ZRBTDRQ_ANCHOR_DECL.len()..];
            if let Some(end) = rest.find('"') {
                anchors.insert(rest[..end].to_string());
                rest = &rest[end..];
            } else {
                break;
            }
        }
    }
    anchors
}

/// Extract every same-page fragment the target document links to — the anchor
/// between `](#` and the closing paren. A destination carrying anything but a
/// bare fragment (a path, a URL) is not a same-page reference and is skipped.
pub(crate) fn zrbtdrq_referenced_anchors(target: &str) -> BTreeSet<String> {
    let mut anchors = BTreeSet::new();
    for line in target.lines() {
        let mut rest = line;
        while let Some(at) = rest.find(ZRBTDRQ_ANCHOR_REF_OPEN) {
            rest = &rest[at + ZRBTDRQ_ANCHOR_REF_OPEN.len()..];
            if let Some(end) = rest.find(')') {
                let anchor = &rest[..end];
                if !anchor.is_empty() {
                    anchors.insert(anchor.to_string());
                }
                rest = &rest[end..];
            } else {
                break;
            }
        }
    }
    anchors
}

/// Every anchor consumed must be defined in the consumer-facing README: both the
/// anchors a handbook linked term points at, and the README's own internal
/// cross-references. A handbook line renders as a link into the public
/// documentation page built from this same README, so resolution here proves the
/// published links cannot dangle — a defect no consumer can route around, and
/// one invisible until someone clicks it.
///
/// An empty consumed or defined set is a FINDING, not a pass. Both sets are
/// extracted by matching literals in the source files, and the failure mode of
/// an extractor is to match nothing — which without this guard reports a clean
/// tree with a checker that has quietly stopped checking.
fn rbtdrq_readme_anchors(dir: &Path) -> rbtdre_Verdict {
    let root = match zrbtdrq_root() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };

    let source = match std::fs::read_to_string(root.join(ZRBTDRQ_ANCHOR_SOURCE)) {
        Ok(s) => s,
        Err(e) => {
            return rbtdre_Verdict::Fail(format!("cannot read {}: {}", ZRBTDRQ_ANCHOR_SOURCE, e));
        }
    };
    let target = match std::fs::read_to_string(root.join(ZRBTDRQ_ANCHOR_TARGET)) {
        Ok(s) => s,
        Err(e) => {
            return rbtdre_Verdict::Fail(format!("cannot read {}: {}", ZRBTDRQ_ANCHOR_TARGET, e));
        }
    };

    let defined = zrbtdrq_defined_anchors(&target);
    let consumed = [
        (ZRBTDRQ_CONSUMER_YELP, ZRBTDRQ_ANCHOR_SOURCE, zrbtdrq_declared_anchors(&source)),
        (ZRBTDRQ_CONSUMER_README, ZRBTDRQ_ANCHOR_TARGET, zrbtdrq_referenced_anchors(&target)),
    ];

    let mut findings = Vec::new();
    let mut inventory = BTreeSet::new();

    if defined.is_empty() {
        findings.push(zrbtdrq_Finding {
            file: ZRBTDRQ_ANCHOR_TARGET.to_string(),
            line: 0,
            detail: "defines no anchors at all — the extractor matched nothing".to_string(),
        });
    }

    for (consumer, file, anchors) in &consumed {
        if anchors.is_empty() {
            findings.push(zrbtdrq_Finding {
                file: file.to_string(),
                line: 0,
                detail: format!("no {} anchors found — the extractor matched nothing", consumer),
            });
        }
        for anchor in anchors {
            inventory.insert(format!("{}\t{}", anchor, consumer));
            if !defined.contains(anchor) {
                findings.push(zrbtdrq_Finding {
                    file: file.to_string(),
                    line: 0,
                    detail: format!(
                        "{} points at anchor {:?}, undefined in {}",
                        consumer, anchor, ZRBTDRQ_ANCHOR_TARGET
                    ),
                });
            }
        }
    }

    zrbtdrq_report(dir, "anchor", &findings, &inventory, "dangling-anchor violation(s)")
}

// ── Case: no shipped .adoc ──────────────────────────────────

/// The one extension the no-.adoc case forbids in the shipping corpus.
pub(crate) const ZRBTDRQ_ADOC_EXT: &str = ".adoc";

/// Repo-relative paths exempt from the no-.adoc case, each with the reason. Same
/// doctrine as the other exemption tables: exact path, never a prefix, and every
/// row is an OPERATOR ACT — an `.adoc` that should ship is a ruling, never a
/// default. Empty today: every tracked `.adoc` sits under a withheld prefix, and
/// none has ever been ruled fit to ship.
pub(crate) const ZRBTDRQ_ADOC_EXEMPT: &[(&str, &str)] = &[];

/// True when `rel` is a shipped `.adoc`: the extension matches and the path is
/// not in the exemption table. Factored out of the case so the predicate can be
/// proven in memory before its live-tree verdict is trusted.
pub(crate) fn zrbtdrq_is_shipped_adoc(rel: &str) -> bool {
    rel.ends_with(ZRBTDRQ_ADOC_EXT)
        && !ZRBTDRQ_ADOC_EXEMPT.iter().any(|(exempt, _)| *exempt == rel)
}

/// Recursively collect every file path beneath `dir`, skipping `skip_dirs`
/// directories only — no extension or size filter. The no-.adoc case reads only
/// file NAMES, never contents, so zrbtdrq_walk's read-oriented filtering (which
/// caps file size and skips binary extensions for the checks that read bytes)
/// would silently exempt an oversize or extension-skip-listed misfile from the
/// very sweep meant to catch it.
pub(crate) fn zrbtdrq_walk_paths(dir: &Path, skip_dirs: &[&str], out: &mut Vec<PathBuf>) {
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            let skipped = path
                .file_name()
                .and_then(|s| s.to_str())
                .map(|name| skip_dirs.contains(&name))
                .unwrap_or(false);
            if !skipped {
                zrbtdrq_walk_paths(&path, skip_dirs, out);
            }
            continue;
        }
        out.push(path);
    }
}

/// The shipped-`.adoc` predicate's self-proof, run before its live-tree verdict
/// is trusted. Both probes are synthetic paths that never exist on disk — no real
/// violation is planted in the repo.
fn zrbtdrq_adoc_self_proof() -> Vec<zrbtdrq_Finding> {
    let mut findings = Vec::new();

    if !zrbtdrq_is_shipped_adoc("Tools/rbk/ZZQ-Example.adoc") {
        findings.push(zrbtdrq_Finding {
            file: ZRBTDRQ_SELF_EXEMPT.to_string(),
            line: 0,
            detail: "adoc matcher missed a known shipping .adoc path".to_string(),
        });
    }
    if zrbtdrq_is_shipped_adoc("Tools/rbk/ZZQ-Example.md") {
        findings.push(zrbtdrq_Finding {
            file: ZRBTDRQ_SELF_EXEMPT.to_string(),
            line: 0,
            detail: "adoc matcher fired on a non-.adoc path".to_string(),
        });
    }

    findings
}

/// No `.adoc` file may ship. Every tracked spec sits under a withheld prefix
/// today (`vov_veiled`, or a kit that never ships), but nothing mechanical
/// enforces that placement — a spec landing under a ship-judged tree (`Tools/rbk/`
/// ships whole) would ride silently into the candidate. The exemption table is
/// the only door, and it starts empty: an `.adoc` that should ship is an operator
/// ruling, never a default. Existence-tolerant roots and the veiled-dir skip are
/// what let one case hold on both the maintainer tree and the candidate — the
/// maintainer tree's own `.adoc` corpus lives entirely under `vov_veiled`, which
/// this walk never enters.
fn rbtdrq_no_adoc(dir: &Path) -> rbtdre_Verdict {
    let root = match zrbtdrq_root() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };

    let mut findings = zrbtdrq_adoc_self_proof();
    let mut inventory = BTreeSet::new();

    for (path, reason) in ZRBTDRQ_ADOC_EXEMPT {
        inventory.insert(format!("{}\texempt: {}", path, reason));
    }

    let mut files = Vec::new();
    for sub in ZRBTDRQ_VEIL_ROOTS {
        let path = root.join(sub);
        if path.is_dir() {
            zrbtdrq_walk_paths(&path, ZRBTDRQ_VEIL_SKIP_DIRS, &mut files);
        }
    }

    for path in files {
        let rel = crate::rbtdrx_platform::rbtdrx_repo_rel(&root, &path);
        if !zrbtdrq_is_shipped_adoc(&rel) {
            continue;
        }
        inventory.insert(rel.clone());
        findings.push(zrbtdrq_Finding {
            file: rel,
            line: 0,
            detail: "ships as .adoc, not in ZRBTDRQ_ADOC_EXEMPT".to_string(),
        });
    }

    zrbtdrq_report(dir, "adoc", &findings, &inventory, "shipped .adoc file(s)")
}

// ── Cases and fixture ───────────────────────────────────────

pub static RBTDRQ_CASES_PYX: &[rbtdre_Case] = &[
    case!(rbtdrq_crate_licenses),
    case!(rbtdrq_license_file),
    case!(rbtdrq_secret_shapes),
    case!(rbtdrq_readme_anchors),
    case!(rbtdrq_no_adoc),
];

pub static RBTDRQ_FIXTURE_PYX: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_PYX,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRQ_CASES_PYX,
    credless: true,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: None, invocations: Some(0) },
};
