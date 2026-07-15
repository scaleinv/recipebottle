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
// RBTDRP — depot-lifecycle fixture for theurge release qualification
//
// The ephemeral depot: a full birth-to-death proof that stands up a fresh depot,
// cycles its SAs, proves the live-unmake guard, and tears it down — the gauntlet's
// create→destroy lifecycle test, run alongside the durable freehold-establish.
//
// It shares the freehold scheme (rbtdrk_freehold) — one prefix family, one moniker
// picker — with the durable fixtures; it does NOT carry its own. The picker's
// `max + 1` always mints a moniker ABOVE the standing freehold's, so this fixture's
// tear-down only reaches the fresh leasehold it minted, never the freehold (only
// the deliberate, suiteless freehold-churn destroys that).
//
// Case 1 — the marshal-zero attestation gate — lives in the sibling rbtdrp_attest
// module; the registry below composes it ahead of this arc's four cases.

use std::path::Path;

use crate::case;
use crate::rbtdrb_probe::{rbtdrb_assert, rbtdrb_Probe};
use crate::rbtdrc_crucible::rbtdrc_with_ctx;
use crate::rbtdre_engine::{rbtdre_Case, rbtdre_Disposition, rbtdre_Fixture, rbtdre_Tariff, rbtdre_Verdict};
use crate::rbtdri_invocation::{
    rbtdri_Context,
    RBTDRI_BURE_CONFIRM_KEY,
    RBTDRI_BURE_CONFIRM_SKIP,
};
use crate::rbtdgc_consts::{
    RBTDGC_LEVY_DEPOT,
    RBTDGC_LIST_DEPOT,
    RBTDGC_RBRD_FILE,
    RBTDGC_UNMAKE_DEPOT,
};
use crate::rbtdrm_manifest::RBTDRM_FIXTURE_DEPOT_LIFECYCLE;
use crate::rbtdrp_attest::rbtdrp_marshal_zero_attestation;
use crate::rbtdrk_freehold::{
    rbtdrk_burs_tincture,
    rbtdrk_cloud_prefix_subdir,
    rbtdrk_compose_project_id,
    rbtdrk_crosscheck_project_id,
    rbtdrk_family_stem,
    rbtdrk_install_depot_moniker,
    rbtdrk_install_freehold_prefixes,
    rbtdrk_invoke_logged,
    rbtdrk_pick_next_moniker,
    rbtdrk_read_env_value,
    rbtdrk_unmake_preamble,
    rbtdrk_UnmakeSpec,
    RBTDRK_FIELD_RBRD_CLOUD_PREFIX,
    RBTDRK_FIELD_RBRD_DEPOT_MONIKER,
};

/// Placeholder moniker installed by tear_down before invoking rbw-dU. With the
/// live moniker still in rbrd.env, RBDC composes to the depot's own project_id
/// and rbgp_depot_unmake's live-disqualify guard refuses the call. Rotating to a
/// value outside the family stem makes RBDC compose to a different value so the
/// guard lets the unmake through. Marshal-zero is the recovery between runs and
/// blanks the field anyway.
const RBTDRP_TEAR_DOWN_PLACEHOLDER_MONIKER: &str = "torndown";

/// `DELETE_REQUESTED` lifecycle state — appears in `rbgp_depot_list` output
/// after a soft-delete, used by tear-down to relax the post-unmake assertion.
const RBTDRP_DELETE_REQUESTED: &str = "DELETE_REQUESTED";

// ── Probe ────────────────────────────────────────────────────
//
// rbtdrb_Probe.check is `fn() -> Result<(), String>` with no parameters,
// so the probe reads the project root from current_dir() — theurge always
// launches from the project root.

/// Live-disqualify case probe: depot levied (RBRD_CLOUD_PREFIX +
/// RBRD_DEPOT_MONIKER both non-blank, RBDC kindle composes a non-empty
/// project_id). Established by the stand-up case.
fn rbtdrp_probe_depot_levied() -> Result<(), String> {
    let root = std::env::current_dir()
        .map_err(|e| format!("cannot resolve project root: {}", e))?;
    let rbrd = root.join(RBTDGC_RBRD_FILE);

    let cloud = rbtdrk_read_env_value(&rbrd, RBTDRK_FIELD_RBRD_CLOUD_PREFIX).unwrap_or_default();
    if cloud.is_empty() {
        return Err(format!(
            "{} blank in {} — freehold prefixes not installed",
            RBTDRK_FIELD_RBRD_CLOUD_PREFIX,
            rbrd.display()
        ));
    }

    let moniker = rbtdrk_read_env_value(&rbrd, RBTDRK_FIELD_RBRD_DEPOT_MONIKER).unwrap_or_default();
    if moniker.is_empty() {
        return Err(format!(
            "{} blank in {} — depot stand-up did not run",
            RBTDRK_FIELD_RBRD_DEPOT_MONIKER,
            rbrd.display()
        ));
    }

    Ok(())
}

// ── Case 2: depot stand-up ───────────────────────────────────

/// Case 2 — depot stand-up. Installs freehold prefixes, picks the next free
/// moniker in the freehold family, levies the depot, re-lists to refresh
/// facts, reads project_id from the `<moniker>.depot-project` fact file, and
/// cross-checks it against the RBDC compose derivation. The moniker survives
/// in rbrd.env for the SA-cycle and tear-down cases.
fn rbtdrp_depot_stand_up(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrp_depot_stand_up_impl(ctx, dir))
}

fn rbtdrp_depot_stand_up_impl(ctx: &mut rbtdri_Context, dir: &Path) -> rbtdre_Verdict {
    let root = ctx.project_root().to_path_buf();

    if let Err(e) = rbtdrk_install_freehold_prefixes(&root) {
        return rbtdre_Verdict::Fail(format!("install freehold prefixes: {}", e));
    }

    let list_pre = match rbtdrk_invoke_logged(
        ctx,
        RBTDGC_LIST_DEPOT,
        &[],
        &[],
        dir,
        "list-pre",
    ) {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("depot list (pre-levy): {}", e)),
    };
    if list_pre.exit_code != 0 {
        return rbtdre_Verdict::Fail(format!(
            "depot list (pre-levy) exit {}\n{}",
            list_pre.exit_code, list_pre.stderr
        ));
    }

    let tincture = match rbtdrk_burs_tincture() {
        Ok(t) => t,
        Err(e) => return rbtdre_Verdict::Fail(format!("read BURS_TINCTURE: {}", e)),
    };
    let family_stem = rbtdrk_family_stem(&tincture);
    let moniker = match rbtdrk_pick_next_moniker(&list_pre, &root, &family_stem) {
        Ok(m) => m,
        Err(e) => return rbtdre_Verdict::Fail(format!("pick next moniker: {}", e)),
    };
    if let Err(e) = rbtdrk_install_depot_moniker(&root, &moniker) {
        return rbtdre_Verdict::Fail(format!("install depot moniker: {}", e));
    }

    let levy = match rbtdrk_invoke_logged(
        ctx,
        RBTDGC_LEVY_DEPOT,
        &[],
        &[],
        dir,
        "levy",
    ) {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("depot levy: {}", e)),
    };
    if levy.exit_code != 0 {
        return rbtdre_Verdict::Fail(format!(
            "depot levy exit {}\n{}",
            levy.exit_code, levy.stderr
        ));
    }

    let list_present = match rbtdrk_invoke_logged(
        ctx,
        RBTDGC_LIST_DEPOT,
        &[],
        &[],
        dir,
        "list-present",
    ) {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("depot list (after levy): {}", e)),
    };
    if list_present.exit_code != 0 {
        return rbtdre_Verdict::Fail(format!(
            "depot list (after levy) exit {}\n{}",
            list_present.exit_code, list_present.stderr
        ));
    }

    let prefix_dir = match rbtdrk_cloud_prefix_subdir(&root) {
        Ok(p) => p,
        Err(e) => return rbtdre_Verdict::Fail(format!("resolve cloud_prefix subdir: {}", e)),
    };
    if let Some(verdict) =
        rbtdrk_crosscheck_project_id(&root, &list_present, &prefix_dir, &moniker, dir)
    {
        return verdict;
    }

    rbtdre_Verdict::Pass
}

// ── Case 4: live-disqualify refusal ──────────────────────────

/// Recovery-diagnostic substring emitted by `rbgp_depot_unmake`'s
/// live-disqualify branch. The branch names `RBRD_DEPOT_MONIKER` rename or
/// `rbw-MZ` as recovery paths; the assertion matches on the field-name token,
/// which is invariant across cosmetic message edits.
const RBTDRP_LIVE_DISQUALIFY_RECOVERY: &str = "RBRD_DEPOT_MONIKER";

/// Case 4 — live-disqualify refusal. Pre-condition: depot levied by stand-up
/// (probe asserts both RBRD_CLOUD_PREFIX and RBRD_DEPOT_MONIKER are non-blank).
/// Composes the live RBDC_DEPOT_PROJECT_ID and invokes `rbw-dU` with it as $1;
/// expects non-zero exit + recovery diagnostic naming `RBRD_DEPOT_MONIKER`
/// (BBAA9 contract). The refusal lands before authenticate, so no GCP traffic
/// occurs — assertion is on exit-code + diagnostic shape only.
fn rbtdrp_depot_live_disqualify(dir: &Path) -> rbtdre_Verdict {
    let probe = rbtdrb_Probe {
        name: "depot levied (RBRD_CLOUD_PREFIX + RBRD_DEPOT_MONIKER set)",
        check: rbtdrp_probe_depot_levied,
        remediation: "rerun the stand-up case (rbtdrp_depot_stand_up) before this case",
    };
    if let Err(v) = rbtdrb_assert(&probe) {
        return v;
    }
    rbtdrc_with_ctx(|ctx| rbtdrp_depot_live_disqualify_impl(ctx, dir))
}

fn rbtdrp_depot_live_disqualify_impl(
    ctx: &mut rbtdri_Context,
    dir: &Path,
) -> rbtdre_Verdict {
    let root = ctx.project_root().to_path_buf();

    let rbrd = root.join(RBTDGC_RBRD_FILE);
    let moniker = match rbtdrk_read_env_value(&rbrd, RBTDRK_FIELD_RBRD_DEPOT_MONIKER) {
        Some(m) if !m.is_empty() => m,
        _ => {
            return rbtdre_Verdict::Fail(
                "RBRD_DEPOT_MONIKER blank — probe should have caught this".to_string(),
            )
        }
    };

    let project_id = match rbtdrk_compose_project_id(&root, &moniker) {
        Ok(p) => p,
        Err(e) => return rbtdre_Verdict::Fail(format!("compose project_id: {}", e)),
    };
    let _ = std::fs::write(dir.join("live-project-id.txt"), &project_id);

    let result = match rbtdrk_invoke_logged(
        ctx,
        RBTDGC_UNMAKE_DEPOT,
        &[&project_id],
        &[(RBTDRI_BURE_CONFIRM_KEY, RBTDRI_BURE_CONFIRM_SKIP)],
        dir,
        "live-disqualify",
    ) {
        Ok(r) => r,
        Err(e) => {
            return rbtdre_Verdict::Fail(format!("{} invocation: {}", RBTDGC_UNMAKE_DEPOT, e))
        }
    };

    if result.exit_code == 0 {
        return rbtdre_Verdict::Fail(format!(
            "{} '{}' exited 0 — BBAA9 live-disqualify contract violated \
             (refusal must die when target == RBDC_DEPOT_PROJECT_ID)",
            RBTDGC_UNMAKE_DEPOT, project_id
        ));
    }

    // BUW dispatch merges stderr→stdout; assertion checks combined output.
    let combined = format!("{}{}", result.stdout, result.stderr);
    if !combined.contains(RBTDRP_LIVE_DISQUALIFY_RECOVERY) {
        return rbtdre_Verdict::Fail(format!(
            "{} live-disqualify diagnostic did not name '{}' as recovery path\n\
             stdout:\n{}\n\nstderr:\n{}",
            RBTDGC_UNMAKE_DEPOT, RBTDRP_LIVE_DISQUALIFY_RECOVERY, result.stdout, result.stderr
        ));
    }

    rbtdre_Verdict::Pass
}

// ── Case 5: depot tear-down ──────────────────────────────────

/// Case 5 — depot tear-down. Pre-condition: depot exists from stand-up. Reads
/// moniker from rbrd.env, composes the project_id from it, rotates
/// RBRD_DEPOT_MONIKER to a placeholder so rbgp_depot_unmake's live-disqualify
/// guard lets the unmake through, invokes rbw-dU with the captured project_id
/// (BURE_CONFIRM=skip), re-lists, and verifies the depot is absent or in
/// DELETE_REQUESTED state via fact-file content read (no stdout-grep).
fn rbtdrp_depot_tear_down(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrp_depot_tear_down_impl(ctx, dir))
}

fn rbtdrp_depot_tear_down_impl(ctx: &mut rbtdri_Context, dir: &Path) -> rbtdre_Verdict {
    let outcome = match rbtdrk_unmake_preamble(
        ctx,
        dir,
        &rbtdrk_UnmakeSpec {
            blank_moniker_msg: "stand-up did not run or rbrd.env is missing the moniker \
                                (RBRD_DEPOT_MONIKER is blank)",
            project_id_filename: "project-id.txt",
            placeholder_moniker: RBTDRP_TEAR_DOWN_PLACEHOLDER_MONIKER,
            unmake_label: "unmake",
        },
    ) {
        Ok(o) => o,
        Err(v) => return v,
    };

    // Post-unmake assertion — tear-down is a fail-CLOSED allowlist: ONLY an
    // absent fact or DELETE_REQUESTED passes; every other state — including an
    // unreadable fact — fails. This strict allowlist IS the gauntlet's
    // create→destroy proof, and its polarity is STRUCTURALLY INVERTED from
    // churn's fail-open denylist; the two are deliberately not merged.
    if !outcome.state_fact.exists() {
        return rbtdre_Verdict::Pass;
    }

    let depot_state = match std::fs::read_to_string(&outcome.state_fact) {
        Ok(s) => s.trim().to_string(),
        Err(e) => {
            return rbtdre_Verdict::Fail(format!(
                "read depot fact '{}': {}",
                outcome.state_fact.display(),
                e
            ))
        }
    };

    if depot_state == RBTDRP_DELETE_REQUESTED {
        return rbtdre_Verdict::Pass;
    }

    rbtdre_Verdict::Fail(format!(
        "depot '{}' (project '{}') still present with unexpected state '{}' after unmake \
         (expected absent or '{}')",
        outcome.moniker, outcome.project_id, depot_state, RBTDRP_DELETE_REQUESTED
    ))
}

// ── Case registry ────────────────────────────────────────────

pub static RBTDRP_CASES_DEPOT_LIFECYCLE: &[rbtdre_Case] = &[
    case!(rbtdrp_marshal_zero_attestation),
    case!(rbtdrp_depot_stand_up),
    case!(rbtdrp_depot_live_disqualify),
    case!(rbtdrp_depot_tear_down),
];

pub static RBTDRP_FIXTURE_DEPOT_LIFECYCLE: rbtdre_Fixture = rbtdre_Fixture {
    name: RBTDRM_FIXTURE_DEPOT_LIFECYCLE,
    disposition: rbtdre_Disposition::StateProgressing,
    setup: None,
    teardown: None,
    cases: RBTDRP_CASES_DEPOT_LIFECYCLE,
    credless: false,
    tariff: rbtdre_Tariff::UNCHECKED,
};
const _: () = assert!(RBTDRP_FIXTURE_DEPOT_LIFECYCLE.cases.len() == 4);
