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
// RBTDRQ — damnatio: the delivered-tree identity assay.
//
// Damnatio memoriae is the erasure of a person from the public record. This
// fixture is that erasure's proof: it asserts, of a tree that has been stripped
// and lustrated, that the maintainer's site — their cloud, their billing, their
// federated identity — is nowhere in it. Sibling of pyx in method (deterministic
// tree-invariants over committed files, a matcher that proves itself before its
// verdict is trusted) and its complement in subject: pyx assays what the tree
// must NOT carry of any secret, damnatio assays what it must not carry of THIS
// OPERATOR.
//
// A MEMBER OF NO SUITE, and that is the whole point. Every case here is true
// only of a stripped, sterilized candidate; run against the maintainer's working
// tree it is red by construction, because that tree is SUPPOSED to hold the
// operator's live configuration. It takes no parameter and means one thing
// wherever it runs: this tree is fit to publish. The release ceremony invokes it
// by name after the strip; nothing else does.
//
// Two nets, and they are complementary because identity comes in two forms.
//
//   SHAPED identity — a UUID, a billing account, an OAuth client id — has a form
//   the sweep can hunt anywhere in the tree, including homes nobody thought to
//   declare. That is the net for the unknown leak.
//
//   SHAPELESS identity — a workforce pool id, a GCP project id, an org number —
//   is an opaque token no form distinguishes from any other. No sweep can find
//   it. The proscription (Tools/rbk/rblm_lustrate.sh) declares every enrolled
//   field site-scoped or common, and the value case asserts each site-scoped one
//   sterile. That is the net for the declared leak, and the completeness case is
//   what keeps the declaration honest: it reads the LIVE enrollment rolls, so a
//   field enrolled tomorrow reddens tomorrow until someone judges it.
//
// NO EXEMPTION TABLE. Not one path, in any case. Where a needle collided with
// something innocent, the needle was sharpened until it did not — never the file
// excused. The three collisions, all real, all still in the tree, all now passed
// over by the matcher itself rather than by a list:
//
//   - Jupyter cell ids and the caged Keycloak realm's entity id are UUIDs. Both
//     are JSON members whose key is exactly "id" — a document-internal id, which
//     is what nbformat and Keycloak mint. Every leaked UUID, by contrast, is a
//     shell/Rust/env assignment or a URL path segment. So the sweep reads those
//     files whole, byte for byte — a tenant GUID pasted into a notebook markdown
//     cell still reddens — and passes over only the bookkeeping.
//   - A log basename carries a run of digit groups a naive billing-account shape
//     matches inside. The shape matches only as a whole token, so it cannot.
//   - The payor regime's own validator, and a handbook's filename example, both
//     name the OAuth client-id suffix. The shape requires the numeric project
//     prefix that makes a client id a client id, so neither fires.
//
// The needles are structural forms, never literals: this source ships, and a
// literal needle would be the very leak it hunts. The self-proof's positives are
// assembled from fragments and are synthetic throughout.

use std::collections::{
    BTreeMap,
    BTreeSet,
};
use std::path::Path;

use crate::case;
use crate::rbtdre_engine::{
    rbtdre_Tariff,
    rbtdre_Case,
    rbtdre_Disposition,
    rbtdre_Fixture,
    rbtdre_Verdict,
};
use crate::rbtdrf_fast::{
    rbtdrf_run_bash,
    RBTDRF_BUV_VALIDATION,
    RBTDRF_RBK_ROOT,
};
use crate::rbtdrm_manifest::RBTDRM_FIXTURE_DAMNATIO;
use crate::rbtdrq_pyx::{
    zrbtdrq_report,
    zrbtdrq_root,
    zrbtdrq_veil_scan_text,
    zrbtdrq_veil_self_proof,
    zrbtdrq_veil_tree_exists,
    zrbtdrq_walk,
    zrbtdrq_Finding,
    ZRBTDRQ_VEIL_CENSUS_ROOT,
    ZRBTDRQ_VEIL_SKIP_DIRS,
};

// ── The swept corpus ────────────────────────────────────────

/// Repo-relative roots walked by the identity sweep — the trees that reach a
/// consumer. `diagrams/` rides here because a rendered diagram displays its
/// source text: a project id baked into a committed `.svg` is read by someone who
/// greps nothing. Each root is existence-tolerant, so the same case holds on the
/// maintainer's tree and on the stripped candidate.
pub(crate) const ZRBTDRQ_IDENTITY_ROOTS: &[&str] =
    &["Tools/buk", "Tools/rbk", "tt", "rbmm_moorings", "diagrams"];

/// The delivered tree's root context document, named once because two damnatio
/// checks reach it for different needle classes: the identity sweep below hunts
/// site-shaped identity, and rbtdrq_veil_stripped hunts veil needles once no
/// veiled tree stands. In the maintainer tree it is the maintainer's own context;
/// in the candidate it is the consumer template's bytes, transposed onto it by
/// expede itself between materialization and the commit and byte-asserted —
/// never a copy this ceremony performs.
pub(crate) const ZRBTDRQ_ROOT_CLAUDE: &str = "CLAUDE.md";

/// Repo-relative single files added to the sweep — the consumer-facing documents
/// at the repo root. Scanning the root path covers whichever tree we are standing
/// in.
pub(crate) const ZRBTDRQ_IDENTITY_FILES: &[&str] = &["README.md", ZRBTDRQ_ROOT_CLAUDE];

/// The veiled trees are skipped: they never ship, and a withheld design document
/// may name the operator's project freely — that is what being withheld means.
/// Build output is skipped for the reason pyx skips it.
pub(crate) const ZRBTDRQ_IDENTITY_SKIP_DIRS: &[&str] = ZRBTDRQ_VEIL_SKIP_DIRS;

// ── The needles ─────────────────────────────────────────────

pub(crate) const ZRBTDRQ_DETAIL_UUID: &str = "UUID bound as a value — a federated tenant, client or subject identity";
pub(crate) const ZRBTDRQ_DETAIL_BILLING: &str = "GCP billing-account id";
pub(crate) const ZRBTDRQ_DETAIL_OAUTH: &str = "Google OAuth client id";

/// The suffix every Google OAuth client id ends with. Present in this source as a
/// structural marker, not as anyone's identity.
pub(crate) const ZRBTDRQ_OAUTH_SUFFIX: &str = ".apps.googleusercontent.com";

/// The JSON key whose value is a document-internal entity id rather than a
/// principal: what nbformat mints per notebook cell, and Keycloak per realm
/// entity. A UUID bound to THIS key, and only this key, is bookkeeping.
pub(crate) const ZRBTDRQ_JSON_ID_KEY: &str = "\"id\"";

/// Group lengths of a UUID: 8-4-4-4-12 hexadecimal, hyphen-separated.
pub(crate) const ZRBTDRQ_UUID_GROUPS: &[usize] = &[8, 4, 4, 4, 12];

/// Group lengths of a GCP billing-account id: three six-character groups of
/// uppercase hexadecimal.
pub(crate) const ZRBTDRQ_BILLING_GROUPS: &[usize] = &[6, 6, 6];

/// True when the byte may sit inside a hyphenated identifier — the class whose
/// presence on either side of a candidate means we are looking at a fragment of
/// something longer, not the token itself.
fn zrbtdrq_is_token_byte(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_'
}

/// True when the span [start, end) stands alone — no identifier character abuts
/// it on either side. This is what keeps a shape from matching a window inside a
/// longer run: a log basename's `…-20260709-212119-1862763-…` holds six-digit
/// groups, but every candidate window has a digit or a hyphen against it.
fn zrbtdrq_stands_alone(bytes: &[u8], start: usize, end: usize) -> bool {
    if start > 0 && zrbtdrq_is_token_byte(bytes[start - 1]) {
        return false;
    }
    if end < bytes.len() && zrbtdrq_is_token_byte(bytes[end]) {
        return false;
    }
    true
}

/// Match hyphen-separated groups of a byte class at `start`. Returns the end
/// offset of the whole run, or None. `admits` decides the class per group, so one
/// walker serves both the UUID (any-case hex) and the billing account (uppercase
/// hex).
fn zrbtdrq_groups_at(
    bytes: &[u8],
    start: usize,
    groups: &[usize],
    admits: fn(u8) -> bool,
) -> Option<usize> {
    let mut cursor = start;
    for (index, width) in groups.iter().enumerate() {
        if index > 0 {
            if cursor >= bytes.len() || bytes[cursor] != b'-' {
                return None;
            }
            cursor += 1;
        }
        if cursor + width > bytes.len() {
            return None;
        }
        for offset in 0..*width {
            if !admits(bytes[cursor + offset]) {
                return None;
            }
        }
        cursor += width;
    }
    Some(cursor)
}

fn zrbtdrq_admits_hex(byte: u8) -> bool {
    byte.is_ascii_hexdigit()
}

fn zrbtdrq_admits_upper_hex(byte: u8) -> bool {
    byte.is_ascii_digit() || (b'A'..=b'F').contains(&byte)
}

/// True when the text preceding a UUID binds it as a JSON `"id"` member — the
/// document-internal entity id. Peels the opening quote, the colon, and the
/// whitespace around them, then demands the key be exactly `"id"`: a
/// `"client_id"` or a `"tenant_id"` ends with different bytes and is NOT passed
/// over.
fn zrbtdrq_bound_as_json_id(prefix: &str) -> bool {
    let head = prefix.trim_end();
    let head = match head.strip_suffix('"') {
        Some(rest) => rest,
        None => return false,
    };
    let head = head.trim_end();
    let head = match head.strip_suffix(':') {
        Some(rest) => rest,
        None => return false,
    };
    head.trim_end().ends_with(ZRBTDRQ_JSON_ID_KEY)
}

/// True when the token running back from `at` is a Google OAuth client id's
/// numeric-project-and-body prefix: digits, a hyphen, then the body. The bare
/// suffix is not enough — the payor regime's own validator names it, and a
/// handbook example names it inside a filename; neither carries the prefix that
/// makes a client id.
fn zrbtdrq_oauth_prefixed(line: &str, at: usize) -> bool {
    let bytes = line.as_bytes();
    let mut start = at;
    while start > 0 && zrbtdrq_is_token_byte(bytes[start - 1]) {
        start -= 1;
    }
    let token = &line[start..at];

    let (digits, body) = match token.split_once('-') {
        Some(split) => split,
        None => return false,
    };
    !digits.is_empty()
        && digits.bytes().all(|b| b.is_ascii_digit())
        && !body.is_empty()
        && body.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

/// Scan one file's text for every identity needle, appending findings.
pub(crate) fn zrbtdrq_identity_scan_text(
    rel: &str,
    text: &str,
    findings: &mut Vec<zrbtdrq_Finding>,
) {
    for (index, line) in text.lines().enumerate() {
        let bytes = line.as_bytes();

        for start in 0..bytes.len() {
            if let Some(end) =
                zrbtdrq_groups_at(bytes, start, ZRBTDRQ_UUID_GROUPS, zrbtdrq_admits_hex)
            {
                if zrbtdrq_stands_alone(bytes, start, end)
                    && !zrbtdrq_bound_as_json_id(&line[..start])
                {
                    findings.push(zrbtdrq_Finding {
                        file: rel.to_string(),
                        line: index + 1,
                        detail: ZRBTDRQ_DETAIL_UUID.to_string(),
                    });
                }
            }

            if let Some(end) =
                zrbtdrq_groups_at(bytes, start, ZRBTDRQ_BILLING_GROUPS, zrbtdrq_admits_upper_hex)
            {
                if zrbtdrq_stands_alone(bytes, start, end) {
                    findings.push(zrbtdrq_Finding {
                        file: rel.to_string(),
                        line: index + 1,
                        detail: ZRBTDRQ_DETAIL_BILLING.to_string(),
                    });
                }
            }
        }

        let mut cursor = 0;
        while let Some(at) = line[cursor..].find(ZRBTDRQ_OAUTH_SUFFIX) {
            let absolute = cursor + at;
            if zrbtdrq_oauth_prefixed(line, absolute) {
                findings.push(zrbtdrq_Finding {
                    file: rel.to_string(),
                    line: index + 1,
                    detail: ZRBTDRQ_DETAIL_OAUTH.to_string(),
                });
            }
            cursor = absolute + ZRBTDRQ_OAUTH_SUFFIX.len();
        }
    }
}

/// The matcher's self-proof, run before its live-tree verdict is trusted. Each
/// positive is assembled at runtime from synthetic fragments, so no identity —
/// nobody's, real or invented — appears whole as a literal in this shipping
/// source. Each negative is one of the three real collisions the tree contains:
/// they are the reason the needles have the edges they have, and if a needle is
/// ever blunted back, its collision reappears here first.
fn zrbtdrq_identity_self_proof() -> Vec<zrbtdrq_Finding> {
    let mut findings = Vec::new();

    let uuid = format!("{}-{}-{}-{}-{}", "0f1e2d3c", "4b5a", "6978", "8796", "a5b4c3d2e1f0");
    let assigned = format!("SOME_IDP_CLIENT_ID={}", uuid);
    let in_url = format!("https://login.example/{}/v2.0", uuid);
    let quoted = format!("pub const SOME_SUBJECT: &str = \"{}\";", uuid);
    let billing = format!("SOME_BILLING_ACCOUNT_ID={}-{}-{}", "0A1B2C", "3D4E5F", "6789AB");
    let oauth = format!("SOME_OAUTH_CLIENT_ID={}-{}{}", "123456789012", "abcdefghijklm", ZRBTDRQ_OAUTH_SUFFIX);

    let positives: &[&str] = &[&assigned, &in_url, &quoted, &billing, &oauth];
    for probe in positives {
        let mut hits = Vec::new();
        zrbtdrq_identity_scan_text("self-proof", probe, &mut hits);
        if hits.is_empty() {
            findings.push(zrbtdrq_Finding {
                file: RBTDRQ_DAMNATIO_SELF.to_string(),
                line: 0,
                detail: format!("matcher missed a known identity shape: {:?}", probe),
            });
        }
    }

    let json_id = format!("   \"id\": \"{}\",", uuid);
    let negatives: &[&str] = &[
        // A notebook cell id and a Keycloak realm entity id — document
        // bookkeeping, the only UUID binding the sweep passes over.
        &json_id,
        // A log basename: six-character digit groups, but never as a whole token.
        "hist-rbw-ts-reveille-20260709-212119-1862763-785.txt",
        // The payor regime's own validator, naming the suffix with no client id.
        "  [[ \"${RBRP_OAUTH_CLIENT_ID}\" =~ \\.apps\\.googleusercontent\\.com$ ]] \\",
        // A handbook's filename example, likewise.
        "client_secret_[id].apps.googleusercontent.com.json",
        // A git object name: forty hex characters, no group structure.
        "commit b63eba327c9d4e1a8f5b2c7d0e3a6f9b1c4d7e0a",
    ];
    for probe in negatives {
        let mut hits = Vec::new();
        zrbtdrq_identity_scan_text("self-proof", probe, &mut hits);
        if !hits.is_empty() {
            findings.push(zrbtdrq_Finding {
                file: RBTDRQ_DAMNATIO_SELF.to_string(),
                line: 0,
                detail: format!("matcher fired on a benign line: {:?}", probe),
            });
        }
    }

    findings
}

/// This module's own source — the file a self-proof finding points at. It is NOT
/// an exemption: this source is swept like any other, and it survives the sweep
/// because it spells no identity, only shapes.
pub(crate) const RBTDRQ_DAMNATIO_SELF: &str = "Tools/rbk/rbtd/src/rbtdrq_damnatio.rs";

// ── Case: identity shapes ───────────────────────────────────

/// No shipping file may carry a shaped site identity. The matcher proves itself
/// first, and a matcher failure is a finding exactly as a tree failure is — so a
/// blunted checker can never report a clean tree.
fn rbtdrq_identity_shapes(dir: &Path) -> rbtdre_Verdict {
    let root = match zrbtdrq_root() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };

    let mut findings = zrbtdrq_identity_self_proof();
    let mut inventory = BTreeSet::new();

    let mut files = Vec::new();
    for sub in ZRBTDRQ_IDENTITY_ROOTS {
        let path = root.join(sub);
        if path.is_dir() {
            zrbtdrq_walk(&path, ZRBTDRQ_IDENTITY_SKIP_DIRS, &mut files);
        }
    }
    for sub in ZRBTDRQ_IDENTITY_FILES {
        let path = root.join(sub);
        if path.is_file() {
            files.push(path);
        }
    }

    for path in files {
        let rel = crate::rbtdrx_platform::rbtdrx_repo_rel(&root, &path);
        inventory.insert(rel.clone());
        let bytes = match std::fs::read(&path) {
            Ok(b) => b,
            Err(_) => continue,
        };
        let text = String::from_utf8_lossy(&bytes);
        zrbtdrq_identity_scan_text(&rel, &text, &mut findings);
    }

    zrbtdrq_report(dir, "identity", &findings, &inventory, "site-identity violation(s)")
}

// ── The proscription, read from its one home ────────────────

/// One judged field: the regime that enrolls it, and what the delivered tree must
/// hold.
struct zrbtdrq_Judgment {
    scope: String,
    var: String,
    disposition: String,
    sterile: String,
}

pub(crate) const ZRBTDRQ_DISPOSITION_SITE: &str = "site";

/// Section markers in the bash reach's output.
const ZRBTDRQ_MARK_ROLLS: &str = "##ROLLS";
const ZRBTDRQ_MARK_PROSCRIPTION: &str = "##PROSCRIPTION";
const ZRBTDRQ_MARK_HOMES: &str = "##HOMES";
const ZRBTDRQ_MARK_HARDPOINTS: &str = "##HARDPOINTS";

/// What the bash reach hands back: the live enrollment rolls, the proscription
/// that judges them, the regime files those judgments apply to, and the hardpoint
/// constants no roll can reach.
struct zrbtdrq_Reach {
    rolls: Vec<(String, String)>,
    proscription: Vec<zrbtdrq_Judgment>,
    homes: Vec<(String, String)>,
    hardpoints: Vec<(String, String, String)>,
}

/// Reach into bash for everything that must not be a second copy in Rust.
///
/// The enrollment rolls are the LIVE ones — buv's parallel arrays, populated by
/// the very `buv_*_enroll` calls the regime modules make at kindle. Nothing here
/// re-parses a regime source, so no static grep can drift from what the system
/// actually enrolls. Kindling needs each regime's values in the environment, so
/// the tree's own regime files are sourced first; RBRO alone is fed probe values,
/// because its file lives outside the repository by design and the fixture must
/// not require the operator's secrets to run.
///
/// The proscription, the scope-to-file mapping and the hardpoints are read back
/// from the lustration module — the same table the transform writes from, so the
/// judgment the fixture enforces and the judgment the verb applies cannot drift.
fn zrbtdrq_reach(root: &Path, dir: &Path) -> Result<zrbtdrq_Reach, String> {
    let buv = crate::rbtdrx_platform::rbtdrx_native_to_posix(&root.join(RBTDRF_BUV_VALIDATION));
    let rbk = crate::rbtdrx_platform::rbtdrx_native_to_posix(&root.join(RBTDRF_RBK_ROOT));
    let moorings = crate::rbtdgc_consts::RBTDGC_MOORINGS_DIR;

    let script = format!(
        "set -euo pipefail\n\
         source '{buv}'\n\
         source '{rbk}/rbcc_constants.sh'\n\
         source '{rbk}/rblm_lustrate.sh'\n\
         source '{rbk}/rbrr_regime.sh'\n\
         source '{rbk}/rbrd_regime.sh'\n\
         source '{rbk}/rbrp_regime.sh'\n\
         source '{rbk}/rbrw_regime.sh'\n\
         source '{rbk}/rbrf_regime.sh'\n\
         source '{rbk}/rbro_regime.sh'\n\
         source '{rbk}/rbrv_regime.sh'\n\
         source '{rbk}/rbrn_regime.sh'\n\
         zbuv_kindle\n\
         source '{moorings}/rbrr.env'\n\
         zrbrr_kindle\n\
         source '{moorings}/rbrd.env'\n\
         zrbrd_kindle\n\
         source '{moorings}/rbrp.env'\n\
         zrbrp_kindle\n\
         source '{moorings}/rbrw.env'\n\
         zrbrw_kindle\n\
         source \"{moorings}/rbmf_foedera/${{RBRR_ACTIVE_FOEDUS}}/rbrf.env\"\n\
         zrbrf_kindle\n\
         RBRO_CLIENT_SECRET=probe RBRO_REFRESH_TOKEN=probe zrbro_kindle\n\
         for z_probe in {moorings}/rbmv_vessels/*/rbrv.env; do source \"${{z_probe}}\"; break; done\n\
         zrbrv_kindle\n\
         for z_probe in {moorings}/*/rbrn.env; do source \"${{z_probe}}\"; break; done\n\
         zrbrn_kindle\n\
         echo '{mark_rolls}'\n\
         for z_i in \"${{!z_buv_scope_roll[@]}}\"; do \
           printf '%s\\t%s\\n' \"${{z_buv_scope_roll[$z_i]}}\" \"${{z_buv_varname_roll[$z_i]}}\"; done\n\
         echo '{mark_proscription}'\n\
         rblm_emit_proscription\n\
         echo '{mark_homes}'\n\
         rblm_emit_homes\n\
         echo '{mark_hardpoints}'\n\
         rblm_emit_hardpoints\n",
        buv = buv,
        rbk = rbk,
        moorings = moorings,
        mark_rolls = ZRBTDRQ_MARK_ROLLS,
        mark_proscription = ZRBTDRQ_MARK_PROSCRIPTION,
        mark_homes = ZRBTDRQ_MARK_HOMES,
        mark_hardpoints = ZRBTDRQ_MARK_HARDPOINTS,
    );

    let stdout = match rbtdrf_run_bash(root, &script, dir, "damnatio-reach")? {
        (0, stdout, _) => stdout,
        (code, _, stderr) => {
            return Err(format!("regime reach failed (exit {}): {}", code, stderr.trim()));
        }
    };

    let mut reach =
        zrbtdrq_Reach { rolls: Vec::new(), proscription: Vec::new(), homes: Vec::new(), hardpoints: Vec::new() };
    let mut section = "";

    for line in stdout.lines() {
        match line {
            ZRBTDRQ_MARK_ROLLS
            | ZRBTDRQ_MARK_PROSCRIPTION
            | ZRBTDRQ_MARK_HOMES
            | ZRBTDRQ_MARK_HARDPOINTS => {
                section = line;
                continue;
            }
            _ => {}
        }
        if line.is_empty() {
            continue;
        }
        let fields: Vec<&str> = line.split('\t').collect();
        match section {
            ZRBTDRQ_MARK_ROLLS if fields.len() >= 2 => {
                reach.rolls.push((fields[0].to_string(), fields[1].to_string()));
            }
            ZRBTDRQ_MARK_PROSCRIPTION if fields.len() >= 3 => {
                reach.proscription.push(zrbtdrq_Judgment {
                    scope: fields[0].to_string(),
                    var: fields[1].to_string(),
                    disposition: fields[2].to_string(),
                    sterile: fields.get(3).unwrap_or(&"").to_string(),
                });
            }
            ZRBTDRQ_MARK_HOMES if fields.len() >= 2 => {
                reach.homes.push((fields[0].to_string(), fields[1].to_string()));
            }
            ZRBTDRQ_MARK_HARDPOINTS if fields.len() >= 3 => {
                reach.hardpoints.push((
                    fields[0].to_string(),
                    fields[1].to_string(),
                    fields[2].to_string(),
                ));
            }
            _ => {}
        }
    }

    if reach.rolls.is_empty() {
        return Err("the enrollment rolls came back empty — the reach kindled nothing".to_string());
    }
    if reach.proscription.is_empty() {
        return Err("the proscription came back empty — the reach read nothing".to_string());
    }

    Ok(reach)
}

/// Read one `VAR=value` assignment out of a config file. Absent is not an error:
/// a bind vessel carries no graft image, a conjure vessel no bind image. The
/// value is returned with surrounding quotes peeled, which is how both the regime
/// files and the hardpoint sources spell it.
fn zrbtdrq_field_value(path: &Path, var: &str) -> Option<String> {
    let text = std::fs::read_to_string(path).ok()?;
    let prefix = format!("{}=", var);
    for line in text.lines() {
        if let Some(value) = line.strip_prefix(&prefix) {
            let value = value.trim();
            let value = value.strip_prefix('"').unwrap_or(value);
            let value = value.strip_suffix('"').unwrap_or(value);
            return Some(value.to_string());
        }
    }
    None
}

// ── Case: proscribed values ─────────────────────────────────

/// Every site-scoped field, in every instance of its regime, must hold its sterile
/// value — and so must every hardpoint constant. This is the net for identity that
/// has no shape: a workforce pool id, a project id, an org number are opaque
/// tokens no sweep can recognize, and this case is the only thing standing between
/// them and the upstream.
fn rbtdrq_proscribed_values(dir: &Path) -> rbtdre_Verdict {
    let root = match zrbtdrq_root() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };
    let reach = match zrbtdrq_reach(&root, dir) {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };

    let mut findings = Vec::new();
    let mut inventory = BTreeSet::new();

    for judgment in &reach.proscription {
        if judgment.disposition != ZRBTDRQ_DISPOSITION_SITE {
            continue;
        }
        for (scope, home) in &reach.homes {
            if *scope != judgment.scope {
                continue;
            }
            let path = root.join(home);
            let held = match zrbtdrq_field_value(&path, &judgment.var) {
                Some(v) => v,
                None => continue,
            };
            inventory.insert(format!("{}\t{}\t{:?}", home, judgment.var, held));
            if held != judgment.sterile {
                findings.push(zrbtdrq_Finding {
                    file: home.clone(),
                    line: 0,
                    detail: format!(
                        "{} is site-scoped and holds a value the proscription did not sanction",
                        judgment.var
                    ),
                });
            }
        }
    }

    for (path, var, sterile) in &reach.hardpoints {
        let held = match zrbtdrq_field_value(&root.join(path), var) {
            Some(v) => v,
            None => {
                findings.push(zrbtdrq_Finding {
                    file: path.clone(),
                    line: 0,
                    detail: format!("hardpoint {} is absent — the proscription names a home that moved", var),
                });
                continue;
            }
        };
        inventory.insert(format!("{}\t{}\t{:?}", path, var, held));
        if held != *sterile {
            findings.push(zrbtdrq_Finding {
                file: path.clone(),
                line: 0,
                detail: format!("hardpoint {} still holds site identity", var),
            });
        }
    }

    zrbtdrq_report(dir, "proscribed", &findings, &inventory, "unsterilized site value(s)")
}

// ── Case: proscription completeness ─────────────────────────

/// Every enrolled regime field must be judged, and every judgment must name an
/// enrolled field. The first direction is the one that matters: a field enrolled
/// tomorrow is site-scoped or common by nobody's decision until someone makes it,
/// and until then this reddens rather than shipping the field unexamined. The
/// second direction keeps the table from rotting: a judgment naming a field that
/// no longer exists is a row nobody has read in a long time.
///
/// The enrolled set is the LIVE roll, never a hand list and never a grep of the
/// regime sources — which is why this case caught three nameplate fields the
/// author's own reading of those sources had missed.
fn rbtdrq_proscription_complete(dir: &Path) -> rbtdre_Verdict {
    let root = match zrbtdrq_root() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };
    let reach = match zrbtdrq_reach(&root, dir) {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };

    let mut findings = Vec::new();
    let mut inventory = BTreeSet::new();

    let mut judged: BTreeMap<(String, String), String> = BTreeMap::new();
    for judgment in &reach.proscription {
        let key = (judgment.scope.clone(), judgment.var.clone());
        if judged.insert(key, judgment.disposition.clone()).is_some() {
            findings.push(zrbtdrq_Finding {
                file: ZRBTDRQ_PROSCRIPTION_HOME.to_string(),
                line: 0,
                detail: format!("{} is judged twice", judgment.var),
            });
        }
    }

    let mut enrolled = BTreeSet::new();
    for (scope, var) in &reach.rolls {
        enrolled.insert((scope.clone(), var.clone()));
        match judged.get(&(scope.clone(), var.clone())) {
            Some(disposition) => {
                inventory.insert(format!("{}\t{}\t{}", scope, var, disposition));
            }
            None => findings.push(zrbtdrq_Finding {
                file: ZRBTDRQ_PROSCRIPTION_HOME.to_string(),
                line: 0,
                detail: format!(
                    "{} is enrolled in {} but unjudged — declare it site-scoped or common",
                    var, scope
                ),
            }),
        }
    }

    for (scope, var) in judged.keys() {
        if !enrolled.contains(&(scope.clone(), var.clone())) {
            findings.push(zrbtdrq_Finding {
                file: ZRBTDRQ_PROSCRIPTION_HOME.to_string(),
                line: 0,
                detail: format!("{} is judged but no longer enrolled in {}", var, scope),
            });
        }
    }

    zrbtdrq_report(dir, "completeness", &findings, &inventory, "unjudged or stale field(s)")
}

/// The proscription's one home — the file a completeness finding points at.
pub(crate) const ZRBTDRQ_PROSCRIPTION_HOME: &str = "Tools/rbk/rblm_lustrate.sh";

// ── Case: the strip landed ──────────────────────────────────

/// No veiled tree may stand in the delivered candidate. The sweep above skips the
/// veiled trees, and the proscription says nothing about them, so on the
/// maintainer's tree both are silent about the largest body of withheld material
/// in the repository. This case is what makes that silence safe: it fails
/// outright if a veiled tree survived the strip.
///
/// Once no veiled tree stands, the candidate's root CLAUDE.md is checked for the
/// same two veil needles pyx's veil corpus hunts (ZRBTDRQ_VEIL_FILES) — a leak
/// that scan cannot catch on its own, because its census is harvested from the
/// veiled trees and it runs only where they still stand (loupe is SOURCE-TREE
/// ONLY). On the maintainer tree this second check is silent: root CLAUDE.md
/// there is the maintainer's own context and names withheld material on purpose.
/// zrbtdrq_veil_tree_exists is what tells the two trees apart, for both checks.
fn rbtdrq_veil_stripped(dir: &Path) -> rbtdre_Verdict {
    let root = match zrbtdrq_root() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };

    let mut findings = Vec::new();
    let inventory = BTreeSet::new();

    let census_root = root.join(ZRBTDRQ_VEIL_CENSUS_ROOT);
    if zrbtdrq_veil_tree_exists(&census_root) {
        findings.push(zrbtdrq_Finding {
            file: ZRBTDRQ_VEIL_CENSUS_ROOT.to_string(),
            line: 0,
            detail: "a withheld tree still stands — the strip did not land".to_string(),
        });
    } else {
        findings.extend(zrbtdrq_veil_self_proof());

        if let Ok(bytes) = std::fs::read(root.join(ZRBTDRQ_ROOT_CLAUDE)) {
            let text = String::from_utf8_lossy(&bytes);
            let empty_census = BTreeSet::new();
            zrbtdrq_veil_scan_text(ZRBTDRQ_ROOT_CLAUDE, &text, &empty_census, &mut findings);
        }
    }

    zrbtdrq_report(
        dir,
        "veilstrip",
        &findings,
        &inventory,
        "surviving withheld tree(s) or veil-leaking root CLAUDE.md",
    )
}

// ── Cases and fixture ───────────────────────────────────────

pub static RBTDRQ_CASES_DAMNATIO: &[rbtdre_Case] = &[
    case!(rbtdrq_identity_shapes),
    case!(rbtdrq_proscribed_values),
    case!(rbtdrq_proscription_complete),
    case!(rbtdrq_veil_stripped),
];

pub static RBTDRQ_FIXTURE_DAMNATIO: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_DAMNATIO,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRQ_CASES_DAMNATIO,
    credless: true,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: None, invocations: Some(0) },
};
