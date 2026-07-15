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
// RBTDRK — shared freehold-scheme machinery for the depot test fixtures
//
// One depot test-prefix scheme — the freehold — serves every depot fixture:
// the durable freehold operations (rbtdrk_depot) and the
// ephemeral depot-lifecycle (rbtdrp_lifecycle). This module is the single home
// for the scheme: prefix bases, family stem, static SA identities, the env-file
// install/rewrite helpers, the auto-increment moniker picker, and the case
// precondition probes. The fixtures compose on top of it; none carries its own
// copy. (The collapse of the former canonical/pristine two-scheme world: the
// surviving cloud/runtime prefix VALUES are `canc`/`canr` and the family stem is
// `canest3`, kept as opaque deployed strings so the live freehold keeps working
// — the names here are freehold vocabulary, the values are vestigial.)
//
// The auto-increment picker's `max + 1` rule is what keeps the lifecycle fixture
// from ever colliding with the standing freehold: a routine lifecycle run always
// mints a FRESH moniker and tears that down — only the deliberate, suiteless
// freehold-churn ever destroys the freehold itself.

use std::path::{Path, PathBuf};
use std::time::{
    Duration,
    Instant,
};

use crate::rbtdre_engine::{
    rbtdre_commit_regime,
    rbtdre_RegimeFile,
    rbtdre_Verdict,
};
use crate::rbtdrx_platform::rbtdrx_path_from_env;
use crate::rbtdri_invocation::{
    RBTDRI_BURE_CONFIRM_KEY,
    RBTDRI_BURE_CONFIRM_SKIP,
    RBTDRI_BURV_OUTPUT_SUBDIR,
    rbtdri_Context,
    rbtdri_InvokeResult,
    rbtdri_invoke_global,
};
use crate::rbtdgc_consts::{
    RBTDGC_BAND_ADMISSION,
    RBTDGC_LIST_DEPOT,
    RBTDGC_PROPAGATION_DEADLINE_SEC,
    RBTDGC_PROPAGATION_INITIAL_DELAY_SEC,
    RBTDGC_PROPAGATION_MAX_DELAY_SEC,
    RBTDGC_RBRD_FILE,
    RBTDGC_RBRR_FILE,
    RBTDGC_UNMAKE_DEPOT,
};

// ── Freehold-scheme identities ───────────────────────────────

/// Freehold RBRR prefix bases installed by the establish/stand-up cases.
/// Per-station tincture from BURS is composed in at runtime so parallel-station
/// runs land in disjoint cloud names. The probe detects freehold state by
/// reading the moniker's family stem (also tinctured) from rbrr.env. (Deployed
/// VALUES retained from the former canonical scheme — opaque strings now.)
pub(crate) const RBTDRK_FREEHOLD_CLOUD_BASE: &str = "canc";
pub(crate) const RBTDRK_FREEHOLD_RUNTIME_BASE: &str = "canr";

/// Family-stem base for freehold depots; six-digit auto-increment suffix per
/// run. Depots persist post-success for operator inspection; reruns pick the
/// next free suffix by walking depot_list output. Per-station tincture is
/// composed in at runtime so each station's monikers fact-file-walk against
/// a disjoint family stem. The `3` is an era bump (past `canest`/`canest2`)
/// that side-stepped pending-delete projectId reservations from burned-bridges
/// teardown: project IDs are globally unique and reserved ~30 days post-delete,
/// and the active-only, single-identity allocator re-derives a reserved ID it
/// can neither see nor own. (Deployed VALUE retained from the former canonical
/// scheme.)
pub(crate) const RBTDRK_FREEHOLD_STEM_BASE: &str = "canest3";

const RBTDRK_FAMILY_NUMERIC_FLOOR: u32 = 100000;
const RBTDRK_FAMILY_NUMERIC_WIDTH: usize = 6;

// rbgp_depot_list emits fact files at
// `<cloud_prefix>/<moniker>.depot` (state) and
// `<cloud_prefix>/<moniker>.depot-project` (project_id). The cloud_prefix
// subdir prevents collisions between same-moniker depots under different
// cloud_prefixes.
pub(crate) const RBTDRK_FACT_EXT_DEPOT: &str = "depot";
pub(crate) const RBTDRK_FACT_EXT_DEPOT_PROJECT: &str = "depot-project";
/// Depot lifecycle state string rbw-dl emits into the `.depot` fact for an ACTIVE
/// project (mirrors the bash RBGP_DEPOT_STATE_COMPLETE). The reuse gate compares
/// the current freehold's state fact against this; anything else (DELETE_REQUESTED,
/// or no fact at all) is treated as "needs creation".
pub(crate) const RBTDRK_DEPOT_STATE_COMPLETE: &str = "COMPLETE";

pub(crate) const RBTDRK_FIELD_RBRD_CLOUD_PREFIX: &str = "RBRD_CLOUD_PREFIX";
pub(crate) const RBTDRK_FIELD_RBRR_RUNTIME_PREFIX: &str = "RBRR_RUNTIME_PREFIX";
pub(crate) const RBTDRK_FIELD_RBRD_DEPOT_MONIKER: &str = "RBRD_DEPOT_MONIKER";

/// BURS station-file env var (exported by bul_launcher.sh) — absolute path
/// to the developer's burs.env. Source for BURS_TINCTURE.
const RBTDRK_ENV_STATION_FILE: &str = "BURD_STATION_FILE";

/// Read BURS_TINCTURE from the station file resolved via BURD_STATION_FILE.
/// BURS validation upstream (zburs_enforce) guarantees the value is 1-3 chars
/// of lowercase alphanumeric starting with a letter.
pub(crate) fn rbtdrk_burs_tincture() -> Result<String, String> {
    let path = rbtdrx_path_from_env(RBTDRK_ENV_STATION_FILE)?;
    rbtdrk_read_env_value(&path, "BURS_TINCTURE")
        .ok_or_else(|| format!("BURS_TINCTURE not in {}", path.display()))
}

/// Compose freehold RBRD_CLOUD_PREFIX with the given tincture.
pub(crate) fn rbtdrk_freehold_cloud_prefix(tincture: &str) -> String {
    format!("{}{}-", RBTDRK_FREEHOLD_CLOUD_BASE, tincture)
}

/// Compose freehold RBRR_RUNTIME_PREFIX with the given tincture.
pub(crate) fn rbtdrk_freehold_runtime_prefix(tincture: &str) -> String {
    format!("{}{}-", RBTDRK_FREEHOLD_RUNTIME_BASE, tincture)
}

/// Compose freehold family stem with the given tincture.
pub(crate) fn rbtdrk_family_stem(tincture: &str) -> String {
    format!("{}{}", RBTDRK_FREEHOLD_STEM_BASE, tincture)
}

// ── Helpers ──────────────────────────────────────────────────

/// Read an env-file value or None if absent. The bash regime files use
/// `KEY=value` lines (unquoted); comment and blank lines are skipped.
pub(crate) fn rbtdrk_read_env_value(path: &Path, key: &str) -> Option<String> {
    let content = std::fs::read_to_string(path).ok()?;
    let prefix = format!("{}=", key);
    for line in content.lines() {
        let trimmed = line.trim_start();
        if trimmed.starts_with('#') {
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix(&prefix) {
            return Some(rest.to_string());
        }
    }
    None
}

/// Resolve a path that may be absolute or relative-to-project-root.
pub(crate) fn rbtdrk_resolve(root: &Path, raw: &str) -> PathBuf {
    if Path::new(raw).is_absolute() {
        PathBuf::from(raw)
    } else {
        root.join(raw)
    }
}

fn rbtdrk_replace_env_fields(content: &str, pairs: &[(&str, &str)]) -> String {
    let mut result: String = content
        .lines()
        .map(|line| {
            for (key, value) in pairs {
                let assign = format!("{}=", key);
                if line.starts_with(&assign) {
                    return format!("{}{}", assign, value);
                }
            }
            line.to_string()
        })
        .collect::<Vec<_>>()
        .join("\n");
    if content.ends_with('\n') {
        result.push('\n');
    }
    result
}

// ── Freehold-prefix install ──────────────────────────────────

/// Idempotently install the freehold canc-/canr- prefixes. CLOUD_PREFIX lands in
/// rbrd.env, RUNTIME_PREFIX lands in rbrr.env. Returns Ok without committing when
/// both already match the freehold markers; otherwise rewrites both files and
/// commits in one go.
pub(crate) fn rbtdrk_install_freehold_prefixes(root: &Path) -> Result<(), String> {
    let rbrr = root.join(RBTDGC_RBRR_FILE);
    let rbrd = root.join(RBTDGC_RBRD_FILE);
    let tincture = rbtdrk_burs_tincture()?;
    let cloud_target = rbtdrk_freehold_cloud_prefix(&tincture);
    let runtime_target = rbtdrk_freehold_runtime_prefix(&tincture);

    let cloud = rbtdrk_read_env_value(&rbrd, RBTDRK_FIELD_RBRD_CLOUD_PREFIX).unwrap_or_default();
    let runtime =
        rbtdrk_read_env_value(&rbrr, RBTDRK_FIELD_RBRR_RUNTIME_PREFIX).unwrap_or_default();
    if cloud == cloud_target && runtime == runtime_target {
        return Ok(());
    }

    if cloud != cloud_target {
        let content = std::fs::read_to_string(&rbrd)
            .map_err(|e| format!("rbtdrk: read {}: {}", rbrd.display(), e))?;
        let new_content = rbtdrk_replace_env_fields(
            &content,
            &[(RBTDRK_FIELD_RBRD_CLOUD_PREFIX, cloud_target.as_str())],
        );
        std::fs::write(&rbrd, &new_content)
            .map_err(|e| format!("rbtdrk: write {}: {}", rbrd.display(), e))?;
    }

    if runtime != runtime_target {
        let content = std::fs::read_to_string(&rbrr)
            .map_err(|e| format!("rbtdrk: read {}: {}", rbrr.display(), e))?;
        let new_content = rbtdrk_replace_env_fields(
            &content,
            &[(RBTDRK_FIELD_RBRR_RUNTIME_PREFIX, runtime_target.as_str())],
        );
        std::fs::write(&rbrr, &new_content)
            .map_err(|e| format!("rbtdrk: write {}: {}", rbrr.display(), e))?;
    }

    let commit_msg = format!(
        "freehold fixture: install freehold prefixes ({}/{})",
        cloud_target, runtime_target
    );
    rbtdre_commit_regime(
        root,
        &[rbtdre_RegimeFile::Rbrr, rbtdre_RegimeFile::Rbrd],
        &commit_msg,
    )
}

pub(crate) fn rbtdrk_install_depot_moniker(root: &Path, moniker: &str) -> Result<(), String> {
    let rbrd = root.join(RBTDGC_RBRD_FILE);
    let content = std::fs::read_to_string(&rbrd)
        .map_err(|e| format!("rbtdrk: read {}: {}", rbrd.display(), e))?;
    let new_content =
        rbtdrk_replace_env_fields(&content, &[(RBTDRK_FIELD_RBRD_DEPOT_MONIKER, moniker)]);
    std::fs::write(&rbrd, &new_content)
        .map_err(|e| format!("rbtdrk: write {}: {}", rbrd.display(), e))?;
    let commit_msg = format!(
        "freehold fixture: set {}={}",
        RBTDRK_FIELD_RBRD_DEPOT_MONIKER, moniker
    );
    rbtdre_commit_regime(root, &[rbtdre_RegimeFile::Rbrd], &commit_msg)
}

/// Compose depot project_id from kindled regime values: <CLOUD>d-<moniker>.
pub(crate) fn rbtdrk_compose_project_id(root: &Path, moniker: &str) -> Result<String, String> {
    let rbrd = root.join(RBTDGC_RBRD_FILE);
    let cloud_prefix = rbtdrk_read_env_value(&rbrd, RBTDRK_FIELD_RBRD_CLOUD_PREFIX)
        .ok_or_else(|| format!("RBRD_CLOUD_PREFIX missing from {}", rbrd.display()))?;
    Ok(format!("{}d-{}", cloud_prefix, moniker))
}

/// Cloud-prefix subdir name used in depot fact-file layout
/// (`<cloud_prefix>/<moniker>.depot`). Derived from RBRD_CLOUD_PREFIX with
/// the structural trailing `-` stripped so it matches the filesystem layout
/// emitted by zrbgp_depot_state_emit.
pub(crate) fn rbtdrk_cloud_prefix_subdir(root: &Path) -> Result<String, String> {
    let rbrd = root.join(RBTDGC_RBRD_FILE);
    let cloud_prefix = rbtdrk_read_env_value(&rbrd, RBTDRK_FIELD_RBRD_CLOUD_PREFIX)
        .ok_or_else(|| format!("RBRD_CLOUD_PREFIX missing from {}", rbrd.display()))?;
    Ok(cloud_prefix.trim_end_matches('-').to_string())
}

/// Parent directory of the depot fact files a `rbgp_depot_list` invocation
/// emits: `<burv_output>/<RBTDRI_BURV_OUTPUT_SUBDIR>/<prefix_dir>`. The
/// cloud_prefix subdir (`rbtdrk_cloud_prefix_subdir`) is what keeps same-moniker
/// depots under different cloud_prefixes from colliding. `pick_next_moniker`
/// `read_dir`s this directory; `rbtdrk_depot_fact_path` joins one leaf onto it.
pub(crate) fn rbtdrk_depot_fact_dir(
    list_result: &rbtdri_InvokeResult,
    prefix_dir: &str,
) -> PathBuf {
    list_result
        .burv_output
        .join(RBTDRI_BURV_OUTPUT_SUBDIR)
        .join(prefix_dir)
}

/// One depot fact file: `<fact_dir>/<moniker>.<ext>` — the state fact
/// (`RBTDRK_FACT_EXT_DEPOT`) or the project-id fact
/// (`RBTDRK_FACT_EXT_DEPOT_PROJECT`). Built on `rbtdrk_depot_fact_dir` so the
/// layout lives in one place. These facts sit one dir deeper than
/// `rbtdri_read_burv_fact`'s prefix-less layout, so this prefixed builder is a
/// genuine analogue, not a re-duplication.
pub(crate) fn rbtdrk_depot_fact_path(
    list_result: &rbtdri_InvokeResult,
    prefix_dir: &str,
    moniker: &str,
    ext: &str,
) -> PathBuf {
    rbtdrk_depot_fact_dir(list_result, prefix_dir).join(format!("{}.{}", moniker, ext))
}

/// Pick the next free moniker for `family_stem` by walking the depot_list
/// invocation's BURV output dir for `<family>NNNNNN.depot` files under the
/// current cloud_prefix subdir. Returns
/// `<family>RBTDRK_FAMILY_NUMERIC_FLOOR` when no matching files exist.
/// Restricting the walk to the current cloud_prefix is what makes allocation
/// collision-safe: a same-numbered moniker under a foreign cloud_prefix is
/// correctly ignored.
///
/// `max + 1` is also the safety boundary between the lifecycle and the
/// freehold: a lifecycle stand-up always picks a moniker ABOVE the standing
/// freehold's, so its tear-down never reaches the freehold.
///
/// Caller contract: `list_result` MUST be from a freshly-invoked depot_list
/// that ran in the current process. The fact-file scan IS the collision
/// check — stale state means picking a colliding moniker. Do not reuse a
/// `list_result` across cases or pass an operator-cached value.
pub(crate) fn rbtdrk_pick_next_moniker(
    list_result: &rbtdri_InvokeResult,
    root: &Path,
    family_stem: &str,
) -> Result<String, String> {
    let prefix_dir = rbtdrk_cloud_prefix_subdir(root)?;
    let dir = rbtdrk_depot_fact_dir(list_result, &prefix_dir);
    let entries = match std::fs::read_dir(&dir) {
        Ok(e) => e,
        Err(_) => {
            return Ok(format!("{}{}", family_stem, RBTDRK_FAMILY_NUMERIC_FLOOR));
        }
    };
    let suffix_ext = format!(".{}", RBTDRK_FACT_EXT_DEPOT);
    let mut max_suffix: Option<u32> = None;
    for entry in entries.flatten() {
        let name = match entry.file_name().into_string() {
            Ok(n) => n,
            Err(_) => continue,
        };
        let stem = match name.strip_suffix(&suffix_ext) {
            Some(s) => s,
            None => continue,
        };
        let numeric = match stem.strip_prefix(family_stem) {
            Some(s) => s,
            None => continue,
        };
        if numeric.len() != RBTDRK_FAMILY_NUMERIC_WIDTH {
            continue;
        }
        let parsed: u32 = match numeric.parse() {
            Ok(n) => n,
            Err(_) => continue,
        };
        max_suffix = Some(max_suffix.map_or(parsed, |m| m.max(parsed)));
    }
    let next = match max_suffix {
        Some(m) => m + 1,
        None => RBTDRK_FAMILY_NUMERIC_FLOOR,
    };
    Ok(format!("{}{}", family_stem, next))
}

/// Wrapper invocation: call `rbtdri_invoke_global` and tee stdout/stderr to
/// `dir/<label>-stdout.txt` / `dir/<label>-stderr.txt` for diagnostic review.
/// Returns `Ok(InvokeResult)` regardless of exit code; callers decide what
/// counts as failure.
pub(crate) fn rbtdrk_invoke_logged(
    ctx: &mut rbtdri_Context,
    colophon: &str,
    args: &[&str],
    extra_env: &[(&str, &str)],
    dir: &Path,
    label: &str,
) -> Result<rbtdri_InvokeResult, String> {
    let result = rbtdri_invoke_global(ctx, colophon, args, extra_env)?;
    let _ = std::fs::write(dir.join(format!("{}-stdout.txt", label)), &result.stdout);
    let _ = std::fs::write(dir.join(format!("{}-stderr.txt", label)), &result.stderr);
    Ok(result)
}

/// Post-admission-grant invocation: `rbtdrk_invoke_logged`, re-invoked while
/// the exit is exactly `RBTDGC_BAND_ADMISSION` under the RBSCIP propagation
/// budget (RBr_3f4). A fixture invocation issued immediately downstream of a
/// fresh admission grant (gird, brevet) is a post-grant site: its first don
/// can draw the Class-C 403 while the just-written binding propagates, and
/// the production don is cinched fail-fast (RBr_7a9), so the fixture owns
/// the wait. The band code is minted only at the don preamble — before the
/// verb body mutates anything — so re-invoking on it is safe for mutating
/// verbs. Any other exit returns immediately; an exhausted budget returns
/// the final 109 result, so a real admission denial still fails the case.
pub(crate) fn rbtdrk_invoke_admission_settled(
    ctx: &mut rbtdri_Context,
    colophon: &str,
    args: &[&str],
    dir: &Path,
    label: &str,
) -> Result<rbtdri_InvokeResult, String> {
    let deadline = Duration::from_secs(RBTDGC_PROPAGATION_DEADLINE_SEC as u64);
    let max_delay = Duration::from_secs(RBTDGC_PROPAGATION_MAX_DELAY_SEC as u64);
    let mut delay = Duration::from_secs(RBTDGC_PROPAGATION_INITIAL_DELAY_SEC as u64);
    let start = Instant::now();
    let mut bend = 0u32;
    loop {
        let result = rbtdrk_invoke_logged(ctx, colophon, args, &[], dir, label)?;
        if result.exit_code != RBTDGC_BAND_ADMISSION {
            return Ok(result);
        }
        if start.elapsed() + delay > deadline {
            return Ok(result);
        }
        bend += 1;
        crate::rbtdrg_info_now!(
            "{}: admission-band exit {} with a fresh grant upstream — propagation bend {} (RBr_3f4); retrying in {}s",
            label,
            RBTDGC_BAND_ADMISSION,
            bend,
            delay.as_secs()
        );
        std::thread::sleep(delay);
        delay = std::cmp::min(delay * 2, max_delay);
    }
}

// ── Probes ───────────────────────────────────────────────────

/// Probes are pure `fn() -> Result<(), String>` per the rbtdrb_Probe shape and
/// have no context, so they read the project root from current_dir() — theurge
/// always launches from the project root.
fn rbtdrk_probe_root() -> Result<PathBuf, String> {
    std::env::current_dir().map_err(|e| format!("cannot resolve project root: {}", e))
}

/// rbrr.env exists. Sanity precondition — the establish cases presume the regime
/// has been initialized at least to the marshal-zero blank-template shape.
pub(crate) fn rbtdrk_probe_rbrr_present() -> Result<(), String> {
    let root = rbtdrk_probe_root()?;
    let rbrr = root.join(RBTDGC_RBRR_FILE);
    if !rbrr.exists() {
        return Err(format!("rbrr.env not found at {}", rbrr.display()));
    }
    Ok(())
}

/// Freehold depot moniker installed in rbrd.env. Established by the ensure case;
/// absence means freehold-ensure didn't run or rbrd.env was rewritten.
pub(crate) fn rbtdrk_probe_freehold_moniker() -> Result<(), String> {
    let root = rbtdrk_probe_root()?;
    let rbrd = root.join(RBTDGC_RBRD_FILE);
    let tincture = rbtdrk_burs_tincture()?;
    let family_stem = rbtdrk_family_stem(&tincture);
    let moniker =
        rbtdrk_read_env_value(&rbrd, RBTDRK_FIELD_RBRD_DEPOT_MONIKER).unwrap_or_default();
    if !moniker.starts_with(&family_stem) {
        return Err(format!(
            "{}={:?} does not begin with '{}' — freehold depot moniker not installed",
            RBTDRK_FIELD_RBRD_DEPOT_MONIKER, moniker, family_stem
        ));
    }
    Ok(())
}

// ── Shared wrapper spines ────────────────────────────────────
//
// The two depot wrappers — REUSE (freehold-ensure) and LIFECYCLE (depot
// stand-up + tear-down) — are near-clones with two load-bearing differences
// that must stay at the call site: the reuse-vs-create branch IS the wrapper's
// instance selection, and the post-unmake assertion is STRUCTURALLY INVERTED
// between tear-down and churn (see the unmake preamble below). These helpers
// lift only the byte-identical spines the two share, never the differences.

/// Cross-check the depot's actual project_id — read from the `<moniker>` depot-
/// project fact in `fact_list`'s BURV output — against the RBDC compose
/// derivation, writing the captured id to `dir/project-id.txt` for diagnostics.
/// Returns `Some(Fail)` on any divergence (missing/empty fact or compose
/// mismatch), `None` when they agree.
///
/// This is the ONLY byte-identical block shared by freehold-ensure (reuse path)
/// and depot stand-up (lifecycle): the cross-check TAIL. The reuse-vs-create
/// branch that selects which `InvokeResult` supplies `fact_list` stays at the
/// call site — that selection is the wrapper's instance choice, not part of the
/// shared spine.
pub(crate) fn rbtdrk_crosscheck_project_id(
    root: &Path,
    fact_list: &rbtdri_InvokeResult,
    prefix_dir: &str,
    moniker: &str,
    dir: &Path,
) -> Option<rbtdre_Verdict> {
    let fact_path =
        rbtdrk_depot_fact_path(fact_list, prefix_dir, moniker, RBTDRK_FACT_EXT_DEPOT_PROJECT);
    let fact_project_id = match std::fs::read_to_string(&fact_path) {
        Ok(s) => s.trim().to_string(),
        Err(e) => {
            return Some(rbtdre_Verdict::Fail(format!(
                "read depot-project fact '{}': {}",
                fact_path.display(),
                e
            )))
        }
    };
    if fact_project_id.is_empty() {
        return Some(rbtdre_Verdict::Fail(format!(
            "depot-project fact is empty: {}",
            fact_path.display()
        )));
    }
    let _ = std::fs::write(dir.join("project-id.txt"), &fact_project_id);

    let composed = match rbtdrk_compose_project_id(root, moniker) {
        Ok(p) => p,
        Err(e) => return Some(rbtdre_Verdict::Fail(format!("compose project_id: {}", e))),
    };
    if composed != fact_project_id {
        return Some(rbtdre_Verdict::Fail(format!(
            "project_id mismatch: RBDC compose='{}' vs depot-list fact='{}' \
             (RBDC kindle derivation diverged from payor creation)",
            composed, fact_project_id
        )));
    }
    None
}

/// Per-call-site forensic labels the shared unmake preamble interpolates. Each
/// is a low-stakes diagnostic string the spec keeps call-site-owned, so
/// tear-down and churn retain their distinct failure-attribution and trace
/// artifacts.
pub(crate) struct rbtdrk_UnmakeSpec<'a> {
    /// Fail message when RBRD_DEPOT_MONIKER is blank (no depot to unmake).
    pub(crate) blank_moniker_msg: &'a str,
    /// Trace filename the composed project_id is written to in `dir`.
    pub(crate) project_id_filename: &'a str,
    /// Placeholder moniker rotated into RBRD so the unmake's live-disqualify
    /// guard releases the real project.
    pub(crate) placeholder_moniker: &'a str,
    /// Invocation label for the unmake call's stdout/stderr capture files.
    pub(crate) unmake_label: &'a str,
}

/// What the unmake preamble hands its caller's post-unmake assertion: the
/// resolved state-fact path plus the identifiers the assertion's Fail message
/// interpolates.
pub(crate) struct rbtdrk_UnmakeOutcome {
    pub(crate) state_fact: PathBuf,
    pub(crate) moniker: String,
    pub(crate) project_id: String,
}

/// The shared preamble of the two depot teardowns — tear-down (lifecycle) and
/// churn — up to the moment the post-unmake state fact is resolved: read the
/// moniker, compose the project_id, record it, rotate the moniker to the spec's
/// placeholder so `rbgp_depot_unmake`'s live-disqualify guard lets the unmake
/// through, unmake (confirm skipped via the test seam), re-list, and resolve the
/// churned moniker's state fact. Returns `Err(Fail)` to short-circuit, else the
/// `rbtdrk_UnmakeOutcome` the caller's assertion needs.
///
/// The caller then applies its OWN post-unmake assertion. Those two assertions
/// are STRUCTURALLY INVERTED — tear-down is a fail-closed allowlist (only
/// absent / DELETE_REQUESTED pass), churn is a fail-open denylist (anything but
/// COMPLETE passes) — and are deliberately NOT merged: a finite allowlist cannot
/// express churn's "complement of {COMPLETE}", and a wrong fold here would
/// silently lose the create→destroy-proof coverage tear-down's allowlist carries.
pub(crate) fn rbtdrk_unmake_preamble(
    ctx: &mut rbtdri_Context,
    dir: &Path,
    spec: &rbtdrk_UnmakeSpec,
) -> Result<rbtdrk_UnmakeOutcome, rbtdre_Verdict> {
    let root = ctx.project_root().to_path_buf();
    let rbrd = root.join(RBTDGC_RBRD_FILE);

    let moniker = match rbtdrk_read_env_value(&rbrd, RBTDRK_FIELD_RBRD_DEPOT_MONIKER) {
        Some(m) if !m.is_empty() => m,
        _ => return Err(rbtdre_Verdict::Fail(spec.blank_moniker_msg.to_string())),
    };

    let project_id = match rbtdrk_compose_project_id(&root, &moniker) {
        Ok(p) => p,
        Err(e) => return Err(rbtdre_Verdict::Fail(format!("compose project_id: {}", e))),
    };
    let _ = std::fs::write(dir.join(spec.project_id_filename), &project_id);

    if let Err(e) = rbtdrk_install_depot_moniker(&root, spec.placeholder_moniker) {
        return Err(rbtdre_Verdict::Fail(format!(
            "rotate moniker before unmake: {}",
            e
        )));
    }

    let unmake = match rbtdrk_invoke_logged(
        ctx,
        RBTDGC_UNMAKE_DEPOT,
        &[&project_id],
        &[(RBTDRI_BURE_CONFIRM_KEY, RBTDRI_BURE_CONFIRM_SKIP)],
        dir,
        spec.unmake_label,
    ) {
        Ok(r) => r,
        Err(e) => return Err(rbtdre_Verdict::Fail(format!("depot unmake: {}", e))),
    };
    if unmake.exit_code != 0 {
        return Err(rbtdre_Verdict::Fail(format!(
            "depot unmake exit {}\n{}",
            unmake.exit_code, unmake.stderr
        )));
    }

    let list_after = match rbtdrk_invoke_logged(ctx, RBTDGC_LIST_DEPOT, &[], &[], dir, "list-after") {
        Ok(r) if r.exit_code == 0 => r,
        Ok(r) => {
            return Err(rbtdre_Verdict::Fail(format!(
                "depot list (after unmake) exit {}\n{}",
                r.exit_code, r.stderr
            )))
        }
        Err(e) => return Err(rbtdre_Verdict::Fail(format!("depot list (after unmake): {}", e))),
    };

    let prefix_dir = match rbtdrk_cloud_prefix_subdir(&root) {
        Ok(p) => p,
        Err(e) => return Err(rbtdre_Verdict::Fail(format!("resolve cloud_prefix subdir: {}", e))),
    };
    let state_fact = rbtdrk_depot_fact_path(&list_after, &prefix_dir, &moniker, RBTDRK_FACT_EXT_DEPOT);

    Ok(rbtdrk_UnmakeOutcome {
        state_fact,
        moniker,
        project_id,
    })
}
