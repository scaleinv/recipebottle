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
// RBTDRS — regime-poison fixture: in-universe negative validation.
//
// Each case drives the REAL validate verb against a real regime (in-tree
// tracked baseline, or a staged synthetic one for operator-local regimes) with
// exactly one field corrupted via the regime-poison tweak — zbuv_poison_apply,
// the single BUK regime-load membrane crossed at every regime kindle — and
// asserts the SPECIFIC band code of the gate that rejects:
//
//   RBTDGC_BAND_REGIME (100)  a regime module's own enforce rule fired
//                             (cross-field, format regex, existence)
//   RBTDGC_BAND_ENROLL (101)  the buv enrollment pipeline rejected
//                             (buv_vet type/format/enum/range/presence, or
//                              buv_scope_sentinel on an unexpected variable)
//
// Asserting the band — not bare nonzero — closes the wrong-layer hole: a
// harness breakage (unbound variable, missing file, refactor typo) exits with
// some other code and fails the case loud, where a bare-nonzero assertion would
// pass on it.
//
// NOT credless, so it cannot ride reveille (whose single tweak slot belongs to
// the credless guard). The per-case poison occupies that slot, so the fixture
// enrolls in picket/bivouac/echelon — see RBTDRA_SUITES.

use std::path::Path;

use crate::case;
use crate::rbtdgc_consts::{
    BUWGC_RC_VALIDATE,
    BUWGC_RS_VALIDATE,
    RBTDGC_BAND_ENROLL,
    RBTDGC_BAND_REGIME,
    RBTDGC_TWEAK_REGIME_POISON,
    RBTDGC_VALIDATE_DEPOT,
    RBTDGC_VALIDATE_NAMEPLATE,
    RBTDGC_VALIDATE_OAUTH,
    RBTDGC_VALIDATE_PAYOR,
    RBTDGC_VALIDATE_REPO,
    RBTDGC_VALIDATE_VESSEL,
};
use crate::rbtdre_engine::{
    rbtdre_Tariff,
    rbtdre_Case,
    rbtdre_Disposition,
    rbtdre_Fixture,
    rbtdre_Verdict,
};
use crate::rbtdri_invocation::{
    rbtdri_find_tabtarget_global,
    rbtdri_tabtarget_command,
    RBTDRI_BURE_TWEAK_NAME_KEY,
    RBTDRI_BURE_TWEAK_VALUE_KEY,
};
use crate::rbtdrm_manifest::RBTDRM_FIXTURE_REGIME_POISON;

// Regime variable names referenced by 2+ poison specs — single definition so a
// typo cannot silently poison a different field than intended.
const RBTDRS_VAR_RBRR_RUNTIME_PREFIX: &str = "RBRR_RUNTIME_PREFIX";
const RBTDRS_VAR_RBRD_CLOUD_PREFIX: &str = "RBRD_CLOUD_PREFIX";
const RBTDRS_VAR_RBRD_DEPOT_MONIKER: &str = "RBRD_DEPOT_MONIKER";

// Folio monikers referenced by 2+ cases — a known-good entry-enabled nameplate
// and known-good conjure vessels, all in-tree. Removing any fails the cases loud
// (the verb cannot locate the regime), not silently.
const RBTDRS_NAMEPLATE_TADMOR: &str = "tadmor";
const RBTDRS_VESSEL_BUSYBOX: &str = "rbev-busybox";
const RBTDRS_VESSEL_PLANTUML: &str = "rbev-bottle-plantuml";

// ── Poison harness ──────────────────────────────────────────

/// Drive a validate tabtarget under the regime-poison tweak, asserting the exit
/// equals `expected_band`. `folio` is the verb's positional args (empty for
/// repo/depot/payor; the nameplate/vessel moniker otherwise). `poison` is the
/// BURE_TWEAK_VALUE: "VAR=value" to corrupt a field, bare "VAR" to unset a
/// required one. The corrupted VAR must carry the regime's enroll scope prefix,
/// or the seam rides inert (zbuv_poison_apply's scope guard). The poison rides
/// BURE_TWEAK_NAME + BURE_TWEAK_VALUE as extra env on the one tabtarget-launch
/// constructor; this fixture is not credless, so the slot is free (the
/// rbtdri_invoke conflict gate fires only under the credless guard).
fn rbtdrs_poison(
    dir: &Path,
    validate_colophon: &str,
    folio: &[&str],
    poison: &str,
    expected_band: i32,
    label: &str,
) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };
    let tt = match rbtdri_find_tabtarget_global(&root, validate_colophon) {
        Ok(p) => p,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };
    let output = match rbtdri_tabtarget_command(&tt)
        .args(folio)
        .env(RBTDRI_BURE_TWEAK_NAME_KEY, RBTDGC_TWEAK_REGIME_POISON)
        .env(RBTDRI_BURE_TWEAK_VALUE_KEY, poison)
        .current_dir(&root)
        .output()
    {
        Ok(o) => o,
        Err(e) => {
            return rbtdre_Verdict::Fail(format!("{}: failed to run {}: {}", label, tt.display(), e));
        }
    };
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
    let code = output.status.code().unwrap_or(-1);
    let _ = std::fs::write(dir.join(format!("{}-stdout.txt", label)), &stdout);
    let _ = std::fs::write(dir.join(format!("{}-stderr.txt", label)), &stderr);
    if code != expected_band {
        return rbtdre_Verdict::Fail(format!(
            "{}: {} under poison '{}' exited {} — expected band {}\nstdout:\n{}\n\nstderr:\n{}",
            label, validate_colophon, poison, code, expected_band, stdout, stderr
        ));
    }
    rbtdre_Verdict::Pass
}

// ── RBRR (repo) — verb rbw-rrv against the tracked rbrr.env ──

fn rbtdrs_rbrr_bad_timeout(dir: &Path) -> rbtdre_Verdict {
    // RBRR_GCB_TIMEOUT enrolls as a plain string; the NNNs format is a
    // zrbrr_enforce regex, so a non-NNNs value rejects in the module → regime.
    rbtdrs_poison(dir, RBTDGC_VALIDATE_REPO, &[], "RBRR_GCB_TIMEOUT=1200",
        RBTDGC_BAND_REGIME, "rbrr-bad-timeout")
}

fn rbtdrs_rbrr_unexpected_var(dir: &Path) -> rbtdre_Verdict {
    // An unenrolled RBRR_* variable trips buv_scope_sentinel → enroll.
    rbtdrs_poison(dir, RBTDGC_VALIDATE_REPO, &[], "RBRR_BOGUS=foo",
        RBTDGC_BAND_ENROLL, "rbrr-unexpected-var")
}

fn rbtdrs_rbrr_bad_vessel_dir(dir: &Path) -> rbtdre_Verdict {
    // A nonexistent directory fails the zrbrr_enforce existence check → regime.
    rbtdrs_poison(dir, RBTDGC_VALIDATE_REPO, &[],
        "RBRR_VESSEL_DIR=/tmp/nonexistent-rbtdrs-vessel-dir",
        RBTDGC_BAND_REGIME, "rbrr-bad-vessel-dir")
}

fn rbtdrs_rbrr_bad_secrets_dir(dir: &Path) -> rbtdre_Verdict {
    rbtdrs_poison(dir, RBTDGC_VALIDATE_REPO, &[],
        "RBRR_SECRETS_DIR=/tmp/nonexistent-rbtdrs-secrets-dir",
        RBTDGC_BAND_REGIME, "rbrr-bad-secrets-dir")
}

fn rbtdrs_rbrr_bad_runtime_prefix_uppercase(dir: &Path) -> rbtdre_Verdict {
    // Valid length, so it clears the buv enroll; uppercase fails the
    // zrbrr_enforce format regex → regime.
    rbtdrs_poison(dir, RBTDGC_VALIDATE_REPO, &[],
        &format!("{}=BAD-", RBTDRS_VAR_RBRR_RUNTIME_PREFIX),
        RBTDGC_BAND_REGIME, "rbrr-bad-runtime-prefix-uppercase")
}

fn rbtdrs_rbrr_bad_runtime_prefix_no_trailing_hyphen(dir: &Path) -> rbtdre_Verdict {
    rbtdrs_poison(dir, RBTDGC_VALIDATE_REPO, &[],
        &format!("{}=acme", RBTDRS_VAR_RBRR_RUNTIME_PREFIX),
        RBTDGC_BAND_REGIME, "rbrr-bad-runtime-prefix-no-trailing-hyphen")
}

fn rbtdrs_rbrr_bad_runtime_prefix_too_long(dir: &Path) -> rbtdre_Verdict {
    // 12 chars exceeds the buv_string_enroll max (11) → enroll.
    rbtdrs_poison(dir, RBTDGC_VALIDATE_REPO, &[],
        &format!("{}=twelvechars-", RBTDRS_VAR_RBRR_RUNTIME_PREFIX),
        RBTDGC_BAND_ENROLL, "rbrr-bad-runtime-prefix-too-long")
}

// ── RBRD (depot) — verb rbw-rdv against the tracked rbrd.env ─

fn rbtdrs_rbrd_missing_moniker(dir: &Path) -> rbtdre_Verdict {
    // Unset a required field → buv presence check → enroll.
    rbtdrs_poison(dir, RBTDGC_VALIDATE_DEPOT, &[], RBTDRS_VAR_RBRD_DEPOT_MONIKER,
        RBTDGC_BAND_ENROLL, "rbrd-missing-moniker")
}

fn rbtdrs_rbrd_bad_moniker(dir: &Path) -> rbtdre_Verdict {
    // Uppercase + hyphen fails the zrbrd_enforce moniker regex → regime.
    rbtdrs_poison(dir, RBTDGC_VALIDATE_DEPOT, &[],
        &format!("{}=BAD-MONIKER", RBTDRS_VAR_RBRD_DEPOT_MONIKER),
        RBTDGC_BAND_REGIME, "rbrd-bad-moniker")
}

fn rbtdrs_rbrd_bad_cloud_prefix_uppercase(dir: &Path) -> rbtdre_Verdict {
    rbtdrs_poison(dir, RBTDGC_VALIDATE_DEPOT, &[],
        &format!("{}=BAD-", RBTDRS_VAR_RBRD_CLOUD_PREFIX),
        RBTDGC_BAND_REGIME, "rbrd-bad-cloud-prefix-uppercase")
}

fn rbtdrs_rbrd_bad_cloud_prefix_no_trailing_hyphen(dir: &Path) -> rbtdre_Verdict {
    rbtdrs_poison(dir, RBTDGC_VALIDATE_DEPOT, &[],
        &format!("{}=acme", RBTDRS_VAR_RBRD_CLOUD_PREFIX),
        RBTDGC_BAND_REGIME, "rbrd-bad-cloud-prefix-no-trailing-hyphen")
}

fn rbtdrs_rbrd_bad_cloud_prefix_too_long(dir: &Path) -> rbtdre_Verdict {
    // 12 chars exceeds the buv_string_enroll max (11) → enroll, before the
    // joint-length enforce ever runs.
    rbtdrs_poison(dir, RBTDGC_VALIDATE_DEPOT, &[],
        &format!("{}=twelvechars-", RBTDRS_VAR_RBRD_CLOUD_PREFIX),
        RBTDGC_BAND_ENROLL, "rbrd-bad-cloud-prefix-too-long")
}

// ── RBRP (payor) — verb rbw-rpv against the tracked rbrp.env ─

fn rbtdrs_rbrp_bad_payor_project(dir: &Path) -> rbtdre_Verdict {
    // Valid length, so it clears the buv enroll; fails the zrbrp_enforce
    // payor-project regex → regime.
    rbtdrs_poison(dir, RBTDGC_VALIDATE_PAYOR, &[],
        "RBRP_PAYOR_PROJECT_ID=not-a-payor-project",
        RBTDGC_BAND_REGIME, "rbrp-bad-payor-project")
}

// ── BURC (config) — verb buw-rcv against the tracked burc.env ─

fn rbtdrs_burc_missing_station_file(dir: &Path) -> rbtdre_Verdict {
    // Unset a required field → buv presence check → enroll.
    rbtdrs_poison(dir, BUWGC_RC_VALIDATE, &[], "BURC_STATION_FILE",
        RBTDGC_BAND_ENROLL, "burc-missing-station-file")
}

// ── RBRN (nameplate) — verb rbw-rnv against a real nameplate ─
//
// Folio is an entry-enabled nameplate; all eight cases poison one field of its
// real regime. Seven reject in the buv pipeline (enum, ipv4, presence,
// sentinel); port-conflict is the lone module-enforce case.

fn rbtdrs_rbrn_missing_moniker(dir: &Path) -> rbtdre_Verdict {
    // Unset a required field → buv presence check → enroll.
    rbtdrs_poison(dir, RBTDGC_VALIDATE_NAMEPLATE, &[RBTDRS_NAMEPLATE_TADMOR],
        "RBRN_MONIKER", RBTDGC_BAND_ENROLL, "rbrn-missing-moniker")
}

fn rbtdrs_rbrn_invalid_runtime(dir: &Path) -> rbtdre_Verdict {
    // Off-enum value fails the buv_enum_enroll check → enroll.
    rbtdrs_poison(dir, RBTDGC_VALIDATE_NAMEPLATE, &[RBTDRS_NAMEPLATE_TADMOR],
        "RBRN_RUNTIME=invalid", RBTDGC_BAND_ENROLL, "rbrn-invalid-runtime")
}

fn rbtdrs_rbrn_invalid_entry_mode(dir: &Path) -> rbtdre_Verdict {
    rbtdrs_poison(dir, RBTDGC_VALIDATE_NAMEPLATE, &[RBTDRS_NAMEPLATE_TADMOR],
        "RBRN_ENTRY_MODE=bogus", RBTDGC_BAND_ENROLL, "rbrn-invalid-entry-mode")
}

fn rbtdrs_rbrn_invalid_dns_mode(dir: &Path) -> rbtdre_Verdict {
    rbtdrs_poison(dir, RBTDGC_VALIDATE_NAMEPLATE, &[RBTDRS_NAMEPLATE_TADMOR],
        "RBRN_UPLINK_DNS_MODE=bogus", RBTDGC_BAND_ENROLL, "rbrn-invalid-dns-mode")
}

fn rbtdrs_rbrn_invalid_access_mode(dir: &Path) -> rbtdre_Verdict {
    rbtdrs_poison(dir, RBTDGC_VALIDATE_NAMEPLATE, &[RBTDRS_NAMEPLATE_TADMOR],
        "RBRN_UPLINK_ACCESS_MODE=bogus", RBTDGC_BAND_ENROLL, "rbrn-invalid-access-mode")
}

fn rbtdrs_rbrn_bad_ip(dir: &Path) -> rbtdre_Verdict {
    // Malformed address fails the buv_ipv4_enroll check → enroll.
    rbtdrs_poison(dir, RBTDGC_VALIDATE_NAMEPLATE, &[RBTDRS_NAMEPLATE_TADMOR],
        "RBRN_ENCLAVE_BASE_IP=not-an-ip", RBTDGC_BAND_ENROLL, "rbrn-bad-ip")
}

fn rbtdrs_rbrn_unexpected_var(dir: &Path) -> rbtdre_Verdict {
    rbtdrs_poison(dir, RBTDGC_VALIDATE_NAMEPLATE, &[RBTDRS_NAMEPLATE_TADMOR],
        "RBRN_BOGUS=foo", RBTDGC_BAND_ENROLL, "rbrn-unexpected-var")
}

fn rbtdrs_rbrn_port_conflict(dir: &Path) -> rbtdre_Verdict {
    // A workstation port at/above the uplink minimum (a valid port number, so it
    // clears the buv enroll) trips the zrbrn_enforce cross-port check → regime.
    rbtdrs_poison(dir, RBTDGC_VALIDATE_NAMEPLATE, &[RBTDRS_NAMEPLATE_TADMOR],
        "RBRN_ENTRY_PORT_WORKSTATION=10001", RBTDGC_BAND_REGIME, "rbrn-port-conflict")
}

// ── RBRV (vessel) — verb rbw-rvv against a real vessel ───────
//
// Mode-specific: the conjure cases use a conjure vessel, the bind case a bind
// vessel, so the gated field being poisoned is active. Folio is the vessel
// moniker (= RBRV_SIGIL).

fn rbtdrs_rbrv_missing_sigil(dir: &Path) -> rbtdre_Verdict {
    // Unset a required field → buv presence check → enroll.
    rbtdrs_poison(dir, RBTDGC_VALIDATE_VESSEL, &[RBTDRS_VESSEL_BUSYBOX],
        "RBRV_SIGIL", RBTDGC_BAND_ENROLL, "rbrv-missing-sigil")
}

fn rbtdrs_rbrv_unexpected_var(dir: &Path) -> rbtdre_Verdict {
    rbtdrs_poison(dir, RBTDGC_VALIDATE_VESSEL, &[RBTDRS_VESSEL_BUSYBOX],
        "RBRV_BOGUS=foo", RBTDGC_BAND_ENROLL, "rbrv-unexpected-var")
}

fn rbtdrs_rbrv_partial_conjure(dir: &Path) -> rbtdre_Verdict {
    // Unset a conjure-gated required field on a conjure vessel → enroll.
    rbtdrs_poison(dir, RBTDGC_VALIDATE_VESSEL, &[RBTDRS_VESSEL_BUSYBOX],
        "RBRV_CONJURE_PLATFORMS", RBTDGC_BAND_ENROLL, "rbrv-partial-conjure")
}

fn rbtdrs_rbrv_no_bind_image(dir: &Path) -> rbtdre_Verdict {
    // Unset the bind-gated required field on a bind vessel → enroll.
    rbtdrs_poison(dir, RBTDGC_VALIDATE_VESSEL, &[RBTDRS_VESSEL_PLANTUML],
        "RBRV_BIND_IMAGE", RBTDGC_BAND_ENROLL, "rbrv-no-bind-image")
}

fn rbtdrs_rbrv_bind_image_tag_only(dir: &Path) -> rbtdre_Verdict {
    // A tag-pinned FQIN clears the buv_fqin enroll but lacks the @sha256:<64-hex>
    // digest, tripping the zrbrv_enforce bind-digest check → regime.
    rbtdrs_poison(dir, RBTDGC_VALIDATE_VESSEL, &[RBTDRS_VESSEL_PLANTUML],
        "RBRV_BIND_IMAGE=docker.io/plantuml/plantuml-server:1.2024.7",
        RBTDGC_BAND_REGIME, "rbrv-bind-image-tag-only")
}

// ── Operator-local regimes — station, oauth, auth ──
//
// These regimes have no in-tree baseline: their files live in the operator's
// station tree, present only on a configured workstation. Each case probes the
// baseline verb un-poisoned first — if it is not green the regime is not
// configured here and the case self-skips (the regime-smoke station precedent);
// when green, the baseline run also proves the poison is the only variable, then
// the poisoned run asserts the band. The poison corrupts an in-memory variable
// in the validate subshell after the file is sourced — it never modifies the
// operator's regime file, so even secret-bearing oauth/auth config is untouched.

/// Operator-local variant of rbtdrs_poison: self-skip when the baseline verb is
/// not green (regime absent on this machine), else assert the poisoned band.
fn rbtdrs_poison_optional(
    dir: &Path,
    validate_colophon: &str,
    folio: &[&str],
    poison: &str,
    expected_band: i32,
    label: &str,
) -> rbtdre_Verdict {
    let root = match std::env::current_dir() {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("cannot get cwd: {}", e)),
    };
    let tt = match rbtdri_find_tabtarget_global(&root, validate_colophon) {
        Ok(p) => p,
        Err(e) => return rbtdre_Verdict::Fail(e),
    };
    let baseline = match rbtdri_tabtarget_command(&tt)
        .args(folio)
        .current_dir(&root)
        .output()
    {
        Ok(o) => o,
        Err(e) => {
            return rbtdre_Verdict::Fail(format!("{}: failed to run {}: {}", label, tt.display(), e));
        }
    };
    let base_code = baseline.status.code().unwrap_or(-1);
    let _ = std::fs::write(dir.join(format!("{}-baseline-stdout.txt", label)), &baseline.stdout);
    let _ = std::fs::write(dir.join(format!("{}-baseline-stderr.txt", label)), &baseline.stderr);
    if base_code != 0 {
        return rbtdre_Verdict::Skip(format!(
            "{}: {} baseline not green (exit {}) — operator-local regime not configured here",
            label, validate_colophon, base_code
        ));
    }
    rbtdrs_poison(dir, validate_colophon, folio, poison, expected_band, label)
}

fn rbtdrs_rbro_missing_refresh_token(dir: &Path) -> rbtdre_Verdict {
    rbtdrs_poison_optional(dir, RBTDGC_VALIDATE_OAUTH, &[], "RBRO_REFRESH_TOKEN",
        RBTDGC_BAND_ENROLL, "rbro-missing-refresh-token")
}

fn rbtdrs_burs_bad_tincture(dir: &Path) -> rbtdre_Verdict {
    // Uppercase clears the length enroll but fails the zburs_enforce regex → regime.
    rbtdrs_poison_optional(dir, BUWGC_RS_VALIDATE, &[], "BURS_TINCTURE=A1",
        RBTDGC_BAND_REGIME, "burs-bad-tincture")
}

// ── Fixture ─────────────────────────────────────────────────

pub static RBTDRS_CASES_REGIME_POISON: &[rbtdre_Case] = &[
    case!(rbtdrs_rbrr_bad_timeout),
    case!(rbtdrs_rbrr_unexpected_var),
    case!(rbtdrs_rbrr_bad_vessel_dir),
    case!(rbtdrs_rbrr_bad_secrets_dir),
    case!(rbtdrs_rbrr_bad_runtime_prefix_uppercase),
    case!(rbtdrs_rbrr_bad_runtime_prefix_no_trailing_hyphen),
    case!(rbtdrs_rbrr_bad_runtime_prefix_too_long),
    case!(rbtdrs_rbrd_missing_moniker),
    case!(rbtdrs_rbrd_bad_moniker),
    case!(rbtdrs_rbrd_bad_cloud_prefix_uppercase),
    case!(rbtdrs_rbrd_bad_cloud_prefix_no_trailing_hyphen),
    case!(rbtdrs_rbrd_bad_cloud_prefix_too_long),
    case!(rbtdrs_rbrp_bad_payor_project),
    case!(rbtdrs_burc_missing_station_file),
    case!(rbtdrs_rbrn_missing_moniker),
    case!(rbtdrs_rbrn_invalid_runtime),
    case!(rbtdrs_rbrn_invalid_entry_mode),
    case!(rbtdrs_rbrn_invalid_dns_mode),
    case!(rbtdrs_rbrn_invalid_access_mode),
    case!(rbtdrs_rbrn_bad_ip),
    case!(rbtdrs_rbrn_unexpected_var),
    case!(rbtdrs_rbrn_port_conflict),
    case!(rbtdrs_rbrv_missing_sigil),
    case!(rbtdrs_rbrv_unexpected_var),
    case!(rbtdrs_rbrv_partial_conjure),
    case!(rbtdrs_rbrv_no_bind_image),
    case!(rbtdrs_rbrv_bind_image_tag_only),
    case!(rbtdrs_rbro_missing_refresh_token),
    case!(rbtdrs_burs_bad_tincture),
];

pub static RBTDRS_FIXTURE_REGIME_POISON: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_REGIME_POISON,
    disposition: rbtdre_Disposition::Independent,
    setup: None,
    teardown: None,
    cases: RBTDRS_CASES_REGIME_POISON,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};
