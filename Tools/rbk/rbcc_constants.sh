#!/bin/bash
#
# Copyright 2025 Scale Invariant, Inc.
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
# Recipe Bottle Common Constants - File paths and naming conventions

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBCC_SOURCED:-}" || buc_die "Module rbcc multiply sourced - check sourcing hierarchy"
ZRBCC_SOURCED=1

# Kit directory — source-time self-location. rbcc lives at the RBK kit root,
# so its own directory IS the kit dir. No launcher environment dependency;
# available the instant this file is sourced (BCG kit-self-location pattern,
# canon: rbtd/rbte_cli.sh).
readonly RBCC_KIT_DIR="${BASH_SOURCE[0]%/*}"

# Generated zipper-derived artifacts — the theurge build materializes both
# (write-on-change), rbq's gates verify them. Absolute, composed from the
# readonly kit dir (source-time, no kindle dependency).
readonly RBCC_rbtdgc_consts_file="${RBCC_KIT_DIR}/rbtd/src/rbtdgc_consts.rs"
readonly RBCC_tabtarget_context_file="${RBCC_KIT_DIR}/claude-rbk-tabtarget-context.md"

# ── Moorings inventory constants ──────────────────────────────────────────
# Moorings-relative path values. Every consumer reads these names directly
# (the transitional RBBC_* aliases were retired by the literal-sweep pace).
# Source-time literals, no kindle dependency.
RBCC_moorings_dir="rbmm_moorings"
RBCC_launchers_subdir="rbml_launchers"
RBCC_users_subdir="rbmu_users"
RBCC_nodes_subdir="rbmn_nodes"
RBCC_vessels_subdir="rbmv_vessels"
RBCC_foedera_subdir="rbmf_foedera"
# Foedera library root — the moorings subdirectory holding one rbef_ subdirectory
# per standing foedus (RBSRF). The single home for "where the foedera live": the
# library DIRECTORY is a distinct fact from any one foedus's rbrf.env, and the
# enumeration sites (canvass, the foedus-identity validator) need it as such.
# rbcc_rbrf_file_capture below composes the per-foedus file off this same root, so
# the moorings/foedera join lives here once and nowhere else.
RBCC_foedera_dir="${RBCC_moorings_dir}/${RBCC_foedera_subdir}"
RBCC_rbrr_file="${RBCC_moorings_dir}/rbrr.env"
RBCC_rbrp_file="${RBCC_moorings_dir}/rbrp.env"
RBCC_rbrm_file="${RBCC_moorings_dir}/rbrm.env"
# Workforce regime file — the manor's ONE workforce pool identity (RBSRW).
# Manor-level (axrd_singleton, one per manor), so it sits flat at the moorings
# root, a sibling of the rbmf_foedera library rather than a member of it — where
# the per-foedus rbrf.env files live. Holds the pool coordinates (org, pool id,
# session) the one-pool Model relocated out of the per-foedus federation regime.
RBCC_rbrw_file="${RBCC_moorings_dir}/rbrw.env"
# Federation regime file — resolved from the ACTIVE foedus's selector, NOT a
# source-time constant. The foedera library (RBCC_foedera_subdir) holds one
# rbef_ subdirectory per standing foedus (RBSRF); RBRR_ACTIVE_FOEDUS names the
# active one. That selector is only populated once rbrr.env is sourced during
# furnish — AFTER this module — so the path cannot be constant-folded here.
# rbcc_rbrf_file_capture (below) composes it post-rbrr; every consumer sources
# rbrf.env only after sourcing rbrr.env, so the selector is live at the call
# site. No-repo-regime contexts never call the resolver, so nothing breaks
# where RBRR_ACTIVE_FOEDUS is unset.
RBCC_rbrd_basename="rbrd.env"
RBCC_rbrd_file="${RBCC_moorings_dir}/${RBCC_rbrd_basename}"

# Literal constants (pure string literals, no variable expansion — available at source time)
RBCC_rbrn_file="rbrn.env"
RBCC_rbro_file="rbro.env"
# Vessel regime file — a bare basename, not a moorings-rooted path: the regime is
# manifold (one per vessel), so each call site composes the vessel directory from
# RBRR_VESSEL_DIR. Placement and contract are homed at the rbrv_regime quoin (RBS0).
# Sibling to the basename-style RBCC_rbrn_file / RBCC_rbro_file above.
RBCC_rbrv_file="rbrv.env"

# Account composition labels — bare fragments that compose GCP SA account-ids/
# emails AND local secret-directory names. These stay bare: a derived
# resource-name string in cloud/filesystem space, structurally like the SA
# email and the -tether/-airgap pool suffixes the heat keeps bare. The unhewn
# infix records that bareness IN THE NAME — an unhewn stone is used undressed:
# do not sprue (an underscore is forbidden in an SA-id, RFC1035) and do not
# consolidate these into the sprued mantle class. rbcc_emit_consts strips the
# unhewn_ segment on emit, so the projected RBTDGC_ACCOUNT_* names are unchanged.
RBCC_account_unhewn_governor="governor"
RBCC_account_unhewn_retriever="retriever"
RBCC_account_unhewn_director="director"
RBCC_account_unhewn_payor="payor"
RBCC_account_unhewn_mason="mason"

# Mantle service-account names — the three impersonatable federation identities
# (governor / director / retriever) established at depot levy. Hardcoded literals
# for grep. The rbma- prefix is hyphenated because a GCP service-account id admits
# only lowercase letters, digits, and hyphens (RFC1035) — the underscore sprue form
# cannot appear in this field; grep rbma still finds all three.
RBCC_account_mantle_governor="rbma-governor"
RBCC_account_mantle_director="rbma-director"
RBCC_account_mantle_retriever="rbma-retriever"

# Mantle identity tokens — THE canonical name for "which mantle to don", carried
# by every credential-mint surface (rba_token_capture / rba_don_capture, the
# rbw-am folio, and the theurge patrol) as one form, never a bare-vs-sprued
# two-form. The VALUE carries the pallium value-sprue rbpa_ so an identity token
# is self-typing under grep and can never be mistaken for an SA-id fragment: the
# underscore the sprue mandates is forbidden in a GCP SA id (RFC1035), so the
# token resolves to the mantle SA only through the rba_don_capture case and the
# raw sprued form never reaches a resource name. Distinct from the bare
# RBCC_account_mantle_* SA-name fragments above (which compose rbma-<role>@… SA
# emails); the polity/terrier bare-mantle-name uses are a separate deferred
# migration and intentionally keep the bare role word.
RBCC_mantle_governor="rbpa_governor"
RBCC_mantle_director="rbpa_director"
RBCC_mantle_retriever="rbpa_retriever"
RBCC_onboarding_nameplate="tadmor"

# Operation-verb tinder — the canonical bash home for RBK operation verbs.
# Members are bare verb tokens; the group carries one author here so it is
# projectable under the single-canonical-author rule. Two surfaces:
#
#   SA-management (defrock/enrobe/roster) — composed into the fact-extension
#   constants below; consumed by the governor/director account surface.
RBCC_verb_defrock="defrock"
RBCC_verb_enrobe="enrobe"
RBCC_verb_roster="roster"
#
#   Image/build lifecycle (anoint/drive/inscribe/kludge/ordain/yoke) — name the
#   registry and build operations. Previously implicit in command-function
#   names (rbrd_inscribe, rbfd_ordain, …) and tabtarget descriptions; homed
#   here so the group has a single owner rather than being reconstructed by
#   grep across rbfd_/rbfl_/rbfk_/rbob_/rbrn_.
RBCC_verb_anoint="anoint"
RBCC_verb_drive="drive"
RBCC_verb_inscribe="inscribe"
RBCC_verb_kludge="kludge"
RBCC_verb_ordain="ordain"
RBCC_verb_yoke="yoke"

# Creed tinder — RB convictions supplied as the rationale (creed) parameter to
# the kit-agnostic BUG clean-tree gate bug_require_clean_tree_creed, keeping the
# opinion RB-side and out of BUK. Each creed continues the gate's canonical
# grievance ("… uncommitted changes — <creed>"), so it reads as the site's
# reason for demanding a clean tree plus a commit-first directive. One creed per
# rationale family (sites sharing a rationale share a creed); the former per-verb
# gate labels retired with the malformed gate they announced. Consumed only by
# bash gate sites (no theurge assertion), so none is projected to the Rust band —
# the band itself (BUBC_band_clean_tree) is the theurge stream's assertion target.
#   clean_build   — image builds that stamp HEAD into the image (conjure, mirror, kludge)
#   clean_capture — Lode captures whose provenance envelope must be committed code (ensconce, conclave, immure, underpin)
#   clean_inscribe — the tripwire ships committed depot-regime bytes as the drift reference (inscribe)
#   clean_affiance — the seated provider must answer to a committed name (affiance)
RBCC_creed_clean_build="a container image built from an uncommitted tree cannot be traced to a commit; commit before building"
RBCC_creed_clean_capture="a Lode's provenance envelope must be the product of committed code; commit before capturing"
RBCC_creed_clean_inscribe="the tripwire ships the tracked depot-regime bytes as the depot's permanent drift reference, so the inscribed state must be committed; commit before inscribing"
RBCC_creed_clean_affiance="the seated provider must answer to a committed name — its id, redirect-URI and STS audience are read from committed federation config; commit before affiancing"

# Fact-file extension tinder — multi-fact registry for buf_write_fact_multi.
# Producers emit "<basename>.<extension>" via filesystem-as-data-bus pattern;
# consumers walk fact files in BURD_OUTPUT_DIR / BURD_TEMP_DIR keyed on extension.
# Roster extensions composed from earlier tinder (BCG tinder-on-tinder).
RBCC_fact_ext_depot="depot"
RBCC_fact_ext_depot_project="depot-project"
RBCC_fact_ext_roster_retriever="${RBCC_verb_roster}-${RBCC_account_unhewn_retriever}"
RBCC_fact_ext_roster_director="${RBCC_verb_roster}-${RBCC_account_unhewn_director}"
RBCC_fact_ext_audit_hallmark="audit-hallmark"
# Foedus descry health verdict — descry writes <foedus>.foedus-health carrying
# one of healthy / provider-absent / coordinate-drift (RBSFD provider-grain
# verdicts) for the reuse-or-establish fixture to branch on (reuse iff healthy).
RBCC_fact_ext_foedus_health="foedus-health"
# Foedus canvass census — canvass writes one <foedus>.foedus per provider under
# the manor pool (stem: the matched rbef_ library name, or the bare provider id
# when the Manor holds a provider the library does not know), carrying
# provider=/state=/selected= lines; selected marks the RBRR_ACTIVE_FOEDUS foedus.
RBCC_fact_ext_foedus="foedus"
# Sitting espy verdict — the read-only probe (rba_espy_sitting) writes
# <foedus>.sitting carrying verdict= (live / lapsed / absent) and, when the
# cache holds an expiry, runway= (whole seconds remaining) — for the theurge
# gate arc to branch on before the may-prompt baseline avow (RBS0 rbtf_espy).
RBCC_fact_ext_sitting="sitting"

# Tweak-name tinder — RB-owned BURE_TWEAK_NAME values (buo sprue, BUS0 Tweak
# Mechanism). The credless guard is the reveille-tier slot reservation: theurge
# sets it on every tabtarget a reveille-tier fixture spawns, and the Payor OAuth
# token-mint membrane (zrbgp_authenticate_capture) rejects under it with
# BUBC_band_credless — a passing reveille run can never use credentials.
RBCC_tweak_credless_guard="buorb_credless_guard"

# HTTP fault-injection seam — the regime-poison analogue for HTTP. Under this
# tweak name, BURE_TWEAK_VALUE is "INFIX=CODE": rbuh's one membrane
# (zrbuh_fault_apply in rbuh_json) overwrites the captured HTTP code for the
# named request infix, so a negative case can drive a caller's error path and
# assert its band code (the terrier gates BUBC_band_engross/expunge/peruse are
# the founding consumers).
RBCC_tweak_http_fault="buorb_http_fault"

# Mid-flight re-don cadence override. Under this tweak name, BURE_TWEAK_VALUE
# is a positive poll count replacing ZRBFC_BUILD_POLL_REDON_CADENCE at the
# build-completion poll's one membrane (zrbfc_wait_build_completion), so a
# short real build exercises the re-don tick without an hour on the clock.
RBCC_tweak_redon_cadence="buorb_redon_cadence"

# Container-role tinder — the canonical bash home for the crucible's container
# roles. Bare role tokens; the crucible is sentry + pentacle + bottle and every
# container name / compose service derives from these. Distinct from the
# RBCC_account_unhewn_* composition labels above (bare fragments for SA names +
# secret dirs). None of these words are reused across families, keeping each token
# monosemous.
RBCC_container_bottle="bottle"
RBCC_container_pentacle="pentacle"
RBCC_container_sentry="sentry"

######################################################################
# Federation regime resolver (rbcc_rbrf_file_capture)

# rbcc_rbrf_file_capture — echo the path to a foedus's rbrf.env in the moorings
# foedera library. With no argument it resolves the ACTIVE foedus from the
# RBRR_ACTIVE_FOEDUS selector (the runtime accessor path); a foedus name may be
# passed explicitly (the Entra guide names the interactive rbef_entrada it
# teaches). Returns nonzero without emitting when no foedus resolves — the
# caller's `source "$(...)" || buc_die` surfaces it. The selector is only live
# after rbrr.env is sourced, which every runtime consumer does before calling
# this; a no-repo-regime context simply never calls it. This on-demand
# resolution replaces the former source-time RBCC_rbrf_file constant — the
# deferred federation family-of-named-instances rework (RBSRF).
rbcc_rbrf_file_capture() {
  local z_foedus="${1:-${RBRR_ACTIVE_FOEDUS:-}}"
  test -n "${z_foedus}" || return 1
  printf '%s\n' "${RBCC_foedera_dir}/${z_foedus}/rbrf.env"
}

# rbcc_source_active_rbrf — resolve the ACTIVE foedus's rbrf.env from the
# selector and source it, dying loud on an unset selector or an unreadable
# file. The single home for what every runtime consumer did as the former
# `source "${RBCC_rbrf_file}"`: a furnish sources it after sourcing rbrr.env,
# so RBRR_ACTIVE_FOEDUS is live at the call. Sourcing here lands the RBRF_*
# fields in the caller's global scope exactly as an inline source would (bare
# assignments in the sourced file, sourced within a function, remain global).
rbcc_source_active_rbrf() {
  local z_rbrf
  z_rbrf=$(rbcc_rbrf_file_capture) || buc_die "No active foedus resolved — RBRR_ACTIVE_FOEDUS unset or blank"
  source "${z_rbrf}"               || buc_die "Failed to source the active foedus RBRF: ${z_rbrf}"
}

######################################################################
# Rust const projection (rbcc single-homed set → RBTDGC_)

# rbcc_emit_consts() - Emit the RBCC-owned co-maintained constants as Rust
# string consts to stdout, one `pub const` line per name/value pair via the
# shared buz_emit_const primitive (BUK must be kindled). The single-homed set:
# moorings/vessels dirs, account labels, mantle identity tokens, .env filenames,
# operation verbs, and container roles. Each Rust const is
# RBTDGC_ + the RBCC stem (RBCC_ prefix stripped) uppercased; the value is
# carried verbatim. Bash stays mixed-case (RBCC_moorings_dir); the generated
# Rust is SCREAMING (RBTDGC_MOORINGS_DIR) per Rust convention. Two mechanical
# name transforms — no per-entry mapping, no drift: the RBCC_ prefix strip +
# uppercase (universal), and a strip of the unhewn_ bare-marker infix so the
# RBCC_account_unhewn_* family projects to RBTDGC_ACCOUNT_* (the marker records
# "stay bare" in the bash name without leaking into the Rust mirror). rbtd's
# lib.rs paths, the manifest account-label mirror, and the
# rbtdrk/rbtdrp .env consts all source these instead of hand-copying.
# A second section projects the BUBC precision exit-code band as i32 consts
# (same mechanical transform, BUBC_ prefix stripped) — theurge asserts exit
# codes as integers. bubc is sourced by the launcher on every dispatch, so the
# band values are present at emission time with no cross-module tinder trick.
# A third section projects BUBC string tinder (the regime-poison tweak name)
# through the same transform via the string primitive.
rbcc_emit_consts() {
  printf '%s\n' "// RBCC constants (rbcc_constants.sh single-homed set)"

  local z_name=""
  local z_stem=""
  local z_upper=""
  for z_name in \
    RBCC_moorings_dir    \
    RBCC_vessels_subdir  \
    RBCC_account_unhewn_governor   \
    RBCC_account_unhewn_retriever  \
    RBCC_account_unhewn_director   \
    RBCC_account_unhewn_payor      \
    RBCC_account_unhewn_mason      \
    RBCC_mantle_governor    \
    RBCC_mantle_director    \
    RBCC_mantle_retriever   \
    RBCC_rbrr_file       \
    RBCC_rbrp_file       \
    RBCC_rbrm_file       \
    RBCC_rbrd_basename   \
    RBCC_rbrd_file       \
    RBCC_rbrn_file       \
    RBCC_rbro_file       \
    RBCC_rbrv_file       \
    RBCC_foedera_subdir  \
    RBCC_fact_ext_foedus_health \
    RBCC_fact_ext_foedus \
    RBCC_fact_ext_sitting \
    RBCC_verb_defrock     \
    RBCC_verb_enrobe     \
    RBCC_verb_roster     \
    RBCC_verb_anoint     \
    RBCC_verb_drive      \
    RBCC_verb_inscribe   \
    RBCC_verb_kludge     \
    RBCC_verb_ordain     \
    RBCC_verb_yoke       \
    RBCC_container_bottle    \
    RBCC_container_pentacle  \
    RBCC_container_sentry    \
    RBCC_tweak_credless_guard \
    RBCC_tweak_http_fault \
    RBCC_tweak_redon_cadence \
  ; do
    z_stem="${z_name#RBCC_}"
    z_stem="${z_stem/unhewn_/}"
    z_upper="$(printf '%s' "${z_stem}" | tr '[:lower:]' '[:upper:]')"
    buz_emit_const "RBTDGC_${z_upper}" "${!z_name}" \
      || buc_die "rbcc_emit_consts: emit failed for ${z_name}"
  done

  printf '%s\n' ""
  printf '%s\n' "// BUBC precision exit-code band (bubc_constants.sh) — numeric"
  for z_name in \
    BUBC_band_base      \
    BUBC_band_width     \
    BUBC_band_regime    \
    BUBC_band_enroll    \
    BUBC_band_recipe    \
    BUBC_band_hygiene   \
    BUBC_band_credless  \
    BUBC_band_chain     \
    BUBC_band_descry    \
    BUBC_band_instate   \
    BUBC_band_admission \
    BUBC_band_vacant    \
    BUBC_band_engross   \
    BUBC_band_expunge   \
    BUBC_band_peruse    \
    BUBC_band_runway    \
    BUBC_band_selftest  \
  ; do
    z_stem="${z_name#BUBC_}"
    z_upper="$(printf '%s' "${z_stem}" | tr '[:lower:]' '[:upper:]')"
    buz_emit_const_i32 "RBTDGC_${z_upper}" "${!z_name}" \
      || buc_die "rbcc_emit_consts: emit failed for ${z_name}"
  done

  printf '%s\n' ""
  printf '%s\n' "// BUBC regime-poison tweak (bubc_constants.sh) — string"
  z_name="BUBC_tweak_regime_poison"
  z_stem="${z_name#BUBC_}"
  z_upper="$(printf '%s' "${z_stem}" | tr '[:lower:]' '[:upper:]')"
  buz_emit_const "RBTDGC_${z_upper}" "${!z_name}" \
    || buc_die "rbcc_emit_consts: emit failed for ${z_name}"
}

######################################################################
# Internal Functions (zrbcc_*)

zrbcc_kindle() {
  test -z "${ZRBCC_KINDLED:-}" || buc_die "Module rbcc already kindled"

  # Curl timeout bounds — all actionable curl sites use these
  readonly RBCC_CURL_CONNECT_TIMEOUT_SEC=10
  readonly RBCC_CURL_MAX_TIME_SEC=60

  readonly ZRBCC_KINDLED=1
}

zrbcc_sentinel() {
  test "${ZRBCC_KINDLED:-}" = "1" || buc_die "Module rbcc not kindled - call zrbcc_kindle first"
}

# eof
