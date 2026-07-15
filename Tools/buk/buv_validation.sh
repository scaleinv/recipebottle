#!/bin/bash
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
# Bash Validation Utility Library
# Compatible with Bash 3.2 (e.g., macOS default shell)

# Multiple inclusion guard
test -z "${ZBUV_INCLUDED:-}" || return 0
ZBUV_INCLUDED=1

# Literal constants — check capture output protocol markers
BUV_check_gated="gated"
BUV_check_fail="fail:"

# Source the console utility library
ZBUV_SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
source "${ZBUV_SCRIPT_DIR}/buc_command.sh"
source "${ZBUV_SCRIPT_DIR}/buym_yelp.sh"
# Band tinder + the regime-poison tweak name: buc_reject (buc_command) and the
# regime-poison seam below both reference BUBC_* constants at runtime. Sourced
# here so the dependency holds wherever buv is sourced, not only on
# launcher-dispatched paths; bubc's inclusion guard makes a re-source a no-op.
source "${ZBUV_SCRIPT_DIR}/bubc_constants.sh"

buv_file_exists() {
  local z_filepath="${1:-}"
  test -f "${z_filepath}" || buc_die "Required file not found: ${z_filepath}"
}

buv_dir_exists() {
  local z_dirpath="${1:-}"
  test -d "${z_dirpath}" || buc_die "Required directory not found: ${z_dirpath}"
}

buv_dir_empty() {
  local z_dirpath="${1:-}"
  test -d "${z_dirpath}" || buc_die "Required directory not found: ${z_dirpath}"
  local z_check_file
  z_check_file=$(mktemp)
  find "${z_dirpath}" -maxdepth 1 -mindepth 1 -print -quit > "${z_check_file}"
  test ! -s "${z_check_file}" || { rm -f "${z_check_file}"; buc_die "Directory must be empty: ${z_dirpath}"; }
  rm -f "${z_check_file}"
}

# ---------------------------------------------------------------------------
# Enrollment infrastructure
# ---------------------------------------------------------------------------

zbuv_kindle() {
  test -z "${ZBUV_KINDLED:-}" || buc_die "Module buv already kindled"

  # Enrollment rolls (9 parallel arrays)
  z_buv_scope_roll=()
  z_buv_varname_roll=()
  z_buv_type_roll=()
  z_buv_gate_var_roll=()
  z_buv_gate_val_roll=()
  z_buv_p1_roll=()
  z_buv_p2_roll=()
  z_buv_group_roll=()
  z_buv_desc_roll=()

  # Group registry rolls (4 parallel arrays, foreign-keyed by group title)
  z_buv_grp_scope_roll=()
  z_buv_grp_title_roll=()
  z_buv_grp_gate_var_roll=()
  z_buv_grp_gate_val_roll=()

  # Mutable kindle state: regime context (set by buv_regime_enroll / buv_group_enroll / buv_gate_enroll)
  z_buv_current_scope=""
  z_buv_current_group=""
  z_buv_current_group_idx=-1
  z_buv_current_gate_var=""
  z_buv_current_gate_val=""

  readonly ZBUV_KINDLED=1
}

zbuv_sentinel() {
  test "${ZBUV_KINDLED:-}" = "1" || buc_die "Module buv not kindled - call zbuv_kindle first"
}

# Test support: reset enrollment state without re-kindling
zbuv_reset_enrollment() {
  zbuv_sentinel

  # Clear enrollment rolls
  z_buv_scope_roll=()
  z_buv_varname_roll=()
  z_buv_type_roll=()
  z_buv_gate_var_roll=()
  z_buv_gate_val_roll=()
  z_buv_p1_roll=()
  z_buv_p2_roll=()
  z_buv_group_roll=()
  z_buv_desc_roll=()

  # Clear group registry rolls
  z_buv_grp_scope_roll=()
  z_buv_grp_title_roll=()
  z_buv_grp_gate_var_roll=()
  z_buv_grp_gate_val_roll=()

  # Reset regime context state
  z_buv_current_scope=""
  z_buv_current_group=""
  z_buv_current_group_idx=-1
  z_buv_current_gate_var=""
  z_buv_current_gate_val=""
}

# Regime context setters — called during kindle to establish enrollment scope

# Regime-poison seam (BUS0 Tweak Mechanism) — the one membrane in the
# regime-load path, crossed at every regime kindle post-source pre-validate.
# Under BUBC_tweak_regime_poison, BURE_TWEAK_VALUE names one variable to
# corrupt: "VAR=value" sets, bare "VAR" unsets. Applies only when VAR carries
# this scope's prefix ("${z_scope}_"), so the poison rides inert through a
# dispatch's host regimes and lands exactly once, on its target — before the
# scope's enrollments, sentinel, vet, and lock ever see the environment.
# BURE_TWEAK_NAME is the optional test-seam slot, so its presence check is
# guarded. The poison name is a bubc tinder constant sourced at module top, so
# its reference stays unguarded — a typo dies under set -u rather than silently
# matching nothing. Any other tweak occupying the slot — notably the reveille-tier
# credless guard — compares unequal here and rides inert.
zbuv_poison_apply() {
  local z_scope="${1:-}"
  test -n "${BURE_TWEAK_NAME:-}" || return 0
  test "${BURE_TWEAK_NAME}" = "${BUBC_tweak_regime_poison}" || return 0

  local z_spec="${BURE_TWEAK_VALUE:-}"
  test -n "${z_spec}" || buc_die "regime poison: BURE_TWEAK_VALUE required ('VAR=value' to set, 'VAR' to unset)"
  local z_var="${z_spec%%=*}"
  [[ "${z_var}" =~ ^[A-Z][A-Z0-9_]*$ ]] || buc_die "regime poison: invalid variable name '${z_var}'"

  case "${z_var}" in
    "${z_scope}_"*) : ;;
    *) return 0 ;;
  esac

  if test "${z_spec}" = "${z_var}"; then
    unset "${z_var}" || buc_die "regime poison: cannot unset ${z_var}"
    buc_log_args "regime poison: unset ${z_var} (scope ${z_scope})"
  else
    export "${z_var}=${z_spec#*=}" || buc_die "regime poison: cannot set ${z_var}"
    buc_log_args "regime poison: set ${z_var} (scope ${z_scope})"
  fi
}

# buv_regime_enroll SCOPE — set current enrollment scope
# Validates that SCOPE is non-empty. All subsequent enroll calls use this scope
# until another buv_regime_enroll is called.
buv_regime_enroll() {
  zbuv_sentinel

  local z_scope="${1:-}"
  test -n "${z_scope}" || buc_die "buv_regime_enroll: scope required"
  z_buv_current_scope="${z_scope}"
  z_buv_current_group=""
  z_buv_current_group_idx=-1
  z_buv_current_gate_var=""
  z_buv_current_gate_val=""

  zbuv_poison_apply "${z_scope}"
}

# buv_group_enroll TITLE — set current group context
# Creates a group registry entry. All subsequent enroll calls are tagged with
# this group title until the next buv_group_enroll call.
# Resets gate context — use buv_gate_enroll after this to gate items.
buv_group_enroll() {
  zbuv_sentinel

  test -n "${z_buv_current_scope}" || buc_die "buv_group_enroll: call buv_regime_enroll first"

  local z_title="${1:-}"
  test -n "${z_title}" || buc_die "buv_group_enroll: title required"

  z_buv_grp_scope_roll+=("${z_buv_current_scope}")
  z_buv_grp_title_roll+=("${z_title}")
  z_buv_grp_gate_var_roll+=("")
  z_buv_grp_gate_val_roll+=("")

  z_buv_current_group="${z_title}"
  z_buv_current_group_idx=$(( ${#z_buv_grp_scope_roll[@]} - 1 ))
  z_buv_current_gate_var=""
  z_buv_current_gate_val=""
}

# buv_gate_enroll GATE_VAR GATE_VAL — set gate context within current group
# All subsequent variable enrolls in this group are gated by this condition.
# Also registers the gate on the current group for render section headers.
buv_gate_enroll() {
  zbuv_sentinel

  test -n "${z_buv_current_group}" || buc_die "buv_gate_enroll: call buv_group_enroll first"

  local z_gate_var="${1:-}"
  local z_gate_val="${2:-}"
  test -n "${z_gate_var}" || buc_die "buv_gate_enroll: gate variable required"
  test -n "${z_gate_val}" || buc_die "buv_gate_enroll: gate value required"

  z_buv_current_gate_var="${z_gate_var}"
  z_buv_current_gate_val="${z_gate_val}"

  z_buv_grp_gate_var_roll[z_buv_current_group_idx]="${z_gate_var}"
  z_buv_grp_gate_val_roll[z_buv_current_group_idx]="${z_gate_val}"
}

# Internal enrollment helper — all public enroll functions delegate here
# Usage: zbuv_enroll VARNAME TYPE P1 P2 DESC
# Gate context inherited from buv_gate_enroll; group from buv_group_enroll.
zbuv_enroll() {
  zbuv_sentinel

  local z_varname="${1:-}"
  local z_type="${2:-}"
  local z_p1="${3:-}"
  local z_p2="${4:-}"
  local z_desc="${5:-}"

  test -n "${z_buv_current_scope}" || buc_die "zbuv_enroll: call buv_regime_enroll first"
  [[ "${z_varname}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || buc_die "zbuv_enroll: invalid variable name: '${z_varname}'"

  z_buv_scope_roll+=("${z_buv_current_scope}")
  z_buv_varname_roll+=("${z_varname}")
  z_buv_type_roll+=("${z_type}")
  z_buv_gate_var_roll+=("${z_buv_current_gate_var}")
  z_buv_gate_val_roll+=("${z_buv_current_gate_val}")
  z_buv_p1_roll+=("${z_p1}")
  z_buv_p2_roll+=("${z_p2}")
  z_buv_group_roll+=("${z_buv_current_group}")
  z_buv_desc_roll+=("${z_desc}")
}

# Public enrollment functions — scalar types
#
# Signature: buv_TYPE_enroll VARNAME P1 P2 "description"
# Scope from buv_regime_enroll; group from buv_group_enroll; gate from buv_gate_enroll.

buv_string_enroll() {
  local z_varname="${1:-}"
  local z_p1="${2:-}"
  local z_p2="${3:-}"
  local z_desc="${4:-}"
  zbuv_enroll "${z_varname}" "string" "${z_p1}" "${z_p2}" "${z_desc}"
}

buv_secret_enroll() {
  local z_varname="${1:-}"
  local z_p1="${2:-}"
  local z_p2="${3:-}"
  local z_desc="${4:-}"
  zbuv_enroll "${z_varname}" "secret" "${z_p1}" "${z_p2}" "${z_desc}"
}

buv_xname_enroll() {
  local z_varname="${1:-}"
  local z_p1="${2:-}"
  local z_p2="${3:-}"
  local z_desc="${4:-}"
  zbuv_enroll "${z_varname}" "xname" "${z_p1}" "${z_p2}" "${z_desc}"
}

buv_gname_enroll() {
  local z_varname="${1:-}"
  local z_p1="${2:-}"
  local z_p2="${3:-}"
  local z_desc="${4:-}"
  zbuv_enroll "${z_varname}" "gname" "${z_p1}" "${z_p2}" "${z_desc}"
}

buv_fqin_enroll() {
  local z_varname="${1:-}"
  local z_p1="${2:-}"
  local z_p2="${3:-}"
  local z_desc="${4:-}"
  zbuv_enroll "${z_varname}" "fqin" "${z_p1}" "${z_p2}" "${z_desc}"
}

buv_bool_enroll() {
  local z_varname="${1:-}"
  local z_desc="${2:-}"
  zbuv_enroll "${z_varname}" "bool" "" "" "${z_desc}"
}

buv_enum_enroll() {
  local z_varname="${1:-}"
  local z_desc="${2:-}"
  shift 2
  zbuv_enroll "${z_varname}" "enum" "$*" "" "${z_desc}"
}

buv_decimal_enroll() {
  local z_varname="${1:-}"
  local z_p1="${2:-}"
  local z_p2="${3:-}"
  local z_desc="${4:-}"
  zbuv_enroll "${z_varname}" "decimal" "${z_p1}" "${z_p2}" "${z_desc}"
}

buv_odref_enroll() {
  local z_varname="${1:-}"
  local z_desc="${2:-}"
  zbuv_enroll "${z_varname}" "odref" "" "" "${z_desc}"
}

buv_ipv4_enroll() {
  local z_varname="${1:-}"
  local z_desc="${2:-}"
  zbuv_enroll "${z_varname}" "ipv4" "" "" "${z_desc}"
}

buv_port_enroll() {
  local z_varname="${1:-}"
  local z_desc="${2:-}"
  zbuv_enroll "${z_varname}" "port" "" "" "${z_desc}"
}

# Public enrollment functions — list types

buv_list_string_enroll() {
  local z_varname="${1:-}"
  local z_p1="${2:-}"
  local z_p2="${3:-}"
  local z_desc="${4:-}"
  zbuv_enroll "${z_varname}" "list_string" "${z_p1}" "${z_p2}" "${z_desc}"
}

buv_list_ipv4_enroll() {
  local z_varname="${1:-}"
  local z_desc="${2:-}"
  zbuv_enroll "${z_varname}" "list_ipv4" "" "" "${z_desc}"
}

buv_list_gname_enroll() {
  local z_varname="${1:-}"
  local z_p1="${2:-}"
  local z_p2="${3:-}"
  local z_desc="${4:-}"
  zbuv_enroll "${z_varname}" "list_gname" "${z_p1}" "${z_p2}" "${z_desc}"
}

buv_list_cidr_enroll() {
  local z_varname="${1:-}"
  local z_desc="${2:-}"
  zbuv_enroll "${z_varname}" "list_cidr" "" "" "${z_desc}"
}

buv_list_domain_enroll() {
  local z_varname="${1:-}"
  local z_desc="${2:-}"
  zbuv_enroll "${z_varname}" "list_domain" "" "" "${z_desc}"
}

# Internal check capture — validates a single enrolled variable by roll index.
# Returns error detail on stdout (empty = pass).
# Echo "${BUV_check_gated}" when gate doesn't match (caller decides skip behavior).
# Echo "${BUV_check_fail}<detail>" on validation failure.
zbuv_check_capture() {
  zbuv_sentinel

  local z_idx="${1:-}"
  local z_varname="${z_buv_varname_roll[$z_idx]}"
  local z_type="${z_buv_type_roll[$z_idx]}"
  local z_gate_var="${z_buv_gate_var_roll[$z_idx]}"
  local z_gate_val="${z_buv_gate_val_roll[$z_idx]}"
  local z_p1="${z_buv_p1_roll[$z_idx]}"
  local z_p2="${z_buv_p2_roll[$z_idx]}"

  # Gating check — if gated and gate doesn't match, skip (pass)
  if test -n "${z_gate_var}"; then
    local z_gate_actual="${!z_gate_var:-}"
    if test "${z_gate_actual}" != "${z_gate_val}"; then
      echo "${BUV_check_gated}"
      return 0
    fi
  fi

  # Unset detection — distinguish "not set" from "set but empty"
  if test -z "${!z_varname+x}"; then
    case "${z_type}" in
      string|secret|gname)
        if test "${z_p1}" = "0"; then return 0; fi ;;
      list_string|list_ipv4|list_gname|list_cidr|list_domain)
        return 0 ;;
    esac
    echo "${BUV_check_fail}${z_varname} is not set (missing from .env?)"
    return 0
  fi

  local z_val="${!z_varname:-}"

  case "${z_type}" in

    string|secret)
      if test "${z_p1}" = "0" && test -z "${z_val}"; then
        return 0
      fi
      if test -z "${z_val}"; then
        echo "${BUV_check_fail}${z_varname} must not be empty"
        return 0
      fi
      if test "${#z_val}" -lt "${z_p1}"; then
        echo "${BUV_check_fail}${z_varname} must be at least ${z_p1} chars, got '${z_val}' (${#z_val})"
        return 0
      fi
      if test "${#z_val}" -gt "${z_p2}"; then
        echo "${BUV_check_fail}${z_varname} must be no more than ${z_p2} chars, got '${z_val}' (${#z_val})"
        return 0
      fi
      ;;

    xname)
      if test -z "${z_val}"; then
        echo "${BUV_check_fail}${z_varname} must not be empty"
        return 0
      fi
      if test "${#z_val}" -lt "${z_p1}"; then
        echo "${BUV_check_fail}${z_varname} must be at least ${z_p1} chars, got '${z_val}' (${#z_val})"
        return 0
      fi
      if test "${#z_val}" -gt "${z_p2}"; then
        echo "${BUV_check_fail}${z_varname} must be no more than ${z_p2} chars, got '${z_val}' (${#z_val})"
        return 0
      fi
      [[ "${z_val}" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]] || {
        echo "${BUV_check_fail}${z_varname} must start with letter and contain only letters, numbers, underscore, hyphen, got '${z_val}'"
        return 0
      }
      ;;

    gname)
      if test -z "${z_val}"; then
        if test "${z_p1}" -gt 0; then
          echo "${BUV_check_fail}${z_varname} must not be empty"
          return 0
        fi
        return 0
      fi
      if test "${#z_val}" -lt "${z_p1}"; then
        echo "${BUV_check_fail}${z_varname} must be at least ${z_p1} chars, got '${z_val}' (${#z_val})"
        return 0
      fi
      if test "${#z_val}" -gt "${z_p2}"; then
        echo "${BUV_check_fail}${z_varname} must be no more than ${z_p2} chars, got '${z_val}' (${#z_val})"
        return 0
      fi
      [[ "${z_val}" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] || {
        echo "${BUV_check_fail}${z_varname} must match ^[a-z][a-z0-9-]*[a-z0-9]$ (lowercase letters, digits, hyphens; start with a letter; end with letter/digit), got '${z_val}'"
        return 0
      }
      ;;

    fqin)
      if test -z "${z_val}"; then
        if test "${z_p1}" -gt 0; then
          echo "${BUV_check_fail}${z_varname} must not be empty"
          return 0
        fi
        return 0
      fi
      if test "${#z_val}" -lt "${z_p1}"; then
        echo "${BUV_check_fail}${z_varname} must be at least ${z_p1} chars, got '${z_val}' (${#z_val})"
        return 0
      fi
      if test "${#z_val}" -gt "${z_p2}"; then
        echo "${BUV_check_fail}${z_varname} must be no more than ${z_p2} chars, got '${z_val}' (${#z_val})"
        return 0
      fi
      [[ "${z_val}" =~ ^[a-zA-Z0-9][a-zA-Z0-9:._/@-]*$ ]] || {
        echo "${BUV_check_fail}${z_varname} must start with letter/number and contain only letters, numbers, colons, dots, underscores, hyphens, forward slashes, at-signs, got '${z_val}'"
        return 0
      }
      ;;

    bool)
      if test -z "${z_val}"; then
        echo "${BUV_check_fail}${z_varname} must not be empty"
        return 0
      fi
      if test "${z_val}" != "0" && test "${z_val}" != "1"; then
        echo "${BUV_check_fail}${z_varname} must be 0 or 1, got: '${z_val}'"
        return 0
      fi
      ;;

    enum)
      if test -z "${z_val}"; then
        echo "${BUV_check_fail}${z_varname} must not be empty"
        return 0
      fi
      local z_choice
      local z_found=0
      for z_choice in ${z_p1}; do
        if test "${z_val}" = "${z_choice}"; then
          z_found=1
          break
        fi
      done
      if test "${z_found}" = "0"; then
        echo "${BUV_check_fail}${z_varname} must be one of: ${z_p1}, got '${z_val}'"
        return 0
      fi
      ;;

    decimal)
      if test -z "${z_val}"; then
        echo "${BUV_check_fail}${z_varname} must not be empty"
        return 0
      fi
      if test "${z_val}" -ge "${z_p1}" && test "${z_val}" -le "${z_p2}"; then
        return 0
      fi
      echo "${BUV_check_fail}${z_varname} value '${z_val}' must be between ${z_p1} and ${z_p2}"
      return 0
      ;;

    odref)
      if test -z "${z_val}"; then
        echo "${BUV_check_fail}${z_varname} must not be empty"
        return 0
      fi
      local z_re='^[a-z0-9.-]+(:[0-9]{2,5})?/([a-z0-9._-]+/)*[a-z0-9._-]+@sha256:[0-9a-f]{64}$'
      [[ "${z_val}" =~ ${z_re} ]] || {
        echo "${BUV_check_fail}${z_varname} has invalid image reference format (require host[:port]/repo@sha256:<64hex>), got '${z_val}'"
        return 0
      }
      ;;

    ipv4)
      if test -z "${z_val}"; then
        echo "${BUV_check_fail}${z_varname} must not be empty"
        return 0
      fi
      [[ "${z_val}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || {
        echo "${BUV_check_fail}${z_varname} has invalid IPv4 format: '${z_val}'"
        return 0
      }
      ;;

    port)
      if test -z "${z_val}"; then
        echo "${BUV_check_fail}${z_varname} must not be empty"
        return 0
      fi
      if test "${z_val}" -ge 1 && test "${z_val}" -le 65535; then
        return 0
      fi
      echo "${BUV_check_fail}${z_varname} value '${z_val}' must be between 1 and 65535"
      return 0
      ;;

    list_string)
      local z_item
      local z_item_num=0
      for z_item in ${z_val}; do
        z_item_num=$((z_item_num + 1))
        if test "${#z_item}" -lt "${z_p1}"; then
          echo "${BUV_check_fail}${z_varname} item #${z_item_num} must be at least ${z_p1} chars, got '${z_item}' (${#z_item})"
          return 0
        fi
        if test "${#z_item}" -gt "${z_p2}"; then
          echo "${BUV_check_fail}${z_varname} item #${z_item_num} must be no more than ${z_p2} chars, got '${z_item}' (${#z_item})"
          return 0
        fi
      done
      ;;

    list_ipv4)
      local z_item
      local z_item_num=0
      for z_item in ${z_val}; do
        z_item_num=$((z_item_num + 1))
        [[ "${z_item}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || {
          echo "${BUV_check_fail}${z_varname} item #${z_item_num} has invalid IPv4 format: '${z_item}'"
          return 0
        }
      done
      ;;

    list_gname)
      local z_item
      local z_item_num=0
      for z_item in ${z_val}; do
        z_item_num=$((z_item_num + 1))
        if test "${#z_item}" -lt "${z_p1}"; then
          echo "${BUV_check_fail}${z_varname} item #${z_item_num} must be at least ${z_p1} chars, got '${z_item}' (${#z_item})"
          return 0
        fi
        if test "${#z_item}" -gt "${z_p2}"; then
          echo "${BUV_check_fail}${z_varname} item #${z_item_num} must be no more than ${z_p2} chars, got '${z_item}' (${#z_item})"
          return 0
        fi
        [[ "${z_item}" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] || {
          echo "${BUV_check_fail}${z_varname} item #${z_item_num} must match ^[a-z][a-z0-9-]*[a-z0-9]$, got '${z_item}'"
          return 0
        }
      done
      ;;

    list_cidr)
      local z_item
      local z_item_num=0
      for z_item in ${z_val}; do
        z_item_num=$((z_item_num + 1))
        [[ "${z_item}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]] || {
          echo "${BUV_check_fail}${z_varname} item #${z_item_num} has invalid CIDR format: '${z_item}'"
          return 0
        }
      done
      ;;

    list_domain)
      local z_item
      local z_item_num=0
      for z_item in ${z_val}; do
        z_item_num=$((z_item_num + 1))
        [[ "${z_item}" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]] || {
          echo "${BUV_check_fail}${z_varname} item #${z_item_num} has invalid domain format: '${z_item}'"
          return 0
        }
      done
      ;;

    *)
      echo "${BUV_check_fail}unknown type: ${z_type}"
      return 0
      ;;

  esac
}

# buv_hallmark_format VALUE — validate hallmark string matches [cbg]YYMMDDHHMMSS-rYYMMDDHHMMSS
# Returns 0 on valid, dies on invalid. Pass empty string to skip (optional fields).
buv_hallmark_format() {
  local z_val="${1:-}"
  test -n "${z_val}" || return 0
  [[ "${z_val}" =~ ^[cbg][0-9]{12}-r[0-9]{12}$ ]] \
    || buc_die "Invalid hallmark format: '${z_val}' (expected [cbg]YYMMDDHHMMSS-rYYMMDDHHMMSS)"
}

# buv_scope_sentinel SCOPE PREFIX — die if any PREFIX_ vars exist that are not enrolled in SCOPE
# Usage: buv_scope_sentinel RBRN RBRN_
buv_scope_sentinel() {
  zbuv_sentinel

  local z_scope="${1:-}"
  local z_prefix="${2:-}"
  test -n "${z_scope}"  || buc_die "buv_scope_sentinel: scope required"
  test -n "${z_prefix}" || buc_die "buv_scope_sentinel: prefix required"

  # Build lookup string from enrolled varnames for this scope
  local z_known=" "
  local z_i
  for z_i in "${!z_buv_scope_roll[@]}"; do
    test "${z_buv_scope_roll[$z_i]}" = "${z_scope}" || continue
    z_known="${z_known}${z_buv_varname_roll[$z_i]} "
  done

  # Scan environment for unexpected vars with this prefix
  local z_unexpected=()
  local z_var
  for z_var in $(compgen -v "${z_prefix}"); do
    case "${z_known}" in
      *" ${z_var} "*) : ;;
      *) z_unexpected+=("${z_var}") ;;
    esac
  done

  if test "${#z_unexpected[@]}" -gt 0; then
    buc_reject "${BUBC_band_enroll}" "Unexpected ${z_prefix}* variables not enrolled in ${z_scope}: ${z_unexpected[*]}"
  fi
}

# buv_docker_env SCOPE ARRAY_VAR — populate ARRAY_VAR with -e VARNAME=val pairs for all enrolled vars in SCOPE
# Usage: buv_docker_env RBRN ZRBRN_DOCKER_ENV
buv_docker_env() {
  zbuv_sentinel

  local z_scope="${1:-}"
  local z_array_var="${2:-}"
  test -n "${z_scope}"     || buc_die "buv_docker_env: scope required"
  test -n "${z_array_var}" || buc_die "buv_docker_env: array variable name required"
  [[ "${z_array_var}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
    || buc_die "buv_docker_env: invalid array variable name: '${z_array_var}'"

  eval "${z_array_var}=()"

  local z_i
  for z_i in "${!z_buv_scope_roll[@]}"; do
    test "${z_buv_scope_roll[$z_i]}" = "${z_scope}" || continue
    local z_varname="${z_buv_varname_roll[$z_i]}"
    local z_val="${!z_varname:-}"
    eval "${z_array_var}+=(\"-e\" \"${z_varname}=${z_val}\")"
  done
}

# buv_vet SCOPE — iterate all enrolled vars in scope; reject on first failure
# A failed value check is the buv enrollment-validation gate firing — it
# rejects with BUBC_band_enroll so negative tests can assert WHICH layer
# refused (the band expansion is unguarded on purpose: a vet failure without
# the bubc tinder dies loud, never soft).
buv_vet() {
  zbuv_sentinel

  local z_scope="${1:-}"
  test -n "${z_scope}" || buc_die "buv_vet: scope required"

  local z_i
  local z_err
  for z_i in "${!z_buv_scope_roll[@]}"; do
    test "${z_buv_scope_roll[$z_i]}" = "${z_scope}" || continue
    z_err=$(zbuv_check_capture "${z_i}")
    test -z "${z_err}" || test "${z_err}" = "${BUV_check_gated}" || buc_reject "${BUBC_band_enroll}" "${z_buv_varname_roll[$z_i]}: ${z_err#"${BUV_check_fail}"}"
  done
}

# buv_lock SCOPE — make all enrolled variables in scope readonly
# Call after enforce succeeds. Prevents downstream mutation of validated config.
buv_lock() {
  zbuv_sentinel

  local -r z_scope="${1:-}"
  test -n "${z_scope}" || buc_die "buv_lock: scope required"

  local z_i
  for z_i in "${!z_buv_scope_roll[@]}"; do
    test "${z_buv_scope_roll[$z_i]}" = "${z_scope}" || continue
    readonly "${z_buv_varname_roll[$z_i]}"
  done
}

buv_export_and_lock() {
  zbuv_sentinel

  local -r z_scope="${1:-}"
  test -n "${z_scope}" || buc_die "buv_export_and_lock: scope required"

  local z_i
  for z_i in "${!z_buv_scope_roll[@]}"; do
    test "${z_buv_scope_roll[$z_i]}" = "${z_scope}" || continue
    export "${z_buv_varname_roll[$z_i]}"
    readonly "${z_buv_varname_roll[$z_i]}"
  done
}

# buv_report SCOPE "Label" — rich per-variable display; returns non-zero if any failed
buv_report() {
  zbuv_sentinel

  local z_scope="${1:-}"
  local z_label="${2:-}"
  test -n "${z_scope}" || buc_die "buv_report: scope required"
  test -n "${z_label}" || buc_die "buv_report: label required"

  local z_any_failed=0

  buc_step "${z_label}"

  local z_i
  for z_i in "${!z_buv_scope_roll[@]}"; do
    test "${z_buv_scope_roll[$z_i]}" = "${z_scope}" || continue

    local z_varname="${z_buv_varname_roll[$z_i]}"
    local z_type="${z_buv_type_roll[$z_i]}"
    local z_val="${!z_varname:-}"
    local z_err

    # Secret redaction — replace display value before PASS/FAIL output
    local z_display_val="${z_val}"
    if test "${z_type}" = "secret" && test -n "${z_val}"; then
      z_display_val="(redacted — ${#z_val} chars)"
    fi

    z_err=$(zbuv_check_capture "${z_i}")
    if test -z "${z_err}"; then
      buc_step "  PASS  ${z_varname}=${z_display_val} [${z_type}]"
    elif test "${z_err}" = "${BUV_check_gated}"; then
      buc_step "  SKIP  ${z_varname} (gated)"
    else
      buc_step "  FAIL  ${z_varname}=${z_display_val} [${z_type}]: ${z_err#"${BUV_check_fail}"}"
      z_any_failed=1
    fi
  done

  return "${z_any_failed}"
}

# zbuv_group_gate_recite SCOPE TITLE — look up group gate from registry
# Sets ZBUV_GRP_GATE_VAR and ZBUV_GRP_GATE_VAL (empty if ungated).
zbuv_group_gate_recite() {
  local z_scope="${1:-}"
  local z_title="${2:-}"

  ZBUV_GRP_GATE_VAR=""
  ZBUV_GRP_GATE_VAL=""

  local z_s
  for z_s in "${!z_buv_grp_scope_roll[@]}"; do
    if test "${z_buv_grp_scope_roll[$z_s]}" = "${z_scope}" \
      && test "${z_buv_grp_title_roll[$z_s]}" = "${z_title}"; then
      ZBUV_GRP_GATE_VAR="${z_buv_grp_gate_var_roll[$z_s]}"
      ZBUV_GRP_GATE_VAL="${z_buv_grp_gate_val_roll[$z_s]}"
      return 0
    fi
  done
}

# zbuv_req_status INDEX — derive req/opt/cond from enrollment data
# Sets ZBUV_REQ_STATUS.
zbuv_req_status() {
  local z_idx="${1:-}"
  local z_gate_var="${z_buv_gate_var_roll[$z_idx]}"
  local z_p1="${z_buv_p1_roll[$z_idx]}"

  if test -n "${z_gate_var}"; then
    ZBUV_REQ_STATUS="cond"
  elif test "${z_p1}" = "0"; then
    ZBUV_REQ_STATUS="opt"
  else
    ZBUV_REQ_STATUS="req"
  fi
}

# buv_render SCOPE "Label" [FILE_PATH] — render all enrolled vars via bupr_ presentation
# Walks enrollment rolls grouped by group, applying group-level gates.
# Optional FILE_PATH displays a gray "File: <path>" line under the title; empty/omitted skips it.
# Requires bupr (PresentationRegime) to be kindled.
buv_render() {
  zbuv_sentinel
  zbupr_sentinel

  local z_scope="${1:-}"
  local z_label="${2:-}"
  local z_file_path="${3:-}"
  test -n "${z_scope}" || buc_die "buv_render: scope required"
  test -n "${z_label}" || buc_die "buv_render: label required"

  local z_current_group=""
  local z_i
  local z_group=""
  local z_varname=""
  local z_type=""
  local z_desc=""

  echo ""
  zbuc_tint BUYC_BRIGHT_WHITE "${z_label}"; echo "${z_buym_format}"
  if test -n "${z_file_path}"; then
    zbuc_tint BUYC_GRAY "File: ${z_file_path}"; echo "  ${z_buym_format}"
  fi
  echo ""

  for z_i in "${!z_buv_scope_roll[@]}"; do
    test "${z_buv_scope_roll[$z_i]}" = "${z_scope}" || continue

    z_group="${z_buv_group_roll[$z_i]}"
    z_varname="${z_buv_varname_roll[$z_i]}"
    z_type="${z_buv_type_roll[$z_i]}"
    z_desc="${z_buv_desc_roll[$z_i]}"

    # Group transition — close previous, open new
    if test "${z_group}" != "${z_current_group}"; then
      if test -n "${z_current_group}"; then
        bupr_section_end
      fi
      z_current_group="${z_group}"

      zbuv_group_gate_recite "${z_scope}" "${z_group}"
      if test -n "${ZBUV_GRP_GATE_VAR}"; then
        bupr_section_begin "${z_group}" "${ZBUV_GRP_GATE_VAR}" "${ZBUV_GRP_GATE_VAL}"
      else
        bupr_section_begin "${z_group}"
      fi
    fi

    zbuv_req_status "${z_i}"
    bupr_section_item "${z_varname}" "${z_type}" "${ZBUV_REQ_STATUS}" "${z_desc}"
  done

  # Close final group
  if test -n "${z_current_group}"; then
    bupr_section_end
  fi
}

# eof

