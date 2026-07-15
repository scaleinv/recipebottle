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
// RBTDRC — crucible test cases for theurge end-to-end testing
//
// Cases execute inside a charged crucible (sentry + pentacle + bottle).
// Thread-local context bridges the static case function signature with
// the mutable invocation context needed for tabtarget calls.

// RCG output discipline: all emission via rbtdrg_*! — no direct println!/eprintln!

use std::cell::RefCell;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use crate::case;
use crate::rbtdra_almanac::rbtdra_lookup_fixture;
use crate::rbtdre_engine::{
    rbtdre_Tariff,
    rbtdre_Case, rbtdre_Disposition, rbtdre_Fixture, rbtdre_Verdict,
};
use crate::rbtdri_invocation::{
    rbtdri_Context, rbtdri_invoke, rbtdri_invoke_env, rbtdri_invoke_global,
    rbtdri_parse_ifrit_verdict,
};
use crate::rbtdgc_consts::{
    RBTDGC_CRUCIBLE_ACTIVE, RBTDGC_CRUCIBLE_BARK,
    RBTDGC_CRUCIBLE_CHARGE, RBTDGC_CRUCIBLE_FIAT, RBTDGC_CRUCIBLE_QUENCH, RBTDGC_CRUCIBLE_WRIT,
};

// ── Thread-local invocation context ──────────────────────────

/// Ifrit binary name inside the bottle container.
const RBTDRC_IFRIT_BINARY: &str = "rbid";

/// Test connectivity target — ICANN-owned, stable single /20 CIDR (192.0.32.0/20)
const RBTDRC_CONNECTIVITY_DOMAIN: &str = "www.internic.net";

thread_local! {
    static RBTDRC_CTX: RefCell<Option<rbtdri_Context>> = RefCell::new(None);
}

/// Store invocation context for case functions. Called before run_sections.
///
/// Also arms the reveille-tier credless guard from the registered fixture's
/// `credless` field AND the colophon census from the fixture's manifest entry
/// — installing a context IS entering a fixture's run, so neither guard can
/// be forgotten at a runner call site. An unregistered fixture name arms no
/// credless guard (the runner has already fataled on lookup failure before
/// reaching here on every real path); an unmanifested fixture name arms no
/// census (None disables both census directions).
pub fn rbtdrc_set_context(ctx: rbtdri_Context) {
    let credless = rbtdra_lookup_fixture(ctx.fixture())
        .map(|f| f.credless)
        .unwrap_or(false);
    crate::rbtdri_invocation::rbtdri_arm_credless(credless);
    crate::rbtdri_invocation::rbtdri_census_arm(
        crate::rbtdrm_manifest::rbtdrm_required_colophons(ctx.fixture()),
        crate::rbtdrm_manifest::rbtdrm_permitted_colophons(ctx.fixture()),
    );
    RBTDRC_CTX.with(|c| *c.borrow_mut() = Some(ctx));
}

/// Retrieve invocation context after cases complete. Called for quench.
/// Disarms the credless guard and the colophon census — the fixture's run is
/// over.
pub fn rbtdrc_take_context() -> rbtdri_Context {
    crate::rbtdri_invocation::rbtdri_arm_credless(false);
    crate::rbtdri_invocation::rbtdri_census_arm(None, &[]);
    RBTDRC_CTX.with(|c| {
        c.borrow_mut()
            .take()
            .expect("rbtdrc: no context — was rbtdrc_set_context called?")
    })
}

pub(crate) fn rbtdrc_with_ctx<F>(f: F) -> rbtdre_Verdict
where
    F: FnOnce(&mut rbtdri_Context) -> rbtdre_Verdict,
{
    RBTDRC_CTX.with(|c| {
        let mut opt = c.borrow_mut();
        let ctx = opt
            .as_mut()
            .expect("rbtdrc: no invocation context for case execution");
        f(ctx)
    })
}

// ── Crucible lifecycle hooks (setup/teardown) ────────────────

/// Setup hook for crucible fixtures: charge → CrucibleActive assertion.
/// Reads ctx from thread-local. Returns Err on any step failure; engine
/// surfaces this as a fixture failure and runs teardown anyway.
///
/// Service-readiness waits are folded into the charge tabtarget itself,
/// driven by the per-nameplate `RBRN_BOTTLE_READINESS_DELAY_SEC` fact.
pub fn rbtdrc_charge_crucible() -> Result<(), String> {
    RBTDRC_CTX.with(|c| {
        let mut opt = c.borrow_mut();
        let ctx = opt
            .as_mut()
            .ok_or_else(|| "rbtdrc: no invocation context for charge".to_string())?;
        zrbtdrc_charge_impl(ctx)
    })
}

/// Teardown hook for crucible fixtures: quench → inverse CrucibleActive
/// assertion. Reads ctx from thread-local. Best-effort — surfaces failures as
/// stderr warnings rather than errors; teardown always completes.
pub fn rbtdrc_quench_crucible() {
    RBTDRC_CTX.with(|c| {
        let mut opt = c.borrow_mut();
        if let Some(ctx) = opt.as_mut() {
            zrbtdrc_quench_impl(ctx);
        } else {
            crate::rbtdrg_error_now!("rbtdrc: no invocation context for quench — skipped");
        }
    });
}

fn zrbtdrc_charge_impl(ctx: &mut rbtdri_Context) -> Result<(), String> {
    let fixture = ctx.fixture().to_string();
    crate::rbtdrg_info_now!("Charging crucible for nameplate '{}'...", fixture);
    match rbtdri_invoke(ctx, RBTDGC_CRUCIBLE_CHARGE, &[]) {
        Ok(r) if r.exit_code == 0 => {
            crate::rbtdrg_info_now!("Crucible charged");
        }
        Ok(r) => {
            return Err(format!("Charge failed (exit {})\n{}", r.exit_code, r.stderr));
        }
        Err(e) => {
            return Err(format!("Charge invocation failed: {}", e));
        }
    }

    crate::rbtdrg_info_now!("Verifying crucible is active after charge...");
    match rbtdri_invoke_global(ctx, RBTDGC_CRUCIBLE_ACTIVE, &[&fixture], &[]) {
        Ok(r) if r.exit_code == 0 => {
            crate::rbtdrg_info_now!("Crucible active confirmed");
        }
        Ok(r) => {
            return Err(format!(
                "Lifecycle assertion failed: crucible not active after charge (exit {})\n{}",
                r.exit_code, r.stderr
            ));
        }
        Err(e) => {
            return Err(format!(
                "CrucibleActive invocation failed after charge: {}",
                e
            ));
        }
    }

    Ok(())
}

fn zrbtdrc_quench_impl(ctx: &mut rbtdri_Context) {
    let fixture = ctx.fixture().to_string();
    crate::rbtdrg_info_now!("Quenching crucible...");
    match rbtdri_invoke(ctx, RBTDGC_CRUCIBLE_QUENCH, &[]) {
        Ok(r) if r.exit_code == 0 => crate::rbtdrg_info_now!("Crucible quenched"),
        Ok(r) => crate::rbtdrg_error_now!("quench exited {}", r.exit_code),
        Err(e) => crate::rbtdrg_error_now!("quench invocation failed: {}", e),
    }

    crate::rbtdrg_info_now!("Verifying crucible is inactive after quench...");
    match rbtdri_invoke_global(ctx, RBTDGC_CRUCIBLE_ACTIVE, &[&fixture], &[]) {
        Ok(r) if r.exit_code != 0 => {
            crate::rbtdrg_info_now!("Crucible inactive confirmed");
        }
        Ok(r) => {
            crate::rbtdrg_error_now!(
                "crucible still active after quench (exit {})",
                r.exit_code
            );
        }
        Err(e) => {
            crate::rbtdrg_error_now!(
                "CrucibleActive invocation failed after quench: {}",
                e
            );
        }
    }
}

// ── Helpers ──────────────────────────────────────────────────

/// Invoke ifrit inside the bottle via bark, saving stdout/stderr to case dir.
fn rbtdrc_invoke_ifrit(
    ctx: &mut rbtdri_Context,
    attack: &str,
    dir: &Path,
) -> rbtdre_Verdict {
    let result = match rbtdri_invoke(ctx, RBTDGC_CRUCIBLE_BARK, &[RBTDRC_IFRIT_BINARY, attack]) {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("bark invocation error: {}", e)),
    };
    let _ = std::fs::write(dir.join("bark-stdout.txt"), &result.stdout);
    let _ = std::fs::write(dir.join("bark-stderr.txt"), &result.stderr);
    rbtdri_parse_ifrit_verdict(&result.stdout, result.exit_code)
}

/// Invoke ifrit inside the bottle via bark with extra arguments.
fn rbtdrc_invoke_ifrit_with_args(
    ctx: &mut rbtdri_Context,
    attack: &str,
    extra_args: &[&str],
    dir: &Path,
) -> rbtdre_Verdict {
    let mut bark_args = vec![RBTDRC_IFRIT_BINARY, attack];
    bark_args.extend_from_slice(extra_args);
    let result = match rbtdri_invoke(ctx, RBTDGC_CRUCIBLE_BARK, &bark_args) {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("bark invocation error: {}", e)),
    };
    let _ = std::fs::write(dir.join("bark-stdout.txt"), &result.stdout);
    let _ = std::fs::write(dir.join("bark-stderr.txt"), &result.stderr);
    rbtdri_parse_ifrit_verdict(&result.stdout, result.exit_code)
}

/// Execute a command in the sentry via writ, returning captured stdout.
///
/// Runs under BURD_NO_LOG so the BUK dispatch does not fold the tabtarget's
/// stderr into stdout (nor emit log-path headers). The captured stdout is then
/// exactly the sentry command's output — rbob_writ's "Writ to sentry" status
/// line (buc_step, stderr) stays out of it, so a value-read needs no header or
/// ANSI filtering and is independent of terminal color (NO_COLOR, dumb TERM,
/// plain ssh pipe). theurge keeps its own per-invocation stdout/stderr capture,
/// so dropping the redundant logs-buk transcript for these probe writs costs
/// no diagnostics.
fn rbtdrc_writ(ctx: &mut rbtdri_Context, args: &[&str]) -> Result<String, String> {
    let result = rbtdri_invoke_env(ctx, RBTDGC_CRUCIBLE_WRIT, args, &[("BURD_NO_LOG", "1")])?;
    if result.exit_code != 0 {
        return Err(format!(
            "writ exit {}\nstdout: {}\nstderr: {}",
            result.exit_code, result.stdout, result.stderr
        ));
    }
    Ok(result.stdout)
}

/// Execute a command in the pentacle via fiat, returning the invocation result.
fn rbtdrc_fiat(ctx: &mut rbtdri_Context, args: &[&str]) -> Result<String, String> {
    let result = rbtdri_invoke(ctx, RBTDGC_CRUCIBLE_FIAT, args)?;
    if result.exit_code != 0 {
        return Err(format!(
            "fiat exit {}\nstdout: {}\nstderr: {}",
            result.exit_code, result.stdout, result.stderr
        ));
    }
    Ok(result.stdout)
}

/// Discover the sentry's enclave IP by reading /etc/resolv.conf from the pentacle via fiat.
/// The pentacle uses the sentry as its DNS server, so resolv.conf nameserver = sentry enclave IP.
/// (Sentry's own resolv.conf points to upstream DNS like 8.8.8.8 — wrong for enclave ops.)
fn rbtdrc_discover_sentry_ip(ctx: &mut rbtdri_Context) -> Result<String, String> {
    let output = rbtdrc_fiat(ctx, &["cat", "/etc/resolv.conf"])?;
    for line in output.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("nameserver") {
            let ip = rest.trim();
            if !ip.is_empty() && rbtdrc_looks_like_ip(ip) {
                return Ok(ip.to_string());
            }
        }
    }
    Err(format!(
        "no nameserver found in pentacle /etc/resolv.conf:\n{}",
        output
    ))
}

/// Resolve a hostname via writ (running dig +short on the sentry).
/// Returns the first line that looks like an IP address (filters BUK log headers).
fn rbtdrc_resolve_via_writ(ctx: &mut rbtdri_Context, hostname: &str) -> Result<String, String> {
    let output = rbtdrc_writ(ctx, &["dig", "+short", hostname])?;
    let ip = output
        .lines()
        .find(|line| {
            let t = line.trim();
            !t.is_empty() && rbtdrc_looks_like_ip(t)
        })
        .map(|line| line.trim().to_string())
        .ok_or_else(|| format!("dig +short {} returned no IP:\n{}", hostname, output))?;
    Ok(ip)
}

/// Quick check: does this string look like an IPv4 address (digits and dots only)?
/// Not a full validator — just enough to reject BUK log headers and DNS comments.
fn rbtdrc_looks_like_ip(s: &str) -> bool {
    !s.is_empty() && s.chars().all(|c| c.is_ascii_digit() || c == '.')
}

/// Extract iptables rule lines from writ output, filtering BUK log headers.
/// Rules start with -P (policy), -N (new chain), or -A (append).
fn rbtdrc_extract_iptables_rules(output: &str) -> String {
    output
        .lines()
        .filter(|l| {
            let t = l.trim();
            t.starts_with("-P ") || t.starts_with("-N ") || t.starts_with("-A ")
        })
        .collect::<Vec<_>>()
        .join("\n")
}

/// Read a named environment variable from sentry's process environment via writ.
/// writ runs under BURD_NO_LOG, so its stdout is the clean command output —
/// the first non-empty line is the value, with no header/ANSI stripping needed.
fn rbtdrc_read_sentry_env(ctx: &mut rbtdri_Context, var: &str) -> Result<String, String> {
    let output = rbtdrc_writ(ctx, &["printenv", var])?;
    output
        .lines()
        .map(|l| l.trim())
        .find(|l| !l.is_empty())
        .map(|l| l.to_string())
        .ok_or_else(|| format!("printenv {} returned no value", var))
}

// ── Basic infra cases (fiat) ──────────────────────────────────

fn rbtdrc_pentacle_dnsmasq_responds(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let sentry_ip = match rbtdrc_discover_sentry_ip(ctx) {
            Ok(ip) => ip,
            Err(e) => return rbtdre_Verdict::Fail(format!("sentry IP discovery: {}", e)),
        };
        let _ = std::fs::write(dir.join("sentry-ip.txt"), &sentry_ip);

        let output = match rbtdrc_fiat(
            ctx,
            &["dig", "+short", &format!("@{}", sentry_ip), RBTDRC_CONNECTIVITY_DOMAIN],
        ) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("fiat dig error: {}", e)),
        };
        let _ = std::fs::write(dir.join("fiat-stdout.txt"), &output);

        if output.trim().is_empty() {
            return rbtdre_Verdict::Fail(format!(
                "dnsmasq on sentry {} returned empty response for {}",
                sentry_ip, RBTDRC_CONNECTIVITY_DOMAIN
            ));
        }
        rbtdre_Verdict::Pass
    })
}

fn rbtdrc_pentacle_ping_sentry(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let sentry_ip = match rbtdrc_discover_sentry_ip(ctx) {
            Ok(ip) => ip,
            Err(e) => return rbtdre_Verdict::Fail(format!("sentry IP discovery: {}", e)),
        };
        let _ = std::fs::write(dir.join("sentry-ip.txt"), &sentry_ip);

        let output = match rbtdrc_fiat(ctx, &["ping", &sentry_ip, "-c", "2"]) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("fiat ping error: {}", e)),
        };
        let _ = std::fs::write(dir.join("fiat-stdout.txt"), &output);

        rbtdre_Verdict::Pass
    })
}

// ── Ifrit attack cases (bark-only, inside observation) ───────

fn rbtdrc_ifrit_dns_allowed(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "dns-allowed-example", dir))
}

fn rbtdrc_ifrit_dns_allowed_example_org(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "dns-allowed-example-org", dir))
}

fn rbtdrc_ifrit_dns_blocked(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "dns-blocked-google", dir))
}

fn rbtdrc_ifrit_apt_blocked(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "apt-get-blocked", dir))
}

fn rbtdrc_ifrit_dns_nonexistent(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "dns-nonexistent", dir))
}

fn rbtdrc_ifrit_dns_tcp(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "dns-tcp", dir))
}

fn rbtdrc_ifrit_dns_udp(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "dns-udp", dir))
}

fn rbtdrc_ifrit_dns_block_direct(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "dns-block-direct", dir))
}

fn rbtdrc_ifrit_dns_block_altport(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "dns-block-altport", dir))
}

fn rbtdrc_ifrit_dns_block_cloudflare(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "dns-block-cloudflare", dir))
}

fn rbtdrc_ifrit_dns_block_quad9(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "dns-block-quad9", dir))
}

fn rbtdrc_ifrit_dns_block_zonetransfer(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "dns-block-zonetransfer", dir))
}

fn rbtdrc_ifrit_dns_block_ipv6(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "dns-block-ipv6", dir))
}

fn rbtdrc_ifrit_dns_block_multicast(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "dns-block-multicast", dir))
}

fn rbtdrc_ifrit_dns_block_spoofing(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "dns-block-spoofing", dir))
}

fn rbtdrc_ifrit_dns_block_tunneling(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "dns-block-tunneling", dir))
}

// ── Observation cases (writ + bark, inside/outside) ──────────

fn rbtdrc_sentry_iptables_loaded(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let output = match rbtdrc_writ(ctx, &["iptables", "-S"]) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("writ error: {}", e)),
        };
        let _ = std::fs::write(dir.join("iptables-rules.txt"), &output);

        if output.trim().is_empty() {
            return rbtdre_Verdict::Fail("iptables -S returned empty output".to_string());
        }
        // Expect at least one policy line (-P) and one append rule (-A)
        if !output.contains("-P") || !output.contains("-A") {
            return rbtdre_Verdict::Fail(format!(
                "iptables rules incomplete (missing -P or -A):\n{}",
                output
            ));
        }
        rbtdre_Verdict::Pass
    })
}

// Structural-presence backstops for the load-bearing iptables clauses and
// kernel sysctl set by rbjs_sentry.sh. Each case is a fast read-and-check
// against sentry's runtime state — fail loudly if a future change strips a
// defensive clause the architecture depends on.

fn rbtdrc_sentry_config_rp_filter(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let entry_mode = match rbtdrc_read_sentry_env(ctx, "RBRN_ENTRY_MODE") {
            Ok(m) => m,
            Err(e) => return rbtdre_Verdict::Fail(format!("read RBRN_ENTRY_MODE: {}", e)),
        };
        let output = match rbtdrc_writ(ctx, &["cat", "/proc/sys/net/ipv4/conf/all/rp_filter"]) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("writ error: {}", e)),
        };
        let _ = std::fs::write(dir.join("rp_filter.txt"), &output);

        let value = output
            .lines()
            .map(|l| l.trim())
            .find(|l| !l.is_empty())
            .map(|l| l.to_string())
            .unwrap_or_default();

        let expected = match entry_mode.as_str() {
            "rbnne_enabled" => "2",
            "rbnne_disabled" => "1",
            other => {
                return rbtdre_Verdict::Fail(format!("unexpected RBRN_ENTRY_MODE '{}'", other));
            }
        };

        if value != expected {
            return rbtdre_Verdict::Fail(format!(
                "rp_filter = {} (expected {} for entry-mode {})",
                value, expected, entry_mode
            ));
        }
        rbtdre_Verdict::Pass
    })
}

fn rbtdrc_sentry_config_prerouting_dnat(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let entry_mode = match rbtdrc_read_sentry_env(ctx, "RBRN_ENTRY_MODE") {
            Ok(m) => m,
            Err(e) => return rbtdre_Verdict::Fail(format!("read RBRN_ENTRY_MODE: {}", e)),
        };
        if entry_mode != "rbnne_enabled" {
            return rbtdre_Verdict::Skip(format!("entry-mode={}", entry_mode));
        }
        let output = match rbtdrc_writ(ctx, &["iptables", "-t", "nat", "-S", "PREROUTING"]) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("writ error: {}", e)),
        };
        let _ = std::fs::write(dir.join("prerouting.txt"), &output);

        let append_rules: Vec<&str> = output
            .lines()
            .filter(|l| l.trim().starts_with("-A "))
            .collect();

        let return_positions: Vec<usize> = append_rules
            .iter()
            .enumerate()
            .filter(|(_, r)| r.contains("-j RETURN"))
            .map(|(i, _)| i)
            .collect();
        let dnat_positions: Vec<usize> = append_rules
            .iter()
            .enumerate()
            .filter(|(_, r)| r.contains("-j DNAT"))
            .map(|(i, _)| i)
            .collect();

        if return_positions.len() != 2 {
            return rbtdre_Verdict::Fail(format!(
                "PREROUTING RETURN rule count = {} (expected 2)",
                return_positions.len()
            ));
        }
        if dnat_positions.is_empty() {
            return rbtdre_Verdict::Fail("PREROUTING DNAT rule absent".to_string());
        }
        let max_return = *return_positions.iter().max().unwrap();
        let min_dnat = *dnat_positions.iter().min().unwrap();
        if max_return >= min_dnat {
            return rbtdre_Verdict::Fail(format!(
                "PREROUTING RETURN at position {} not before DNAT at position {}",
                max_return, min_dnat
            ));
        }
        rbtdre_Verdict::Pass
    })
}

fn rbtdrc_sentry_config_postrouting_masquerade(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let entry_mode = match rbtdrc_read_sentry_env(ctx, "RBRN_ENTRY_MODE") {
            Ok(m) => m,
            Err(e) => return rbtdre_Verdict::Fail(format!("read RBRN_ENTRY_MODE: {}", e)),
        };
        if entry_mode != "rbnne_enabled" {
            return rbtdre_Verdict::Skip(format!("entry-mode={}", entry_mode));
        }
        let output = match rbtdrc_writ(ctx, &["iptables", "-t", "nat", "-S", "POSTROUTING"]) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("writ error: {}", e)),
        };
        let _ = std::fs::write(dir.join("postrouting.txt"), &output);

        // Entry-port MASQUERADE has -p tcp and --dport; the egress MASQUERADE
        // (uplink path, set when uplink access-mode != disabled) has neither.
        let entry_masq = output
            .lines()
            .any(|l| l.contains("-j MASQUERADE") && l.contains("-p tcp") && l.contains("--dport"));

        if !entry_masq {
            return rbtdre_Verdict::Fail(
                "POSTROUTING entry-port MASQUERADE rule absent".to_string(),
            );
        }
        rbtdre_Verdict::Pass
    })
}

fn rbtdrc_sentry_config_forward_estab_related(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let output = match rbtdrc_writ(ctx, &["iptables", "-S", "FORWARD"]) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("writ error: {}", e)),
        };
        let _ = std::fs::write(dir.join("forward.txt"), &output);

        let append_rules: Vec<&str> = output
            .lines()
            .filter(|l| l.trim().starts_with("-A "))
            .collect();

        let estab_pos = append_rules
            .iter()
            .position(|r| r.contains("RELATED") && r.contains("ESTABLISHED") && r.contains("-j ACCEPT"));
        let jump_pos = append_rules
            .iter()
            .position(|r| r.contains("-j RBM-FORWARD"));

        let estab_pos = match estab_pos {
            Some(p) => p,
            None => {
                return rbtdre_Verdict::Fail(
                    "FORWARD ESTABLISHED,RELATED ACCEPT rule absent".to_string(),
                );
            }
        };
        let jump_pos = match jump_pos {
            Some(p) => p,
            None => {
                return rbtdre_Verdict::Fail("FORWARD -j RBM-FORWARD jump absent".to_string());
            }
        };

        if estab_pos >= jump_pos {
            return rbtdre_Verdict::Fail(format!(
                "FORWARD ESTABLISHED,RELATED at position {} not before RBM-FORWARD jump at position {}",
                estab_pos, jump_pos
            ));
        }
        rbtdre_Verdict::Pass
    })
}

fn rbtdrc_dns_blocked_with_observation(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        // Before: capture iptables state from sentry
        let before = match rbtdrc_writ(ctx, &["iptables", "-L", "-v", "-n", "-x"]) {
            Ok(o) => {
                let _ = std::fs::write(dir.join("iptables-before.txt"), &o);
                o
            }
            Err(e) => return rbtdre_Verdict::Fail(format!("before-capture: {}", e)),
        };

        // Attack: invoke ifrit dns-blocked-google inside bottle
        let ifrit_verdict = rbtdrc_invoke_ifrit(ctx, "dns-blocked-google", dir);

        // After: capture iptables state from sentry
        let after = match rbtdrc_writ(ctx, &["iptables", "-L", "-v", "-n", "-x"]) {
            Ok(o) => {
                let _ = std::fs::write(dir.join("iptables-after.txt"), &o);
                o
            }
            Err(e) => return rbtdre_Verdict::Fail(format!("after-capture: {}", e)),
        };

        // Log observation: did sentry state change during the attack?
        let delta = if before != after {
            "CHANGED — sentry processed traffic during attack"
        } else {
            "UNCHANGED — no observable sentry state change"
        };
        let observation = format!(
            "Ifrit verdict: {}\nIptables delta: {}\n",
            match &ifrit_verdict {
                rbtdre_Verdict::Pass => "PASS",
                rbtdre_Verdict::Fail(_) => "FAIL",
                rbtdre_Verdict::Skip(_) => "SKIP",
            },
            delta,
        );
        let _ = std::fs::write(dir.join("observation.txt"), &observation);

        // Primary verdict is the ifrit result
        ifrit_verdict
    })
}

// ── Correlated cases (writ resolves IP, bark tests) ──────────

fn rbtdrc_tcp443_allow_example(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let ip = match rbtdrc_resolve_via_writ(ctx, RBTDRC_CONNECTIVITY_DOMAIN) {
            Ok(ip) => ip,
            Err(e) => return rbtdre_Verdict::Fail(format!("writ resolve {}: {}", RBTDRC_CONNECTIVITY_DOMAIN, e)),
        };
        let _ = std::fs::write(dir.join("resolved-ip.txt"), &ip);
        rbtdrc_invoke_ifrit_with_args(ctx, "tcp443-connect", &[&ip], dir)
    })
}

fn rbtdrc_tcp443_block_google(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let ip = match rbtdrc_resolve_via_writ(ctx, "google.com") {
            Ok(ip) => ip,
            Err(e) => return rbtdre_Verdict::Fail(format!("writ resolve google.com: {}", e)),
        };
        let _ = std::fs::write(dir.join("resolved-ip.txt"), &ip);
        rbtdrc_invoke_ifrit_with_args(ctx, "tcp443-block", &[&ip], dir)
    })
}

fn rbtdrc_icmp_first_hop(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "icmp-first-hop", dir))
}

fn rbtdrc_icmp_second_hop_blocked(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "icmp-second-hop-blocked", dir))
}

fn rbtdrc_udp_non_dns_blocked(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "udp-non-dns-blocked", dir))
}

fn rbtdrc_cidr_all_ports_allowed(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "cidr-all-ports-allowed", dir))
}

// ── Ported sortie cases (bark-only) ──────────────────────────

fn rbtdrc_sortie_dns_exfil_subdomain(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "dns-exfil-subdomain", dir))
}

fn rbtdrc_sortie_meta_cloud_endpoint(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "meta-cloud-endpoint", dir))
}

fn rbtdrc_sortie_net_forbidden_cidr(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "net-forbidden-cidr", dir))
}

// Attacks rivet RBr_3d3.
fn rbtdrc_sortie_direct_sentry_probe(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "direct-sentry-probe", dir))
}

fn rbtdrc_sortie_icmp_exfil_payload(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "icmp-exfil-payload", dir))
}

fn rbtdrc_sortie_net_ipv6_escape(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "net-ipv6-escape", dir))
}

fn rbtdrc_sortie_net_srcip_spoof(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "net-srcip-spoof", dir))
}

// Regression backstop for the residual spoof-as-arbitrary-external case
// left open by per-IP RETURN exclusion + rp_filter=2 loose. Empirically
// passes on macOS Docker Desktop 28.x because Docker's bridge enforces
// source-IP at egress below iptables — see sortie_net_srcip_spoof_external
// in rbida_sorties.rs for the empirical-finding note.
fn rbtdrc_sortie_net_srcip_spoof_external(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "net-srcip-spoof-external", dir))
}

fn rbtdrc_sortie_proto_smuggle_rawsock(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "proto-smuggle-rawsock", dir))
}

fn rbtdrc_sortie_net_fragment_evasion(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "net-fragment-evasion", dir))
}

fn rbtdrc_sortie_direct_arp_poison(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "direct-arp-poison", dir))
}

fn rbtdrc_sortie_ns_capability_escape(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "ns-capability-escape", dir))
}

// ── Novel unilateral attack cases (bark-only) ────────────────

fn rbtdrc_sortie_net_route_manipulation(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "net-route-manipulation", dir))
}

fn rbtdrc_sortie_net_enclave_subnet_escape(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "net-enclave-subnet-escape", dir))
}

// Attacks rivet RBr_3d3.
fn rbtdrc_sortie_net_dnat_entry_reflection(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "net-dnat-entry-reflection", dir))
}

// ── Advanced adversarial probe cases ──────────────────────────

fn rbtdrc_sortie_dns_rebinding(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "dns-rebinding", dir))
}

fn rbtdrc_sortie_proc_sys_write(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "proc-sys-write", dir))
}

fn rbtdrc_sortie_http_end_to_end(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "http-end-to-end", dir))
}

fn rbtdrc_sortie_conntrack_spoofed_ack(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "conntrack-spoofed-ack", dir))
}

fn rbtdrc_sortie_offpath_blocked_dest(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "offpath-blocked-dest", dir))
}

fn rbtdrc_sortie_conntrack_pipeline_selfcheck(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "conntrack-pipeline-selfcheck", dir))
}

fn rbtdrc_sortie_sentry_udp_non_dns(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| rbtdrc_invoke_ifrit(ctx, "sentry-udp-non-dns", dir))
}

// ── Sentry self-protection coordinated cases ─────────────────

/// Coordinated: attempt outbound connections from sentry itself to non-allowed destinations.
/// The sentry's OUTPUT DROP policy should block these — verifies sentry can't be used as a pivot.
fn rbtdrc_coordinated_sentry_egress_lockdown(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        // Negative: attempt TCP to 1.1.1.1:443 from sentry via bash /dev/tcp
        let tcp1_result = rbtdri_invoke(
            ctx,
            RBTDGC_CRUCIBLE_WRIT,
            &["timeout", "2", "bash", "-c", "echo > /dev/tcp/1.1.1.1/443"],
        );
        let tcp1_blocked = match &tcp1_result {
            Ok(r) => {
                let _ = std::fs::write(dir.join("tcp1-stdout.txt"), &r.stdout);
                let _ = std::fs::write(dir.join("tcp1-stderr.txt"), &r.stderr);
                r.exit_code != 0
            }
            Err(e) => {
                let _ = std::fs::write(dir.join("tcp1-error.txt"), format!("{}", e));
                true // invocation error = blocked
            }
        };
        if !tcp1_blocked {
            return rbtdre_Verdict::Fail(
                "BREACH: sentry TCP to 1.1.1.1:443 succeeded — OUTPUT chain not blocking egress"
                    .to_string(),
            );
        }

        // Negative: attempt TCP to 140.82.121.4:443 (GitHub) from sentry
        let tcp2_result = rbtdri_invoke(
            ctx,
            RBTDGC_CRUCIBLE_WRIT,
            &[
                "timeout",
                "2",
                "bash",
                "-c",
                "echo > /dev/tcp/140.82.121.4/443",
            ],
        );
        let tcp2_blocked = match &tcp2_result {
            Ok(r) => {
                let _ = std::fs::write(dir.join("tcp2-stdout.txt"), &r.stdout);
                let _ = std::fs::write(dir.join("tcp2-stderr.txt"), &r.stderr);
                r.exit_code != 0
            }
            Err(e) => {
                let _ = std::fs::write(dir.join("tcp2-error.txt"), format!("{}", e));
                true
            }
        };
        if !tcp2_blocked {
            return rbtdre_Verdict::Fail(
                "BREACH: sentry TCP to 140.82.121.4:443 succeeded — OUTPUT chain not blocking egress"
                    .to_string(),
            );
        }

        // Positive control: dig @8.8.8.8 connectivity domain from sentry must succeed
        // (proves dnsmasq's egress path works — specific OUTPUT ACCEPT for DNS)
        let dig_result = match rbtdrc_writ(
            ctx,
            &["dig", "+short", "@8.8.8.8", RBTDRC_CONNECTIVITY_DOMAIN],
        ) {
            Ok(o) => o,
            Err(e) => {
                return rbtdre_Verdict::Fail(format!(
                    "positive control failed: dig @8.8.8.8 {} from sentry: {}", RBTDRC_CONNECTIVITY_DOMAIN,
                    e
                ))
            }
        };
        let _ = std::fs::write(dir.join("dig-positive.txt"), &dig_result);

        let has_ip = dig_result
            .lines()
            .any(|l| rbtdrc_looks_like_ip(l.trim()));
        if !has_ip {
            return rbtdre_Verdict::Fail(format!(
                "positive control: dig @8.8.8.8 {} returned no IP:\n{}", RBTDRC_CONNECTIVITY_DOMAIN,
                dig_result
            ));
        }

        let _ = std::fs::write(
            dir.join("observation.txt"),
            "Sentry egress lockdown verified: TCP to 1.1.1.1:443 blocked, TCP to 140.82.121.4:443 blocked, DNS egress works",
        );
        rbtdre_Verdict::Pass
    })
}

/// Coordinated: invoke ifrit DNS queries (allowed + blocked), then read dnsmasq log
/// to verify both queries appear. Proves audit trail is intact.
fn rbtdrc_coordinated_dnsmasq_query_audit(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        // Invoke ifrit dns-allowed-example via bark
        let allowed_result = match rbtdri_invoke(
            ctx,
            RBTDGC_CRUCIBLE_BARK,
            &[RBTDRC_IFRIT_BINARY, "dns-allowed-example"],
        ) {
            Ok(r) => r,
            Err(e) => return rbtdre_Verdict::Fail(format!("bark dns-allowed-example: {}", e)),
        };
        let _ = std::fs::write(dir.join("allowed-stdout.txt"), &allowed_result.stdout);
        let _ = std::fs::write(dir.join("allowed-stderr.txt"), &allowed_result.stderr);

        // Invoke ifrit dns-blocked-google via bark
        let blocked_result = match rbtdri_invoke(
            ctx,
            RBTDGC_CRUCIBLE_BARK,
            &[RBTDRC_IFRIT_BINARY, "dns-blocked-google"],
        ) {
            Ok(r) => r,
            Err(e) => return rbtdre_Verdict::Fail(format!("bark dns-blocked-google: {}", e)),
        };
        let _ = std::fs::write(dir.join("blocked-stdout.txt"), &blocked_result.stdout);
        let _ = std::fs::write(dir.join("blocked-stderr.txt"), &blocked_result.stderr);

        // Brief delay for dnsmasq log flush
        std::thread::sleep(std::time::Duration::from_millis(500));

        // Read dnsmasq log from sentry via writ
        let log_output = match rbtdrc_writ(ctx, &["cat", "/var/log/dnsmasq.log"]) {
            Ok(o) => o,
            Err(e) => {
                return rbtdre_Verdict::Fail(format!(
                    "cannot read dnsmasq log: {}",
                    e
                ))
            }
        };
        let _ = std::fs::write(dir.join("dnsmasq-log.txt"), &log_output);

        // writ runs under BURD_NO_LOG, so log_output is the raw dnsmasq log.
        let log_content = &log_output;

        // Verify connectivity domain query appears in log
        let has_example = log_content
            .lines()
            .any(|l| l.contains(RBTDRC_CONNECTIVITY_DOMAIN));
        if !has_example {
            return rbtdre_Verdict::Fail(
                format!("dnsmasq log missing {} query — audit trail incomplete", RBTDRC_CONNECTIVITY_DOMAIN),
            );
        }

        // Verify google.com query appears in log (blocked queries should still be logged)
        let has_google = log_content
            .lines()
            .any(|l| l.contains("google.com"));
        if !has_google {
            return rbtdre_Verdict::Fail(
                "dnsmasq log missing google.com query — blocked queries not audited".to_string(),
            );
        }

        let _ = std::fs::write(
            dir.join("observation.txt"),
            format!("dnsmasq audit verified: both allowed ({}) and blocked (google.com) queries logged", RBTDRC_CONNECTIVITY_DOMAIN),
        );
        rbtdre_Verdict::Pass
    })
}

/// Coordinated: ifrit sends TCP RST packets at sentry DNS, theurge verifies DNS still works.
fn rbtdrc_coordinated_tcp_rst_hijack(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let sentry_ip = match rbtdrc_discover_sentry_ip(ctx) {
            Ok(ip) => ip,
            Err(e) => return rbtdre_Verdict::Fail(format!("sentry IP discovery: {}", e)),
        };
        let _ = std::fs::write(dir.join("sentry-ip.txt"), &sentry_ip);
        let dig_server = format!("@{}", sentry_ip);

        // Pre-snapshot: verify DNS works on sentry before attack
        let pre_resolve = match rbtdrc_writ(
            ctx,
            &["dig", "+short", &dig_server, RBTDRC_CONNECTIVITY_DOMAIN],
        ) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("pre dig {}: {}", RBTDRC_CONNECTIVITY_DOMAIN, e)),
        };
        let _ = std::fs::write(dir.join("pre-resolve.txt"), &pre_resolve);

        let pre_ip = pre_resolve
            .lines()
            .find(|l| rbtdrc_looks_like_ip(l.trim()))
            .unwrap_or("")
            .trim()
            .to_string();
        if pre_ip.is_empty() {
            return rbtdre_Verdict::Fail(
                format!("pre-snapshot: {} did not resolve — DNS not working before attack", RBTDRC_CONNECTIVITY_DOMAIN),
            );
        }

        // Attack: invoke tcp-rst-hijack from bottle
        let result = match rbtdri_invoke(
            ctx,
            RBTDGC_CRUCIBLE_BARK,
            &[RBTDRC_IFRIT_BINARY, "tcp-rst-hijack"],
        ) {
            Ok(r) => r,
            Err(e) => return rbtdre_Verdict::Fail(format!("bark invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("bark-stdout.txt"), &result.stdout);
        let _ = std::fs::write(dir.join("bark-stderr.txt"), &result.stderr);

        // Brief pause for any RST effects to propagate
        std::thread::sleep(std::time::Duration::from_millis(500));

        // Post-snapshot: verify DNS still works on sentry after attack
        let post_resolve = match rbtdrc_writ(
            ctx,
            &["dig", "+short", &dig_server, RBTDRC_CONNECTIVITY_DOMAIN],
        ) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("post dig {}: {}", RBTDRC_CONNECTIVITY_DOMAIN, e)),
        };
        let _ = std::fs::write(dir.join("post-resolve.txt"), &post_resolve);

        let post_ip = post_resolve
            .lines()
            .find(|l| rbtdrc_looks_like_ip(l.trim()))
            .unwrap_or("")
            .trim()
            .to_string();

        if post_ip.is_empty() {
            return rbtdre_Verdict::Fail(
                "BREACH: DNS stopped resolving after TCP RST attack — sentry DNS connection disrupted".to_string(),
            );
        }

        if pre_ip != post_ip {
            return rbtdre_Verdict::Fail(format!(
                "BREACH: DNS resolution changed after RST attack: {} → {}",
                pre_ip, post_ip
            ));
        }

        let _ = std::fs::write(
            dir.join("observation.txt"),
            format!(
                "TCP RST hijack defense verified:\n  {}: {} → {} (stable)\n  ifrit exit: {}\n  ifrit output: {}\n",
                RBTDRC_CONNECTIVITY_DOMAIN,
                pre_ip, post_ip, result.exit_code, result.stdout.trim()
            ),
        );
        rbtdre_Verdict::Pass
    })
}

// ── Coordinated attack cases (writ observes sentry, bark attacks) ──

/// Parse `ip neigh show` output into (IP, MAC) pairs.
/// Format: "10.242.0.3 dev eth1 lladdr 02:42:0a:f2:00:03 REACHABLE"
fn rbtdrc_parse_arp_table(output: &str) -> Vec<(String, String)> {
    let mut entries = Vec::new();
    for line in output.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        // Look for lines with "lladdr" field
        if let Some(pos) = parts.iter().position(|&p| p == "lladdr") {
            if let (Some(&ip), Some(&mac)) = (parts.first(), parts.get(pos + 1)) {
                entries.push((ip.to_string(), mac.to_lowercase()));
            }
        }
    }
    entries
}

/// Find the MAC associated with a given IP in parsed ARP entries.
fn rbtdrc_arp_mac_for_ip<'a>(entries: &'a [(String, String)], ip: &str) -> Option<&'a str> {
    entries
        .iter()
        .find(|(entry_ip, _)| entry_ip == ip)
        .map(|(_, mac)| mac.as_str())
}

/// Coordinated ARP test: ifrit sends gratuitous ARP claiming sentry's IP,
/// theurge verifies sentry's ARP table was not corrupted.
fn rbtdrc_coordinated_arp_gratuitous(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        // Discover sentry IP
        let sentry_ip = match rbtdrc_discover_sentry_ip(ctx) {
            Ok(ip) => ip,
            Err(e) => return rbtdre_Verdict::Fail(format!("sentry IP discovery: {}", e)),
        };
        let _ = std::fs::write(dir.join("sentry-ip.txt"), &sentry_ip);

        // Pre-snapshot: sentry ARP table
        let pre_arp = match rbtdrc_writ(ctx, &["ip", "neigh", "show"]) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("pre-snapshot: {}", e)),
        };
        let _ = std::fs::write(dir.join("pre-arp.txt"), &pre_arp);

        // Execute attack via bark
        let result = match rbtdri_invoke(
            ctx,
            RBTDGC_CRUCIBLE_BARK,
            &[RBTDRC_IFRIT_BINARY, "arp-send-gratuitous"],
        ) {
            Ok(r) => r,
            Err(e) => return rbtdre_Verdict::Fail(format!("bark invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("bark-stdout.txt"), &result.stdout);
        let _ = std::fs::write(dir.join("bark-stderr.txt"), &result.stderr);

        // If ifrit couldn't execute (AF_PACKET blocked), that's SECURE
        if result.exit_code != 0 {
            let _ = std::fs::write(
                dir.join("observation.txt"),
                "SECURE: ifrit could not send L2 frames (AF_PACKET blocked)",
            );
            return rbtdre_Verdict::Pass;
        }

        // Brief delay for ARP to propagate
        std::thread::sleep(std::time::Duration::from_millis(500));

        // Post-snapshot: sentry ARP table
        let post_arp = match rbtdrc_writ(ctx, &["ip", "neigh", "show"]) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("post-snapshot: {}", e)),
        };
        let _ = std::fs::write(dir.join("post-arp.txt"), &post_arp);

        // Parse both snapshots
        let pre_entries = rbtdrc_parse_arp_table(&pre_arp);
        let post_entries = rbtdrc_parse_arp_table(&post_arp);

        // Check: did the sentry's ARP entry for bottle IP change MAC?
        // Get bottle IP from the pre-snapshot (it should be there as a neighbor)
        let observation = format!(
            "Pre-ARP entries: {:?}\nPost-ARP entries: {:?}\nSentry IP: {}\n",
            pre_entries, post_entries, sentry_ip
        );
        let _ = std::fs::write(dir.join("observation.txt"), &observation);

        // Check that no ARP entry now maps sentry's own IP to a different MAC
        // (gratuitous ARP claimed sentry IP at bottle MAC)
        if let Some(post_mac) = rbtdrc_arp_mac_for_ip(&post_entries, &sentry_ip) {
            if let Some(pre_mac) = rbtdrc_arp_mac_for_ip(&pre_entries, &sentry_ip) {
                if pre_mac != post_mac {
                    return rbtdre_Verdict::Fail(format!(
                        "BREACH: sentry ARP entry for own IP {} changed MAC: {} → {}",
                        sentry_ip, pre_mac, post_mac
                    ));
                }
            } else {
                // New entry appeared for sentry's own IP — suspicious
                return rbtdre_Verdict::Fail(format!(
                    "BREACH: new ARP entry appeared for sentry IP {} with MAC {}",
                    sentry_ip, post_mac
                ));
            }
        }

        // Also check that no pre-existing entries had their MAC changed
        for (ip, pre_mac) in &pre_entries {
            if let Some(post_mac) = rbtdrc_arp_mac_for_ip(&post_entries, ip) {
                if pre_mac != post_mac {
                    return rbtdre_Verdict::Fail(format!(
                        "BREACH: sentry ARP entry for {} changed MAC: {} → {}",
                        ip, pre_mac, post_mac
                    ));
                }
            }
        }

        rbtdre_Verdict::Pass
    })
}

/// Coordinated ARP test: ifrit sends targeted ARP reply claiming gateway IP
/// is at bottle MAC, theurge verifies sentry's routing/ARP was not corrupted.
fn rbtdrc_coordinated_arp_gateway_poison(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        // Discover sentry IP
        let sentry_ip = match rbtdrc_discover_sentry_ip(ctx) {
            Ok(ip) => ip,
            Err(e) => return rbtdre_Verdict::Fail(format!("sentry IP discovery: {}", e)),
        };
        let _ = std::fs::write(dir.join("sentry-ip.txt"), &sentry_ip);

        // Compute expected gateway IP (.1 on sentry's subnet)
        let prefix: String = sentry_ip
            .rsplit('.')
            .skip(1)
            .collect::<Vec<_>>()
            .into_iter()
            .rev()
            .collect::<Vec<_>>()
            .join(".");
        let gateway_ip = format!("{}.1", prefix);
        let _ = std::fs::write(dir.join("gateway-ip.txt"), &gateway_ip);

        // Pre-snapshot
        let pre_arp = match rbtdrc_writ(ctx, &["ip", "neigh", "show"]) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("pre-snapshot: {}", e)),
        };
        let _ = std::fs::write(dir.join("pre-arp.txt"), &pre_arp);
        let pre_entries = rbtdrc_parse_arp_table(&pre_arp);

        // Record gateway's pre-attack MAC (if it has an ARP entry)
        let pre_gw_mac = rbtdrc_arp_mac_for_ip(&pre_entries, &gateway_ip).map(|s| s.to_string());
        let _ = std::fs::write(
            dir.join("pre-gw-mac.txt"),
            pre_gw_mac.as_deref().unwrap_or("(none)"),
        );

        // Execute attack via bark
        let result = match rbtdri_invoke(
            ctx,
            RBTDGC_CRUCIBLE_BARK,
            &[RBTDRC_IFRIT_BINARY, "arp-send-gateway-poison"],
        ) {
            Ok(r) => r,
            Err(e) => return rbtdre_Verdict::Fail(format!("bark invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("bark-stdout.txt"), &result.stdout);
        let _ = std::fs::write(dir.join("bark-stderr.txt"), &result.stderr);

        if result.exit_code != 0 {
            let _ = std::fs::write(
                dir.join("observation.txt"),
                "SECURE: ifrit could not send L2 frames (AF_PACKET blocked)",
            );
            return rbtdre_Verdict::Pass;
        }

        std::thread::sleep(std::time::Duration::from_millis(500));

        // Post-snapshot
        let post_arp = match rbtdrc_writ(ctx, &["ip", "neigh", "show"]) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("post-snapshot: {}", e)),
        };
        let _ = std::fs::write(dir.join("post-arp.txt"), &post_arp);
        let post_entries = rbtdrc_parse_arp_table(&post_arp);

        let post_gw_mac = rbtdrc_arp_mac_for_ip(&post_entries, &gateway_ip).map(|s| s.to_string());

        let observation = format!(
            "Gateway IP: {}\nPre gateway MAC: {:?}\nPost gateway MAC: {:?}\n",
            gateway_ip, pre_gw_mac, post_gw_mac
        );
        let _ = std::fs::write(dir.join("observation.txt"), &observation);

        // Check: did gateway MAC change?
        match (&pre_gw_mac, &post_gw_mac) {
            (Some(pre), Some(post)) if pre != post => {
                return rbtdre_Verdict::Fail(format!(
                    "BREACH: sentry ARP for gateway {} changed MAC: {} → {}",
                    gateway_ip, pre, post
                ));
            }
            (None, Some(post)) => {
                // New gateway entry appeared — check it's not the bottle's MAC
                // We can't know bottle MAC from theurge, but a new entry after
                // an ARP poison attempt is suspicious. Log it.
                let _ = std::fs::write(
                    dir.join("new-gw-entry.txt"),
                    format!("New gateway ARP entry: {} → {}", gateway_ip, post),
                );
                // Not necessarily a breach — Docker may have refreshed the entry.
                // But check if any other entries changed.
            }
            _ => {}
        }

        // Verify no pre-existing entries had their MAC changed
        for (ip, pre_mac) in &pre_entries {
            if let Some(post_mac) = rbtdrc_arp_mac_for_ip(&post_entries, ip) {
                if pre_mac != post_mac {
                    return rbtdre_Verdict::Fail(format!(
                        "BREACH: sentry ARP entry for {} changed MAC: {} → {}",
                        ip, pre_mac, post_mac
                    ));
                }
            }
        }

        rbtdre_Verdict::Pass
    })
}

/// Coordinated ARP test: run the full DirectArpPoison sortie from inside bottle,
/// then verify from outside that the sentry's ARP table remained stable.
fn rbtdrc_coordinated_arp_table_stability(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        // Pre-snapshot
        let pre_arp = match rbtdrc_writ(ctx, &["ip", "neigh", "show"]) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("pre-snapshot: {}", e)),
        };
        let _ = std::fs::write(dir.join("pre-arp.txt"), &pre_arp);
        let pre_entries = rbtdrc_parse_arp_table(&pre_arp);

        // Run the full ARP sortie (gratuitous + targeted + cache check)
        let result = match rbtdri_invoke(
            ctx,
            RBTDGC_CRUCIBLE_BARK,
            &[RBTDRC_IFRIT_BINARY, "direct-arp-poison"],
        ) {
            Ok(r) => r,
            Err(e) => return rbtdre_Verdict::Fail(format!("bark invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("bark-stdout.txt"), &result.stdout);
        let _ = std::fs::write(dir.join("bark-stderr.txt"), &result.stderr);

        // The sortie itself reports BREACH if AF_PACKET is available (expected).
        // We don't care about the ifrit's verdict — we care about the sentry's state.
        let ifrit_detail = result.stdout.clone();

        std::thread::sleep(std::time::Duration::from_millis(500));

        // Post-snapshot
        let post_arp = match rbtdrc_writ(ctx, &["ip", "neigh", "show"]) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("post-snapshot: {}", e)),
        };
        let _ = std::fs::write(dir.join("post-arp.txt"), &post_arp);
        let post_entries = rbtdrc_parse_arp_table(&post_arp);

        let observation = format!(
            "Ifrit verdict (informational): {}\nPre entries: {:?}\nPost entries: {:?}\n",
            ifrit_detail.trim(),
            pre_entries,
            post_entries,
        );
        let _ = std::fs::write(dir.join("observation.txt"), &observation);

        // Verify: no pre-existing MAC associations changed
        for (ip, pre_mac) in &pre_entries {
            if let Some(post_mac) = rbtdrc_arp_mac_for_ip(&post_entries, ip) {
                if pre_mac != post_mac {
                    return rbtdre_Verdict::Fail(format!(
                        "BREACH: sentry ARP entry for {} changed MAC: {} → {} after full ARP sortie",
                        ip, pre_mac, post_mac
                    ));
                }
            }
        }

        rbtdre_Verdict::Pass
    })
}

// ── Coordinated integrity cases (sentry state persistence) ──

/// Coordinated integrity test: run a battery of existing attacks, then verify
/// sentry's critical processes, iptables rules, and network interfaces are unchanged.
fn rbtdrc_coordinated_sentry_integrity(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        // Pre-snapshot: verify dnsmasq is running (procps provides pidof)
        let pre_procs = match rbtdrc_writ(ctx, &["pidof", "dnsmasq"]) {
            Ok(o) => o,
            Err(_) => {
                return rbtdre_Verdict::Fail(
                    "pre-snapshot: dnsmasq not running before attacks".to_string(),
                )
            }
        };
        let _ = std::fs::write(dir.join("pre-procs.txt"), &pre_procs);

        let pre_iptables = match rbtdrc_writ(ctx, &["iptables", "-S"]) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("pre-snapshot iptables: {}", e)),
        };
        let pre_iptables_rules = rbtdrc_extract_iptables_rules(&pre_iptables);
        let _ = std::fs::write(dir.join("pre-iptables.txt"), &pre_iptables);

        let pre_links = match rbtdrc_writ(ctx, &["ip", "link", "show"]) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("pre-snapshot ip link: {}", e)),
        };
        let _ = std::fs::write(dir.join("pre-links.txt"), &pre_links);

        // Run battery of 3 different attack types
        let attacks = [
            "dns-blocked-google",
            "direct-arp-poison",
            "proto-smuggle-rawsock",
        ];
        for (i, attack) in attacks.iter().enumerate() {
            let result = rbtdri_invoke(
                ctx,
                RBTDGC_CRUCIBLE_BARK,
                &[RBTDRC_IFRIT_BINARY, attack],
            );
            if let Ok(r) = &result {
                let _ = std::fs::write(
                    dir.join(format!("attack-{}-stdout.txt", i)),
                    &r.stdout,
                );
                let _ = std::fs::write(
                    dir.join(format!("attack-{}-stderr.txt", i)),
                    &r.stderr,
                );
            }
            // Ignore attack verdicts — we only care about sentry state after
        }

        std::thread::sleep(std::time::Duration::from_millis(500));

        // Post-snapshot: verify dnsmasq still running
        let post_procs = match rbtdrc_writ(ctx, &["pidof", "dnsmasq"]) {
            Ok(o) => o,
            Err(_) => {
                return rbtdre_Verdict::Fail(
                    "BREACH: dnsmasq process not found after attack battery".to_string(),
                )
            }
        };
        let _ = std::fs::write(dir.join("post-procs.txt"), &post_procs);

        let post_iptables = match rbtdrc_writ(ctx, &["iptables", "-S"]) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("post-snapshot iptables: {}", e)),
        };
        let post_iptables_rules = rbtdrc_extract_iptables_rules(&post_iptables);
        let _ = std::fs::write(dir.join("post-iptables.txt"), &post_iptables);

        let post_links = match rbtdrc_writ(ctx, &["ip", "link", "show"]) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("post-snapshot ip link: {}", e)),
        };
        let _ = std::fs::write(dir.join("post-links.txt"), &post_links);

        // Verify: iptables rules unchanged (compare rule lines only, not BUK headers)
        if pre_iptables_rules != post_iptables_rules {
            let _ = std::fs::write(
                dir.join("iptables-diff.txt"),
                format!(
                    "BEFORE:\n{}\nAFTER:\n{}\n",
                    pre_iptables_rules, post_iptables_rules
                ),
            );
            return rbtdre_Verdict::Fail(
                "BREACH: iptables rules changed after attack battery".to_string(),
            );
        }

        // Verify: network interfaces unchanged
        if pre_links != post_links {
            let _ = std::fs::write(
                dir.join("links-diff.txt"),
                format!("BEFORE:\n{}\nAFTER:\n{}\n", pre_links, post_links),
            );
            return rbtdre_Verdict::Fail(
                "BREACH: network interfaces changed after attack battery".to_string(),
            );
        }

        let _ = std::fs::write(
            dir.join("observation.txt"),
            format!(
                "Sentry integrity verified after {} attacks: dnsmasq running, iptables stable, interfaces stable",
                attacks.len()
            ),
        );
        rbtdre_Verdict::Pass
    })
}

/// Coordinated integrity test: ifrit sends forged DNS responses claiming google.com → 1.2.3.4,
/// theurge verifies frozen DNS records on sentry's dnsmasq are unchanged.
fn rbtdrc_coordinated_dns_cache_integrity(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        // Discover sentry enclave IP to query its dnsmasq directly
        let sentry_ip = match rbtdrc_discover_sentry_ip(ctx) {
            Ok(ip) => ip,
            Err(e) => return rbtdre_Verdict::Fail(format!("sentry IP discovery: {}", e)),
        };
        let _ = std::fs::write(dir.join("sentry-ip.txt"), &sentry_ip);
        let dig_server = format!("@{}", sentry_ip);

        // Pre-snapshot: query connectivity domain via sentry's dnsmasq (allowed, should resolve)
        let pre_example = match rbtdrc_writ(
            ctx,
            &["dig", "+short", &dig_server, RBTDRC_CONNECTIVITY_DOMAIN],
        ) {
            Ok(o) => o,
            Err(e) => {
                return rbtdre_Verdict::Fail(format!("pre dig {}: {}", RBTDRC_CONNECTIVITY_DOMAIN, e))
            }
        };
        let _ = std::fs::write(dir.join("pre-example.txt"), &pre_example);

        // Pre-snapshot: query google.com via sentry's dnsmasq (blocked)
        let pre_google_result = rbtdri_invoke(
            ctx,
            RBTDGC_CRUCIBLE_WRIT,
            &["dig", "+short", "+time=2", "+tries=1", &dig_server, "google.com"],
        );
        let pre_google = match &pre_google_result {
            Ok(r) => r.stdout.clone(),
            Err(_) => String::new(),
        };
        let _ = std::fs::write(dir.join("pre-google.txt"), &pre_google);

        // Attack: invoke dns-forge-response from bottle
        let result = match rbtdri_invoke(
            ctx,
            RBTDGC_CRUCIBLE_BARK,
            &[RBTDRC_IFRIT_BINARY, "dns-forge-response"],
        ) {
            Ok(r) => r,
            Err(e) => return rbtdre_Verdict::Fail(format!("bark invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("bark-stdout.txt"), &result.stdout);
        let _ = std::fs::write(dir.join("bark-stderr.txt"), &result.stderr);

        std::thread::sleep(std::time::Duration::from_millis(500));

        // Post-snapshot: query connectivity domain again
        let post_example = match rbtdrc_writ(
            ctx,
            &["dig", "+short", &dig_server, RBTDRC_CONNECTIVITY_DOMAIN],
        ) {
            Ok(o) => o,
            Err(e) => {
                return rbtdre_Verdict::Fail(format!("post dig {}: {}", RBTDRC_CONNECTIVITY_DOMAIN, e))
            }
        };
        let _ = std::fs::write(dir.join("post-example.txt"), &post_example);

        // Post-snapshot: query google.com again
        let post_google_result = rbtdri_invoke(
            ctx,
            RBTDGC_CRUCIBLE_WRIT,
            &["dig", "+short", "+time=2", "+tries=1", &dig_server, "google.com"],
        );
        let post_google = match &post_google_result {
            Ok(r) => r.stdout.clone(),
            Err(_) => String::new(),
        };
        let _ = std::fs::write(dir.join("post-google.txt"), &post_google);

        // Verify: connectivity domain resolution unchanged
        let pre_example_ip = pre_example
            .lines()
            .find(|l| rbtdrc_looks_like_ip(l.trim()))
            .unwrap_or("")
            .trim();
        let post_example_ip = post_example
            .lines()
            .find(|l| rbtdrc_looks_like_ip(l.trim()))
            .unwrap_or("")
            .trim();

        if pre_example_ip.is_empty() {
            return rbtdre_Verdict::Fail(
                format!("pre-snapshot: {} did not resolve (expected frozen record)", RBTDRC_CONNECTIVITY_DOMAIN),
            );
        }
        if pre_example_ip != post_example_ip {
            return rbtdre_Verdict::Fail(format!(
                "BREACH: {} resolution changed: {} → {}", RBTDRC_CONNECTIVITY_DOMAIN,
                pre_example_ip, post_example_ip
            ));
        }

        // Verify: google.com still not resolvable (forged response ignored)
        if post_google.lines().any(|l| l.trim() == "1.2.3.4") {
            return rbtdre_Verdict::Fail(
                "BREACH: google.com now resolves to 1.2.3.4 — DNS cache was poisoned".to_string(),
            );
        }

        let _ = std::fs::write(
            dir.join("observation.txt"),
            format!(
                "DNS cache integrity verified:\n  {}: {} → {} (stable)\n  google.com: forged 1.2.3.4 response ignored\n  ifrit exit: {}\n",
                RBTDRC_CONNECTIVITY_DOMAIN,
                pre_example_ip, post_example_ip, result.exit_code
            ),
        );
        rbtdre_Verdict::Pass
    })
}

/// Coordinated integrity test: ifrit floods bridge with random MAC frames,
/// theurge verifies sentry↔bottle connectivity survives.
fn rbtdrc_coordinated_mac_flood_resilience(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let sentry_ip = match rbtdrc_discover_sentry_ip(ctx) {
            Ok(ip) => ip,
            Err(e) => return rbtdre_Verdict::Fail(format!("sentry IP discovery: {}", e)),
        };
        let _ = std::fs::write(dir.join("sentry-ip.txt"), &sentry_ip);

        // Pre: verify connectivity in all three directions
        let pre_writ = match rbtdrc_writ(ctx, &["echo", "pre-connectivity-check"]) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("pre writ check: {}", e)),
        };
        let _ = std::fs::write(dir.join("pre-writ.txt"), &pre_writ);

        let pre_fiat = match rbtdrc_fiat(ctx, &["echo", "pre-connectivity-check"]) {
            Ok(o) => o,
            Err(e) => return rbtdre_Verdict::Fail(format!("pre fiat check: {}", e)),
        };
        let _ = std::fs::write(dir.join("pre-fiat.txt"), &pre_fiat);

        // Attack: invoke mac-flood-bridge from bottle
        let result = match rbtdri_invoke(
            ctx,
            RBTDGC_CRUCIBLE_BARK,
            &[RBTDRC_IFRIT_BINARY, "mac-flood-bridge"],
        ) {
            Ok(r) => r,
            Err(e) => return rbtdre_Verdict::Fail(format!("bark invocation: {}", e)),
        };
        let _ = std::fs::write(dir.join("bark-stdout.txt"), &result.stdout);
        let _ = std::fs::write(dir.join("bark-stderr.txt"), &result.stderr);

        // If ifrit couldn't execute (AF_PACKET blocked), that's SECURE
        if result.exit_code != 0 {
            let _ = std::fs::write(
                dir.join("observation.txt"),
                "SECURE: ifrit could not send L2 frames (AF_PACKET blocked)",
            );
            return rbtdre_Verdict::Pass;
        }

        std::thread::sleep(std::time::Duration::from_millis(500));

        // Post: verify connectivity survived the flood
        let post_writ = match rbtdrc_writ(ctx, &["echo", "post-connectivity-check"]) {
            Ok(o) => o,
            Err(e) => {
                return rbtdre_Verdict::Fail(format!(
                    "BREACH: writ failed post-MAC-flood: {}",
                    e
                ))
            }
        };
        let _ = std::fs::write(dir.join("post-writ.txt"), &post_writ);

        let post_fiat = match rbtdrc_fiat(ctx, &["echo", "post-connectivity-check"]) {
            Ok(o) => o,
            Err(e) => {
                return rbtdre_Verdict::Fail(format!(
                    "BREACH: fiat failed post-MAC-flood: {}",
                    e
                ))
            }
        };
        let _ = std::fs::write(dir.join("post-fiat.txt"), &post_fiat);

        // Post: bark still works (sentry→bottle direction)
        match rbtdri_invoke(
            ctx,
            RBTDGC_CRUCIBLE_BARK,
            &["echo", "post-connectivity-check"],
        ) {
            Ok(r) if r.exit_code == 0 => {
                let _ = std::fs::write(dir.join("post-bark.txt"), &r.stdout);
            }
            Ok(r) => {
                return rbtdre_Verdict::Fail(format!(
                    "BREACH: bark failed post-MAC-flood (exit {}): {}",
                    r.exit_code, r.stderr
                ))
            }
            Err(e) => {
                return rbtdre_Verdict::Fail(format!(
                    "BREACH: bark invocation failed post-MAC-flood: {}",
                    e
                ))
            }
        }

        let _ = std::fs::write(
            dir.join("observation.txt"),
            format!(
                "Bridge resilience verified post-MAC-flood:\n  writ: ok\n  fiat: ok\n  bark: ok\n  ifrit exit: {}\n",
                result.exit_code
            ),
        );
        rbtdre_Verdict::Pass
    })
}

// ── Host-side helpers (HTTP probes, port discovery) ──────────

/// Read RBRN_ENTRY_PORT_WORKSTATION from the nameplate's rbrn.env file.
/// Caller's fixture name must equal a valid nameplate moniker — only crucible
/// fixtures (srjcl/pluml) call this.
fn rbtdrc_read_nameplate_port(ctx: &rbtdri_Context) -> Result<u16, String> {
    let env_path = ctx
        .project_root()
        .join(crate::rbtdgc_consts::RBTDGC_MOORINGS_DIR)
        .join(ctx.fixture())
        .join("rbrn.env");
    let content = std::fs::read_to_string(&env_path)
        .map_err(|e| format!("cannot read {}: {}", env_path.display(), e))?;
    for line in content.lines() {
        if let Some(rest) = line.strip_prefix("RBRN_ENTRY_PORT_WORKSTATION=") {
            return rest
                .trim()
                .parse::<u16>()
                .map_err(|e| format!("invalid port '{}': {}", rest.trim(), e));
        }
    }
    Err(format!(
        "RBRN_ENTRY_PORT_WORKSTATION not found in {}",
        env_path.display()
    ))
}

/// Simple curl GET, returns (body, exit_code).
fn rbtdrc_curl_get(url: &str) -> Result<(String, i32), String> {
    let output = Command::new("curl")
        .args(["-s", "--connect-timeout", "5", "--max-time", "10", url])
        .output()
        .map_err(|e| format!("curl exec failed: {}", e))?;
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    let code = output.status.code().unwrap_or(-1);
    Ok((stdout, code))
}

/// Curl GET returning HTTP status code only.
fn rbtdrc_curl_status(url: &str, headers: &[(&str, &str)]) -> Result<String, String> {
    let mut cmd = Command::new("curl");
    cmd.args([
        "-s",
        "-o",
        "/dev/null",
        "-w",
        "%{http_code}",
        "--connect-timeout",
        "5",
        "--max-time",
        "10",
    ]);
    for (name, value) in headers {
        cmd.arg("-H").arg(format!("{}: {}", name, value));
    }
    cmd.arg(url);
    let output = cmd
        .output()
        .map_err(|e| format!("curl exec failed: {}", e))?;
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

/// Curl POST with body from stdin, returns response body.
fn rbtdrc_curl_post_stdin(url: &str, body: &str) -> Result<String, String> {
    let mut child = Command::new("curl")
        .args(["-s", "--data-binary", "@-", url])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("curl POST spawn failed: {}", e))?;
    child
        .stdin
        .take()
        .unwrap()
        .write_all(body.as_bytes())
        .map_err(|e| format!("curl POST write failed: {}", e))?;
    let output = child
        .wait_with_output()
        .map_err(|e| format!("curl POST wait failed: {}", e))?;
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

// ── SRJCL Jupyter cases (host-side probes) ───────────────────

fn rbtdrc_srjcl_jupyter_running(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let result =
            match rbtdri_invoke(ctx, RBTDGC_CRUCIBLE_BARK, &["ps", "aux"]) {
                Ok(r) => r,
                Err(e) => return rbtdre_Verdict::Fail(format!("bark ps aux: {}", e)),
            };
        let _ = std::fs::write(dir.join("bark-stdout.txt"), &result.stdout);
        let _ = std::fs::write(dir.join("bark-stderr.txt"), &result.stderr);

        if result.exit_code != 0 {
            return rbtdre_Verdict::Fail(format!(
                "ps aux exited {}\n{}",
                result.exit_code, result.stderr
            ));
        }
        if !result.stdout.contains("jupyter") {
            return rbtdre_Verdict::Fail("jupyter not running in bottle".to_string());
        }
        rbtdre_Verdict::Pass
    })
}

fn rbtdrc_srjcl_jupyter_connectivity(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let port = match rbtdrc_read_nameplate_port(ctx) {
            Ok(p) => p,
            Err(e) => return rbtdre_Verdict::Fail(format!("port discovery: {}", e)),
        };
        let url = format!("http://localhost:{}/lab", port);
        let status = match rbtdrc_curl_status(
            &url,
            &[
                ("User-Agent", "Mozilla/5.0"),
                ("Accept", "text/html,application/xhtml+xml"),
            ],
        ) {
            Ok(s) => s,
            Err(e) => return rbtdre_Verdict::Fail(format!("curl error: {}", e)),
        };
        let _ = std::fs::write(dir.join("http-status.txt"), &status);

        if status != "200" {
            return rbtdre_Verdict::Fail(format!(
                "expected HTTP 200 from Jupyter, got: {}",
                status
            ));
        }
        rbtdre_Verdict::Pass
    })
}

fn rbtdrc_srjcl_websocket_kernel(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let port = match rbtdrc_read_nameplate_port(ctx) {
            Ok(p) => p,
            Err(e) => return rbtdre_Verdict::Fail(format!("port discovery: {}", e)),
        };
        let base = format!("http://localhost:{}", port);

        // Step 1: GET /lab to obtain XSRF cookie
        let xsrf = match rbtdrc_curl_get_cookie(&base, "/lab", "_xsrf") {
            Ok(v) => v,
            Err(e) => return rbtdre_Verdict::Fail(format!("XSRF fetch: {}", e)),
        };
        let _ = std::fs::write(dir.join("xsrf-token.txt"), &xsrf);

        // Step 2: POST /api/sessions to create a kernel
        let session_body = r#"{"kernel":{"name":"python3"},"name":"test.ipynb","path":"test.ipynb","type":"notebook"}"#;
        let session_json = match rbtdrc_curl_post_json(
            &format!("{}/api/sessions", base),
            session_body,
            &xsrf,
        ) {
            Ok(j) => j,
            Err(e) => return rbtdre_Verdict::Fail(format!("session create: {}", e)),
        };
        let _ = std::fs::write(dir.join("session-response.json"), &session_json);

        let kernel_id = match rbtdrc_extract_json_string(&session_json, "kernel", "id") {
            Some(id) => id,
            None => {
                return rbtdre_Verdict::Fail(format!(
                    "no kernel.id in session response: {}",
                    session_json
                ))
            }
        };
        let session_id = match rbtdrc_extract_json_string_top(&session_json, "id") {
            Some(id) => id,
            None => {
                return rbtdre_Verdict::Fail(format!(
                    "no id in session response: {}",
                    session_json
                ))
            }
        };

        // Step 3: WebSocket connect to kernel channels
        let ws_url = format!(
            "ws://localhost:{}/api/kernels/{}/channels",
            port, kernel_id
        );
        let ws_result = rbtdrc_websocket_kernel_execute(&ws_url, &xsrf, dir);

        // Step 4: Clean up session (best-effort)
        let _ = rbtdrc_curl_delete(
            &format!("{}/api/sessions/{}", base, session_id),
            &xsrf,
        );

        ws_result
    })
}

/// Curl GET returning a specific Set-Cookie value.
fn rbtdrc_curl_get_cookie(base: &str, path: &str, cookie_name: &str) -> Result<String, String> {
    let url = format!("{}{}", base, path);
    let output = Command::new("curl")
        .args([
            "-s",
            "-D", "-",           // dump headers to stdout
            "-o", "/dev/null",   // discard body
            "--connect-timeout", "5",
            "--max-time", "10",
            "-H", "User-Agent: Mozilla/5.0",
        ])
        .arg(&url)
        .output()
        .map_err(|e| format!("curl exec failed: {}", e))?;
    let headers = String::from_utf8_lossy(&output.stdout);
    for line in headers.lines() {
        if let Some(rest) = line.to_lowercase().strip_prefix("set-cookie:") {
            let rest = rest.trim();
            if let Some(cv) = rest.strip_prefix(&format!("{}=", cookie_name)) {
                let value = cv.split(';').next().unwrap_or("").trim().to_string();
                if !value.is_empty() {
                    return Ok(value);
                }
            }
        }
    }
    Err(format!("cookie '{}' not found in response headers", cookie_name))
}

/// Curl POST with JSON body and XSRF token, returns response body.
fn rbtdrc_curl_post_json(url: &str, body: &str, xsrf: &str) -> Result<String, String> {
    let mut child = Command::new("curl")
        .args([
            "-s",
            "--connect-timeout", "5",
            "--max-time", "10",
            "-X", "POST",
            "-H", "Content-Type: application/json",
        ])
        .arg("-H")
        .arg(format!("X-XSRFToken: {}", xsrf))
        .arg("-b")
        .arg(format!("_xsrf={}", xsrf))
        .arg("--data-binary")
        .arg("@-")
        .arg(url)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("curl POST spawn failed: {}", e))?;
    child
        .stdin
        .take()
        .unwrap()
        .write_all(body.as_bytes())
        .map_err(|e| format!("curl POST write failed: {}", e))?;
    let output = child
        .wait_with_output()
        .map_err(|e| format!("curl POST wait failed: {}", e))?;
    if !output.status.success() {
        return Err(format!(
            "curl POST exited {}: {}",
            output.status.code().unwrap_or(-1),
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

/// Curl DELETE with XSRF token (best-effort cleanup).
fn rbtdrc_curl_delete(url: &str, xsrf: &str) -> Result<(), String> {
    Command::new("curl")
        .args([
            "-s",
            "--connect-timeout", "5",
            "--max-time", "10",
            "-X", "DELETE",
        ])
        .arg("-H")
        .arg(format!("X-XSRFToken: {}", xsrf))
        .arg("-b")
        .arg(format!("_xsrf={}", xsrf))
        .arg(url)
        .output()
        .map_err(|e| format!("curl DELETE failed: {}", e))?;
    Ok(())
}

/// Minimal JSON string extraction: obj.key.subkey (no serde dependency).
fn rbtdrc_extract_json_string(json: &str, key: &str, subkey: &str) -> Option<String> {
    let needle = format!("\"{}\"", key);
    let pos = json.find(&needle)?;
    let rest = &json[pos + needle.len()..];
    let sub_needle = format!("\"{}\"", subkey);
    let sub_pos = rest.find(&sub_needle)?;
    let after = &rest[sub_pos + sub_needle.len()..];
    rbtdrc_extract_quoted_value(after)
}

/// Minimal JSON string extraction: obj.key (top-level).
fn rbtdrc_extract_json_string_top(json: &str, key: &str) -> Option<String> {
    let needle = format!("\"{}\"", key);
    let pos = json.find(&needle)?;
    let after = &json[pos + needle.len()..];
    rbtdrc_extract_quoted_value(after)
}

fn rbtdrc_extract_quoted_value(s: &str) -> Option<String> {
    // skip whitespace and colon, find opening quote
    let trimmed = s.trim_start();
    let rest = trimmed.strip_prefix(':')?;
    let rest = rest.trim_start();
    let rest = rest.strip_prefix('"')?;
    let end = rest.find('"')?;
    Some(rest[..end].to_string())
}

/// Connect via WebSocket, execute a trivial Python expression, verify result.
fn rbtdrc_websocket_kernel_execute(
    ws_url: &str,
    xsrf: &str,
    dir: &Path,
) -> rbtdre_Verdict {
    use tungstenite::client::connect_with_config;
    use tungstenite::http::Request;
    use tungstenite::Message;

    // Build HTTP request with cookies
    // Extract host:port from ws URL for Host header
    let host_port = ws_url
        .strip_prefix("ws://")
        .and_then(|s| s.split('/').next())
        .unwrap_or("localhost");

    let request = match Request::builder()
        .uri(ws_url)
        .header("Host", host_port)
        .header("Cookie", format!("_xsrf={}", xsrf))
        .header("User-Agent", "Mozilla/5.0")
        .header("Connection", "Upgrade")
        .header("Upgrade", "websocket")
        .header("Sec-WebSocket-Version", "13")
        .header("Sec-WebSocket-Key", tungstenite::handshake::client::generate_key())
        .body(())
    {
        Ok(r) => r,
        Err(e) => return rbtdre_Verdict::Fail(format!("WS request build: {}", e)),
    };

    let (mut ws, _response) = match connect_with_config(request, None, 3) {
        Ok(pair) => pair,
        Err(e) => return rbtdre_Verdict::Fail(format!("WS connect: {}", e)),
    };

    // Send kernel_info_request to trigger readiness
    let msg_id_info = "theurge-kernel-info-001";
    let session_id = "theurge-session-001";
    let kernel_info_req = format!(
        r#"{{"header":{{"msg_id":"{}","username":"","session":"{}","msg_type":"kernel_info_request","version":"5.3"}},"parent_header":{{}},"metadata":{{}},"content":{{}},"channel":"shell","buffers":[]}}"#,
        msg_id_info, session_id
    );
    if let Err(e) = ws.send(Message::Text(kernel_info_req)) {
        return rbtdre_Verdict::Fail(format!("WS send kernel_info: {}", e));
    }

    // Wait for kernel idle after kernel_info_request
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(15);
    let mut kernel_ready = false;
    while std::time::Instant::now() < deadline {
        let msg = match ws.read() {
            Ok(m) => m,
            Err(e) => return rbtdre_Verdict::Fail(format!("WS read (ready): {}", e)),
        };
        if let Message::Text(ref text) = msg {
            let _ = std::fs::write(dir.join("ws-ready-trace.txt"),
                format!("{}\n---\n", text));
            if text.contains("\"execution_state\"")
                && text.contains("\"idle\"")
                && text.contains("kernel_info_request")
            {
                kernel_ready = true;
                break;
            }
        }
    }
    if !kernel_ready {
        let _ = ws.close(None);
        return rbtdre_Verdict::Fail("timeout waiting for kernel ready".to_string());
    }

    // Send execute_request: print("Hello from theurge")
    let msg_id_exec = "theurge-execute-001";
    let execute_req = format!(
        r#"{{"header":{{"msg_id":"{}","username":"","session":"{}","msg_type":"execute_request","version":"5.3"}},"parent_header":{{}},"metadata":{{}},"content":{{"code":"print(\"Hello from theurge\")","silent":false,"store_history":true,"user_expressions":{{}},"allow_stdin":false}},"channel":"shell","buffers":[]}}"#,
        msg_id_exec, session_id
    );
    if let Err(e) = ws.send(Message::Text(execute_req)) {
        return rbtdre_Verdict::Fail(format!("WS send execute: {}", e));
    }

    // Read messages until we see the stream output or execution goes idle
    let exec_deadline = std::time::Instant::now() + std::time::Duration::from_secs(15);
    let mut saw_output = false;
    let mut execution_idle = false;
    let mut trace = String::new();
    while std::time::Instant::now() < exec_deadline {
        let msg = match ws.read() {
            Ok(m) => m,
            Err(e) => {
                let _ = std::fs::write(dir.join("ws-exec-trace.txt"), &trace);
                return rbtdre_Verdict::Fail(format!("WS read (exec): {}", e));
            }
        };
        if let Message::Text(ref text) = msg {
            trace.push_str(text);
            trace.push_str("\n---\n");
            // Check for stream output with our expected text
            if text.contains("\"msg_type\":\"stream\"")
                || text.contains("\"msg_type\": \"stream\"")
            {
                if text.contains("Hello from theurge") {
                    saw_output = true;
                }
            }
            // Check for execution idle (completion)
            if text.contains("\"execution_state\"")
                && text.contains("\"idle\"")
                && !text.contains("kernel_info_request")
            {
                execution_idle = true;
                if execution_idle {
                    break;
                }
            }
        }
    }
    let _ = std::fs::write(dir.join("ws-exec-trace.txt"), &trace);
    let _ = ws.close(None);

    if !saw_output {
        return rbtdre_Verdict::Fail(format!(
            "kernel executed but no stream output with expected text (idle={})",
            execution_idle
        ));
    }
    rbtdre_Verdict::Pass
}

// ── PLUML PlantUML cases (host-side HTTP probes) ─────────────

/// Known PlantUML diagram hash for Alice/Bob conversation.
const RBTDRC_PLUML_KNOWN_HASH: &str =
    "SyfFKj2rKt3CoKnELR1Io4ZDoSbNACb8BKhbWeZf0cMTyfEi59Boym40";

fn rbtdrc_pluml_text_rendering(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let port = match rbtdrc_read_nameplate_port(ctx) {
            Ok(p) => p,
            Err(e) => return rbtdre_Verdict::Fail(format!("port discovery: {}", e)),
        };
        let url = format!(
            "http://localhost:{}/txt/{}",
            port, RBTDRC_PLUML_KNOWN_HASH
        );
        let (body, _) = match rbtdrc_curl_get(&url) {
            Ok(r) => r,
            Err(e) => return rbtdre_Verdict::Fail(format!("curl error: {}", e)),
        };
        let _ = std::fs::write(dir.join("curl-response.txt"), &body);

        for expected in &["Bob", "Alice", "hello there", "boo"] {
            if !body.contains(expected) {
                return rbtdre_Verdict::Fail(format!(
                    "expected '{}' in response:\n{}",
                    expected, body
                ));
            }
        }
        rbtdre_Verdict::Pass
    })
}

fn rbtdrc_pluml_local_diagram(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let port = match rbtdrc_read_nameplate_port(ctx) {
            Ok(p) => p,
            Err(e) => return rbtdre_Verdict::Fail(format!("port discovery: {}", e)),
        };
        let url = format!("http://localhost:{}/txt/uml", port);
        let diagram = "@startuml\nBob -> Alice: hello there\nAlice --> Bob: boo\n@enduml";
        let body = match rbtdrc_curl_post_stdin(&url, diagram) {
            Ok(b) => b,
            Err(e) => return rbtdre_Verdict::Fail(format!("curl POST error: {}", e)),
        };
        let _ = std::fs::write(dir.join("curl-response.txt"), &body);

        for expected in &["Bob", "Alice", "hello there", "boo"] {
            if !body.contains(expected) {
                return rbtdre_Verdict::Fail(format!(
                    "expected '{}' in response:\n{}",
                    expected, body
                ));
            }
        }
        rbtdre_Verdict::Pass
    })
}

fn rbtdrc_pluml_http_headers(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let port = match rbtdrc_read_nameplate_port(ctx) {
            Ok(p) => p,
            Err(e) => return rbtdre_Verdict::Fail(format!("port discovery: {}", e)),
        };
        let url = format!(
            "http://localhost:{}/txt/{}",
            port, RBTDRC_PLUML_KNOWN_HASH
        );
        let status = match rbtdrc_curl_status(
            &url,
            &[
                ("User-Agent", "Mozilla/5.0"),
                ("Accept", "text/plain"),
            ],
        ) {
            Ok(s) => s,
            Err(e) => return rbtdre_Verdict::Fail(format!("curl error: {}", e)),
        };
        let _ = std::fs::write(dir.join("http-status.txt"), &status);

        if status != "200" {
            return rbtdre_Verdict::Fail(format!("expected HTTP 200, got: {}", status));
        }
        rbtdre_Verdict::Pass
    })
}

fn rbtdrc_pluml_invalid_hash(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let port = match rbtdrc_read_nameplate_port(ctx) {
            Ok(p) => p,
            Err(e) => return rbtdre_Verdict::Fail(format!("port discovery: {}", e)),
        };
        let url = format!("http://localhost:{}/txt/invalid_hash", port);
        let (body, _) = match rbtdrc_curl_get(&url) {
            Ok(r) => r,
            Err(e) => return rbtdre_Verdict::Fail(format!("curl error: {}", e)),
        };
        let _ = std::fs::write(dir.join("curl-response.txt"), &body);

        if body.contains("Bob") {
            return rbtdre_Verdict::Fail(
                "expected no 'Bob' in invalid hash response".to_string(),
            );
        }
        rbtdre_Verdict::Pass
    })
}

fn rbtdrc_pluml_malformed_diagram(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let port = match rbtdrc_read_nameplate_port(ctx) {
            Ok(p) => p,
            Err(e) => return rbtdre_Verdict::Fail(format!("port discovery: {}", e)),
        };
        let url = format!("http://localhost:{}/txt/uml", port);
        let body = match rbtdrc_curl_post_stdin(&url, "invalid uml content") {
            Ok(b) => b,
            Err(e) => return rbtdre_Verdict::Fail(format!("curl POST error: {}", e)),
        };
        let _ = std::fs::write(dir.join("curl-response.txt"), &body);

        if body.contains("Bob") {
            return rbtdre_Verdict::Fail(
                "expected no 'Bob' in malformed diagram response".to_string(),
            );
        }
        rbtdre_Verdict::Pass
    })
}

/// Generative case — deliberately distinct from the hermetic probe cases above.
/// Pure light→dark recolor of a PlantUML default-skin SVG. No crucible, no I/O —
/// a function of the rendered bytes already in hand, so it carries zero container
/// dependency and is unit-tested on its own. Surveys the exact default-skin
/// palette these sequence diagrams emit and maps each color to a dark-canvas
/// equivalent; the page background is dropped to `transparent` so the figure
/// blends with GitHub's dark canvas under a `<picture media="(prefers-color-scheme:
/// dark)">` source. Colors outside the surveyed palette pass through unchanged —
/// a characterized membrane, not a silent catch-all: a future custom-skinned
/// diagram would need its colors added to the palette here rather than be
/// recolored by guesswork.
fn zrbtdrc_darken_svg(light: &str) -> String {
    // Surveyed PlantUML default-skin palette: (light_hex, dark_hex). No entry is
    // a substring of another, so replacement order among them is immaterial.
    const RBTDRC_DARK_PALETTE: &[(&str, &str)] = &[
        ("#000000", "#E6E6E6"), // text + arrow ink
        ("#181818", "#9DA5B4"), // lifelines, borders, dashes
        ("#E2E2F0", "#3B3B54"), // participant box fill
        ("#FEFFDD", "#48421F"), // note fill
        ("#EEEEEE", "#2B2B2B"), // group / alt-region background
    ];
    // Drop the opaque page background first (specific substring, before any
    // general hex mapping touches the same bytes).
    let mut out = light.replace("background:#FFFFFF;", "background:transparent;");
    for (light_hex, dark_hex) in RBTDRC_DARK_PALETTE {
        out = out.replace(light_hex, dark_hex);
    }
    out
}

/// Re-renders every `diagrams/*.puml` source under the project root through the
/// pluml-crucible PlantUML server, asserting each response is a well-formed SVG,
/// and writes two committed siblings per source: the light `{stem}.svg` straight
/// from the server, and a `{stem}-dark.svg` recolored by `zrbtdrc_darken_svg`.
/// README embeds the pair via `<picture>` so each diagram tracks the reader's
/// color scheme. This is the one pluml case that writes tracked repo files; the
/// diagram set lives in the glob alone (drop a new `rbdgX_*.puml` in `diagrams/`
/// and it is rendered in both modes — no second list to maintain). Idempotent —
/// identical source yields byte-stable output, so a clean tree stays clean. Fails
/// loud when the diagrams dir is missing or empty, or when a render returns a
/// non-SVG (the server emits a valid <svg> even for diagram syntax errors, so the
/// "Syntax Error" payload is rejected explicitly).
fn rbtdrc_pluml_render_diagrams(dir: &Path) -> rbtdre_Verdict {
    rbtdrc_with_ctx(|ctx| {
        let port = match rbtdrc_read_nameplate_port(ctx) {
            Ok(p) => p,
            Err(e) => return rbtdre_Verdict::Fail(format!("port discovery: {}", e)),
        };
        let url = format!("http://localhost:{}/svg/uml", port);
        let diagrams_dir = ctx.project_root().join("diagrams");

        let entries = match std::fs::read_dir(&diagrams_dir) {
            Ok(e) => e,
            Err(e) => {
                return rbtdre_Verdict::Fail(format!(
                    "cannot read diagrams dir {}: {}",
                    diagrams_dir.display(),
                    e
                ))
            }
        };
        let mut sources: Vec<PathBuf> = entries
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("puml"))
            .collect();
        sources.sort();

        if sources.is_empty() {
            return rbtdre_Verdict::Fail(format!(
                "no .puml sources under {}",
                diagrams_dir.display()
            ));
        }

        let mut rendered: Vec<String> = Vec::new();
        for src in &sources {
            let stem = src
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("")
                .to_string();
            let body = match std::fs::read_to_string(src) {
                Ok(b) => b,
                Err(e) => {
                    return rbtdre_Verdict::Fail(format!("read {}: {}", src.display(), e))
                }
            };
            let svg = match rbtdrc_curl_post_stdin(&url, &body) {
                Ok(s) => s,
                Err(e) => {
                    return rbtdre_Verdict::Fail(format!("render {}: curl POST: {}", stem, e))
                }
            };
            if !svg.contains("<svg") || !svg.contains("</svg>") {
                let _ = std::fs::write(dir.join(format!("{}-bad.txt", stem)), &svg);
                return rbtdre_Verdict::Fail(format!(
                    "{}: response is not a well-formed SVG",
                    stem
                ));
            }
            if svg.contains("Syntax Error") {
                let _ = std::fs::write(dir.join(format!("{}-bad.svg", stem)), &svg);
                return rbtdre_Verdict::Fail(format!(
                    "{}: PlantUML reported a syntax error",
                    stem
                ));
            }
            let out = diagrams_dir.join(format!("{}.svg", stem));
            if let Err(e) = std::fs::write(&out, &svg) {
                return rbtdre_Verdict::Fail(format!("write {}: {}", out.display(), e));
            }
            let dark_out = diagrams_dir.join(format!("{}-dark.svg", stem));
            if let Err(e) = std::fs::write(&dark_out, zrbtdrc_darken_svg(&svg)) {
                return rbtdre_Verdict::Fail(format!("write {}: {}", dark_out.display(), e));
            }
            rendered.push(stem);
        }

        let _ = std::fs::write(dir.join("rendered.txt"), rendered.join("\n"));
        rbtdre_Verdict::Pass
    })
}

// ── Case registry ────────────────────────────────────────────

// ── Crucible fixtures (charge/quench lifecycle) ──────────────

pub static RBTDRC_FIXTURE_TADMOR: rbtdre_Fixture = rbtdre_Fixture {
    name: crate::rbtdrm_manifest::RBTDRM_FIXTURE_TADMOR,
    disposition: rbtdre_Disposition::Independent,
    setup: Some(rbtdrc_charge_crucible),
    teardown: Some(rbtdrc_quench_crucible),
    cases: RBTDRC_CASES_SECURITY,
    credless: false,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: Some(1200), invocations: None },
};

// Moriah is the airgap-bottle nameplate; runtime semantics are identical
// to tadmor so the fixture shares RBTDRC_CASES_SECURITY. The distinction
// is provenance (cloud-built airgap vs local kludge), not behavior.
pub static RBTDRC_FIXTURE_MORIAH: rbtdre_Fixture = rbtdre_Fixture {
    name: crate::rbtdrm_manifest::RBTDRM_FIXTURE_MORIAH,
    disposition: rbtdre_Disposition::Independent,
    setup: Some(rbtdrc_charge_crucible),
    teardown: Some(rbtdrc_quench_crucible),
    cases: RBTDRC_CASES_SECURITY,
    credless: false,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: Some(1200), invocations: None },
};

pub static RBTDRC_FIXTURE_SRJCL: rbtdre_Fixture = rbtdre_Fixture {
    name: crate::rbtdrm_manifest::RBTDRM_FIXTURE_SRJCL,
    disposition: rbtdre_Disposition::Independent,
    setup: Some(rbtdrc_charge_crucible),
    teardown: Some(rbtdrc_quench_crucible),
    cases: RBTDRC_CASES_SRJCL,
    credless: false,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: Some(600), invocations: None },
};

pub static RBTDRC_FIXTURE_PLUML: rbtdre_Fixture = rbtdre_Fixture {
    name: crate::rbtdrm_manifest::RBTDRM_FIXTURE_PLUML,
    disposition: rbtdre_Disposition::Independent,
    setup: Some(rbtdrc_charge_crucible),
    teardown: Some(rbtdrc_quench_crucible),
    cases: RBTDRC_CASES_PLUML,
    credless: false,
    tariff: rbtdre_Tariff { min_secs: None, max_secs: Some(600), invocations: None },
};


pub static RBTDRC_CASES_SRJCL: &[rbtdre_Case] = &[
    case!(rbtdrc_srjcl_jupyter_running),
    case!(rbtdrc_srjcl_jupyter_connectivity),
    case!(rbtdrc_srjcl_websocket_kernel),
];

pub static RBTDRC_CASES_PLUML: &[rbtdre_Case] = &[
    case!(rbtdrc_pluml_text_rendering),
    case!(rbtdrc_pluml_local_diagram),
    case!(rbtdrc_pluml_http_headers),
    case!(rbtdrc_pluml_invalid_hash),
    case!(rbtdrc_pluml_malformed_diagram),
    case!(rbtdrc_pluml_render_diagrams),
];

// Bottle/sentry security cases — shared by RBTDRC_FIXTURE_TADMOR and
// RBTDRC_FIXTURE_MORIAH. The engine surfaces fixture identity in its own output.
static RBTDRC_CASES_SECURITY: &[rbtdre_Case] = &[
    case!(rbtdrc_pentacle_dnsmasq_responds),
    case!(rbtdrc_pentacle_ping_sentry),
    case!(rbtdrc_ifrit_dns_allowed),
    case!(rbtdrc_ifrit_dns_allowed_example_org),
    case!(rbtdrc_ifrit_dns_blocked),
    case!(rbtdrc_ifrit_apt_blocked),
    case!(rbtdrc_ifrit_dns_nonexistent),
    case!(rbtdrc_ifrit_dns_tcp),
    case!(rbtdrc_ifrit_dns_udp),
    case!(rbtdrc_ifrit_dns_block_direct),
    case!(rbtdrc_ifrit_dns_block_altport),
    case!(rbtdrc_ifrit_dns_block_cloudflare),
    case!(rbtdrc_ifrit_dns_block_quad9),
    case!(rbtdrc_ifrit_dns_block_zonetransfer),
    case!(rbtdrc_ifrit_dns_block_ipv6),
    case!(rbtdrc_ifrit_dns_block_multicast),
    case!(rbtdrc_ifrit_dns_block_spoofing),
    case!(rbtdrc_ifrit_dns_block_tunneling),
    case!(rbtdrc_sentry_iptables_loaded),
    case!(rbtdrc_sentry_config_rp_filter),
    case!(rbtdrc_sentry_config_prerouting_dnat),
    case!(rbtdrc_sentry_config_postrouting_masquerade),
    case!(rbtdrc_sentry_config_forward_estab_related),
    case!(rbtdrc_dns_blocked_with_observation),
    case!(rbtdrc_tcp443_allow_example),
    case!(rbtdrc_tcp443_block_google),
    case!(rbtdrc_icmp_first_hop),
    case!(rbtdrc_icmp_second_hop_blocked),
    case!(rbtdrc_udp_non_dns_blocked),
    case!(rbtdrc_cidr_all_ports_allowed),
    case!(rbtdrc_sortie_dns_exfil_subdomain),
    case!(rbtdrc_sortie_meta_cloud_endpoint),
    case!(rbtdrc_sortie_net_forbidden_cidr),
    case!(rbtdrc_sortie_direct_sentry_probe),
    case!(rbtdrc_sortie_icmp_exfil_payload),
    case!(rbtdrc_sortie_net_ipv6_escape),
    case!(rbtdrc_sortie_net_srcip_spoof),
    case!(rbtdrc_sortie_net_srcip_spoof_external),
    case!(rbtdrc_sortie_proto_smuggle_rawsock),
    case!(rbtdrc_sortie_net_fragment_evasion),
    case!(rbtdrc_sortie_direct_arp_poison),
    case!(rbtdrc_sortie_ns_capability_escape),
    case!(rbtdrc_sortie_dns_rebinding),
    case!(rbtdrc_sortie_proc_sys_write),
    case!(rbtdrc_sortie_http_end_to_end),
    case!(rbtdrc_sortie_conntrack_spoofed_ack),
    case!(rbtdrc_sortie_offpath_blocked_dest),
    case!(rbtdrc_sortie_conntrack_pipeline_selfcheck),
    case!(rbtdrc_sortie_sentry_udp_non_dns),
    case!(rbtdrc_sortie_net_route_manipulation),
    case!(rbtdrc_sortie_net_enclave_subnet_escape),
    case!(rbtdrc_sortie_net_dnat_entry_reflection),
    case!(rbtdrc_coordinated_arp_gratuitous),
    case!(rbtdrc_coordinated_arp_gateway_poison),
    case!(rbtdrc_coordinated_arp_table_stability),
    case!(rbtdrc_coordinated_sentry_integrity),
    case!(rbtdrc_coordinated_dns_cache_integrity),
    case!(rbtdrc_coordinated_mac_flood_resilience),
    case!(rbtdrc_coordinated_tcp_rst_hijack),
    case!(rbtdrc_coordinated_sentry_egress_lockdown),
    case!(rbtdrc_coordinated_dnsmasq_query_audit),
];


// ── Crucible-free unit tests ─────────────────────────────────
//
// zrbtdrc_darken_svg is a pure function of the rendered bytes, so its
// correctness is proven here without charging a crucible — distinct from the
// crucible case, which proves the PlantUML server renders well-formed SVG.

#[cfg(test)]
mod rbtdrc_tests {
    use super::*;

    #[test]
    fn zrbtdrc_darken_svg_maps_the_surveyed_palette() {
        let light = concat!(
            r##"<svg style="width:10px;height:10px;background:#FFFFFF;">"##,
            r##"<text fill="#000000">x</text>"##,
            r##"<line style="stroke:#181818;"/>"##,
            r##"<rect fill="#E2E2F0"/><rect fill="#FEFFDD"/><rect fill="#EEEEEE"/></svg>"##,
        );
        let dark = zrbtdrc_darken_svg(light);

        // Page background dropped to transparent.
        assert!(dark.contains("background:transparent;"));
        assert!(!dark.contains("background:#FFFFFF;"));

        // Every surveyed light color is gone, replaced by its dark mapping —
        // and the map reaches colors inside style="..." strings, not just
        // fill="..."/stroke="..." attributes (blunt hex substitution).
        assert!(!dark.contains("#000000") && dark.contains("#E6E6E6"));
        assert!(!dark.contains("#181818") && dark.contains("#9DA5B4"));
        assert!(!dark.contains("#E2E2F0") && dark.contains("#3B3B54"));
        assert!(!dark.contains("#FEFFDD") && dark.contains("#48421F"));
        assert!(!dark.contains("#EEEEEE") && dark.contains("#2B2B2B"));
    }

    #[test]
    fn zrbtdrc_darken_svg_passes_unsurveyed_colors_through() {
        // A color outside the surveyed palette is left untouched — the membrane
        // is characterized, not a guess-everything recolor.
        let light = r##"<rect fill="#AB12CD"/>"##;
        assert_eq!(zrbtdrc_darken_svg(light), light);
    }
}
