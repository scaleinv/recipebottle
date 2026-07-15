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
// RBTDRU — cupel: python cloud-step conformance scan.
//
// The python cloud steps (every `*.py` under a `Tools/rbk/rbgj*` job directory)
// are held to a supply-chain conformance discipline parallel to the bash
// command floor: imports are bounded to a stdlib floor anchored on each import's
// module root, dynamic-import surface is banned outright, and `subprocess`
// argv[0] literals are classified against the same GCB tool floor as bash
// command positions — one floor, two languages (CBG, CBp rules). Python
// elsewhere in the kits (e.g. in-bottle attack scripts) is not cloud-step
// surface and stays out of scope.
//
// Accepted scanner limits (lexer-grade, mirroring the bash lexer's): an aliased
// module (`import subprocess as sp`) hides the attribute chain, and code
// assembled in strings is invisible. The corpus is reviewed source; the scan is
// the drift tripwire, not a sandbox.

use std::collections::BTreeSet;
use std::path::{
    Path,
    PathBuf,
};

use crate::rbtdru_cupel::{
    zrbtdru_is_gcb,
    zrbtdru_walk_ext,
    zrbtdru_Finding,
    zrbtdru_ScanResult,
    ZRBTDRU_GCB_ALLOWED,
    ZRBTDRU_KIT_ROOTS,
    ZRBTDRU_LINT_EXCLUDED_DIR_PREFIXES,
    ZRBTDRU_POSIX_FLOOR,
    ZRBTDRU_PY_EXT,
    ZRBTDRU_PY_IMPORT_ALLOWED,
};

/// One lexical token of a python step body. The scanner needs identifiers
/// (import roots, dynamic-import surface, the `subprocess` attribute chain),
/// string literals (subprocess argv[0]), and the punctuation that joins them;
/// everything else — comments, whitespace — is dropped at lex time.
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum zrbtdru_PyToken {
    Ident(String),
    Str(String),
    Punct(char),
}

/// Tokenize python source into (line, token) pairs. Handles single- and
/// triple-quoted strings (escapes consumed, content preserved) and strips
/// `#` comments. Scanner-grade, not a parser — soundness rests on the step
/// files being valid python, exactly as the bash lexer rests on the corpus
/// being shellcheck-clean.
pub(crate) fn zrbtdru_py_tokens(src: &str) -> Vec<(usize, zrbtdru_PyToken)> {
    let chars: Vec<char> = src.chars().collect();
    let mut out: Vec<(usize, zrbtdru_PyToken)> = Vec::new();
    let mut i = 0;
    let mut line = 1;
    while i < chars.len() {
        let c = chars[i];
        if c == '\n' {
            line += 1;
            i += 1;
            continue;
        }
        if c == '#' {
            while i < chars.len() && chars[i] != '\n' {
                i += 1;
            }
            continue;
        }
        if c == '"' || c == '\'' {
            let quote = c;
            let triple = i + 2 < chars.len() && chars[i + 1] == quote && chars[i + 2] == quote;
            let start_line = line;
            let mut content = String::new();
            if triple {
                i += 3;
                while i < chars.len() {
                    if chars[i] == '\\' && i + 1 < chars.len() {
                        if chars[i + 1] == '\n' {
                            line += 1;
                        }
                        content.push(chars[i + 1]);
                        i += 2;
                        continue;
                    }
                    if chars[i] == quote
                        && i + 2 < chars.len()
                        && chars[i + 1] == quote
                        && chars[i + 2] == quote
                    {
                        i += 3;
                        break;
                    }
                    if chars[i] == '\n' {
                        line += 1;
                    }
                    content.push(chars[i]);
                    i += 1;
                }
            } else {
                i += 1;
                while i < chars.len() {
                    if chars[i] == '\\' && i + 1 < chars.len() {
                        content.push(chars[i + 1]);
                        i += 2;
                        continue;
                    }
                    if chars[i] == quote {
                        i += 1;
                        break;
                    }
                    if chars[i] == '\n' {
                        // Unterminated single-quoted string is a python syntax
                        // error; stop at the line so the scan stays sane.
                        break;
                    }
                    content.push(chars[i]);
                    i += 1;
                }
            }
            out.push((start_line, zrbtdru_PyToken::Str(content)));
            continue;
        }
        if c.is_ascii_alphabetic() || c == '_' {
            let mut ident = String::new();
            while i < chars.len() && (chars[i].is_ascii_alphanumeric() || chars[i] == '_') {
                ident.push(chars[i]);
                i += 1;
            }
            out.push((line, zrbtdru_PyToken::Ident(ident)));
            continue;
        }
        if !c.is_whitespace() {
            out.push((line, zrbtdru_PyToken::Punct(c)));
        }
        i += 1;
    }
    out
}

/// Module roots named by a python import line: `import a.b, c` yields
/// ["a", "c"]; `from x.y import z` yields ["x"]. Non-import lines yield
/// nothing.
pub(crate) fn zrbtdru_py_import_roots(line: &str) -> Vec<String> {
    let trimmed = line.trim_start();
    if let Some(rest) = trimmed.strip_prefix("from ") {
        let root: String = rest
            .trim_start()
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
            .collect();
        if root.is_empty() {
            return Vec::new();
        }
        return vec![root];
    }
    let rest = match trimmed.strip_prefix("import ") {
        Some(r) => r,
        None => return Vec::new(),
    };
    rest.split(',')
        .map(|part| {
            part.trim_start()
                .chars()
                .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
                .collect::<String>()
        })
        .filter(|root| !root.is_empty())
        .collect()
}

/// Scan one python step body, appending findings and inventory entries.
/// Three checks:
///
///   - Import allowlist — every import's module root must be on the python
///     stdlib floor. `from subprocess import …` is additionally rejected even
///     though the root is sanctioned: only the attribute-call form keeps
///     `subprocess` argv[0] visible to the scan below.
///   - Dynamic-import ban — `importlib` / `__import__` anywhere, and `exec` /
///     `eval` as builtin calls. Dynamic import defeats static conformance.
///   - Subprocess argv[0] — a `subprocess.«fn»([` whose first list element is
///     a string literal is classified against the GCB tool floor (POSIX floor
///     ∪ the curated container-tool list). A non-literal argv[0] is skipped,
///     like dynamic tokens in the bash scan.
///
/// Accepted scanner limits (lexer-grade, mirroring the bash lexer's): an
/// aliased module (`import subprocess as sp`) hides the attribute chain, and
/// code assembled in strings is invisible. The corpus is reviewed source; the
/// scan is the drift tripwire, not a sandbox.
pub(crate) fn zrbtdru_py_scan(
    src: &str,
    rel: &str,
    findings: &mut Vec<zrbtdru_Finding>,
    inventory: &mut BTreeSet<String>,
) {
    for (idx, line) in src.lines().enumerate() {
        for root in zrbtdru_py_import_roots(line) {
            inventory.insert(root.clone());
            if !ZRBTDRU_PY_IMPORT_ALLOWED.contains(&root.as_str()) {
                findings.push(zrbtdru_Finding {
                    file: rel.to_string(),
                    line: idx + 1,
                    command: root,
                    detail: "unsanctioned import — not in the python stdlib import floor"
                        .to_string(),
                });
            }
        }
        if line.trim_start().starts_with("from subprocess ") {
            findings.push(zrbtdru_Finding {
                file: rel.to_string(),
                line: idx + 1,
                command: "subprocess".to_string(),
                detail: "from-import of subprocess — use subprocess.«fn»(…) so argv[0] stays scannable"
                    .to_string(),
            });
        }
    }

    let tokens = zrbtdru_py_tokens(src);
    for (i, (line, tok)) in tokens.iter().enumerate() {
        let ident = match tok {
            zrbtdru_PyToken::Ident(s) => s.as_str(),
            _ => continue,
        };
        let after_dot = i > 0 && tokens[i - 1].1 == zrbtdru_PyToken::Punct('.');
        if ident == "importlib" || ident == "__import__" {
            findings.push(zrbtdru_Finding {
                file: rel.to_string(),
                line: *line,
                command: ident.to_string(),
                detail: "banned dynamic-import surface — defeats static conformance".to_string(),
            });
            continue;
        }
        if (ident == "exec" || ident == "eval") && !after_dot {
            let called = matches!(tokens.get(i + 1), Some((_, zrbtdru_PyToken::Punct('('))));
            if called {
                findings.push(zrbtdru_Finding {
                    file: rel.to_string(),
                    line: *line,
                    command: ident.to_string(),
                    detail: "banned dynamic-exec builtin — defeats static conformance".to_string(),
                });
            }
            continue;
        }
        if ident == "subprocess" && !after_dot {
            let shape_ok = matches!(tokens.get(i + 1), Some((_, zrbtdru_PyToken::Punct('.'))))
                && matches!(tokens.get(i + 2), Some((_, zrbtdru_PyToken::Ident(_))))
                && matches!(tokens.get(i + 3), Some((_, zrbtdru_PyToken::Punct('('))))
                && matches!(tokens.get(i + 4), Some((_, zrbtdru_PyToken::Punct('['))));
            if !shape_ok {
                continue;
            }
            if let Some((arg_line, zrbtdru_PyToken::Str(argv0))) = tokens.get(i + 5) {
                inventory.insert(argv0.clone());
                if !ZRBTDRU_POSIX_FLOOR.contains(&argv0.as_str())
                    && !ZRBTDRU_GCB_ALLOWED.contains(&argv0.as_str())
                {
                    findings.push(zrbtdru_Finding {
                        file: rel.to_string(),
                        line: *arg_line,
                        command: argv0.clone(),
                        detail:
                            "unknown subprocess target — not in the curated GCB container-tool allowlist"
                                .to_string(),
                    });
                }
            }
        }
    }
}

/// Walk the python cloud-step surface — every `*.py` under a GCB job
/// directory in the release kit roots — and scan each body. Python elsewhere
/// in the kits (e.g. in-bottle attack scripts) is not cloud-step surface and
/// stays out of scope.
pub(crate) fn zrbtdru_scan_python(tools: &Path) -> Result<zrbtdru_ScanResult, String> {
    let mut files: Vec<PathBuf> = Vec::new();
    for kit in ZRBTDRU_KIT_ROOTS {
        zrbtdru_walk_ext(&tools.join(kit), ZRBTDRU_PY_EXT, ZRBTDRU_LINT_EXCLUDED_DIR_PREFIXES, &mut files);
    }
    files.sort();

    let root = tools.parent().unwrap_or(tools);
    let mut findings: Vec<zrbtdru_Finding> = Vec::new();
    let mut inventory: BTreeSet<String> = BTreeSet::new();
    for path in &files {
        if !zrbtdru_is_gcb(path) {
            continue;
        }
        let src = std::fs::read_to_string(path)
            .map_err(|e| format!("read {} failed: {}", path.display(), e))?;
        let rel = path.strip_prefix(root).unwrap_or(path).display().to_string();
        zrbtdru_py_scan(&src, &rel, &mut findings, &mut inventory);
    }
    Ok(zrbtdru_ScanResult { findings, inventory })
}
