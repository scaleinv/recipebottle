#!/bin/bash
#
# Copyright 2026 Scale Invariant, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Author: Brad Hyslop <bhyslop@scaleinvariant.org>
#
# BUBC — BUK Bootstrap Constants
# Source-time literal constants for BUK kit layout.
# No kindle dependency — available immediately upon sourcing.

# Guard against multiple inclusion
test -z "${ZBUBC_SOURCED:-}" || return 0
ZBUBC_SOURCED=1

# Source-time literal constants.
BUBC_launchers_subdir="rbml_launchers"
BUBC_rbmn_nodes_subdir="rbmn_nodes"
BUBC_rbmu_users_subdir="rbmu_users"

# Platform identifiers (bunne_* — BURN node-regime enum sprue family).
# These values are the canonical OS-family identifiers used in BURN_PLATFORM
# enrollment and in per-tabtarget platform invariant assertions.
# BUBC_platforms_<family> tinder constants provide single source of truth so
# code refers to the identifier by family name rather than hardcoding the
# literal token at every comparison site.
BUBC_platforms_linux="bunne_linux"
BUBC_platforms_mac="bunne_mac"
BUBC_platforms_windows="bunne_windows"

# Windows OpenSSH layout — forward slashes throughout so identical strings
# work in PowerShell, terminal display, and icacls invocations.
BUBC_windows_sshd_config='C:/ProgramData/ssh/sshd_config'
BUBC_windows_admin_auth_keys='C:/ProgramData/ssh/administrators_authorized_keys'
BUBC_windows_ssh_port="22"
BUBC_windows_fw_rule_name="sshd"
BUBC_windows_fw_display_name="OpenSSH Server"

# Precision exit-code band — deliberate-rejection gate codes.
# Design position, allocation rule, and the rejected stderr-sentinel
# alternative: BCG "Precision Exit-Code Band". This block is the sole mint —
# no band code is defined anywhere else.
# An in-band exit status means a named rejection gate fired on purpose;
# exit 1 stays "imprecise death" (buc_die default). buc_die propagates
# in-band $? values unchanged (the band membrane), so existing
# `cmd || buc_die` chains carry these codes to the dispatch boundary where
# the test orchestrator asserts them in negative cases.
# Placement: clear of shell-reserved codes (2, 126, 127, 128+n signals),
# the sysexits.h range (64-78), and timeout(1)/container-runtime reserved
# codes (124-125). Curl overlaps by design: its codes topped out at 92 when
# the band was placed, but curl 8.6.0 (2024-01) minted CURLE_TOO_LARGE=100
# and 8.8.0 (2024-05) CURLE_ECH_REQUIRED=101 — on band_regime/band_enroll —
# and it grows at roughly one code a year. Re-basing was declined (zero-sum
# window under the 124 ceiling; renumbers the census; rents years only,
# while containment holds forever). Containment rule (normative): a curl
# exit status is captured and classified at the call site
# (`|| z_curl_status=$?`, then branch), never handed to the band membrane;
# a bare `curl ... || buc_die` chain is rule-barred.
# Allocation rule: one code per rejection GATE, never per validation rule.
# Gates may share a code only if they never co-occur in one test case's
# spawn path — share across alternatives, never along a pipeline.
# No band code is minted outside this block.
BUBC_band_base=100
# Terminal width: the ceiling at 124 (timeout/container-runtime codes) fixes
# the band's maximum extent at 100-123; width 24 claims that whole window, so
# the band can never widen again. When it fills, capacity comes from the
# allocation rule (share across alternatives), never from growth.
BUBC_band_width=24
# Gate codes, allocated upward from base. The regime-load pipeline crosses
# two gates in one spawn path — the buv layer (vet value checks + scope
# sentinel) and the regime module's own custom enforce rules — so per the
# allocation rule they carry distinct codes:
BUBC_band_regime=100    # regime-module custom enforce rejection (cross-field, format regex, existence)
BUBC_band_enroll=101    # buv enrollment-validation rejection (buv_vet, buv_scope_sentinel)
BUBC_band_recipe=102    # recipe validation rejection
BUBC_band_hygiene=103   # Dockerfile FROM-line hygiene rejection (rbfh)
BUBC_band_credless=104  # credless guard at token mint (reveille-tier suite invariant)
BUBC_band_chain=105     # chaining-fact resolution rejection (broken express-or-chain, or wrong-kind touchmark) — one gate, alternative firings never co-occur in a spawn path
# Foedus test-bed cardinality verbs (descry/instate). Distinct codes per the
# allocation rule: descry (pool-health probe) and instate (active-foedus
# selector rewrite) co-occur in the reuse-or-establish fixture's spawn path,
# so they may not share a code. Neither is the chaining band (105) — neither
# resolves an express-or-chain fact.
BUBC_band_descry=106    # foedus descry rejection (unresolvable foedus name, broken pool read)
BUBC_band_instate=107   # foedus instate rejection (missing/unresolvable foedus identity)
# Clean-tree gate: bug_require_clean_tree_creed refuses a dirty working tree
# (staged/unstaged). One gate, kit-agnostic; the caller's rationale (a creed)
# rides the message, never the band. Distinct code — not an alternative of any
# gate above.
BUBC_band_clean_tree=108 # clean-tree gate rejection (dirty working tree at a clean-tree-gated operation)
# Mantle admission: the don's Leg-3 403 (rba_don_capture) is a structural
# admission-deficit Palisade signature, distinct from every gate above — no
# express-or-chain fact, no regime/enrollment rule, no descry/instate
# cardinality op. One gate: a citizen not brevetted onto the wielded mantle.
BUBC_band_admission=109 # mantle admission rejection (don denied — citizen not brevetted onto the mantle)
# Read-side vacancy: a read verb (summon/plumb/augur) names an artifact that
# is not present in the registry — knowable only after a round-trip, distinct
# from the local chaining resolve (105). Plumb's spawn path crosses the
# vessel-resolve chaining gate, so the allocation rule forbids reusing 105
# along that pipeline. One gate: the named hallmark or Lode is not there.
BUBC_band_vacant=110    # read-side absent-artifact rejection (summon/plumb/augur — named hallmark or Lode not present in registry)
# Terrier data-layer gates (rbgft): each sub-operation's deliberate refusal of
# an unexpected HTTP outcome is one gate. Distinct codes per the allocation
# rule — the three sub-operations chain along one spawn path (the terrier
# proof runs engross → peruse → expunge in a single dispatch), so they may not
# share. Within a gate, sequential firings share the gate's code — the read's
# list / fetch / body-parse deficits are rules of one gate, not three gates
# (the descry precedent). The idempotent SUCCESS dispositions (engross 412,
# expunge 404) are exit-0 stdout outcomes, never band firings.
BUBC_band_engross=111   # terrier engross rejection (unexpected HTTP on the conditioned create)
BUBC_band_expunge=112   # terrier expunge rejection (unexpected HTTP on the conditioned delete)
BUBC_band_peruse=113    # terrier read rejection (list/fetch deficit or malformed muniment body; peruse and peruse_manor share the gate)
# The escheat hygiene sweep (RBSME) rides its own gate: its raw-grain survey and
# expunge deliberately bypass the muniment sub-operations above, and the verb
# never calls them, so no spawn path chains the gates — but the semantic is its
# own (a hygiene refusal, not an admission-path refusal), so it takes the last
# free code rather than sharing.
BUBC_band_escheat=114   # terrier escheat rejection (survey list/fetch deficit, raw-expunge unexpected HTTP, or folder-purge failure)
# Sitting runway floor: the avow sitting-reuse gate turns away a live sitting
# whose remaining runway is below the required floor, naming the novate remedy.
# Fires on the reuse path only (a fresh sitting has full runway by
# construction), before any leg — distinct from the credless guard (104,
# refuses acquisition outright) and the admission band (109, the don's Leg-3
# 403), and it shares no spawn path with either along a single pipeline.
BUBC_band_runway=115    # sitting-runway rejection (live sitting below the required-runway floor at reuse; novate to open a fresh one)
# Free codes: 116-122, allocated upward from 116.
# Self-test probe pins the band top, proving full-width propagation:
BUBC_band_selftest=123  # BUK self-test deliberate rejection (buw-xb fixture)

# Regime-poison tweak (BUS0 Tweak Mechanism; buost_ is BUK's reserved buo
# segment). The seam is one membrane in buv_regime_enroll — the single buv
# entry every regime kindle crosses, post-source pre-validate. Under this
# tweak name, BURE_TWEAK_VALUE names one variable to corrupt: "VAR=value"
# sets, bare "VAR" unsets. The seam applies only when VAR carries the
# enrolling scope's prefix, so a poison rides inert through the host
# regimes of a dispatch and lands exactly once, on its target.
BUBC_tweak_regime_poison="buost_regime_poison"

# Windows registry preconditions for unattended power-on posture.
# Operator-handbook step (BUSJHW Windows: Host Availability) sets these;
# bujb_invigilate_windows reads them. Single source of truth so the path
# the handbook tells the operator to set is the path invigilate queries.
# PowerShell-canonical form (HKLM:\ prefix, mixed case — registry is
# case-insensitive at the OS level so display case is purely cosmetic).
BUBC_windows_passwordless_path='HKLM:\Software\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device'
BUBC_windows_passwordless_value='DevicePasswordLessBuildVersion'
BUBC_windows_aoac_path='HKLM:\System\CurrentControlSet\Control\Power'
BUBC_windows_aoac_value='PlatformAoAcOverride'

# eof
