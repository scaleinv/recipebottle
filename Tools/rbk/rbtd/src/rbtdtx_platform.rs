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
// Tests for rbtdrx_platform — POSIX↔native path transmutation.
//
// Public API (rbtdrx_is_cygwin, rbtdrx_posix_to_native, rbtdrx_native_to_posix)
// caches Cygwin detection via OnceLock, so we exercise the impl helpers that
// take is_cygwin explicitly. This keeps both branches reachable from a Linux
// test host where the public API would always return identity.

use std::path::PathBuf;

use crate::rbtdrx_platform::{
    rbtdrx_cygdrive_to_native, rbtdrx_drive_to_cygdrive, rbtdrx_looks_native_windows,
    rbtdrx_native_to_posix_for, rbtdrx_posix_to_native_for, rbtdrx_repo_rel,
};

// ── Identity behaviour on non-Cygwin platforms ─────────────────────────

#[test]
fn rbtdtx_identity_posix_to_native_when_not_cygwin() {
    let cases = ["/home/brad/projects/foo", "/tmp/x", "/cygdrive/c/foo", "relative/path"];
    for c in cases {
        let got = rbtdrx_posix_to_native_for(c, false).expect("non-cygwin should never error");
        assert_eq!(got, PathBuf::from(c), "identity broken for {}", c);
    }
}

#[test]
fn rbtdtx_identity_native_to_posix_when_not_cygwin() {
    let cases = ["C:\\foo", "C:/foo", "/home/brad", "relative\\path"];
    for c in cases {
        let got = rbtdrx_native_to_posix_for(c, false);
        assert_eq!(got, c, "identity broken for {}", c);
    }
}

// ── Repo-canonical relative paths ───────────────────────────────────────

#[test]
fn rbtdtx_repo_rel_strips_root() {
    use std::path::Path;
    let root = Path::new("/repo");
    assert_eq!(rbtdrx_repo_rel(root, Path::new("/repo/Tools/rbk/x.sh")), "Tools/rbk/x.sh");
}

#[test]
fn rbtdtx_repo_rel_non_child_passes_whole() {
    use std::path::Path;
    assert_eq!(rbtdrx_repo_rel(Path::new("/repo"), Path::new("/other/y.sh")), "/other/y.sh");
}

#[test]
fn rbtdtx_repo_rel_normalizes_backslashes() {
    use std::path::Path;
    // On Windows strip_prefix yields `Tools\rbk\x.sh`; on POSIX a literal
    // backslash inside a component exercises the same replace.
    let rel = rbtdrx_repo_rel(Path::new("/repo"), Path::new("/repo/Tools\\rbk\\x.sh"));
    assert_eq!(rel, "Tools/rbk/x.sh");
}

// ── /cygdrive ↔ drive-letter fast path ─────────────────────────────────

#[test]
fn rbtdtx_cygdrive_to_native_basic() {
    assert_eq!(
        rbtdrx_cygdrive_to_native("/cygdrive/c/foo/bar"),
        Some(PathBuf::from("C:\\foo\\bar"))
    );
    assert_eq!(
        rbtdrx_cygdrive_to_native("/cygdrive/d/Users/brad/projects"),
        Some(PathBuf::from("D:\\Users\\brad\\projects"))
    );
}

#[test]
fn rbtdtx_cygdrive_to_native_drive_only() {
    // /cygdrive/c (no trailing slash, no tail) → "C:"
    assert_eq!(rbtdrx_cygdrive_to_native("/cygdrive/c"), Some(PathBuf::from("C:")));
}

#[test]
fn rbtdtx_cygdrive_to_native_uppercases_drive() {
    // Cygwin lowercases drives in /cygdrive/, but Rust callers prefer the
    // conventional uppercase form in PathBufs.
    assert_eq!(
        rbtdrx_cygdrive_to_native("/cygdrive/c/tmp"),
        Some(PathBuf::from("C:\\tmp"))
    );
}

#[test]
fn rbtdtx_cygdrive_to_native_rejects_non_drive() {
    // /cygdrive/foo/bar — not a single drive letter
    assert_eq!(rbtdrx_cygdrive_to_native("/cygdrive/foo/bar"), None);
    // /cygdrive/1/foo — digit, not alpha
    assert_eq!(rbtdrx_cygdrive_to_native("/cygdrive/1/foo"), None);
}

#[test]
fn rbtdtx_cygdrive_to_native_passes_non_cygdrive() {
    assert_eq!(rbtdrx_cygdrive_to_native("/home/brad/foo"), None);
    assert_eq!(rbtdrx_cygdrive_to_native("relative/path"), None);
    assert_eq!(rbtdrx_cygdrive_to_native(""), None);
}

#[test]
fn rbtdtx_drive_to_cygdrive_basic() {
    assert_eq!(
        rbtdrx_drive_to_cygdrive("C:\\foo\\bar"),
        Some("/cygdrive/c/foo/bar".to_string())
    );
    assert_eq!(
        rbtdrx_drive_to_cygdrive("D:/Users/brad"),
        Some("/cygdrive/d/Users/brad".to_string())
    );
}

#[test]
fn rbtdtx_drive_to_cygdrive_lowercases_drive() {
    assert_eq!(
        rbtdrx_drive_to_cygdrive("C:\\tmp"),
        Some("/cygdrive/c/tmp".to_string())
    );
}

#[test]
fn rbtdtx_drive_to_cygdrive_drive_only() {
    assert_eq!(rbtdrx_drive_to_cygdrive("C:"), Some("/cygdrive/c".to_string()));
}

#[test]
fn rbtdtx_drive_to_cygdrive_mixed_separators() {
    // Rust's PathBuf::join on Windows produces mixed paths — must still
    // convert cleanly.
    assert_eq!(
        rbtdrx_drive_to_cygdrive("C:\\foo/bar\\baz"),
        Some("/cygdrive/c/foo/bar/baz".to_string())
    );
}

#[test]
fn rbtdtx_drive_to_cygdrive_rejects_non_drive() {
    assert_eq!(rbtdrx_drive_to_cygdrive("/home/brad"), None);
    assert_eq!(rbtdrx_drive_to_cygdrive("foo:bar"), None);
    assert_eq!(rbtdrx_drive_to_cygdrive(""), None);
    assert_eq!(rbtdrx_drive_to_cygdrive("C"), None);
}

// ── looks_native_windows predicate ─────────────────────────────────────

#[test]
fn rbtdtx_looks_native_windows_recognises_drive_paths() {
    assert!(rbtdrx_looks_native_windows("C:\\foo"));
    assert!(rbtdrx_looks_native_windows("c:/foo"));
    assert!(rbtdrx_looks_native_windows("Z:"));
}

#[test]
fn rbtdtx_looks_native_windows_rejects_posix() {
    assert!(!rbtdrx_looks_native_windows("/home/brad"));
    assert!(!rbtdrx_looks_native_windows("/cygdrive/c/foo"));
    assert!(!rbtdrx_looks_native_windows("relative/path"));
    assert!(!rbtdrx_looks_native_windows(""));
}

// ── Composite conversion paths under is_cygwin=true ────────────────────

#[test]
fn rbtdtx_posix_to_native_cygdrive_shape() {
    let got = rbtdrx_posix_to_native_for("/cygdrive/c/Users/brad", true)
        .expect("/cygdrive shape uses fast path, no cygpath");
    assert_eq!(got, PathBuf::from("C:\\Users\\brad"));
}

#[test]
fn rbtdtx_posix_to_native_passes_native_shape_unchanged() {
    // Already-native input passes through without needing cygpath.
    let got = rbtdrx_posix_to_native_for("C:\\already\\native", true)
        .expect("native shape uses fast path, no cygpath");
    assert_eq!(got, PathBuf::from("C:\\already\\native"));
}

#[test]
fn rbtdtx_native_to_posix_drive_shape() {
    assert_eq!(
        rbtdrx_native_to_posix_for("C:\\foo\\bar", true),
        "/cygdrive/c/foo/bar"
    );
}

#[test]
fn rbtdtx_native_to_posix_normalises_posix_input() {
    // Already-POSIX input with stray backslashes (defensive normalisation).
    assert_eq!(
        rbtdrx_native_to_posix_for("/home/brad\\foo", true),
        "/home/brad/foo"
    );
}

#[test]
fn rbtdtx_native_to_posix_already_posix_passthrough() {
    assert_eq!(
        rbtdrx_native_to_posix_for("/home/brad/projects", true),
        "/home/brad/projects"
    );
}

// ── Round-trip identity for drive-letter paths ─────────────────────────

#[test]
fn rbtdtx_round_trip_drive_paths() {
    let originals = [
        "/cygdrive/c/foo/bar",
        "/cygdrive/d/Users/brad/projects/rbm",
        "/cygdrive/z/x",
    ];
    for orig in originals {
        let native = rbtdrx_posix_to_native_for(orig, true)
            .expect("/cygdrive uses fast path");
        let native_str = native.to_string_lossy();
        let round = rbtdrx_native_to_posix_for(&native_str, true);
        assert_eq!(round, orig, "round-trip broke for {}", orig);
    }
}
