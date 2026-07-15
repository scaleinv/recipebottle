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
// RBTDRI — tabtarget invocation layer for theurge
//
// Theurge invokes bottle operations exclusively through tabtargets, never
// reimplementing bash command logic. This module provides:
//
//   1. Tabtarget discovery — imprint-scoped, global, or nameplate-scoped
//   2. Tabtarget execution with BURV isolation — per-invocation output/temp dirs
//   3. Ifrit verdict parsing — extract verdict from ifrit stdout + exit code
//   4. BURV fact file reading — extract structured output from tabtarget results

use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::OnceLock;

use crate::rbtdgc_consts::{RBTDGC_ORDAIN_HALLMARK, RBTDGC_VERB_ORDAIN};
use crate::rbtdre_engine::rbtdre_Verdict;
use crate::rbtdrx_platform::{rbtdrx_is_cygwin, rbtdrx_native_to_posix, rbtdrx_posix_to_native};

/// BUK dispatch output subdirectory — tabtargets write facts to BURV_OUTPUT_ROOT_DIR/current.
/// Matches BURD_OUTPUT_DIR = "${BURC_OUTPUT_ROOT_DIR}/current" from bud_dispatch.sh.
pub const RBTDRI_BURV_OUTPUT_SUBDIR: &str = "current";

/// Env var name read by `buc_require` (buc_command.sh:335) to bypass interactive
/// confirmation prompts in non-interactive contexts (test fixtures, automation).
pub const RBTDRI_BURE_CONFIRM_KEY: &str = "BURE_CONFIRM";

/// BURE tweak-slot env var (BUS0 Tweak Mechanism) — the single test-seam
/// channel every tabtarget inherits. The credless guard rides this slot for
/// reveille-tier fixtures; case-supplied tweaks ride it everywhere else.
pub const RBTDRI_BURE_TWEAK_NAME_KEY: &str = "BURE_TWEAK_NAME";

/// BURE tweak-value env var — the payload paired with `BURE_TWEAK_NAME`. The
/// regime-poison tweak reads it as `VAR=value` (set) or bare `VAR` (unset).
pub const RBTDRI_BURE_TWEAK_VALUE_KEY: &str = "BURE_TWEAK_VALUE";

/// Value paired with `RBTDRI_BURE_CONFIRM_KEY` to skip the confirmation prompt.
pub const RBTDRI_BURE_CONFIRM_SKIP: &str = "skip";

/// BUK dispatch env var carrying the temp root for theurge — anchors BURV
/// per-invoke temp dirs under temp-buk/ rather than /tmp/. Required: theurge
/// fails at startup if unset. Set by bud_dispatch.sh on every tabtarget call.
pub const RBTDRI_BURD_TEMP_DIR_KEY: &str = "BURD_TEMP_DIR";

/// Canonical Cygwin bash in POSIX form. theurge nativizes this via RBTDRX
/// (cygpath) to launch scripts: a bare "bash" from a Windows-native binary
/// resolves through `CreateProcess` to System32's WSL launcher, never Cygwin's.
const RBTDRI_CYGWIN_BASH_POSIX: &str = "/bin/bash";

/// BURV invoke-directory name from a zero-based invoke count.
///
/// Single source of truth for the `invoke-NNNNN` naming pattern; tests call
/// this rather than hand-expanding the literal.
pub fn rbtdri_invoke_dir_name(invoke_num: u32) -> String {
    format!("invoke-{:05}", invoke_num)
}

// ── Invocation result ────────────────────────────────────────

/// Captured output from a tabtarget invocation.
#[derive(Debug)]
pub struct rbtdri_InvokeResult {
    pub stdout: String,
    pub stderr: String,
    pub exit_code: i32,
    pub burv_output: PathBuf,
}

// ── Invocation context ───────────────────────────────────────

/// Per-case invocation context. Tracks BURV isolation state so each tabtarget
/// invocation within a case gets its own output and temp directories, matching
/// the zbuto_invoke() pattern from buto_operations.sh.
///
/// `fixture` carries the fixture name. For crucible fixtures (tadmor/srjcl/
/// pluml) the fixture name happens to equal a valid nameplate moniker — that's
/// the convention crucible-scoped tabtargets exploit when imprinting (e.g.,
/// `rbw-cC.Charge.{fixture}.sh`). Non-crucible fixtures (regime-*, calibrant-*,
/// canonical-*, etc.) carry their fixture name in this slot too, but no
/// nameplate-shaped consumer reads them.
pub struct rbtdri_Context {
    pub(crate) project_root: PathBuf,
    pub(crate) fixture: String,
    pub(crate) burv_temp_root: PathBuf,
    pub(crate) burv_output_root: PathBuf,
    pub(crate) invoke_count: u32,
    /// One-shot flag: when set, the NEXT invoke reuses the immediately-prior
    /// invoke's BURV root instead of minting a fresh one (see
    /// `chain_next_invoke`). Consumed and cleared by `rbtdri_invoke_impl`.
    pub(crate) chain_next: bool,
}

impl rbtdri_Context {
    pub fn new(
        project_root: &Path,
        fixture: &str,
        burv_temp_root: &Path,
        burv_output_root: &Path,
    ) -> Self {
        Self {
            project_root: project_root.to_path_buf(),
            fixture: fixture.to_string(),
            burv_temp_root: burv_temp_root.to_path_buf(),
            burv_output_root: burv_output_root.to_path_buf(),
            invoke_count: 0,
            chain_next: false,
        }
    }

    pub fn fixture(&self) -> &str {
        &self.fixture
    }

    pub fn project_root(&self) -> &Path {
        &self.project_root
    }

    /// Mark the NEXT tabtarget invocation to chain off the immediately-prior
    /// invoke's BURV root, rather than running in fresh isolation.
    ///
    /// Theurge gives every invoke its own `BURV_OUTPUT_ROOT_DIR`, so
    /// `bud_dispatch`'s start-of-dispatch `current/`->`previous/` promotion never
    /// crosses invokes — each invoke's `previous/` is empty. That suits isolated
    /// operations but breaks the depth-1 cross-tabtarget chain a real operator
    /// gets for free by sharing one `../output-buk` root: the chaining fact one
    /// tabtarget writes to `current/` never reaches the next tabtarget's
    /// `previous/`. The bole derived-pull base-anchor election is the consumer —
    /// `ensconce` writes the touchmark to `current/`, the following `ordain`
    /// reads it from `previous/`.
    ///
    /// Calling this before such a pair makes the next invoke reuse the prior
    /// invoke's root, so the prior invoke's `current/` is promoted into this
    /// invoke's `previous/` — replicating the operator flow for exactly the
    /// invokes that need it, leaving every other invoke's isolation intact.
    /// One-shot: consumed by the next invoke and cleared. Depth-1 only — bud
    /// keeps a single generation, so only the immediate predecessor is visible.
    pub fn chain_next_invoke(&mut self) {
        self.chain_next = true;
    }

    /// Read the suite-monotonic BURV invoke counter. The suite loop reads it
    /// after each fixture and seeds the next Context, so per-invoke dir names
    /// stay unique across fixtures (see set_invoke_count).
    pub fn invoke_count(&self) -> u32 {
        self.invoke_count
    }

    /// Seed the BURV invoke counter so this fixture's invokes continue the
    /// suite-monotonic sequence rather than restarting at 0. Crate-internal code
    /// mutates the field directly; the bin crate must go through this setter
    /// because the field is pub(crate) and so not visible across the lib/bin
    /// boundary.
    pub fn set_invoke_count(&mut self, count: u32) {
        self.invoke_count = count;
    }
}

// ── Credless guard ───────────────────────────────────────────

thread_local! {
    /// Reveille-tier credless guard arm state. Thread-local (not process-global)
    /// to match the rbtdrc context channel: cases, hooks, and direct-Command
    /// helpers all run on the thread that installed the context, and unit
    /// tests on parallel threads cannot interfere with each other.
    static RBTDRI_CREDLESS_ARMED: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

/// Arm or disarm the credless guard for the current thread. Armed by
/// `rbtdrc_set_context` from the fixture's `credless` field and disarmed by
/// `rbtdrc_take_context`, so the guard rides every invocation of a reveille-tier
/// fixture's cases regardless of which suite hosts the fixture.
pub fn rbtdri_arm_credless(armed: bool) {
    RBTDRI_CREDLESS_ARMED.with(|c| c.set(armed));
}

/// Read the current thread's credless guard arm state.
pub fn rbtdri_credless_armed() -> bool {
    RBTDRI_CREDLESS_ARMED.with(|c| c.get())
}

// ── Tariff invocation tally ──────────────────────────────────

thread_local! {
    /// Per-fixture tabtarget-invocation tally, feeding the tariff footprint.
    /// Thread-local for the same reason as the credless guard: the fixture's
    /// setup, cases, and teardown all run on the thread that installed the
    /// context, so a tally reset before the fixture and read after it captures
    /// exactly that fixture's tabtarget launches. Unit tests on parallel threads
    /// cannot perturb one another.
    static RBTDRI_TARIFF_COUNT: std::cell::Cell<u32> = const { std::cell::Cell::new(0) };
}

/// Zero the current thread's tariff tally. Called by the engine before a
/// fixture's setup so the count spans the whole fixture footprint.
pub fn rbtdri_tariff_reset() {
    RBTDRI_TARIFF_COUNT.with(|c| c.set(0));
}

/// Read the current thread's tariff tally — the tabtarget-invocation count since
/// the last reset. Read by the engine after a fixture's teardown.
pub fn rbtdri_tariff_count() -> u32 {
    RBTDRI_TARIFF_COUNT.with(|c| c.get())
}

/// Bump the tariff tally by one. Called once per tabtarget launch from the
/// single construction funnel below (`rbtdri_tabtarget_command`) — the one
/// chokepoint every tabtarget spawn passes through, funnelled and direct-Command
/// alike. Saturating so a runaway fixture cannot wrap the counter.
fn zrbtdri_tariff_bump() {
    RBTDRI_TARIFF_COUNT.with(|c| c.set(c.get().saturating_add(1)));
}

// ── Colophon census (declared vs used) ───────────────────────
//
// A fixture's `rbtdrm_required_colophons` manifest entry declares the
// colophons its cases are expected to invoke; `rbtdrm_permitted_colophons`
// declares a second, positive-only tier — admitted at the invoke chokepoint
// exactly like a required colophon, but never demanded by the negative
// check (a conditional-by-design invocation may legitimately go unused on a
// healthy run). Enforcement is two-directional, and the two directions live
// at DIFFERENT chokepoints by design:
//
//   * POSITIVE (an invoke of an undeclared colophon refuses) — in
//     `rbtdri_invoke_impl`, the shared implementation of the `rbtdri_invoke*`
//     primitives, which can return an error. Direct-Command bypass launches
//     cannot be refused there (a `Command` constructor has no failure path).
//   * USED-SET RECORDING — in `rbtdri_tabtarget_command`, the one constructor
//     every tabtarget spawn passes through, funnelled and direct-Command
//     alike (the same universal chokepoint as the tariff tally), so a bypass
//     launch still satisfies the negative direction. The colophon is the
//     script filename's leading dot-segment — the same
//     {colophon}.{frontispiece}[.{imprint}].sh contract discovery matches on.
//
// The NEGATIVE check itself (a declared colophon never invoked fails a
// fully-green run) is evaluated by rbtdre_engine once the fixture completes.
//
// Thread-local for the same reason as the credless guard and the tariff
// tally: case functions and setup/teardown hooks reach their fixture's
// invocation state only through the rbtdrc thread-local channel, on the
// thread that runs the whole fixture. Armed by `rbtdrc_set_context` from the
// fixture's manifest entry and disarmed by `rbtdrc_take_context`, exactly as
// the credless guard is — installing a context IS entering a fixture's run,
// so arming cannot be forgotten at a runner call site.
//
// `None` means "this fixture carries no manifest entry" — census tracking is
// disabled entirely (neither direction enforced, nothing recorded), distinct
// from `Some(&[])` ("declares zero colophons", which enforces the empty
// declaration: any funnel invoke refuses). The distinction matters: ad hoc
// fixture names used by invocation-mechanics tests (never meant to interact
// with census policy) resolve to `None` and are untouched by this feature.
thread_local! {
    static RBTDRI_CENSUS_DECLARED: std::cell::RefCell<Option<&'static [&'static str]>> =
        const { std::cell::RefCell::new(None) };
    static RBTDRI_CENSUS_PERMITTED: std::cell::RefCell<&'static [&'static str]> =
        const { std::cell::RefCell::new(&[]) };
    static RBTDRI_CENSUS_USED: std::cell::RefCell<std::collections::HashSet<String>> =
        std::cell::RefCell::new(std::collections::HashSet::new());
}

/// Arm the census for the fixture about to run — the declared (required)
/// colophon set (`None` disables census tracking for this run), the
/// permitted colophon set (positive-only; empty when the fixture declares
/// none), and a cleared used-set. Callers pass `rbtdrm_required_colophons`
/// and `rbtdrm_permitted_colophons` directly; this module stays independent
/// of the manifest module, so tests can arm an arbitrary synthetic pair
/// without a real manifest entry.
pub fn rbtdri_census_arm(
    declared: Option<&'static [&'static str]>,
    permitted: &'static [&'static str],
) {
    RBTDRI_CENSUS_DECLARED.with(|d| *d.borrow_mut() = declared);
    RBTDRI_CENSUS_PERMITTED.with(|p| *p.borrow_mut() = permitted);
    RBTDRI_CENSUS_USED.with(|u| u.borrow_mut().clear());
}

/// Read the current thread's armed declared-colophon (required) set.
pub fn rbtdri_census_declared() -> Option<&'static [&'static str]> {
    RBTDRI_CENSUS_DECLARED.with(|d| *d.borrow())
}

/// Read the current thread's armed permitted-colophon set — positive-only,
/// never consulted by the negative (post-fixture) census direction.
pub fn rbtdri_census_permitted() -> &'static [&'static str] {
    RBTDRI_CENSUS_PERMITTED.with(|p| *p.borrow())
}

/// Read the current thread's used-colophon set — every colophon whose
/// tabtarget was launched (funnel or bypass) since the last arm.
pub fn rbtdri_census_used() -> std::collections::HashSet<String> {
    RBTDRI_CENSUS_USED.with(|u| u.borrow().clone())
}

/// Record a launched tabtarget's colophon into the census used-set. Sits in
/// `rbtdri_tabtarget_command` beside the tariff bump — the universal launch
/// chokepoint — so direct-Command bypass launches count toward the negative
/// census direction just like funnelled ones. The colophon is derived from
/// the script filename's leading dot-segment. No-op while disarmed.
fn zrbtdri_census_record(tabtarget: &Path) {
    let armed = RBTDRI_CENSUS_DECLARED.with(|d| d.borrow().is_some());
    if !armed {
        return;
    }
    if let Some(colophon) = tabtarget
        .file_name()
        .and_then(|n| n.to_str())
        .and_then(|n| n.split('.').next())
    {
        RBTDRI_CENSUS_USED.with(|u| {
            u.borrow_mut().insert(colophon.to_string());
        });
    }
}

// ── Tabtarget discovery ──────────────────────────────────────

/// Find the tabtarget script for a colophon + imprint (nameplate or role).
///
/// Scans tt/ for files matching `{colophon}.*.{imprint}.sh`.
/// Returns error if zero or multiple matches — exactly one must exist.
pub fn rbtdri_find_tabtarget(
    project_root: &Path,
    colophon: &str,
    imprint: &str,
) -> Result<PathBuf, String> {
    let tt_dir = project_root.join("tt");
    let prefix = format!("{}.", colophon);
    let suffix = format!(".{}.sh", imprint);

    let entries = std::fs::read_dir(&tt_dir)
        .map_err(|e| format!("rbtdri: cannot read tt/ directory: {}", e))?;

    let matches: Vec<PathBuf> = entries
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path())
        .filter(|path| {
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                name.starts_with(&prefix) && name.ends_with(&suffix)
            } else {
                false
            }
        })
        .collect();

    match matches.len() {
        0 => Err(format!(
            "rbtdri: no tabtarget for colophon '{}' imprint '{}'",
            colophon, imprint
        )),
        1 => Ok(matches.into_iter().next().unwrap()),
        n => Err(format!(
            "rbtdri: {} tabtargets match colophon '{}' imprint '{}' — expected exactly one",
            n, colophon, imprint
        )),
    }
}

/// Find a global tabtarget (no imprint suffix).
///
/// Scans tt/ for files matching `{colophon}.{frontispiece}.sh` (exactly two dots).
/// Rejects files with imprint suffixes (three+ dots).
pub fn rbtdri_find_tabtarget_global(
    project_root: &Path,
    colophon: &str,
) -> Result<PathBuf, String> {
    let tt_dir = project_root.join("tt");
    let prefix = format!("{}.", colophon);

    let entries = std::fs::read_dir(&tt_dir)
        .map_err(|e| format!("rbtdri: cannot read tt/ directory: {}", e))?;

    let matches: Vec<PathBuf> = entries
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path())
        .filter(|path| {
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                if name.starts_with(&prefix) && name.ends_with(".sh") {
                    // Global: no imprint — exactly one part between colophon and .sh
                    let middle = &name[prefix.len()..name.len() - 3]; // strip ".sh"
                    !middle.contains('.')
                } else {
                    false
                }
            } else {
                false
            }
        })
        .collect();

    match matches.len() {
        0 => Err(format!(
            "rbtdri: no global tabtarget for colophon '{}'",
            colophon
        )),
        1 => Ok(matches.into_iter().next().unwrap()),
        n => Err(format!(
            "rbtdri: {} global tabtargets match colophon '{}' — expected exactly one",
            n, colophon
        )),
    }
}

// ── Tabtarget invocation with BURV isolation ─────────────────

static RBTDRI_BASH_PROGRAM: OnceLock<String> = OnceLock::new();

/// The bash program theurge launches scripts with, resolved once per process.
///
/// On Cygwin a bare `"bash"` from a Windows-native binary resolves through
/// `CreateProcess` to System32's WSL launcher, never Cygwin's bash — so we
/// nativize the canonical Cygwin bash (`/bin/bash`) via RBTDRX's cygpath. That
/// keeps cygpath inside theurge's existing Rust dependency rather than kit bash,
/// and cygpath itself resolves correctly from a native binary (no System32 twin,
/// unlike bash). Off Cygwin — and as a fallback if cygpath fails — it is "bash".
pub fn rbtdri_bash_program() -> &'static str {
    RBTDRI_BASH_PROGRAM
        .get_or_init(|| {
            if rbtdrx_is_cygwin() {
                match rbtdrx_posix_to_native(RBTDRI_CYGWIN_BASH_POSIX) {
                    Ok(p) => p.to_string_lossy().into_owned(),
                    Err(_) => "bash".to_string(),
                }
            } else {
                "bash".to_string()
            }
        })
        .as_str()
}

/// Build a `Command` that launches a tabtarget — a bash `.sh` — portably.
///
/// A Windows-native theurge (`x86_64-pc-windows-gnu`) cannot `CreateProcess` a
/// `.sh` directly: Rust's `Command` on Windows launches only `.exe`. So we run
/// the script through bash — via `rbtdri_bash_program()` so the right bash is
/// chosen on Cygwin — with the script path rendered to POSIX form (RBTDRX). On
/// Linux/macOS that conversion is identity and the bash program is just "bash",
/// so the call site is unconditional. Callers chain `.args(...)`,
/// `.current_dir(...)`, and `.env(...)` as on any `Command::new` result.
///
/// The credless guard, the tariff tally, AND the census used-set recording all
/// land here — the one constructor every tabtarget launch goes through,
/// including the direct-Command case helpers that bypass `rbtdri_invoke*`. A
/// reveille-tier fixture cannot spawn an unguarded tabtarget by construction,
/// no tabtarget launch escapes the invocation count, and every launch counts
/// toward the negative census direction. Non-tabtarget subprocesses
/// (docker/curl/git in the verification helpers, the inline `bash -c` in
/// rbtdrf) are deliberately NOT built here and so are deliberately NOT tallied
/// nor census-recorded — these facilities count tabtarget invocations, not
/// every child process.
pub fn rbtdri_tabtarget_command(tabtarget: &Path) -> Command {
    zrbtdri_tariff_bump();
    zrbtdri_census_record(tabtarget);
    let mut cmd = Command::new(rbtdri_bash_program());
    cmd.arg(rbtdrx_native_to_posix(tabtarget));
    if rbtdri_credless_armed() {
        cmd.env(
            RBTDRI_BURE_TWEAK_NAME_KEY,
            crate::rbtdgc_consts::RBTDGC_TWEAK_CREDLESS_GUARD,
        );
    }
    cmd
}

/// Internal: execute a resolved tabtarget with BURV isolation and optional extra env vars.
///
/// Honors the context's one-shot `chain_next` flag (see
/// `rbtdri_Context::chain_next_invoke`): when set, this invoke reuses the
/// immediately-prior invoke's BURV root instead of minting a fresh one — so
/// `bud_dispatch` promotes that invoke's `current/` into this invoke's
/// `previous/`. The flag is consumed and cleared here.
///
/// Census positive check lands here — the one implementation every
/// `rbtdri_invoke*` primitive funnels through, the only launch path that can
/// refuse. Used-set recording does NOT live here: it rides
/// `rbtdri_tabtarget_command` (reached below on the allowed path), the
/// universal chokepoint that bypass launches also pass through.
fn rbtdri_invoke_impl(
    ctx: &mut rbtdri_Context,
    colophon: &str,
    tabtarget: &Path,
    args: &[&str],
    extra_env: &[(&str, &str)],
) -> Result<rbtdri_InvokeResult, String> {
    if let Some(declared) = rbtdri_census_declared() {
        let permitted = rbtdri_census_permitted();
        if !declared.iter().any(|d| *d == colophon) && !permitted.iter().any(|p| *p == colophon) {
            return Err(format!(
                "rbtdri: fixture '{}' invoked colophon '{}' which is not declared in its \
                 required-colophons census — add it to rbtdrm_required_colophons('{}') or \
                 rbtdrm_permitted_colophons('{}'), or invoke a declared colophon instead",
                ctx.fixture, colophon, ctx.fixture, ctx.fixture
            ));
        }
    }

    let invoke_num = if std::mem::take(&mut ctx.chain_next) {
        // Chain off the immediately-prior invoke: reuse its root (do NOT mint a
        // fresh one or bump the counter), so bud's promotion carries that
        // invoke's current/ into this one's previous/. Depth-1 by construction.
        ctx.invoke_count.checked_sub(1).ok_or_else(|| {
            "rbtdri: chain_next_invoke set with no prior invoke to chain from".to_string()
        })?
    } else {
        let n = ctx.invoke_count;
        ctx.invoke_count += 1;
        n
    };

    let dir_name = rbtdri_invoke_dir_name(invoke_num);
    let burv_output = ctx.burv_output_root.join(&dir_name);
    let burv_temp = ctx.burv_temp_root.join(&dir_name);

    std::fs::create_dir_all(&burv_output)
        .map_err(|e| format!("rbtdri: failed to create BURV output dir: {}", e))?;
    std::fs::create_dir_all(&burv_temp)
        .map_err(|e| format!("rbtdri: failed to create BURV temp dir: {}", e))?;

    // Tweak-slot conflict gate (BUS0): under the credless guard the single
    // tweak slot belongs to the guard — a reveille-tier case supplying its own
    // tweak has self-identified as not belonging in reveille. Fail loud rather
    // than letting the case silently overwrite the guard.
    if rbtdri_credless_armed()
        && extra_env.iter().any(|(k, _)| *k == RBTDRI_BURE_TWEAK_NAME_KEY)
    {
        return Err(format!(
            "rbtdri: fixture '{}' is reveille-tier credless — its tweak slot belongs to \
             the credless guard, so a case may not set {} (a case needing a seam \
             does not belong in reveille)",
            ctx.fixture, RBTDRI_BURE_TWEAK_NAME_KEY
        ));
    }

    let mut cmd = rbtdri_tabtarget_command(tabtarget);
    cmd.args(args)
        .current_dir(&ctx.project_root)
        .env("BURV_OUTPUT_ROOT_DIR", rbtdrx_native_to_posix(&burv_output))
        .env("BURV_TEMP_ROOT_DIR", rbtdrx_native_to_posix(&burv_temp));

    for (key, value) in extra_env {
        cmd.env(key, value);
    }

    let output = cmd
        .output()
        .map_err(|e| format!("rbtdri: failed to execute '{}': {}", tabtarget.display(), e))?;

    Ok(rbtdri_InvokeResult {
        stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        exit_code: output.status.code().unwrap_or(-1),
        burv_output,
    })
}

/// Invoke a fixture-imprinted tabtarget (colophon + ctx.fixture). For crucible
/// fixtures the fixture name is also a nameplate moniker, which is the
/// imprint shape this resolves against.
pub fn rbtdri_invoke(
    ctx: &mut rbtdri_Context,
    colophon: &str,
    args: &[&str],
) -> Result<rbtdri_InvokeResult, String> {
    let tabtarget = rbtdri_find_tabtarget(&ctx.project_root, colophon, &ctx.fixture)?;
    rbtdri_invoke_impl(ctx, colophon, &tabtarget, args, &[])
}

/// Invoke a fixture-imprinted tabtarget (like `rbtdri_invoke`) with extra
/// environment variables threaded into the child process — e.g. BURD_NO_LOG
/// to keep BUK dispatch from folding the tabtarget's stderr into stdout.
pub fn rbtdri_invoke_env(
    ctx: &mut rbtdri_Context,
    colophon: &str,
    args: &[&str],
    extra_env: &[(&str, &str)],
) -> Result<rbtdri_InvokeResult, String> {
    let tabtarget = rbtdri_find_tabtarget(&ctx.project_root, colophon, &ctx.fixture)?;
    rbtdri_invoke_impl(ctx, colophon, &tabtarget, args, extra_env)
}

/// Invoke a global tabtarget (no imprint) with optional extra environment variables.
pub fn rbtdri_invoke_global(
    ctx: &mut rbtdri_Context,
    colophon: &str,
    args: &[&str],
    extra_env: &[(&str, &str)],
) -> Result<rbtdri_InvokeResult, String> {
    let tabtarget = rbtdri_find_tabtarget_global(&ctx.project_root, colophon)?;
    rbtdri_invoke_impl(ctx, colophon, &tabtarget, args, extra_env)
}

/// Invoke a tabtarget with an explicit imprint (overrides ctx.fixture for discovery).
pub fn rbtdri_invoke_imprint(
    ctx: &mut rbtdri_Context,
    colophon: &str,
    imprint: &str,
    args: &[&str],
) -> Result<rbtdri_InvokeResult, String> {
    let tabtarget = rbtdri_find_tabtarget(&ctx.project_root, colophon, imprint)?;
    rbtdri_invoke_impl(ctx, colophon, &tabtarget, args, &[])
}

/// Invoke a tabtarget with an explicit imprint and extra environment variables
/// — the imprint-discovery sibling of `rbtdri_invoke_env`.
pub fn rbtdri_invoke_imprint_env(
    ctx: &mut rbtdri_Context,
    colophon: &str,
    imprint: &str,
    args: &[&str],
    extra_env: &[(&str, &str)],
) -> Result<rbtdri_InvokeResult, String> {
    let tabtarget = rbtdri_find_tabtarget(&ctx.project_root, colophon, imprint)?;
    rbtdri_invoke_impl(ctx, colophon, &tabtarget, args, extra_env)
}

// ── BURV fact file reading ───────────────────────────────────

/// Read a fact file from a tabtarget's BURV output directory.
/// Fact files are single-line values written by tabtargets to BURD_OUTPUT_DIR,
/// which is BURV_OUTPUT_ROOT_DIR/current per BUK dispatch convention.
pub fn rbtdri_read_burv_fact(
    result: &rbtdri_InvokeResult,
    fact_name: &str,
) -> Result<String, String> {
    let path = result.burv_output.join(RBTDRI_BURV_OUTPUT_SUBDIR).join(fact_name);
    let content = std::fs::read_to_string(&path)
        .map_err(|e| format!("rbtdri: cannot read fact '{}' from {}: {}", fact_name, path.display(), e))?;
    let trimmed = content.trim().to_string();
    if trimmed.is_empty() {
        return Err(format!("rbtdri: fact '{}' is empty in {}", fact_name, path.display()));
    }
    Ok(trimmed)
}

/// Enumerate multi-fact files in a tabtarget's BURV output directory.
/// Multi-facts follow the convention `<root>.<ext>` written by buf_write_fact_multi;
/// returns the sorted list of roots whose files have the requested extension.
/// Returns an empty Vec if no matching files exist.
pub fn rbtdri_read_burv_facts_multi(
    result: &rbtdri_InvokeResult,
    extension: &str,
) -> Result<Vec<String>, String> {
    let dir = result.burv_output.join(RBTDRI_BURV_OUTPUT_SUBDIR);
    let entries = std::fs::read_dir(&dir).map_err(|e| {
        format!(
            "rbtdri: cannot enumerate fact dir {}: {}",
            dir.display(),
            e
        )
    })?;
    let suffix = format!(".{}", extension);
    let mut roots: Vec<String> = entries
        .filter_map(|entry| entry.ok())
        .filter_map(|entry| entry.file_name().into_string().ok())
        .filter_map(|name| name.strip_suffix(&suffix).map(str::to_string))
        .collect();
    roots.sort();
    Ok(roots)
}

// ── Ordain fact-file names ───────────────────────────────────

/// BURV fact file names written by ordain — single definition, matching
/// rbgc_constants.sh values. Read by the ordain-capture helpers below.
pub(crate) const RBTDRI_FACT_HALLMARK: &str = "rbf_fact_hallmark";
pub(crate) const RBTDRI_FACT_GAR_ROOT: &str = "rbf_fact_gar_root";
pub(crate) const RBTDRI_FACT_ARK_STEM: &str = "rbf_fact_ark_stem";

// ── Ordain capture + invoke-or-fail helpers ──────────────────

/// Invoke a tabtarget via `rbtdri_invoke_global` and write its stdout/stderr to
/// `dir` under the `label` prefix. Private spine of `rbtdri_invoke_or_fail`.
fn rbtdri_invoke_logged(
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

/// Invoke a tabtarget via `rbtdri_invoke_logged` and convert non-success outcomes
/// into Fail verdicts with consistent operation-prefixed messages. `target` is
/// the per-call distinguishing string (vessel sigil, vessel dir, nameplate)
/// included in the error prefix; pass `""` for operations without a target.
pub(crate) fn rbtdri_invoke_or_fail(
    ctx: &mut rbtdri_Context,
    operation: &str,
    target: &str,
    colophon: &str,
    args: &[&str],
    extra_env: &[(&str, &str)],
    dir: &Path,
    label: &str,
) -> Result<rbtdri_InvokeResult, rbtdre_Verdict> {
    let prefix = if target.is_empty() {
        operation.to_string()
    } else {
        format!("{} {}", operation, target)
    };
    let result = rbtdri_invoke_logged(ctx, colophon, args, extra_env, dir, label)
        .map_err(|e| rbtdre_Verdict::Fail(format!("{} invocation: {}", prefix, e)))?;
    if result.exit_code != 0 {
        return Err(rbtdre_Verdict::Fail(format!(
            "{} exit {}\n{}",
            prefix, result.exit_code, result.stderr
        )));
    }
    Ok(result)
}

/// Run an ordain on `vessel_dir` and return the captured hallmark string.
/// Writes invocation logs to `dir` under the `label` prefix; returns Fail
/// verdict-bearing Err so callers can early-return cleanly.
pub(crate) fn rbtdri_ordain_capture(
    ctx: &mut rbtdri_Context,
    dir: &Path,
    vessel_dir: &str,
    extra_env: &[(&str, &str)],
    label: &str,
) -> Result<String, rbtdre_Verdict> {
    let result = rbtdri_invoke_or_fail(
        ctx,
        RBTDGC_VERB_ORDAIN,
        vessel_dir,
        RBTDGC_ORDAIN_HALLMARK,
        &[vessel_dir],
        extra_env,
        dir,
        label,
    )?;
    let hallmark = rbtdri_read_burv_fact(&result, RBTDRI_FACT_HALLMARK).map_err(|e| {
        rbtdre_Verdict::Fail(format!(
            "read hallmark fact after {} {}: {}",
            RBTDGC_VERB_ORDAIN, vessel_dir, e
        ))
    })?;
    let _ = std::fs::write(dir.join(format!("{}-hallmark.txt", label)), &hallmark);
    Ok(hallmark)
}

/// Same as `rbtdri_ordain_capture` but also returns gar_root and ark_stem facts
/// needed by verification tails to construct local docker refs after wrest.
pub(crate) fn rbtdri_ordain_capture_full(
    ctx: &mut rbtdri_Context,
    dir: &Path,
    vessel_dir: &str,
    extra_env: &[(&str, &str)],
    label: &str,
) -> Result<(String, String, String), rbtdre_Verdict> {
    let result = rbtdri_invoke_or_fail(
        ctx,
        RBTDGC_VERB_ORDAIN,
        vessel_dir,
        RBTDGC_ORDAIN_HALLMARK,
        &[vessel_dir],
        extra_env,
        dir,
        label,
    )?;
    let hallmark = rbtdri_read_burv_fact(&result, RBTDRI_FACT_HALLMARK).map_err(|e| {
        rbtdre_Verdict::Fail(format!(
            "read hallmark fact after {} {}: {}",
            RBTDGC_VERB_ORDAIN, vessel_dir, e
        ))
    })?;
    let gar_root = rbtdri_read_burv_fact(&result, RBTDRI_FACT_GAR_ROOT).map_err(|e| {
        rbtdre_Verdict::Fail(format!(
            "read gar_root fact after {} {}: {}",
            RBTDGC_VERB_ORDAIN, vessel_dir, e
        ))
    })?;
    let ark_stem = rbtdri_read_burv_fact(&result, RBTDRI_FACT_ARK_STEM).map_err(|e| {
        rbtdre_Verdict::Fail(format!(
            "read ark_stem fact after {} {}: {}",
            RBTDGC_VERB_ORDAIN, vessel_dir, e
        ))
    })?;
    let _ = std::fs::write(dir.join(format!("{}-hallmark.txt", label)), &hallmark);
    Ok((hallmark, gar_root, ark_stem))
}

// ── GAR image-reference builders ─────────────────────────────
//
// Two deliberately-separate GAR ref shapes — never fold into one signature.
// Categorical roots at the canonical hallmark home (the GAR category, with the
// hallmark naming both the subtree and the tag); fact-rooted roots at an
// ordain-captured per-vessel build namespace (gar_root + ark_stem, the hallmark
// only the tag). The same hallmark can carry both forms in one scope.

/// Category-rooted GAR ref: `{category}/{hallmark}/{basename}:{hallmark}` — the
/// canonical hallmark home, where the hallmark names both subtree and tag.
pub(crate) fn rbtdri_gar_ref_categorical(category: &str, basename: &str, hallmark: &str) -> String {
    format!("{}/{}/{}:{}", category, hallmark, basename, hallmark)
}

/// Fact-rooted GAR ref: `{gar_root}/{ark_stem}/{basename}:{hallmark}` — the
/// per-vessel build namespace named by ordain-captured facts.
pub(crate) fn rbtdri_gar_ref_fact(
    gar_root: &str,
    ark_stem: &str,
    basename: &str,
    hallmark: &str,
) -> String {
    format!("{}/{}/{}:{}", gar_root, ark_stem, basename, hallmark)
}

// ── Ifrit verdict parsing ────────────────────────────────────

/// Ifrit verdict wire protocol: ifrit prints exactly one line matching
/// `IFRIT_VERDICT: PASS` or `IFRIT_VERDICT: FAIL <detail>` to stdout.
/// Missing verdict line is always a failure — no silent pass-through.
pub fn rbtdri_parse_ifrit_verdict(stdout: &str, exit_code: i32) -> rbtdre_Verdict {
    for line in stdout.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("IFRIT_VERDICT:") {
            let rest = rest.trim();
            if rest.starts_with("PASS") {
                return rbtdre_Verdict::Pass;
            }
            if let Some(detail) = rest.strip_prefix("FAIL") {
                let detail = detail.trim();
                if detail.is_empty() {
                    return rbtdre_Verdict::Fail("ifrit reported failure".to_string());
                }
                return rbtdre_Verdict::Fail(detail.to_string());
            }
        }
    }

    if exit_code == 0 {
        rbtdre_Verdict::Fail("ifrit exited 0 but no verdict line found".to_string())
    } else {
        rbtdre_Verdict::Fail(format!("ifrit exited {} with no verdict line", exit_code))
    }
}
