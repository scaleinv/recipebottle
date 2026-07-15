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
// RBTDRF — reveille-tier test cases for theurge
//
// Ports enrollment-validation (47), regime-validation (21), and regime-smoke (7)
// from bash test framework to theurge. Cases shell out to bash — theurge invokes
// the actual bash utilities and asserts on exit codes. No reimplementation.

use std::path::Path;
use std::process::Command;

use crate::case;
use crate::rbtdre_engine::{rbtdre_Case, rbtdre_Disposition, rbtdre_Fixture, rbtdre_Tariff, rbtdre_Verdict};
use crate::rbtdri_invocation::{rbtdri_find_tabtarget_global, rbtdri_tabtarget_command, rbtdri_bash_program};
use crate::rbtdgc_consts::{
    BUWGC_RC_RENDER,
    BUWGC_RC_VALIDATE,
    BUWGC_RS_RENDER,
    BUWGC_RS_VALIDATE,
    RBTDGC_BAND_CREDLESS,
    RBTDGC_BAND_ENROLL,
    RBTDGC_BAND_HYGIENE,
    RBTDGC_BAND_RECIPE,
    RBTDGC_HYGIENE_CHECK_DOCKERFILE,
    RBTDGC_HYGIENE_CHECK_VESSEL,
    RBTDGC_JETTISON_IMAGE,
    RBTDGC_LIST_DEPOT,
    RBTDGC_PRESAGE_IMMURE,
    RBTDGC_RBRV_FILE,
    RBTDGC_RENDER_NAMEPLATE,
    RBTDGC_RENDER_PAYOR,
    RBTDGC_RENDER_REPO,
    RBTDGC_RENDER_VESSEL,
    RBTDGC_UNMAKE_DEPOT,
    RBTDGC_VALIDATE_NAMEPLATE,
    RBTDGC_VALIDATE_PAYOR,
    RBTDGC_VALIDATE_REPO,
    RBTDGC_VALIDATE_VESSEL,
};
use crate::rbtdrm_manifest::{
    RBTDRM_FIXTURE_CLIPBOARD,
    RBTDRM_FIXTURE_DOCKERFILE_HYGIENE,
    RBTDRM_FIXTURE_ENROLLMENT_VALIDATION,
    RBTDRM_FIXTURE_FOUNDRY_PATH,
    RBTDRM_FIXTURE_PODVM_RESOLVE,
    RBTDRM_FIXTURE_RECIPE_VALIDATION,
    RBTDRM_FIXTURE_REGIME_SMOKE,
    RBTDRM_FIXTURE_REGIME_VALIDATION,
};
use crate::rbtdrx_platform::rbtdrx_native_to_posix;

// Repo-root-relative kit paths. Test harnesses run with cwd = repo root, so
// these are repo-root-relative. Hoisted per RCG Identity Rule (cf.
// VVCC_REGISTRY_PATH) so running-code joins reference a named const rather
// than an inline magic string.
pub(crate) const RBTDRF_RBK_ROOT: &str = "Tools/rbk";
pub(crate) const RBTDRF_BUV_VALIDATION: &str = "Tools/buk/buv_validation.sh";
const RBTDRF_BUC_COMMAND: &str = "Tools/buk/buc_command.sh";
const RBTDRF_BUYM_YELP: &str = "Tools/buk/buym_yelp.sh";
const RBTDRF_BUBC_CONSTANTS: &str = "Tools/buk/bubc_constants.sh";
const RBTDRF_BURD_REGIME: &str = "Tools/buk/burd_regime.sh";
const RBTDRF_RBLDS_SPINE: &str = "Tools/rbk/rblds_spine.sh";

// ── Helpers ──────────────────────────────────────────────────

// buv_report is a report path, not a buc_reject gate: its documented contract
// is "returns non-zero if any failed", a bare 1 — so the one report-mixed
// negative asserts this, not a band. Still precise enough to catch an off-band
// harness breakage (a buc_die elsewhere also exits 1, but the report's own
// failure is the last command and deterministic under set -e).
const RBTDRF_REPORT_NONZERO: i32 = 1;

/// Sub-assertion within a case: run bash snippet, assert the exact exit code.
/// `expect_code` is 0 for a positive; for a negative it is the rejection gate's
/// band code (buv_vet rejects with RBTDGC_BAND_ENROLL). Asserting the precise
/// code, not bare nonzero, closes the wrong-reason hole: a harness breakage
/// exits off-band and fails the case loud rather than passing as a "rejection".
struct RbtdrfSub {
    label: &'static str,
    setup: &'static str,
    command: &'static str,
    expect_code: i32,
}

impl RbtdrfSub {
    const fn ok(label: &'static str, setup: &'static str) -> Self {
        Self { label, setup, command: "buv_vet \"TEST\"", expect_code: 0 }
    }
    const fn fatal(label: &'static str, setup: &'static str) -> Self {
        Self { label, setup, command: "buv_vet \"TEST\"", expect_code: RBTDGC_BAND_ENROLL }
    }
    const fn ok_cmd(label: &'static str, setup: &'static str, command: &'static str) -> Self {
        Self { label, setup, command, expect_code: 0 }
    }
    const fn fatal_cmd(
        label: &'static str,
        setup: &'static str,
        command: &'static str,
        expect_code: i32,
    ) -> Self {
        Self { label, setup, command, expect_code }
    }
}

/// Run a bash script, return (exit_code, stdout, stderr). Saves traces to case dir.
pub(crate) fn rbtdrf_run_bash(
    project_root: &Path,
    script: &str,
    dir: &Path,
    trace_prefix: &str,
) -> Result<(i32, String, String), String> {
    let output = Command::new(rbtdri_bash_program())
        .arg("-c")
        .arg(script)
        .current_dir(project_root)
        .output()
        .map_err(|e| format!("bash execution failed: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
    let code = output.status.code().unwrap_or(-1);

    let _ = std::fs::write(dir.join(format!("{}-script.sh", trace_prefix)), script);
    let _ = std::fs::write(dir.join(format!("{}-stdout.txt", trace_prefix)), &stdout);
    let _ = std::fs::write(dir.join(format!("{}-stderr.txt", trace_prefix)), &stderr);

    Ok((code, stdout, stderr))
}

/// Run enrollment-validation sub-assertions against BUV.
fn rbtdrf_run_ev(
    dir: &Path,
    enrollment: &str,
    subs: &[RbtdrfSub],
) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };
    let buv = root.join(RBTDRF_BUV_VALIDATION);

    for (i, sub) in subs.iter().enumerate() {
        let script = format!(
            "set -euo pipefail\nsource '{}'\nzbuv_kindle\nzbuv_reset_enrollment\n{}\n{}\n{}",
            rbtdrx_native_to_posix(&buv),
            enrollment,
            sub.setup,
            sub.command,
        );

        match rbtdrf_run_bash(&root, &script, dir, &format!("sub-{}", i)) {
            Ok((code, _, stderr)) => {
                if code != sub.expect_code {
                    return rbtdre_Verdict::Fail(format!(
                        "{}: expected exit {}, got {}\nstderr:\n{}",
                        sub.label, sub.expect_code, code, stderr
                    ));
                }
            }
            Err(e) => {
                return rbtdre_Verdict::Fail(format!("{}: {}", sub.label, e));
            }
        }
    }
    rbtdre_Verdict::Pass
}

/// Run a tabtarget and check exit 0.
fn rbtdrf_run_tt(
    project_root: &Path,
    colophon: &str,
    args: &[&str],
    dir: &Path,
    label: &str,
) -> Result<(), String> {
    let tt = rbtdri_find_tabtarget_global(project_root, colophon)?;
    let output = rbtdri_tabtarget_command(&tt)
        .args(args)
        .current_dir(project_root)
        .output()
        .map_err(|e| format!("{}: failed to run {}: {}", label, tt.display(), e))?;

    let code = output.status.code().unwrap_or(-1);
    let _ = std::fs::write(dir.join(format!("{}-stdout.txt", label)), &output.stdout);
    let _ = std::fs::write(dir.join(format!("{}-stderr.txt", label)), &output.stderr);

    if code != 0 {
        return Err(format!(
            "{}: {} exited {} — {}",
            label,
            colophon,
            code,
            String::from_utf8_lossy(&output.stderr),
        ));
    }
    Ok(())
}

/// Run a tabtarget expected to exit with a specific non-zero code. Asserts the
/// exact exit code rather than bare non-zero, closing the wrong-reason hole:
/// a harness breakage exits off-band and fails the case loud. Invocation errors
/// (tabtarget not found, launcher failure) still propagate as Err.
fn rbtdrf_run_tt_neg(
    project_root: &Path,
    colophon: &str,
    args: &[&str],
    dir: &Path,
    label: &str,
    expect_code: i32,
) -> Result<(), String> {
    let tt = rbtdri_find_tabtarget_global(project_root, colophon)?;
    let output = rbtdri_tabtarget_command(&tt)
        .args(args)
        .current_dir(project_root)
        .output()
        .map_err(|e| format!("{}: failed to run {}: {}", label, tt.display(), e))?;

    let code = output.status.code().unwrap_or(-1);
    let _ = std::fs::write(dir.join(format!("{}-stdout.txt", label)), &output.stdout);
    let _ = std::fs::write(dir.join(format!("{}-stderr.txt", label)), &output.stderr);

    if code != expect_code {
        return Err(format!(
            "{}: {} expected exit {}, got {}\nstderr:\n{}",
            label, colophon, expect_code, code,
            String::from_utf8_lossy(&output.stderr),
        ));
    }
    Ok(())
}

// ── Enrollment-validation cases ─────────────────────────────

// --- Length types ---

fn rbtdrf_ev_string_valid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Strings\"\n\
         buv_string_enroll TEST_NAME 1 20 \"Test name\"\n\
         buv_string_enroll TEST_DESC 3 50 \"Test description\"",
        &[RbtdrfSub::ok("valid strings",
            "export TEST_NAME=\"hello\"\nexport TEST_DESC=\"a valid description\"")],
    )
}

fn rbtdrf_ev_string_empty_optional(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Strings\"\n\
         buv_string_enroll TEST_OPT 0 20 \"Optional field\"",
        &[RbtdrfSub::ok("empty optional", "export TEST_OPT=\"\"")],
    )
}

fn rbtdrf_ev_string_too_short(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Strings\"\n\
         buv_string_enroll TEST_NAME 5 20 \"Test name\"",
        &[RbtdrfSub::fatal("too short", "export TEST_NAME=\"ab\"")],
    )
}

fn rbtdrf_ev_string_too_long(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Strings\"\n\
         buv_string_enroll TEST_NAME 1 5 \"Test name\"",
        &[RbtdrfSub::fatal("too long", "export TEST_NAME=\"toolongvalue\"")],
    )
}

fn rbtdrf_ev_string_empty_required(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Strings\"\n\
         buv_string_enroll TEST_NAME 1 20 \"Test name\"",
        &[RbtdrfSub::fatal("empty required", "export TEST_NAME=\"\"")],
    )
}

fn rbtdrf_ev_xname_valid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Xnames\"\n\
         buv_xname_enroll TEST_IDENT 2 12 \"Identifier\"",
        &[
            RbtdrfSub::ok("standard xname", "export TEST_IDENT=\"myName\""),
            RbtdrfSub::ok("underscore and hyphen", "export TEST_IDENT=\"my_var-1\""),
        ],
    )
}

fn rbtdrf_ev_xname_invalid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Xnames\"\n\
         buv_xname_enroll TEST_IDENT 2 12 \"Identifier\"",
        &[
            RbtdrfSub::fatal("starts with digit", "export TEST_IDENT=\"1bad\""),
            RbtdrfSub::fatal("contains dot", "export TEST_IDENT=\"my.name\""),
            RbtdrfSub::fatal("too short", "export TEST_IDENT=\"x\""),
            RbtdrfSub::fatal("too long", "export TEST_IDENT=\"abcdefghijklm\""),
        ],
    )
}

fn rbtdrf_ev_gname_valid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Gnames\"\n\
         buv_gname_enroll TEST_PROJECT 3 20 \"Project ID\"",
        &[RbtdrfSub::ok("valid gname", "export TEST_PROJECT=\"my-project-01\"")],
    )
}

fn rbtdrf_ev_gname_invalid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Gnames\"\n\
         buv_gname_enroll TEST_PROJECT 3 20 \"Project ID\"",
        &[
            RbtdrfSub::fatal("uppercase", "export TEST_PROJECT=\"MyProject\""),
            RbtdrfSub::fatal("ends with hyphen", "export TEST_PROJECT=\"my-project-\""),
            RbtdrfSub::fatal("starts with digit", "export TEST_PROJECT=\"1project\""),
        ],
    )
}

fn rbtdrf_ev_fqin_valid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"FQINs\"\n\
         buv_fqin_enroll TEST_IMAGE 5 100 \"Image reference\"",
        &[RbtdrfSub::ok("valid fqin",
            "export TEST_IMAGE=\"us-central1-docker.pkg.dev/my-proj/repo/image:latest\"")],
    )
}

fn rbtdrf_ev_fqin_invalid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"FQINs\"\n\
         buv_fqin_enroll TEST_IMAGE 5 100 \"Image reference\"",
        &[
            RbtdrfSub::fatal("special char", "export TEST_IMAGE=\".invalid/path\""),
            RbtdrfSub::fatal("empty", "export TEST_IMAGE=\"\""),
        ],
    )
}

// --- Choice types ---

fn rbtdrf_ev_bool_valid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Booleans\"\n\
         buv_bool_enroll TEST_ENABLED \"Feature enabled\"",
        &[
            RbtdrfSub::ok("value 1", "export TEST_ENABLED=\"1\""),
            RbtdrfSub::ok("value 0", "export TEST_ENABLED=\"0\""),
        ],
    )
}

fn rbtdrf_ev_bool_invalid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Booleans\"\n\
         buv_bool_enroll TEST_ENABLED \"Feature enabled\"",
        &[
            RbtdrfSub::fatal("string true", "export TEST_ENABLED=\"true\""),
            RbtdrfSub::fatal("string yes", "export TEST_ENABLED=\"yes\""),
            RbtdrfSub::fatal("number 2", "export TEST_ENABLED=\"2\""),
        ],
    )
}

fn rbtdrf_ev_bool_empty(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Booleans\"\n\
         buv_bool_enroll TEST_ENABLED \"Feature enabled\"",
        &[RbtdrfSub::fatal("empty", "export TEST_ENABLED=\"\"")],
    )
}

fn rbtdrf_ev_enum_valid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Enums\"\n\
         buv_enum_enroll TEST_MODE \"Operating mode\" debug release test",
        &[
            RbtdrfSub::ok("first choice", "export TEST_MODE=\"debug\""),
            RbtdrfSub::ok("last choice", "export TEST_MODE=\"test\""),
        ],
    )
}

fn rbtdrf_ev_enum_invalid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Enums\"\n\
         buv_enum_enroll TEST_MODE \"Operating mode\" debug release test",
        &[
            RbtdrfSub::fatal("not a choice", "export TEST_MODE=\"production\""),
            RbtdrfSub::fatal("case mismatch", "export TEST_MODE=\"Debug\""),
        ],
    )
}

fn rbtdrf_ev_enum_empty(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Enums\"\n\
         buv_enum_enroll TEST_MODE \"Operating mode\" debug release test",
        &[RbtdrfSub::fatal("empty", "export TEST_MODE=\"\"")],
    )
}

// --- Numeric types ---

fn rbtdrf_ev_decimal_valid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Numerics\"\n\
         buv_decimal_enroll TEST_COUNT 1 100 \"Item count\"",
        &[
            RbtdrfSub::ok("at minimum", "export TEST_COUNT=\"1\""),
            RbtdrfSub::ok("at maximum", "export TEST_COUNT=\"100\""),
            RbtdrfSub::ok("mid-range", "export TEST_COUNT=\"50\""),
        ],
    )
}

fn rbtdrf_ev_decimal_below(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Numerics\"\n\
         buv_decimal_enroll TEST_COUNT 1 100 \"Item count\"",
        &[RbtdrfSub::fatal("below minimum", "export TEST_COUNT=\"0\"")],
    )
}

fn rbtdrf_ev_decimal_above(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Numerics\"\n\
         buv_decimal_enroll TEST_COUNT 1 100 \"Item count\"",
        &[RbtdrfSub::fatal("above maximum", "export TEST_COUNT=\"101\"")],
    )
}

fn rbtdrf_ev_decimal_empty(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Numerics\"\n\
         buv_decimal_enroll TEST_COUNT 1 100 \"Item count\"",
        &[RbtdrfSub::fatal("empty", "export TEST_COUNT=\"\"")],
    )
}

fn rbtdrf_ev_ipv4_valid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Network\"\n\
         buv_ipv4_enroll TEST_ADDR \"Server address\"",
        &[RbtdrfSub::ok("valid address", "export TEST_ADDR=\"192.168.1.1\"")],
    )
}

fn rbtdrf_ev_ipv4_invalid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Network\"\n\
         buv_ipv4_enroll TEST_ADDR \"Server address\"",
        &[
            RbtdrfSub::fatal("not dotted-quad", "export TEST_ADDR=\"not-an-ip\""),
            RbtdrfSub::fatal("empty", "export TEST_ADDR=\"\""),
        ],
    )
}

fn rbtdrf_ev_port_valid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Network\"\n\
         buv_port_enroll TEST_PORT \"Service port\"",
        &[
            RbtdrfSub::ok("common port", "export TEST_PORT=\"8080\""),
            RbtdrfSub::ok("minimum port", "export TEST_PORT=\"1\""),
            RbtdrfSub::ok("maximum port", "export TEST_PORT=\"65535\""),
        ],
    )
}

fn rbtdrf_ev_port_invalid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Network\"\n\
         buv_port_enroll TEST_PORT \"Service port\"",
        &[
            RbtdrfSub::fatal("zero", "export TEST_PORT=\"0\""),
            RbtdrfSub::fatal("above max", "export TEST_PORT=\"65536\""),
            RbtdrfSub::fatal("empty", "export TEST_PORT=\"\""),
        ],
    )
}

// --- Reference types ---

const RBTDRF_VALID_DIGEST: &str =
    "sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789";

fn rbtdrf_ev_odref_valid(dir: &Path) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };
    let buv = root.join(RBTDRF_BUV_VALIDATION);
    let enrollment = format!(
        "set -euo pipefail\nsource '{}'\nzbuv_kindle\nzbuv_reset_enrollment\n\
         buv_regime_enroll \"TEST\"\nbuv_group_enroll \"References\"\n\
         buv_odref_enroll TEST_IMAGE \"Container image\"",
        rbtdrx_native_to_posix(&buv),
    );
    let d = RBTDRF_VALID_DIGEST;

    let subs: &[(&str, &str)] = &[
        ("standard registry", &format!("docker.io/library/alpine@{}", d)),
        ("multi-level repo", &format!("us-central1-docker.pkg.dev/my-proj/my-repo/tool@{}", d)),
        ("registry with port", &format!("registry.local:5000/myimage@{}", d)),
    ];

    for (i, (label, image)) in subs.iter().enumerate() {
        let script = format!("{}\nexport TEST_IMAGE=\"{}\"\nbuv_vet \"TEST\"", enrollment, image);
        match rbtdrf_run_bash(&root, &script, dir, &format!("sub-{}", i)) {
            Ok((0, _, _)) => {}
            Ok((code, _, _)) => {
                return rbtdre_Verdict::Fail(format!("{}: expected ok, got exit {}", label, code));
            }
            Err(e) => return rbtdre_Verdict::Fail(format!("{}: {}", label, e)),
        }
    }
    rbtdre_Verdict::Pass
}

fn rbtdrf_ev_odref_no_digest(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"References\"\n\
         buv_odref_enroll TEST_IMAGE \"Container image\"",
        &[RbtdrfSub::fatal("tag only",
            "export TEST_IMAGE=\"docker.io/library/alpine:latest\"")],
    )
}

fn rbtdrf_ev_odref_malformed(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"References\"\n\
         buv_odref_enroll TEST_IMAGE \"Container image\"",
        &[
            RbtdrfSub::fatal("wrong algorithm",
                "export TEST_IMAGE=\"docker.io/library/alpine@md5:abcdef0123456789\""),
            RbtdrfSub::fatal("short hex",
                "export TEST_IMAGE=\"docker.io/library/alpine@sha256:abcdef\""),
            RbtdrfSub::fatal("uppercase hex",
                "export TEST_IMAGE=\"docker.io/library/alpine@sha256:ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef0123456789\""),
        ],
    )
}

fn rbtdrf_ev_odref_empty(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"References\"\n\
         buv_odref_enroll TEST_IMAGE \"Container image\"",
        &[RbtdrfSub::fatal("empty", "export TEST_IMAGE=\"\"")],
    )
}

// --- List types ---

fn rbtdrf_ev_list_string_valid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Lists\"\n\
         buv_list_string_enroll TEST_TAGS 2 10 \"Tags\"",
        &[RbtdrfSub::ok("valid items", "export TEST_TAGS=\"foo bar baz\"")],
    )
}

fn rbtdrf_ev_list_string_empty(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Lists\"\n\
         buv_list_string_enroll TEST_TAGS 2 10 \"Tags\"",
        &[RbtdrfSub::ok("empty list", "export TEST_TAGS=\"\"")],
    )
}

fn rbtdrf_ev_list_string_bad_item(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Lists\"\n\
         buv_list_string_enroll TEST_TAGS 3 10 \"Tags\"",
        &[
            RbtdrfSub::fatal("item too short", "export TEST_TAGS=\"good ab okay\""),
            RbtdrfSub::fatal("item too long", "export TEST_TAGS=\"good toolongvalue okay\""),
        ],
    )
}

fn rbtdrf_ev_list_ipv4_valid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Lists\"\n\
         buv_list_ipv4_enroll TEST_SERVERS \"Server addresses\"",
        &[RbtdrfSub::ok("valid addresses",
            "export TEST_SERVERS=\"192.168.1.1 10.0.0.1 172.16.0.1\"")],
    )
}

fn rbtdrf_ev_list_ipv4_invalid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Lists\"\n\
         buv_list_ipv4_enroll TEST_SERVERS \"Server addresses\"",
        &[RbtdrfSub::fatal("bad address",
            "export TEST_SERVERS=\"192.168.1.1 not-an-ip 10.0.0.1\"")],
    )
}

fn rbtdrf_ev_list_ipv4_empty(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Lists\"\n\
         buv_list_ipv4_enroll TEST_SERVERS \"Server addresses\"",
        &[RbtdrfSub::ok("empty list", "export TEST_SERVERS=\"\"")],
    )
}

fn rbtdrf_ev_list_gname_valid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Lists\"\n\
         buv_list_gname_enroll TEST_PROJECTS 3 20 \"Project IDs\"",
        &[RbtdrfSub::ok("valid names",
            "export TEST_PROJECTS=\"my-project other-proj test-01\"")],
    )
}

fn rbtdrf_ev_list_gname_invalid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Lists\"\n\
         buv_list_gname_enroll TEST_PROJECTS 3 20 \"Project IDs\"",
        &[RbtdrfSub::fatal("uppercase in item",
            "export TEST_PROJECTS=\"my-project BadName test-01\"")],
    )
}

// --- Gating ---

fn rbtdrf_ev_gate_active_valid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Gated Features\"\n\
         buv_enum_enroll TEST_MODE \"Feature mode\" enabled disabled\n\
         buv_gate_enroll TEST_MODE enabled\n\
         buv_port_enroll TEST_PORT \"Feature port\"",
        &[RbtdrfSub::ok("gate active valid",
            "export TEST_MODE=\"enabled\"\nexport TEST_PORT=\"8080\"")],
    )
}

fn rbtdrf_ev_gate_active_invalid(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Gated Features\"\n\
         buv_enum_enroll TEST_MODE \"Feature mode\" enabled disabled\n\
         buv_gate_enroll TEST_MODE enabled\n\
         buv_port_enroll TEST_PORT \"Feature port\"",
        &[RbtdrfSub::fatal("gate active invalid",
            "export TEST_MODE=\"enabled\"\nexport TEST_PORT=\"0\"")],
    )
}

fn rbtdrf_ev_gate_inactive(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Gated Features\"\n\
         buv_enum_enroll TEST_MODE \"Feature mode\" enabled disabled\n\
         buv_gate_enroll TEST_MODE enabled\n\
         buv_port_enroll TEST_PORT \"Feature port\"",
        &[RbtdrfSub::ok("gate inactive skips",
            "export TEST_MODE=\"disabled\"\nexport TEST_PORT=\"invalid-not-checked\"")],
    )
}

fn rbtdrf_ev_gate_multi(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\n\
         buv_group_enroll \"Core\"\n\
         buv_xname_enroll TEST_NAME 2 12 \"Service name\"\n\
         buv_group_enroll \"Feature A\"\n\
         buv_enum_enroll TEST_FEAT_A \"Feature A mode\" on off\n\
         buv_gate_enroll TEST_FEAT_A on\n\
         buv_port_enroll TEST_FEAT_A_PORT \"Feature A port\"\n\
         buv_group_enroll \"Feature B\"\n\
         buv_enum_enroll TEST_FEAT_B \"Feature B mode\" on off\n\
         buv_gate_enroll TEST_FEAT_B on\n\
         buv_string_enroll TEST_FEAT_B_LABEL 1 20 \"Feature B label\"",
        &[
            RbtdrfSub::ok("A on, B off",
                "export TEST_NAME=\"myservice\"\n\
                 export TEST_FEAT_A=\"on\"\nexport TEST_FEAT_A_PORT=\"9090\"\n\
                 export TEST_FEAT_B=\"off\"\nexport TEST_FEAT_B_LABEL=\"\""),
            RbtdrfSub::ok("both on",
                "export TEST_NAME=\"myservice\"\n\
                 export TEST_FEAT_A=\"on\"\nexport TEST_FEAT_A_PORT=\"9090\"\n\
                 export TEST_FEAT_B=\"on\"\nexport TEST_FEAT_B_LABEL=\"hello\""),
        ],
    )
}

// --- Enforce/Report ---

fn rbtdrf_ev_enforce_all_pass(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Core\"\n\
         buv_xname_enroll TEST_NAME 2 12 \"Name\"\n\
         buv_bool_enroll TEST_FLAG \"Flag\"\n\
         buv_decimal_enroll TEST_COUNT 1 10 \"Count\"",
        &[RbtdrfSub::ok("all pass",
            "export TEST_NAME=\"myname\"\nexport TEST_FLAG=\"1\"\nexport TEST_COUNT=\"5\"")],
    )
}

fn rbtdrf_ev_enforce_first_bad(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Core\"\n\
         buv_xname_enroll TEST_NAME 2 12 \"Name\"\n\
         buv_bool_enroll TEST_FLAG \"Flag\"\n\
         buv_decimal_enroll TEST_COUNT 1 10 \"Count\"",
        &[
            RbtdrfSub::fatal("first var invalid",
                "export TEST_NAME=\"1\"\nexport TEST_FLAG=\"1\"\nexport TEST_COUNT=\"5\""),
            RbtdrfSub::fatal("middle var invalid",
                "export TEST_NAME=\"myname\"\nexport TEST_FLAG=\"maybe\"\nexport TEST_COUNT=\"5\""),
            RbtdrfSub::fatal("last var invalid",
                "export TEST_NAME=\"myname\"\nexport TEST_FLAG=\"1\"\nexport TEST_COUNT=\"99\""),
        ],
    )
}

fn rbtdrf_ev_report_all_pass(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Core\"\n\
         buv_xname_enroll TEST_NAME 2 12 \"Name\"\n\
         buv_bool_enroll TEST_FLAG \"Flag\"",
        &[RbtdrfSub::ok_cmd("all pass report",
            "export TEST_NAME=\"myname\"\nexport TEST_FLAG=\"0\"",
            "buv_report \"TEST\" \"All-pass report\"")],
    )
}

fn rbtdrf_ev_report_mixed(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Core\"\n\
         buv_xname_enroll TEST_NAME 2 12 \"Name\"\n\
         buv_bool_enroll TEST_FLAG \"Flag\"",
        &[RbtdrfSub::fatal_cmd("mixed report",
            "export TEST_NAME=\"myname\"\nexport TEST_FLAG=\"bad\"",
            "buv_report \"TEST\" \"Mixed report\"", RBTDRF_REPORT_NONZERO)],
    )
}

fn rbtdrf_ev_report_gated(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_run_ev(dir,
        "buv_regime_enroll \"TEST\"\nbuv_group_enroll \"Gated\"\n\
         buv_enum_enroll TEST_MODE \"Mode\" on off\n\
         buv_gate_enroll TEST_MODE on\n\
         buv_port_enroll TEST_PORT \"Port\"",
        &[RbtdrfSub::ok_cmd("gated report passes",
            "export TEST_MODE=\"off\"\nexport TEST_PORT=\"\"",
            "buv_report \"TEST\" \"Gated report\"")],
    )
}

fn rbtdrf_ev_multiscope(dir: &Path) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };
    let buv = root.join(RBTDRF_BUV_VALIDATION);

    // Two-scope enrollment: ALPHA and BETA
    let enrollment = format!(
        "set -euo pipefail\nsource '{}'\nzbuv_kindle\nzbuv_reset_enrollment\n\
         buv_regime_enroll \"ALPHA\"\nbuv_group_enroll \"Alpha Vars\"\n\
         buv_bool_enroll TEST_ALPHA_FLAG \"Alpha flag\"\n\
         buv_regime_enroll \"BETA\"\nbuv_group_enroll \"Beta Vars\"\n\
         buv_bool_enroll TEST_BETA_FLAG \"Beta flag\"\n\
         export TEST_ALPHA_FLAG=\"1\"\nexport TEST_BETA_FLAG=\"bad\"\n",
        rbtdrx_native_to_posix(&buv),
    );

    // Sub 1: vet ALPHA passes (BETA is bad but not in scope)
    let script1 = format!("{}buv_vet \"ALPHA\"", enrollment);
    match rbtdrf_run_bash(&root, &script1, dir, "sub-0") {
        Ok((code, _, _)) if code == 0 => {}
        Ok((code, _, _)) => {
            return rbtdre_Verdict::Fail(format!("alpha scope: expected ok, got exit {}", code));
        }
        Err(e) => return rbtdre_Verdict::Fail(format!("alpha scope: {}", e)),
    }

    // Sub 2: vet BETA fails at the buv enrollment gate (band_enroll)
    let script2 = format!("{}buv_vet \"BETA\"", enrollment);
    match rbtdrf_run_bash(&root, &script2, dir, "sub-1") {
        Ok((code, _, _)) if code == RBTDGC_BAND_ENROLL => {}
        Ok((code, _, stderr)) => {
            return rbtdre_Verdict::Fail(format!(
                "beta scope: expected exit {}, got {}\nstderr:\n{}",
                RBTDGC_BAND_ENROLL, code, stderr
            ));
        }
        Err(e) => return rbtdre_Verdict::Fail(format!("beta scope: {}", e)),
    }

    rbtdre_Verdict::Pass
}

// ── Regime-validation cases ─────────────────────────────────

// Env-var name consts — single source of truth for prefix-related env vars
// referenced across rv_rbrr negatives and rs_rbrr_nonempty_prefix smoke.
const RBTDRF_VAR_RBRD_CLOUD_PREFIX: &str = "RBRD_CLOUD_PREFIX";
const RBTDRF_VAR_RBRR_RUNTIME_PREFIX: &str = "RBRR_RUNTIME_PREFIX";

// Expected RBGL_HALLMARKS_ROOT value — must match RBGC_GAR_CATEGORY_HALLMARKS.
const RBTDRF_VAL_HALLMARKS_ROOT: &str = "rbi_hm";

// --- Positive tests ---

fn rbtdrf_rv_rbrr_repo(dir: &Path) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };
    match rbtdrf_run_tt(&root, RBTDGC_VALIDATE_REPO, &[], dir, "rbrr-repo-validate") {
        Ok(()) => rbtdre_Verdict::Pass,
        Err(e) => rbtdre_Verdict::Fail(e),
    }
}

fn rbtdrf_rv_rbrv_all_vessels(dir: &Path) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };

    // Discover vessels: source rbrr.env to get RBRR_VESSEL_DIR, scan it
    let buv = root.join(RBTDRF_BUV_VALIDATION);
    let rbk = root.join(RBTDRF_RBK_ROOT);
    let buv_p = rbtdrx_native_to_posix(&buv);
    let rbk_p = rbtdrx_native_to_posix(&rbk);
    let script = format!(
        "set -euo pipefail\n\
         source '{}'\n\
         source '{}/rbcc_constants.sh'\n\
         source '{}/rbgc_constants.sh'\n\
         source '{}/rbrr_regime.sh'\n\
         source '{}/rbrd_regime.sh'\n\
         source '{}/rbdc_derived.sh'\n\
         zbuv_kindle\nzrbcc_kindle\n\
         source \"${{PWD}}/{moorings}/rbrr.env\"\n\
         source \"${{PWD}}/{moorings}/rbrd.env\"\n\
         zrbrr_kindle\nzrbrd_kindle\nzrbrr_enforce\nzrbrd_enforce\nzrbdc_kindle\n\
         echo \"${{RBRR_VESSEL_DIR}}\"",
        buv_p,
        rbk_p, rbk_p, rbk_p, rbk_p, rbk_p,
        moorings = crate::rbtdgc_consts::RBTDGC_MOORINGS_DIR,
    );

    let vessel_dir = match rbtdrf_run_bash(&root, &script, dir, "rbrv-discover") {
        Ok((0, stdout, _)) => stdout.trim().to_string(),
        Ok((code, _, _)) => {
            return rbtdre_Verdict::Fail(format!("vessel discovery failed (exit {})", code));
        }
        Err(e) => return rbtdre_Verdict::Fail(e),
    };

    let entries = match std::fs::read_dir(&vessel_dir) {
        Ok(e) => e,
        Err(e) => {
            return rbtdre_Verdict::Fail(format!("cannot read {}: {}", vessel_dir, e));
        }
    };

    let mut found = false;
    for entry in entries.filter_map(|e| e.ok()) {
        let path = entry.path();
        if path.is_dir() && path.join(RBTDGC_RBRV_FILE).exists() {
            found = true;
            let sigil = entry.file_name().to_string_lossy().to_string();
            if let Err(e) = rbtdrf_run_tt(
                &root, RBTDGC_VALIDATE_VESSEL, &[&sigil], dir,
                &format!("rbrv-{}-validate", sigil),
            ) {
                return rbtdre_Verdict::Fail(e);
            }
        }
    }

    if !found {
        return rbtdre_Verdict::Fail(format!("no vessels found in {}", vessel_dir));
    }
    rbtdre_Verdict::Pass
}

fn rbtdrf_rv_rbrn_all_nameplates(dir: &Path) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };

    // Discover nameplates by listing rbmm_moorings/*/rbrn.env
    let rbk_dir = root.join(crate::rbtdgc_consts::RBTDGC_MOORINGS_DIR);
    let entries = match std::fs::read_dir(&rbk_dir) {
        Ok(e) => e,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot read {}: {}", crate::rbtdgc_consts::RBTDGC_MOORINGS_DIR, e)),
    };

    let mut found = false;
    for entry in entries.filter_map(|e| e.ok()) {
        let path = entry.path();
        if path.is_dir() && path.join("rbrn.env").exists() {
            found = true;
            let moniker = entry.file_name().to_string_lossy().to_string();
            if let Err(e) = rbtdrf_run_tt(
                &root, RBTDGC_VALIDATE_NAMEPLATE, &[&moniker], dir,
                &format!("rbrn-{}-validate", moniker),
            ) {
                return rbtdre_Verdict::Fail(e);
            }
        }
    }

    if !found {
        return rbtdre_Verdict::Fail(format!("no nameplates found in {}/", crate::rbtdgc_consts::RBTDGC_MOORINGS_DIR));
    }
    rbtdre_Verdict::Pass
}

// ── Regime-smoke cases ──────────────────────────────────────

fn rbtdrf_rs_render_validate(dir: &Path, render: &str, validate: &str, label: &str) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };
    if let Err(e) = rbtdrf_run_tt(&root, render, &[], dir, &format!("{}-render", label)) {
        return rbtdre_Verdict::Fail(e);
    }
    if let Err(e) = rbtdrf_run_tt(&root, validate, &[], dir, &format!("{}-validate", label)) {
        return rbtdre_Verdict::Fail(e);
    }
    rbtdre_Verdict::Pass
}

fn rbtdrf_rs_burc(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_rs_render_validate(dir, BUWGC_RC_RENDER, BUWGC_RC_VALIDATE, "burc")
}

fn rbtdrf_rs_burs(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_rs_render_validate(dir, BUWGC_RS_RENDER, BUWGC_RS_VALIDATE, "burs")
}

fn rbtdrf_rs_rbrn(dir: &Path) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };

    // Discover nameplates by listing rbmm_moorings/*/rbrn.env
    let rbk_dir = root.join(crate::rbtdgc_consts::RBTDGC_MOORINGS_DIR);
    let entries = match std::fs::read_dir(&rbk_dir) {
        Ok(e) => e,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot read {}: {}", crate::rbtdgc_consts::RBTDGC_MOORINGS_DIR, e)),
    };

    let mut found = false;
    for entry in entries.filter_map(|e| e.ok()) {
        let path = entry.path();
        if path.is_dir() && path.join("rbrn.env").exists() {
            found = true;
            let moniker = entry.file_name().to_string_lossy().to_string();
            if let Err(e) = rbtdrf_run_tt(
                &root, RBTDGC_RENDER_NAMEPLATE, &[&moniker], dir,
                &format!("rbrn-{}-render", moniker),
            ) {
                return rbtdre_Verdict::Fail(e);
            }
            if let Err(e) = rbtdrf_run_tt(
                &root, RBTDGC_VALIDATE_NAMEPLATE, &[&moniker], dir,
                &format!("rbrn-{}-validate", moniker),
            ) {
                return rbtdre_Verdict::Fail(e);
            }
        }
    }

    if !found {
        return rbtdre_Verdict::Fail(format!("no nameplates found in {}/", crate::rbtdgc_consts::RBTDGC_MOORINGS_DIR));
    }
    rbtdre_Verdict::Pass
}

fn rbtdrf_rs_rbrr(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_rs_render_validate(dir, RBTDGC_RENDER_REPO, RBTDGC_VALIDATE_REPO, "rbrr")
}

fn rbtdrf_rs_rbrr_nonempty_prefix(dir: &Path) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };
    let buv = root.join(RBTDRF_BUV_VALIDATION);
    let rbk = root.join(RBTDRF_RBK_ROOT);

    let buv_p = rbtdrx_native_to_posix(&buv);
    let rbk_p = rbtdrx_native_to_posix(&rbk);
    let script = format!(
        "set -euo pipefail\n\
         source '{}'\n\
         source '{}/rbcc_constants.sh'\n\
         source '{}/rbgc_constants.sh'\n\
         source '{}/rbrr_regime.sh'\n\
         source '{}/rbrd_regime.sh'\n\
         source '{}/rbgl_layout.sh'\n\
         zbuv_kindle\nzrbcc_kindle\nzrbgc_kindle\n\
         source \"${{PWD}}/{moorings}/rbrr.env\"\n\
         source \"${{PWD}}/{moorings}/rbrd.env\"\n\
         {cloud_var}=\"acme-\"\n\
         {runtime_var}=\"acme-\"\n\
         zrbrr_kindle\nzrbrd_kindle\nzrbrr_enforce\nzrbrd_enforce\nzrbgl_kindle\n\
         echo \"hallmarks_root=${{RBGL_HALLMARKS_ROOT}}\"\n\
         echo \"runtime_prefix=${{{runtime_var}}}\"",
        buv_p,
        rbk_p, rbk_p, rbk_p, rbk_p, rbk_p,
        cloud_var = RBTDRF_VAR_RBRD_CLOUD_PREFIX,
        runtime_var = RBTDRF_VAR_RBRR_RUNTIME_PREFIX,
        moorings = crate::rbtdgc_consts::RBTDGC_MOORINGS_DIR,
    );

    match rbtdrf_run_bash(&root, &script, dir, "rbrr-nonempty-prefix") {
        Ok((0, stdout, _)) => {
            let expected_line = format!("hallmarks_root={}", RBTDRF_VAL_HALLMARKS_ROOT);
            let hallmarks_ok = stdout
                .lines()
                .any(|l| l.trim() == expected_line);
            let runtime_ok = stdout
                .lines()
                .any(|l| l.trim() == "runtime_prefix=acme-");
            if !hallmarks_ok {
                return rbtdre_Verdict::Fail(format!(
                    "RBGL_HALLMARKS_ROOT did not match category constant; stdout:\n{}",
                    stdout
                ));
            }
            if !runtime_ok {
                return rbtdre_Verdict::Fail(format!(
                    "RBRR_RUNTIME_PREFIX did not propagate; stdout:\n{}",
                    stdout
                ));
            }
            rbtdre_Verdict::Pass
        }
        Ok((code, _, stderr)) => {
            rbtdre_Verdict::Fail(format!("kindle failed (exit {}); stderr:\n{}", code, stderr))
        }
        Err(e) => rbtdre_Verdict::Fail(e),
    }
}

fn rbtdrf_rs_rbrv(dir: &Path) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };

    // Discover vessels: source rbrr.env to get RBRR_VESSEL_DIR, scan it
    let buv = root.join(RBTDRF_BUV_VALIDATION);
    let rbk = root.join(RBTDRF_RBK_ROOT);

    let buv_p = rbtdrx_native_to_posix(&buv);
    let rbk_p = rbtdrx_native_to_posix(&rbk);
    let script = format!(
        "set -euo pipefail\n\
         source '{}'\n\
         source '{}/rbcc_constants.sh'\n\
         source '{}/rbgc_constants.sh'\n\
         source '{}/rbrr_regime.sh'\n\
         source '{}/rbrd_regime.sh'\n\
         source '{}/rbdc_derived.sh'\n\
         zbuv_kindle\nzrbcc_kindle\n\
         source \"${{PWD}}/{moorings}/rbrr.env\"\n\
         source \"${{PWD}}/{moorings}/rbrd.env\"\n\
         zrbrr_kindle\nzrbrd_kindle\nzrbrr_enforce\nzrbrd_enforce\nzrbdc_kindle\n\
         echo \"${{RBRR_VESSEL_DIR}}\"",
        buv_p,
        rbk_p, rbk_p, rbk_p, rbk_p, rbk_p,
        moorings = crate::rbtdgc_consts::RBTDGC_MOORINGS_DIR,
    );

    let vessel_dir = match rbtdrf_run_bash(&root, &script, dir, "rbrv-discover") {
        Ok((0, stdout, _)) => stdout.trim().to_string(),
        Ok((code, _, _)) => {
            return rbtdre_Verdict::Fail(format!("vessel discovery failed (exit {})", code));
        }
        Err(e) => return rbtdre_Verdict::Fail(e),
    };

    let entries = match std::fs::read_dir(&vessel_dir) {
        Ok(e) => e,
        Err(e) => {
            return rbtdre_Verdict::Fail(format!("cannot read {}: {}", vessel_dir, e));
        }
    };

    let mut found = false;
    for entry in entries.filter_map(|e| e.ok()) {
        let path = entry.path();
        if path.is_dir() && path.join(RBTDGC_RBRV_FILE).exists() {
            found = true;
            let sigil = entry.file_name().to_string_lossy().to_string();
            if let Err(e) = rbtdrf_run_tt(
                &root, RBTDGC_RENDER_VESSEL, &[&sigil], dir,
                &format!("rbrv-{}-render", sigil),
            ) {
                return rbtdre_Verdict::Fail(e);
            }
            if let Err(e) = rbtdrf_run_tt(
                &root, RBTDGC_VALIDATE_VESSEL, &[&sigil], dir,
                &format!("rbrv-{}-validate", sigil),
            ) {
                return rbtdre_Verdict::Fail(e);
            }
        }
    }

    if !found {
        return rbtdre_Verdict::Fail(format!("no vessels found in {}", vessel_dir));
    }
    rbtdre_Verdict::Pass
}

fn rbtdrf_rs_rbrp(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_rs_render_validate(dir, RBTDGC_RENDER_PAYOR, RBTDGC_VALIDATE_PAYOR, "rbrp")
}

fn rbtdrf_rs_burd(dir: &Path) -> rbtdre_Verdict {
    // BURD dispatch environment verification — invoke a minimal tabtarget
    // (buw-rcv is fast, side-effect-free) and confirm the dispatch machinery
    // ran successfully. The original bash test verified BURD sentinel+enforce
    // inside a live dispatch context; here we verify dispatch works by observing
    // a tabtarget that goes through the full BUK dispatch path.
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };
    if let Err(e) = rbtdrf_run_tt(&root, BUWGC_RC_VALIDATE, &[], dir, "burd-dispatch") {
        return rbtdre_Verdict::Fail(e);
    }
    rbtdre_Verdict::Pass
}

// ── Tabtarget-refusal cases ─────────────────────────────────

/// rbw-dU empty-arg refusal. Invoking rbw-dU with no argument must die
/// non-zero and emit the rbw-dl pointer (operator discovery for candidate
/// depot project IDs) rather than fail silent or opaque. BUW dispatch merges
/// stderr→stdout via `2>&1` (bud_dispatch.sh:372), so the captured
/// stdout carries the buc_warn/buc_info/buc_tabtarget/buc_die output
/// from rbgp_depot_unmake's no-arg branch (rbgp_payor.sh:937-942).
///
/// Pure shell, no GCP traffic — refusal lands before authenticate.
fn rbtdrf_rs_unmake_empty_arg_refusal(dir: &Path) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };

    let tt = match rbtdri_find_tabtarget_global(&root, RBTDGC_UNMAKE_DEPOT) {
        Ok(p) => p,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };

    let output = match rbtdri_tabtarget_command(&tt).current_dir(&root).output() {
        Ok(o) => o,
        Err(e) => {
            return rbtdre_Verdict::Fail(format!(
                "failed to run {}: {}",
                tt.display(),
                e
            ));
        }
    };

    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
    let code = output.status.code().unwrap_or(-1);
    let _ = std::fs::write(dir.join("empty-arg-stdout.txt"), &stdout);
    let _ = std::fs::write(dir.join("empty-arg-stderr.txt"), &stderr);

    if code == 0 {
        return rbtdre_Verdict::Fail(format!(
            "{} exited 0 with no argument — empty-arg refusal contract violated",
            RBTDGC_UNMAKE_DEPOT
        ));
    }

    let combined = format!("{}{}", stdout, stderr);
    if !combined.contains(RBTDGC_LIST_DEPOT) {
        return rbtdre_Verdict::Fail(format!(
            "{} empty-arg refusal did not point at {} for operator discovery\n\
             stdout:\n{}\n\nstderr:\n{}",
            RBTDGC_UNMAKE_DEPOT, RBTDGC_LIST_DEPOT, stdout, stderr
        ));
    }

    rbtdre_Verdict::Pass
}

/// Credless-guard proof — the BUS0 suite-invariant case. A deliberate cloud
/// verb (rbw-iJ, registry delete) invoked from a reveille-tier fixture must die
/// at the token-mint chokepoint with the credless band code: the guard env
/// arrives via `rbtdri_tabtarget_command` because this fixture is
/// `credless: true`, and `rba_avow` rejects before touching the IdP or
/// any credential — so the verdict is identical on credentialed and bare
/// machines. The junk ref names a nonexistent namespace and the verb's
/// interactive confirm sits after the mint, so even a broken guard cannot
/// delete anything — the case just fails loud on the wrong exit code.
fn rbtdrf_rs_credless_guard_mint_refusal(dir: &Path) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };

    let tt = match rbtdri_find_tabtarget_global(&root, RBTDGC_JETTISON_IMAGE) {
        Ok(p) => p,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };

    let output = match rbtdri_tabtarget_command(&tt)
        .arg("rbi_xx/credless-guard-proof:none")
        .current_dir(&root)
        .output()
    {
        Ok(o) => o,
        Err(e) => {
            return rbtdre_Verdict::Fail(format!("failed to run {}: {}", tt.display(), e));
        }
    };

    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
    let code = output.status.code().unwrap_or(-1);
    let _ = std::fs::write(dir.join("credless-guard-stdout.txt"), &stdout);
    let _ = std::fs::write(dir.join("credless-guard-stderr.txt"), &stderr);

    if code != RBTDGC_BAND_CREDLESS {
        return rbtdre_Verdict::Fail(format!(
            "{} under the credless guard exited {} — expected the credless band \
             code {} from the token-mint gate\nstdout:\n{}\n\nstderr:\n{}",
            RBTDGC_JETTISON_IMAGE, code, RBTDGC_BAND_CREDLESS, stdout, stderr
        ));
    }

    rbtdre_Verdict::Pass
}

// ── Dockerfile-hygiene cases ────────────────────────────────
//
// Drives the Dockerfile FROM-line hygiene contract through the rbw-fhc and
// rbw-fhv tabtargets — exercising the contract surface, not module internals.
// Eight synthetic cases (5 positive, 3 negative) feed inline Dockerfile bodies
// to rbw-fhc; one all-vessels case iterates real conjure vessels through
// rbw-fhv with a Rust-side counter that fails verdict on zero iterations.

const RBTDRF_DH_BODY_PARAMETERIZED: &str = "FROM ${RBF_IMAGE_1}\n";
const RBTDRF_DH_BODY_SCRATCH: &str = "FROM scratch\n";
const RBTDRF_DH_BODY_MULTISTAGE_AS: &str = "FROM ${RBF_IMAGE_1} AS builder\n";
const RBTDRF_DH_BODY_EMPTY: &str = "";
const RBTDRF_DH_BODY_COMMENTS_ONLY: &str = "# top-level comment\n# another comment\n";
const RBTDRF_DH_BODY_HARDCODED_LITERAL: &str = "FROM python:3.12-slim\n";
const RBTDRF_DH_BODY_TAB_IN_FROM: &str = "FROM\t${RBF_IMAGE_1}\n";
const RBTDRF_DH_BODY_TRAILING_BACKSLASH: &str = "FROM ${RBF_IMAGE_1} \\\n";

fn rbtdrf_dh_run_synthetic(
    dir: &Path,
    label: &str,
    body: &str,
    expect_code: i32,
) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };
    let dockerfile = dir.join(format!("{}-Dockerfile", label));
    if let Err(e) = std::fs::write(&dockerfile, body) {
        return rbtdre_Verdict::Fail(format!("{}: write Dockerfile failed: {}", label, e));
    }
    let path_str = dockerfile.to_string_lossy().into_owned();
    let result = if expect_code == 0 {
        rbtdrf_run_tt(&root, RBTDGC_HYGIENE_CHECK_DOCKERFILE, &[&path_str], dir, label)
    } else {
        rbtdrf_run_tt_neg(&root, RBTDGC_HYGIENE_CHECK_DOCKERFILE, &[&path_str], dir, label, expect_code)
    };
    match result {
        Ok(()) => rbtdre_Verdict::Pass,
        Err(e) => rbtdre_Verdict::Fail(e),
    }
}

fn rbtdrf_dh_accept_parameterized(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_dh_run_synthetic(dir, "dh-accept-parameterized", RBTDRF_DH_BODY_PARAMETERIZED, 0)
}

fn rbtdrf_dh_accept_scratch(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_dh_run_synthetic(dir, "dh-accept-scratch", RBTDRF_DH_BODY_SCRATCH, 0)
}

fn rbtdrf_dh_accept_multistage_as(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_dh_run_synthetic(dir, "dh-accept-multistage-as", RBTDRF_DH_BODY_MULTISTAGE_AS, 0)
}

fn rbtdrf_dh_accept_empty(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_dh_run_synthetic(dir, "dh-accept-empty", RBTDRF_DH_BODY_EMPTY, 0)
}

fn rbtdrf_dh_accept_comments_only(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_dh_run_synthetic(dir, "dh-accept-comments-only", RBTDRF_DH_BODY_COMMENTS_ONLY, 0)
}

fn rbtdrf_dh_reject_hardcoded_literal(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_dh_run_synthetic(dir, "dh-reject-hardcoded-literal", RBTDRF_DH_BODY_HARDCODED_LITERAL, RBTDGC_BAND_HYGIENE)
}

fn rbtdrf_dh_reject_tab_in_from(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_dh_run_synthetic(dir, "dh-reject-tab-in-from", RBTDRF_DH_BODY_TAB_IN_FROM, RBTDGC_BAND_HYGIENE)
}

fn rbtdrf_dh_reject_trailing_backslash(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_dh_run_synthetic(dir, "dh-reject-trailing-backslash", RBTDRF_DH_BODY_TRAILING_BACKSLASH, RBTDGC_BAND_HYGIENE)
}

fn rbtdrf_dh_all_vessels_pass(dir: &Path) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };

    // Resolve RBRR_VESSEL_DIR via one-shot bash (kindle ceremony unavoidable
    // for derived-path resolution).
    let buv = root.join(RBTDRF_BUV_VALIDATION);
    let rbk = root.join(RBTDRF_RBK_ROOT);
    let buv_p = rbtdrx_native_to_posix(&buv);
    let rbk_p = rbtdrx_native_to_posix(&rbk);
    let resolve_script = format!(
        "set -euo pipefail\n\
         source '{}'\n\
         source '{}/rbcc_constants.sh'\n\
         source '{}/rbgc_constants.sh'\n\
         source '{}/rbrr_regime.sh'\n\
         source '{}/rbrd_regime.sh'\n\
         source '{}/rbdc_derived.sh'\n\
         zbuv_kindle\nzrbcc_kindle\n\
         source \"${{PWD}}/{moorings}/rbrr.env\"\n\
         source \"${{PWD}}/{moorings}/rbrd.env\"\n\
         zrbrr_kindle\nzrbrd_kindle\nzrbrr_enforce\nzrbrd_enforce\nzrbdc_kindle\n\
         printf '%s' \"${{RBRR_VESSEL_DIR}}\"",
        buv_p,
        rbk_p, rbk_p, rbk_p, rbk_p, rbk_p,
        moorings = crate::rbtdgc_consts::RBTDGC_MOORINGS_DIR,
    );
    let vessel_dir = match rbtdrf_run_bash(&root, &resolve_script, dir, "resolve-vessel-dir") {
        Ok((0, stdout, _)) => stdout,
        Ok((code, _, stderr)) => {
            return rbtdre_Verdict::Fail(format!(
                "resolve RBRR_VESSEL_DIR failed (exit {}): {}",
                code, stderr
            ));
        }
        Err(e) => return rbtdre_Verdict::Fail(e),
    };
    let vessel_dir = vessel_dir.trim();
    if vessel_dir.is_empty() {
        return rbtdre_Verdict::Fail("RBRR_VESSEL_DIR resolved to empty string".to_string());
    }

    let entries = match std::fs::read_dir(vessel_dir) {
        Ok(e) => e,
        Err(e) => {
            return rbtdre_Verdict::Fail(format!(
                "read_dir({}) failed: {}",
                vessel_dir, e
            ));
        }
    };

    // rbw-fhv silently succeeds on non-conjure vessels (hygiene contract is
    // vacuously satisfied where there's no local Dockerfile), so theurge
    // iterates without pre-filtering — surface integrity stays intact and
    // no rbrv.env internals are touched here.
    let mut count: usize = 0;
    for entry in entries {
        let entry = match entry {
            Ok(e) => e,
            Err(e) => return rbtdre_Verdict::Fail(format!("dir entry error: {}", e)),
        };
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        if !path.join(RBTDGC_RBRV_FILE).is_file() {
            continue;
        }
        let sigil = match path.file_name().and_then(|s| s.to_str()) {
            Some(s) => s.to_string(),
            None => continue,
        };

        if let Err(e) = rbtdrf_run_tt(
            &root,
            RBTDGC_HYGIENE_CHECK_VESSEL,
            &[&sigil],
            dir,
            &format!("vessel-{}", sigil),
        ) {
            return rbtdre_Verdict::Fail(e);
        }
        count += 1;
    }

    if count == 0 {
        return rbtdre_Verdict::Fail(format!(
            "zero vessels iterated under {} — busted RBRR_VESSEL_DIR resolution",
            vessel_dir
        ));
    }

    rbtdre_Verdict::Pass
}

// ── Foundry-path cases ──────────────────────────────────────
//
// Drives buc_native_path_capture directly: source buc_command.sh, force
// BURD_OSTYPE, assert the normalized stdout (or, for the bare-absolute
// unsurveyed shape, that the capture returns non-zero). The normalizer is
// sentinel-free and reads only its argument plus BURD_OSTYPE, so this stays a
// dependency-free unit test — no foundry kindle, no regime, no credentials —
// and exercises the Cygwin transform on any host by forcing the platform fact.

fn rbtdrf_np_run(
    dir: &Path,
    label: &str,
    ostype: &str,
    input: &str,
    expect: Option<&str>,
) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };
    let buc = root.join(RBTDRF_BUC_COMMAND);

    let assertion = match expect {
        Some(out) => format!("test \"$(buc_native_path_capture '{}')\" = '{}'", input, out),
        None => format!("buc_native_path_capture '{}'", input),
    };
    let script = format!(
        "set -euo pipefail\nsource '{}'\nexport BURD_OSTYPE='{}'\n{}",
        rbtdrx_native_to_posix(&buc),
        ostype,
        assertion,
    );

    let expect_ok = expect.is_some();
    match rbtdrf_run_bash(&root, &script, dir, label) {
        Ok((code, _, _)) => {
            let ok = code == 0;
            if ok == expect_ok {
                rbtdre_Verdict::Pass
            } else if expect_ok {
                rbtdre_Verdict::Fail(format!("{}: expected ok, got exit {}", label, code))
            } else {
                rbtdre_Verdict::Fail(format!("{}: expected non-zero (unsurveyed), got exit 0", label))
            }
        }
        Err(e) => rbtdre_Verdict::Fail(format!("{}: {}", label, e)),
    }
}

fn rbtdrf_np_cygdrive_transform(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_np_run(dir, "np-cygdrive-transform", "cygwin",
        "/cygdrive/c/Users/foo", Some("c:/Users/foo"))
}

fn rbtdrf_np_relative_passthrough(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_np_run(dir, "np-relative-passthrough", "cygwin",
        "rbmv_vessels/rbev-busybox", Some("rbmv_vessels/rbev-busybox"))
}

fn rbtdrf_np_native_passthrough(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_np_run(dir, "np-native-passthrough", "cygwin",
        "c:/Users/foo", Some("c:/Users/foo"))
}

fn rbtdrf_np_offcygwin_identity(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_np_run(dir, "np-offcygwin-identity", "linux-gnu",
        "/cygdrive/c/Users/foo", Some("/cygdrive/c/Users/foo"))
}

fn rbtdrf_np_bare_absolute_unsurveyed(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_np_run(dir, "np-bare-absolute-unsurveyed", "cygwin",
        "/etc/hosts", None)
}

// ── Redon-tick cases ────────────────────────────────────────
//
// Drives zrbfc_redon_tick (rbfcb_host.sh) — the build poll's mid-flight
// re-don — at its lapsed-sitting branch, deterministically and credless:
// XDG_RUNTIME_DIR is pointed at an empty scratch dir so the sitting cache
// resolves to nothing, the don's sitting read misses before any network
// touch, and the tick must die with the open-a-sitting advisory. The furnish
// ceremony mirrors rba_cli's zrba_furnish plus the don's rbrd/rbdc arm —
// committed regime files only; BURD_TEMP_DIR is supplied directly since no
// dispatch runs here. (The positive — the tick firing on cadence in a real
// short build — rides the hallmark-lifecycle ordain under the
// RBCC_tweak_redon_cadence seam, picket tier.)

/// Lapse-advisory fragment asserted on the tick's death. Mirror:
/// rbfcb_host.sh `zrbfc_redon_tick` buc_die line — same literal.
const RBTDRF_RT_LAPSE_FRAGMENT: &str = "sitting lapsed mid-build";

fn rbtdrf_rt_lapse_advisory(dir: &Path) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };
    let dir_p = rbtdrx_native_to_posix(dir);
    let buc_p = rbtdrx_native_to_posix(&root.join(RBTDRF_BUC_COMMAND));
    let buym_p = rbtdrx_native_to_posix(&root.join(RBTDRF_BUYM_YELP));
    let bubc_p = rbtdrx_native_to_posix(&root.join(RBTDRF_BUBC_CONSTANTS));
    let buv_p = rbtdrx_native_to_posix(&root.join(RBTDRF_BUV_VALIDATION));
    let burd_p = rbtdrx_native_to_posix(&root.join(RBTDRF_BURD_REGIME));
    let rbk_p = rbtdrx_native_to_posix(&root.join(RBTDRF_RBK_ROOT));

    let script = format!(
        "set -euo pipefail\n\
         export BURD_TEMP_DIR='{dir_p}'\n\
         export XDG_RUNTIME_DIR='{dir_p}/rt-no-sitting'\n\
         source '{buc_p}'\n\
         source '{buym_p}'\n\
         source '{bubc_p}'\n\
         source '{buv_p}'\n\
         source '{burd_p}'\n\
         source '{rbk_p}/rbrr_regime.sh'\n\
         source '{rbk_p}/rbrd_regime.sh'\n\
         source '{rbk_p}/rbrf_regime.sh'\n\
         source '{rbk_p}/rbrw_regime.sh'\n\
         source '{rbk_p}/rbcc_constants.sh'\n\
         source '{rbk_p}/rbgc_constants.sh'\n\
         source '{rbk_p}/rbdc_derived.sh'\n\
         source '{rbk_p}/rbgo_oauth.sh'\n\
         source '{rbk_p}/rba_auth.sh'\n\
         source '{rbk_p}/rbfcb_host.sh'\n\
         zbuv_kindle\n\
         zburd_kindle\n\
         source \"${{PWD}}/{moorings}/rbrr.env\"\n\
         source \"${{PWD}}/{moorings}/rbrd.env\"\n\
         zrbrr_kindle\n\
         zrbrd_kindle\n\
         zrbrr_enforce\n\
         zrbrd_enforce\n\
         zrbcc_kindle\n\
         zrbgc_kindle\n\
         zrbdc_kindle\n\
         zrbgo_kindle\n\
         zrba_kindle\n\
         rbcc_source_active_rbrf\n\
         source \"${{RBCC_rbrw_file}}\"\n\
         zrbrf_kindle\n\
         zrbrw_kindle\n\
         zrbfc_redon_tick 'LapseProbe' 'poll 1'\n",
        moorings = crate::rbtdgc_consts::RBTDGC_MOORINGS_DIR,
    );

    match rbtdrf_run_bash(&root, &script, dir, "rt-lapse-advisory") {
        Ok((code, stdout, stderr)) => {
            if code == 0 {
                return rbtdre_Verdict::Fail(
                    "rt-lapse-advisory: expected the tick to die on a lapsed sitting, got exit 0"
                        .to_string(),
                );
            }
            if !stdout.contains(RBTDRF_RT_LAPSE_FRAGMENT)
                && !stderr.contains(RBTDRF_RT_LAPSE_FRAGMENT)
            {
                return rbtdre_Verdict::Fail(format!(
                    "rt-lapse-advisory: exit {} without the lapse advisory '{}':\nstderr:\n{}",
                    code, RBTDRF_RT_LAPSE_FRAGMENT, stderr
                ));
            }
            rbtdre_Verdict::Pass
        }
        Err(e) => rbtdre_Verdict::Fail(format!("rt-lapse-advisory: {}", e)),
    }
}

// ── Clipboard cases ─────────────────────────────────────────
//
// Drives buc_clipboard_copy_predicate — BUK's platform-normalized clipboard
// copy (probe chain: pbcopy / clip.exe / wl-copy / xclip), the foundry-path
// sibling on the BUK-footing axis. The decline case proves the fail-soft
// contract deterministically by emptying PATH: the predicate must return
// non-zero without dying, leaving the z_buc_clipboard_tool result-global
// empty. The round-trip case proves a real copy lands by reading the
// clipboard back via arboard — read capability deliberately confined to this
// test binary, never on the shipped bash surface — saving and restoring the
// operator's clipboard text around the assert (non-text prior content cannot
// be restored; the clipboard is cleared instead). Roster-only fixture: the
// round-trip mutates the live desktop clipboard, so it runs on demand via
// FixtureRun, never as a suite passenger.

fn rbtdrf_cb_no_tool_decline(dir: &Path) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };
    let buc = root.join(RBTDRF_BUC_COMMAND);

    // Source first (needs PATH), then empty PATH so command -v finds no
    // external tool; the predicate must decline (non-zero) with the tool
    // result-global empty, and must not die on the way.
    let script = format!(
        "set -euo pipefail\nsource '{}'\nPATH=''\n\
         buc_clipboard_copy_predicate 'rbtd-clip-probe' && exit 1\n\
         test -z \"${{z_buc_clipboard_tool:-}}\" || exit 2\nexit 0",
        rbtdrx_native_to_posix(&buc),
    );

    match rbtdrf_run_bash(&root, &script, dir, "cb-no-tool-decline") {
        Ok((0, _, _)) => rbtdre_Verdict::Pass,
        Ok((1, _, _)) => rbtdre_Verdict::Fail(
            "cb-no-tool-decline: predicate claimed success with PATH emptied".to_string()),
        Ok((2, _, _)) => rbtdre_Verdict::Fail(
            "cb-no-tool-decline: z_buc_clipboard_tool non-empty with no tool present".to_string()),
        Ok((code, _, stderr)) => rbtdre_Verdict::Fail(format!(
            "cb-no-tool-decline: unexpected exit {} (predicate died?): {}", code, stderr)),
        Err(e) => rbtdre_Verdict::Fail(format!("cb-no-tool-decline: {}", e)),
    }
}

fn rbtdrf_cb_round_trip(dir: &Path) -> rbtdre_Verdict {
    // WSL split surface: the bash-side probe picks clip.exe (the Windows
    // clipboard) while this Linux-built binary reads the Wayland/X side.
    // WSLg bridges the two in some configurations — unsurveyed; skip until
    // proven, rather than fail on a mismatch our code did not cause.
    if std::env::var_os("WSL_DISTRO_NAME").is_some() || std::env::var_os("WSL_INTEROP").is_some() {
        return rbtdre_Verdict::Skip(
            "WSL: bash copies via clip.exe but a Linux test binary reads the Wayland/X clipboard — split unsurveyed".to_string());
    }

    let mut clipboard = match arboard::Clipboard::new() {
        Ok(c) => c,
        Err(e) => return rbtdre_Verdict::Skip(format!("no clipboard context: {}", e)),
    };
    // Save the operator's clipboard text for restore; Err means empty or
    // non-text (an image cannot be saved through the text API).
    let prior = clipboard.get_text().ok();

    let sentinel = format!("rbtd-clip-{}", std::process::id());

    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };
    let buc = root.join(RBTDRF_BUC_COMMAND);
    let script = format!(
        "set -euo pipefail\nsource '{}'\nbuc_clipboard_copy_predicate '{}'",
        rbtdrx_native_to_posix(&buc),
        sentinel,
    );

    match rbtdrf_run_bash(&root, &script, dir, "cb-round-trip") {
        Ok((0, _, _)) => {}
        Ok((_, _, _)) => {
            // No bash-side tool (or the tool declined) — the display-only
            // degradation environment, not a failure of the predicate.
            return rbtdre_Verdict::Skip(
                "no bash-side clipboard tool present (or copy declined) — display-only environment".to_string());
        }
        Err(e) => return rbtdre_Verdict::Fail(format!("cb-round-trip: {}", e)),
    }

    // Brief poll: some tools (wl-copy) serve the selection asynchronously.
    let mut seen = String::new();
    for _ in 0..10 {
        if let Ok(text) = clipboard.get_text() {
            seen = text;
            if seen == sentinel {
                break;
            }
        }
        std::thread::sleep(std::time::Duration::from_millis(200));
    }

    // Restore before verdicting, best-effort: prior text goes back; a prior
    // we could not read as text was already clobbered by the copy — clear
    // rather than leave test residue on the operator's clipboard.
    match prior {
        Some(text) => { let _ = clipboard.set_text(text); }
        None => { let _ = clipboard.clear(); }
    }

    if seen == sentinel {
        rbtdre_Verdict::Pass
    } else {
        rbtdre_Verdict::Fail(format!(
            "cb-round-trip: clipboard read back '{}' != sentinel '{}'", seen, sentinel))
    }
}

// ── Recipe-validation cases ─────────────────────────────────
//
// Drives zrbld_spine_validate — the Lode capture-assembly spine's dispatch-time
// substitution-coverage check — directly: write a substitution-keys file and an
// already-include-expanded step body, source buv_validation + rblds_spine and
// kindle buv so buc_log_args resolves, then assert the check accepts a fully
// covered body and returns non-zero at the first _RBGL_* reference absent from
// the keys. The check is sentinel-free and reads only its two file arguments, so
// this stays a dependency-free unit test — no rbld kindle, no regime, no creds.

fn rbtdrf_rc_run(
    dir: &Path,
    label: &str,
    keys: &str,
    body: &str,
    expect_code: i32,
) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };
    let keys_file = dir.join(format!("{}-keys.txt", label));
    let body_file = dir.join(format!("{}-body.sh", label));
    if let Err(e) = std::fs::write(&keys_file, keys) {
        return rbtdre_Verdict::Fail(format!("{}: write keys failed: {}", label, e));
    }
    if let Err(e) = std::fs::write(&body_file, body) {
        return rbtdre_Verdict::Fail(format!("{}: write body failed: {}", label, e));
    }
    let buv = root.join(RBTDRF_BUV_VALIDATION);
    let spine = root.join(RBTDRF_RBLDS_SPINE);
    let script = format!(
        "set -euo pipefail\n\
         source '{}'\n\
         source '{}'\n\
         zbuv_kindle\n\
         zrbld_spine_validate '{}' '{}'",
        rbtdrx_native_to_posix(&buv),
        rbtdrx_native_to_posix(&spine),
        rbtdrx_native_to_posix(&keys_file),
        rbtdrx_native_to_posix(&body_file),
    );

    match rbtdrf_run_bash(&root, &script, dir, label) {
        Ok((code, _, stderr)) => {
            if code == expect_code {
                rbtdre_Verdict::Pass
            } else {
                rbtdre_Verdict::Fail(format!(
                    "{}: expected exit {}, got {}\nstderr:\n{}",
                    label, expect_code, code, stderr
                ))
            }
        }
        Err(e) => rbtdre_Verdict::Fail(format!("{}: {}", label, e)),
    }
}

fn rbtdrf_rc_accept_all_covered(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_rc_run(dir, "rc-accept-all-covered",
        "_RBGL_A\n_RBGL_B\n", "echo \"${_RBGL_A}\" \"${_RBGL_B}\"\n", 0)
}

fn rbtdrf_rc_reject_missing_key(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_rc_run(dir, "rc-reject-missing-key",
        "_RBGL_A\n", "echo \"${_RBGL_B}\"\n", RBTDGC_BAND_RECIPE)
}

fn rbtdrf_rc_accept_comment_only(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_rc_run(dir, "rc-accept-comment-only",
        "_RBGL_A\n", "# uses _RBGL_ABSENT\necho \"${_RBGL_A}\"\n", 0)
}

fn rbtdrf_rc_reject_substring(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_rc_run(dir, "rc-reject-substring",
        "_RBGL_TAG_BOLE\n", "echo \"${_RBGL_TAG}\"\n", RBTDGC_BAND_RECIPE)
}

fn rbtdrf_rc_accept_substring_real(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_rc_run(dir, "rc-accept-substring-real",
        "_RBGL_TAG_BOLE\n", "echo \"${_RBGL_TAG_BOLE}\"\n", 0)
}

fn rbtdrf_rc_accept_no_refs(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_rc_run(dir, "rc-accept-no-refs",
        "_RBGL_A\n", "echo hello world\n", 0)
}

fn rbtdrf_rc_accept_multi_token(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_rc_run(dir, "rc-accept-multi-token",
        "_RBGL_A\n_RBGL_B\n", "X=\"${_RBGL_A}/${_RBGL_B}\"\n", 0)
}

fn rbtdrf_rc_reject_multi_second(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_rc_run(dir, "rc-reject-multi-second",
        "_RBGL_A\n", "X=\"${_RBGL_A}/${_RBGL_B}\"\n", RBTDGC_BAND_RECIPE)
}

fn rbtdrf_rc_accept_empty_keys(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_rc_run(dir, "rc-accept-empty-keys",
        "", "echo hello\n", 0)
}

fn rbtdrf_rc_reject_empty_keys_ref(dir: &Path) -> rbtdre_Verdict {
    rbtdrf_rc_run(dir, "rc-reject-empty-keys-ref",
        "", "echo \"${_RBGL_A}\"\n", RBTDGC_BAND_RECIPE)
}

// ── Case arrays ─────────────────────────────────────────────

pub static RBTDRF_CASES_ENROLLMENT_VALIDATION: &[rbtdre_Case] = &[
    case!(rbtdrf_ev_string_valid),
    case!(rbtdrf_ev_string_empty_optional),
    case!(rbtdrf_ev_string_too_short),
    case!(rbtdrf_ev_string_too_long),
    case!(rbtdrf_ev_string_empty_required),
    case!(rbtdrf_ev_xname_valid),
    case!(rbtdrf_ev_xname_invalid),
    case!(rbtdrf_ev_gname_valid),
    case!(rbtdrf_ev_gname_invalid),
    case!(rbtdrf_ev_fqin_valid),
    case!(rbtdrf_ev_fqin_invalid),
    case!(rbtdrf_ev_bool_valid),
    case!(rbtdrf_ev_bool_invalid),
    case!(rbtdrf_ev_bool_empty),
    case!(rbtdrf_ev_enum_valid),
    case!(rbtdrf_ev_enum_invalid),
    case!(rbtdrf_ev_enum_empty),
    case!(rbtdrf_ev_decimal_valid),
    case!(rbtdrf_ev_decimal_below),
    case!(rbtdrf_ev_decimal_above),
    case!(rbtdrf_ev_decimal_empty),
    case!(rbtdrf_ev_ipv4_valid),
    case!(rbtdrf_ev_ipv4_invalid),
    case!(rbtdrf_ev_port_valid),
    case!(rbtdrf_ev_port_invalid),
    case!(rbtdrf_ev_odref_valid),
    case!(rbtdrf_ev_odref_no_digest),
    case!(rbtdrf_ev_odref_malformed),
    case!(rbtdrf_ev_odref_empty),
    case!(rbtdrf_ev_list_string_valid),
    case!(rbtdrf_ev_list_string_empty),
    case!(rbtdrf_ev_list_string_bad_item),
    case!(rbtdrf_ev_list_ipv4_valid),
    case!(rbtdrf_ev_list_ipv4_invalid),
    case!(rbtdrf_ev_list_ipv4_empty),
    case!(rbtdrf_ev_list_gname_valid),
    case!(rbtdrf_ev_list_gname_invalid),
    case!(rbtdrf_ev_gate_active_valid),
    case!(rbtdrf_ev_gate_active_invalid),
    case!(rbtdrf_ev_gate_inactive),
    case!(rbtdrf_ev_gate_multi),
    case!(rbtdrf_ev_enforce_all_pass),
    case!(rbtdrf_ev_enforce_first_bad),
    case!(rbtdrf_ev_report_all_pass),
    case!(rbtdrf_ev_report_mixed),
    case!(rbtdrf_ev_report_gated),
    case!(rbtdrf_ev_multiscope),
];

pub static RBTDRF_CASES_REGIME_VALIDATION: &[rbtdre_Case] = &[
    case!(rbtdrf_rv_rbrr_repo),
    case!(rbtdrf_rv_rbrv_all_vessels),
    case!(rbtdrf_rv_rbrn_all_nameplates),
];

pub static RBTDRF_CASES_REGIME_SMOKE: &[rbtdre_Case] = &[
    case!(rbtdrf_rs_burc),
    case!(rbtdrf_rs_burs),
    case!(rbtdrf_rs_rbrn),
    case!(rbtdrf_rs_rbrr),
    case!(rbtdrf_rs_rbrr_nonempty_prefix),
    case!(rbtdrf_rs_rbrv),
    case!(rbtdrf_rs_rbrp),
    case!(rbtdrf_rs_burd),
    case!(rbtdrf_rs_unmake_empty_arg_refusal),
    case!(rbtdrf_rs_credless_guard_mint_refusal),
];

// ── Fixture statics ──────────────────────────────────────────

pub static RBTDRF_FIXTURE_ENROLLMENT_VALIDATION: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_ENROLLMENT_VALIDATION,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRF_CASES_ENROLLMENT_VALIDATION,
    credless: true,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: None, invocations: Some(0) },
};

pub static RBTDRF_FIXTURE_REGIME_VALIDATION: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_REGIME_VALIDATION,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRF_CASES_REGIME_VALIDATION,
    credless: true,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: Some(30), invocations: Some(19) },
};

pub static RBTDRF_FIXTURE_REGIME_SMOKE: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_REGIME_SMOKE,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRF_CASES_REGIME_SMOKE,
    credless: true,
    tariff: rbtdre_Tariff { min_secs: Some(2), max_secs: Some(60), invocations: Some(47) },
};

pub static RBTDRF_CASES_DOCKERFILE_HYGIENE: &[rbtdre_Case] = &[
    case!(rbtdrf_dh_accept_parameterized),
    case!(rbtdrf_dh_accept_scratch),
    case!(rbtdrf_dh_accept_multistage_as),
    case!(rbtdrf_dh_accept_empty),
    case!(rbtdrf_dh_accept_comments_only),
    case!(rbtdrf_dh_reject_hardcoded_literal),
    case!(rbtdrf_dh_reject_tab_in_from),
    case!(rbtdrf_dh_reject_trailing_backslash),
    case!(rbtdrf_dh_all_vessels_pass),
];

pub static RBTDRF_FIXTURE_DOCKERFILE_HYGIENE: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_DOCKERFILE_HYGIENE,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRF_CASES_DOCKERFILE_HYGIENE,
    credless: true,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: Some(20), invocations: Some(19) },
};

pub static RBTDRF_CASES_FOUNDRY_PATH: &[rbtdre_Case] = &[
    case!(rbtdrf_np_cygdrive_transform),
    case!(rbtdrf_np_relative_passthrough),
    case!(rbtdrf_np_native_passthrough),
    case!(rbtdrf_np_offcygwin_identity),
    case!(rbtdrf_np_bare_absolute_unsurveyed),
    case!(rbtdrf_rt_lapse_advisory),
];

pub static RBTDRF_FIXTURE_FOUNDRY_PATH: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_FOUNDRY_PATH,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRF_CASES_FOUNDRY_PATH,
    credless: true,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: None, invocations: Some(0) },
};

pub static RBTDRF_CASES_CLIPBOARD: &[rbtdre_Case] = &[
    case!(rbtdrf_cb_no_tool_decline),
    case!(rbtdrf_cb_round_trip),
];

pub static RBTDRF_FIXTURE_CLIPBOARD: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_CLIPBOARD,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRF_CASES_CLIPBOARD,
    credless: true,
    tariff: rbtdre_Tariff::UNCHECKED,
};

pub static RBTDRF_CASES_RECIPE_VALIDATION: &[rbtdre_Case] = &[
    case!(rbtdrf_rc_accept_all_covered),
    case!(rbtdrf_rc_reject_missing_key),
    case!(rbtdrf_rc_accept_comment_only),
    case!(rbtdrf_rc_reject_substring),
    case!(rbtdrf_rc_accept_substring_real),
    case!(rbtdrf_rc_accept_no_refs),
    case!(rbtdrf_rc_accept_multi_token),
    case!(rbtdrf_rc_reject_multi_second),
    case!(rbtdrf_rc_accept_empty_keys),
    case!(rbtdrf_rc_reject_empty_keys_ref),
];

pub static RBTDRF_FIXTURE_RECIPE_VALIDATION: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_RECIPE_VALIDATION,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRF_CASES_RECIPE_VALIDATION,
    credless: true,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: None, invocations: Some(0) },
};

// ── Podvm-resolve cases ─────────────────────────────────────
//
// Asserts that zrbld_immure_resolve_family maps both podvm brands correctly.
// Invokes the presage colophon (RBTDGC_PRESAGE_IMMURE) — the read-only dry-run
// verb that resolves a family and reports what immure would capture. Presage
// never loads credentials nor fires a build, so the reveille tier drives it
// directly with no test seam.

fn rbtdrf_pr_invoke(
    dir: &Path,
    label: &str,
    args: &[&str],
) -> Result<String, rbtdre_Verdict> {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return Err(rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e))),
    };
    let tt = match rbtdri_find_tabtarget_global(&root, RBTDGC_PRESAGE_IMMURE) {
        Ok(p) => p,
        Err(e) => return Err(rbtdre_Verdict::Fail(e)),
    };
    let output = match rbtdri_tabtarget_command(&tt)
        .args(args)
        .current_dir(&root)
        .output()
    {
        Ok(o) => o,
        Err(e) => {
            return Err(rbtdre_Verdict::Fail(format!(
                "{}: failed to run {}: {}",
                label,
                tt.display(),
                e
            )));
        }
    };
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
    let _ = std::fs::write(dir.join(format!("{}-stdout.txt", label)), &stdout);
    let _ = std::fs::write(dir.join(format!("{}-stderr.txt", label)), &stderr);
    if !output.status.success() {
        return Err(rbtdre_Verdict::Fail(format!(
            "{}: presage exited nonzero ({:?})\ncombined output:\n{}{}",
            label,
            output.status.code(),
            stdout,
            stderr
        )));
    }
    Ok(format!("{}{}", stdout, stderr))
}

fn rbtdrf_podvm_resolve(dir: &Path) -> rbtdre_Verdict {
    // native brand
    let combined_native = match rbtdrf_pr_invoke(dir, "pr-native", &["podvm-native", "5.6"]) {
        Ok(s) => s,
        Err(v) => return v,
    };
    let needle_native = "podvm-native -> quay.io/podman/machine-os (kind vn)";
    if !combined_native.contains(needle_native) {
        return rbtdre_Verdict::Fail(format!(
            "podvm-native mapping not found in output\nexpected substring: {}\ncombined output:\n{}",
            needle_native, combined_native
        ));
    }

    // wsl brand
    let combined_wsl = match rbtdrf_pr_invoke(dir, "pr-wsl", &["podvm-wsl", "5.6"]) {
        Ok(s) => s,
        Err(v) => return v,
    };
    let needle_wsl = "podvm-wsl -> quay.io/podman/machine-os-wsl (kind vw)";
    if !combined_wsl.contains(needle_wsl) {
        return rbtdre_Verdict::Fail(format!(
            "podvm-wsl mapping not found in output\nexpected substring: {}\ncombined output:\n{}",
            needle_wsl, combined_wsl
        ));
    }

    rbtdre_Verdict::Pass
}

pub static RBTDRF_CASES_PODVM_RESOLVE: &[rbtdre_Case] = &[
    case!(rbtdrf_podvm_resolve),
];

pub static RBTDRF_FIXTURE_PODVM_RESOLVE: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_PODVM_RESOLVE,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRF_CASES_PODVM_RESOLVE,
    credless: true,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: None, invocations: Some(2) },
};
