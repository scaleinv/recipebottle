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
# BUK Zipper - Colophon registry via parallel arrays with regime-selection channels

set -euo pipefail

# Multiple inclusion detection
test -z "${ZBUZ_SOURCED:-}" || buc_die "Module buz multiply sourced - check sourcing hierarchy"
ZBUZ_SOURCED=1

######################################################################
# Internal kindle boilerplate

zbuz_kindle() {
  test -z "${ZBUZ_KINDLED:-}" || buc_die "buz already kindled"

  # Registry rolls (populated by buz_enroll in consumer kindle, same-process only)
  z_buz_varname_roll=()
  z_buz_colophon_roll=()
  z_buz_module_roll=()
  z_buz_command_roll=()
  z_buz_channel_roll=()
  z_buz_describe_roll=()

  # Group rolls (populated by buz_group, consumed by buz_emit_context)
  z_buz_group_index_roll=()
  z_buz_group_prefix_roll=()
  z_buz_group_description_roll=()

  # Tome rolls (populated by buz_tome, consumed by buz_emit_colophon_consts and
  # buz_emit_context). A tome is a division of the shared roll — the run one
  # zipper contributes. It marks the roll index where that run begins and carries
  # the zipper's const add/strip prefixes plus a name the context emitter scopes
  # by. One level above the group: a tome holds groups, a group holds colophons.
  z_buz_tome_index_roll=()
  z_buz_tome_name_roll=()
  z_buz_tome_add_roll=()
  z_buz_tome_strip_roll=()

  readonly ZBUZ_KINDLED=1
}

######################################################################
# Internal sentinel

zbuz_sentinel() {
  test "${ZBUZ_KINDLED:-}" = "1" || buc_die "Module buz not kindled - call zbuz_kindle first"
}

######################################################################
# Internal helpers

# zbuz_resolve_tabtarget_capture() - Resolve colophon to tabtarget path
# Args: colophon
# Returns: tabtarget path or exit 1
zbuz_resolve_tabtarget_capture() {
  zbuz_sentinel

  local z_colophon="${1:-}"
  test -n "${z_colophon}" || return 1

  local z_matches=("${BURC_TABTARGET_DIR}/${z_colophon}."*.sh)

  # Bash 3.2: no-match glob returns literal — check with test -e
  test -e "${z_matches[0]}" || return 1

  # Allow multiple matches (imprinted colophons share a colophon prefix)
  # Return first match as representative
  echo "${z_matches[0]}"
}

######################################################################
# Tome declaration (registry division for multi-zipper projection)

# buz_tome() - Open a tome: the division of the shared roll one zipper owns.
# Args: name, add_prefix, strip_prefix
# Records the current roll length as this tome's start index, the same marker
# trick buz_group uses one level down. The colophon-const emitter walks each
# tome's run with that tome's add/strip prefixes, and the context emitter scopes
# its markdown to one named tome — so a roll shared by several zippers projects
# each zipper's colophons under its own const prefix without cross-leak. Call
# once per zipper, before that zipper's first buz_group/buz_enroll.
buz_tome() {
  zbuz_sentinel

  local -r z_name="${1:-}"
  local -r z_add_prefix="${2:-}"
  local -r z_strip_prefix="${3:-}"
  test -n "${z_name}"         || buc_die "buz_tome: name required"
  test -n "${z_add_prefix}"   || buc_die "buz_tome: add prefix required"
  test -n "${z_strip_prefix}" || buc_die "buz_tome: strip prefix required"

  z_buz_tome_index_roll+=("${#z_buz_colophon_roll[@]}")
  z_buz_tome_name_roll+=("${z_name}")
  z_buz_tome_add_roll+=("${z_add_prefix}")
  z_buz_tome_strip_roll+=("${z_strip_prefix}")
}

# buz_tome_declared_predicate() - True when the named tome is open in this process.
# Args: name
# A generated artifact is defined over a ROSTER of tomes, but the emitter walks
# only the tomes its caller happened to kindle — so a caller that forgets one
# produces a smaller file rather than an error, and the omission surfaces far from
# the mistake. BUK cannot hold the roster (it is kit-ignorant by charter), so it
# offers the question instead, and the generator that owns the artifact asserts
# the answer.
buz_tome_declared_predicate() {
  zbuz_sentinel

  local -r z_name="${1:-}"
  test -n "${z_name}" || buc_die "buz_tome_declared_predicate: name required"

  local z_i=0
  for z_i in "${!z_buz_tome_name_roll[@]}"; do
    test "${z_buz_tome_name_roll[${z_i}]}" = "${z_name}" && return 0
  done
  return 1
}

######################################################################
# Group declaration (category metadata for context generation)

# buz_group() - Declare a colophon group category
# Args: constant_name, prefix, description
# Stores group metadata at the current roll position for buz_emit_context.
buz_group() {
  zbuz_sentinel

  local -r z_constant="${1:-}"
  local -r z_prefix="${2:-}"
  local -r z_description="${3:-}"
  test -n "${z_constant}"    || buc_die "buz_group: constant name required"
  test -n "${z_prefix}"      || buc_die "buz_group: prefix required"
  test -n "${z_description}" || buc_die "buz_group: description required"

  z_buz_group_index_roll+=("${#z_buz_colophon_roll[@]}")
  z_buz_group_prefix_roll+=("${z_prefix}")
  z_buz_group_description_roll+=("${z_description}")
}

######################################################################
# Public enroll (kindle-only registry population)

# buz_enroll() - Register colophon tuple in parallel rolls
# Args: varname, colophon, module, command, channel, description
# All 6 arguments required. Channel: "" (none), "imprint", or "param1".
# Assigns colophon string to caller's variable via printf -v
# Side effects: populates registry rolls (must be called in same process, NOT inside $())
buz_enroll() {
  zbuz_sentinel

  test $# -eq 6 || buc_die "buz_enroll: requires 6 arguments (varname colophon module command channel description), got $#"

  local -r z_varname="${1}"
  local -r z_colophon="${2}"
  local -r z_module="${3}"
  local -r z_command="${4}"
  local -r z_channel="${5}"
  local -r z_description="${6}"
  test -n "${z_varname}"     || buc_die "buz_enroll: varname required"
  test -n "${z_colophon}"    || buc_die "buz_enroll: colophon required"
  test -n "${z_module}"      || buc_die "buz_enroll: module required"
  test -n "${z_command}"     || buc_die "buz_enroll: command required"
  test -n "${z_description}" || buc_die "buz_enroll: description required"

  # Validate channel value (empty string is valid — means no channel)
  case "${z_channel}" in
    ""|"imprint"|"param1") ;;
    *) buc_die "buz_enroll: invalid channel: ${z_channel}" ;;
  esac

  # Validate variable name
  [[ "${z_varname}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
    || buc_die "buz_enroll: invalid variable name: ${z_varname}"

  # Roll population (only persists in same-process context, lost in $() subshell)
  z_buz_varname_roll+=("${z_varname}")
  z_buz_colophon_roll+=("${z_colophon}")
  z_buz_module_roll+=("${z_module}")
  z_buz_command_roll+=("${z_command}")
  z_buz_channel_roll+=("${z_channel}")
  z_buz_describe_roll+=("${z_description}")

  # Assign colophon to caller's variable
  printf -v "${z_varname}" '%s' "${z_colophon}" || buc_die "buz_enroll: printf -v failed for ${z_varname}"
}

######################################################################
# Rust const projection (emit one pub const line per name/value pair)

# buz_emit_const() - Emit one Rust string const declaration to stdout
# Args: const_name, value
# Writes: pub const <const_name>: &str = "<value>";
# RBK-ignorant: names nothing domain-specific. Per-pair scalar interface —
# callers loop their own data and invoke once per pair (bash 3.2 has no clean
# way to pass a pair-list to a function; per-pair scalar calls are trivial).
buz_emit_const() {
  zbuz_sentinel

  local -r z_name="${1:-}"
  local -r z_value="${2:-}"
  test -n "${z_name}"  || buc_die "buz_emit_const: const name required"
  test -n "${z_value}" || buc_die "buz_emit_const: value required"

  printf 'pub const %s: &str = "%s";\n' "${z_name}" "${z_value}"
}

# buz_emit_const_i32() - Emit one Rust numeric const declaration to stdout
# Args: const_name, value
# Writes: pub const <const_name>: i32 = <value>;
# Numeric sibling of buz_emit_const for values consumers compare as integers
# (exit codes — process status lands as i32 on the Rust side). Value must be
# all digits: the band lives in 0-255 exit space, so no sign handling.
buz_emit_const_i32() {
  zbuz_sentinel

  local -r z_name="${1:-}"
  local -r z_value="${2:-}"
  test -n "${z_name}" || buc_die "buz_emit_const_i32: const name required"
  [[ "${z_value}" =~ ^[0-9]+$ ]] || buc_die "buz_emit_const_i32: all-digit value required for ${z_name}, got '${z_value}'"

  printf 'pub const %s: i32 = %s;\n' "${z_name}" "${z_value}"
}

# buz_emit_colophon_consts() - Emit Rust string consts for every enrolled
# colophon, walking each tome's run under that tome's prefixes.
# No args: the add/strip prefixes live on the tomes now (buz_tome), so one call
# projects every zipper's colophons, each under its own const prefix. For a tome
# carrying (add, strip), each const name is <add> followed by the enroll varname
# with <strip> removed; each value is the colophon string. Tomes emit in
# declaration order, separated by a blank line (none before the first), so the
# first tome's block keeps the byte position it had before tomes existed.
# RBK-ignorant: every prefix comes from a tome the caller declared. Emits the
# const lines only — the file banner is the caller's concern, since the
# generated file may concatenate several emitters' sections.
buz_emit_colophon_consts() {
  zbuz_sentinel

  (( ${#z_buz_tome_index_roll[@]} )) \
    || buc_die "buz_emit_colophon_consts: no tomes declared — call buz_tome before enrolling"

  local -r z_total="${#z_buz_colophon_roll[@]}"
  local z_t=""
  for z_t in "${!z_buz_tome_index_roll[@]}"; do
    if (( z_t > 0 )); then
      printf '%s\n' ""
    fi

    local z_start="${z_buz_tome_index_roll[z_t]}"
    local z_end="${z_total}"
    if (( z_t + 1 < ${#z_buz_tome_index_roll[@]} )); then
      z_end="${z_buz_tome_index_roll[z_t + 1]}"
    fi

    local z_add="${z_buz_tome_add_roll[z_t]}"
    local z_strip="${z_buz_tome_strip_roll[z_t]}"

    local z_i="${z_start}"
    while (( z_i < z_end )); do
      local z_stem="${z_buz_varname_roll[z_i]#"${z_strip}"}"
      buz_emit_const "${z_add}${z_stem}" "${z_buz_colophon_roll[z_i]}" \
        || buc_die "buz_emit_colophon_consts: emit failed for colophon ${z_buz_colophon_roll[z_i]}"
      z_i=$((z_i + 1))
    done
  done
}

######################################################################
# Context generation (emit markdown from registry metadata)

# buz_emit_context() - Emit one named tome's colophons as markdown, by group.
# Args: tome_name, tabtarget_dir
# Writes markdown to stdout for the named tome's run of the roll only, so a roll
# shared by several zippers never leaks another zipper's colophons into this
# tome's context file. Groups come from buz_group; descriptions from buz_enroll;
# frontispiece extracted from tabtarget filenames on disk.
buz_emit_context() {
  zbuz_sentinel

  local -r z_tome_name="${1:-}"
  local -r z_tt_dir="${2:-}"
  test -n "${z_tome_name}" || buc_die "buz_emit_context: tome name required"
  test -n "${z_tt_dir}"    || buc_die "buz_emit_context: tabtarget directory required"

  # Resolve the named tome to its [start, end) slice of the shared roll.
  local z_start=""
  local z_end="${#z_buz_colophon_roll[@]}"
  local z_t=""
  for z_t in "${!z_buz_tome_name_roll[@]}"; do
    test "${z_buz_tome_name_roll[z_t]}" = "${z_tome_name}" || continue
    z_start="${z_buz_tome_index_roll[z_t]}"
    if (( z_t + 1 < ${#z_buz_tome_index_roll[@]} )); then
      z_end="${z_buz_tome_index_roll[z_t + 1]}"
    fi
    break
  done
  test -n "${z_start}" || buc_die "buz_emit_context: unknown tome: ${z_tome_name}"

  printf '%s\n' "## Command Reference (Generated)"
  printf '%s\n' ""
  printf '%s\n' "<!-- Generated by buz_emit_context from zipper registry. Do not edit. -->"
  printf '%s\n' "<!-- Regenerate: tt/rbw-tb.Build.sh -->"
  printf '%s\n' ""
  printf '%s\n' "**Folio** is the runtime target value passed to a command (nameplate moniker, role name, etc.)."
  printf '%s\n' "The Folio column shows how each tabtarget receives it:"
  printf '%s\n' ""
  printf '%s\n' "- **imprint**: Folio is baked into the filename — one tabtarget per target (e.g., \`tt/rbw-cC.Charge.tadmor.sh\`)"
  printf '%s\n' "- **param1**: Folio is passed as a command-line argument (e.g., \`tt/rbw-cKB.KludgeBottle.sh tadmor\`)"
  printf '%s\n' "- **—**: No folio needed — standalone command"
  printf '%s\n' ""

  # Advance the group cursor past any groups that fall before this tome's start.
  local z_group_cursor=0
  while (( z_group_cursor < ${#z_buz_group_index_roll[@]} )) \
        && (( z_buz_group_index_roll[z_group_cursor] < z_start )); do
    z_group_cursor=$((z_group_cursor + 1))
  done

  local z_in_table=0
  local z_group_open=0
  local z_pending_desc=""
  local z_pending_prefix=""
  local z_i="${z_start}"

  while (( z_i < z_end )); do
    # Note (don't emit yet) the group header when we reach its starting index —
    # emission is deferred until the group's first surviving row, so a group
    # whose every colophon lacks a tabtarget on disk never prints an empty table.
    if (( z_group_cursor < ${#z_buz_group_index_roll[@]} )) \
       && (( z_i == z_buz_group_index_roll[z_group_cursor] )); then
      z_group_open=0
      z_pending_desc="${z_buz_group_description_roll[z_group_cursor]}"
      z_pending_prefix="${z_buz_group_prefix_roll[z_group_cursor]}"
      z_group_cursor=$((z_group_cursor + 1))
    fi

    # Resolve frontispiece from tabtarget filename; a colophon with no matching
    # tabtarget on disk (withheld from this tree) is omitted, not gutted.
    local z_colophon="${z_buz_colophon_roll[z_i]}"
    local z_matches=("${z_tt_dir}/${z_colophon}."*.sh)
    if ! test -e "${z_matches[0]}"; then
      z_i=$((z_i + 1))
      continue
    fi
    local z_basename="${z_matches[0]##*/}"
    local z_stem="${z_basename%.sh}"
    local z_skip=$(( ${#z_colophon} + 1 ))
    local z_after="${z_stem:z_skip}"
    local z_frontispiece="${z_after%%.*}"

    if (( ! z_group_open )); then
      if (( z_in_table )); then
        printf '%s\n' ""
      fi
      printf '### %s (`%s`)\n' "${z_pending_desc}" "${z_pending_prefix}"
      printf '%s\n' ""
      printf '%s\n' "| Colophon | Frontispiece | Folio | Purpose |"
      printf '%s\n' "|----------|-------------|-------|---------|"
      z_group_open=1
      z_in_table=1
    fi

    local z_channel="${z_buz_channel_roll[z_i]:-}"
    local z_folio_display="${z_channel:-—}"
    local z_desc="${z_buz_describe_roll[z_i]:-}"
    printf '| `%s` | %s | %s | %s |\n' "${z_colophon}" "${z_frontispiece}" "${z_folio_display}" "${z_desc}"

    z_i=$((z_i + 1))
  done

  if (( z_in_table )); then
    printf '%s\n' ""
  fi
}

######################################################################
# Healthcheck (opt-in tabtarget validation — called by consumer, not by BUK)

# buz_healthcheck() - Validate that all enrolled colophons have tabtargets on disk
# Collects every enrolled colophon lacking a tabtarget and dies with the full
# list (not first-only), so a completeness sweep names every gap in one pass.
# Call after enrollment is complete.
buz_healthcheck() {
  zbuz_sentinel

  local z_missing=()
  local z_i=""
  for z_i in "${!z_buz_colophon_roll[@]}"; do
    zbuz_resolve_tabtarget_capture "${z_buz_colophon_roll[z_i]}" >/dev/null \
      || z_missing+=("${z_buz_colophon_roll[z_i]}")
  done

  test "${#z_missing[@]}" -eq 0 || buc_die \
    "buz_healthcheck: ${#z_missing[@]} enrolled colophon(s) without a tabtarget in ${BURC_TABTARGET_DIR}/: ${z_missing[*]}"
}

######################################################################
# Lookup dispatch

# buz_exec_lookup() - Resolve colophon via registry and exec
# Args: colophon, base_dir [, extra args passed through to exec]
# Execs: BUZ_FOLIO=<folio> ${base_dir}/${module} ${command} [extra args]
# Dies if colophon not found
buz_exec_lookup() {
  zbuz_sentinel

  local z_colophon="${1:-}"
  local z_base_dir="${2:-}"
  test -n "${z_colophon}" || buc_die "buz_exec_lookup: colophon required"
  test -n "${z_base_dir}" || buc_die "buz_exec_lookup: base_dir required"
  shift 2

  # Find colophon in registry
  local z_found=""
  local z_i=""
  for z_i in "${!z_buz_colophon_roll[@]}"; do
    test "${z_buz_colophon_roll[z_i]}" = "${z_colophon}" || continue
    z_found="${z_i}"
    break
  done
  test -n "${z_found}" || buc_die "buz_exec_lookup: colophon not found: ${z_colophon}"

  # Decode folio from channel
  local z_folio=""
  local z_args=("$@")
  case "${z_buz_channel_roll[z_found]}" in
    "")
      if (( ${#z_args[@]} )); then
        buc_warn "Colophon '${z_colophon}' takes no folio; ignoring unexpected argument(s): ${z_args[*]}"
        z_args=()
      fi
      ;;
    "imprint")
      z_folio="${BURD_TOKEN_3}"
      ;;
    "param1")
      if (( ${#z_args[@]} )); then
        z_folio="${z_args[0]}"
        z_args=("${z_args[@]:1}")
      fi
      ;;
    *)
      buc_die "buz_exec_lookup: unknown channel: ${z_buz_channel_roll[z_found]}"
      ;;
  esac

  # Dispatch with folio in exec environment
  BUZ_FOLIO="${z_folio}" exec "${z_base_dir}/${z_buz_module_roll[z_found]}" "${z_buz_command_roll[z_found]}" ${z_args[@]+"${z_args[@]}"}
}

# eof
