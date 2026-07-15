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
# BUTCYM - Yelp module test cases for BUK self-test
#
# Exercises buym_yelp.sh: diastema markers, yawp functions,
# buyf_format_yawp resolver, configurators, and buh semantic
# line functions.  Pure local — no GCP, no containers.

set -euo pipefail

######################################################################
# Helpers — each runs in a subshell via zbuto_invoke

zbutcym_cmd_resolve() {
  buyc_unconditional
  zbuym_kindle
  buyy_cmd_yawp "git status"
  buyf_format_yawp "" "${z_buym_yelp}"
  printf '%b' "${z_buym_format}" >&2
}

zbutcym_link_osc8() {
  buyc_unconditional
  zbuym_kindle
  buyy_link_yawp "https://example.com" "Depot"
  buyf_format_yawp "" "${z_buym_yelp}"
  printf '%b' "${z_buym_format}" >&2
}

zbutcym_link_fallback() {
  export BURD_NO_HYPERLINKS=1
  buyc_unconditional
  zbuym_kindle
  buyy_link_yawp "https://example.com" "Depot"
  buyf_format_yawp "" "${z_buym_yelp}"
  printf '%b' "${z_buym_format}" >&2
}

zbutcym_ambient_preservation() {
  buyc_unconditional
  zbuym_kindle
  buyy_cmd_yawp "test"
  buyf_format_yawp "\033[1;33m" "${z_buym_yelp}"
  printf '%b' "${z_buym_format}" >&2
}

zbutcym_fast_path() {
  buyc_unconditional
  zbuym_kindle
  buyf_format_yawp "" "plain text no markers"
  printf '%b' "${z_buym_format}" >&2
}

zbutcym_multi_markers() {
  buyc_unconditional
  zbuym_kindle
  buyy_link_yawp "https://example.com" "Vessel"
  local z_vessel="${z_buym_yelp}"
  buyy_link_yawp "https://example.com" "Depot"
  local z_depot="${z_buym_yelp}"
  buyy_cmd_yawp "run"
  local z_cmd="${z_buym_yelp}"
  buyf_format_yawp "" "A ${z_vessel} in a ${z_depot} via ${z_cmd}."
  printf '%b' "${z_buym_format}" >&2
}

zbutcym_plain_mode() {
  buyc_plain
  zbuym_kindle
  buyy_cmd_yawp "test"
  buyf_format_yawp "" "${z_buym_yelp}"
  printf '%b' "${z_buym_format}" >&2
}

zbutcym_gray_color() {
  buyc_unconditional
  zbuym_kindle
  printf '%b' "[${BUYC_GRAY}]" >&2
}

zbutcym_gray_plain() {
  buyc_plain
  zbuym_kindle
  printf '%b' "[${BUYC_GRAY}]" >&2
}

zbutcym_strip_cmd() {
  # color ON — strip must ignore terminal mode
  buyc_unconditional
  zbuym_kindle
  buyy_cmd_yawp "git status"
  buyf_strip_yawp "Run ${z_buym_yelp} now"
  printf '%b' "${z_buym_format}" >&2
}

zbutcym_strip_link() {
  buyc_unconditional
  zbuym_kindle
  buyy_link_yawp "https://example.com" "Depot"
  buyf_strip_yawp "See ${z_buym_yelp}."
  printf '%b' "${z_buym_format}" >&2
}

zbutcym_strip_href() {
  buyc_unconditional
  zbuym_kindle
  buyy_href_yawp "https://example.com" "Docs"
  buyf_strip_yawp "${z_buym_yelp}"
  printf '%b' "${z_buym_format}" >&2
}

zbutcym_strip_fast_path() {
  buyc_unconditional
  zbuym_kindle
  buyf_strip_yawp "plain text no markers"
  printf '%b' "${z_buym_format}" >&2
}

# Cold buc_die: buym sourced (by butt_testbench) but NOT kindled here.
# buc_die must kindle buym lazily via the zbuc_print sentinel, render the
# gray operation sigil, and never dereference an unset BUYC_* readonly
# under set -u.  The nested subshell contains buc_die's exit 1 so the
# helper returns normally and zbuto_invoke captures the rendered stderr.
zbutcym_cold_die() {
  buyc_unconditional
  buc_context "cold-ctx"
  ( buc_die "cold boom" ) || true
  printf 'survived\n' >&2
}

zbutcym_cold_die_plain() {
  buyc_plain
  buc_context "cold-ctx"
  ( buc_die "cold boom" ) || true
  printf 'survived\n' >&2
}

######################################################################
# Test cases

butcym_cmd_resolve_tcase() {
  buto_trace "buyy_cmd_yawp: CMD diastema resolves to cyan ANSI"
  zbuto_invoke zbutcym_cmd_resolve
  buto_fatal_on_error "${ZBUTO_STATUS}" "cmd resolve failed" "STDERR: ${ZBUTO_STDERR}"
  local z_cyan
  z_cyan=$(printf '\033[36m')
  case "${ZBUTO_STDERR}" in
    *"${z_cyan}git status"*) ;;
    *) buto_fatal "Cyan escape not found around 'git status'" "Got: ${ZBUTO_STDERR}" ;;
  esac
  # Verify no diastema bytes survive
  case "${ZBUTO_STDERR}" in
    *$'\x02'*) buto_fatal "Diastema byte survived in output" "Got: ${ZBUTO_STDERR}" ;;
    *) ;;
  esac
}

butcym_link_osc8_tcase() {
  buto_trace "buyy_link_yawp: LINK diastema resolves to OSC-8 hyperlink"
  zbuto_invoke zbutcym_link_osc8
  buto_fatal_on_error "${ZBUTO_STATUS}" "link osc8 failed" "STDERR: ${ZBUTO_STDERR}"
  local z_osc
  z_osc=$(printf '\033]8;;')
  case "${ZBUTO_STDERR}" in
    *"${z_osc}https://example.com#Depot"*) ;;
    *) buto_fatal "OSC-8 URL not found" "Got: ${ZBUTO_STDERR}" ;;
  esac
  case "${ZBUTO_STDERR}" in
    *"Depot"*) ;;
    *) buto_fatal "Display text 'Depot' not found" "Got: ${ZBUTO_STDERR}" ;;
  esac
}

butcym_link_fallback_tcase() {
  buto_trace "buyy_link_yawp: BURD_NO_HYPERLINKS falls back to angle-bracket URL"
  zbuto_invoke zbutcym_link_fallback
  buto_fatal_on_error "${ZBUTO_STATUS}" "link fallback failed" "STDERR: ${ZBUTO_STDERR}"
  case "${ZBUTO_STDERR}" in
    *"<https://example.com#Depot>"*) ;;
    *) buto_fatal "Fallback angle-bracket URL not found" "Got: ${ZBUTO_STDERR}" ;;
  esac
  local z_osc
  z_osc=$(printf '\033]8;;')
  case "${ZBUTO_STDERR}" in
    *"${z_osc}"*) buto_fatal "OSC-8 should not appear in fallback mode" ;;
    *) ;;
  esac
}

butcym_ambient_preservation_tcase() {
  buto_trace "buyf_format_yawp: DIASTEMA_END restores ambient color, not terminal default"
  zbuto_invoke zbutcym_ambient_preservation
  buto_fatal_on_error "${ZBUTO_STATUS}" "ambient preservation failed" "STDERR: ${ZBUTO_STDERR}"
  # After the CMD region closes, the ambient (bright yellow) should appear
  local z_yellow
  z_yellow=$(printf '\033[1;33m')
  local z_cyan
  z_cyan=$(printf '\033[36m')
  # Pattern: cyan "test" then ambient yellow (not reset)
  case "${ZBUTO_STDERR}" in
    *"${z_cyan}test${z_yellow}"*) ;;
    *) buto_fatal "Ambient color not restored after DIASTEMA_END" "Got: ${ZBUTO_STDERR}" ;;
  esac
}

butcym_fast_path_tcase() {
  buto_trace "buyf_format_yawp: no diastema markers takes fast path"
  zbuto_invoke zbutcym_fast_path
  buto_fatal_on_error "${ZBUTO_STATUS}" "fast path failed" "STDERR: ${ZBUTO_STDERR}"
  case "${ZBUTO_STDERR}" in
    *"plain text no markers"*) ;;
    *) buto_fatal "Plain text not found in output" "Got: ${ZBUTO_STDERR}" ;;
  esac
  case "${ZBUTO_STDERR}" in
    *$'\x02'*) buto_fatal "Diastema byte in fast-path output" "Got: ${ZBUTO_STDERR}" ;;
    *) ;;
  esac
}

butcym_multi_markers_tcase() {
  buto_trace "buyf_format_yawp: multiple links and cmd in one string all resolve"
  zbuto_invoke zbutcym_multi_markers
  buto_fatal_on_error "${ZBUTO_STATUS}" "multi markers failed" "STDERR: ${ZBUTO_STDERR}"
  local z_osc
  z_osc=$(printf '\033]8;;')
  local z_cyan
  z_cyan=$(printf '\033[36m')
  # Two OSC-8 links (Vessel and Depot)
  local z_count=0
  local z_tmp="${ZBUTO_STDERR}"
  while test "${z_tmp}" != "${z_tmp#*"${z_osc}"}"; do
    z_count=$((z_count + 1))
    z_tmp="${z_tmp#*"${z_osc}"}"
  done
  # Each link has two OSC-8 sequences (open + close), so 2 links = 4 occurrences
  test "${z_count}" -ge 4 || buto_fatal "Expected at least 4 OSC-8 sequences for 2 links, got ${z_count}"
  # CMD marker resolved
  case "${ZBUTO_STDERR}" in
    *"${z_cyan}run"*) ;;
    *) buto_fatal "CMD marker not resolved" "Got: ${ZBUTO_STDERR}" ;;
  esac
  # No diastema survivors
  case "${ZBUTO_STDERR}" in
    *$'\x02'*) buto_fatal "Diastema byte survived in multi-marker output" ;;
    *) ;;
  esac
}

butcym_plain_mode_tcase() {
  buto_trace "buyc_plain: no ANSI escapes in output"
  zbuto_invoke zbutcym_plain_mode
  buto_fatal_on_error "${ZBUTO_STATUS}" "plain mode failed" "STDERR: ${ZBUTO_STDERR}"
  case "${ZBUTO_STDERR}" in
    *$'\033'*) buto_fatal "ESC byte found in plain mode output" "Got: ${ZBUTO_STDERR}" ;;
    *) ;;
  esac
  case "${ZBUTO_STDERR}" in
    *"test"*) ;;
    *) buto_fatal "Content 'test' not found in plain mode output" "Got: ${ZBUTO_STDERR}" ;;
  esac
  case "${ZBUTO_STDERR}" in
    *$'\x02'*) buto_fatal "Diastema byte survived in plain mode" ;;
    *) ;;
  esac
}

butcym_gray_color_tcase() {
  buto_trace "BUYC_GRAY: resolves to ANSI gray in color mode"
  zbuto_invoke zbutcym_gray_color
  buto_fatal_on_error "${ZBUTO_STATUS}" "gray color failed" "STDERR: ${ZBUTO_STDERR}"
  local z_gray
  z_gray=$(printf '\033[90m')
  case "${ZBUTO_STDERR}" in
    *"[${z_gray}]"*) ;;
    *) buto_fatal "Gray ANSI not found" "Got: ${ZBUTO_STDERR}" ;;
  esac
}

butcym_gray_plain_tcase() {
  buto_trace "BUYC_GRAY: empty when color is off"
  zbuto_invoke zbutcym_gray_plain
  buto_fatal_on_error "${ZBUTO_STATUS}" "gray plain failed" "STDERR: ${ZBUTO_STDERR}"
  case "${ZBUTO_STDERR}" in
    *"[]"*) ;;
    *) buto_fatal "Gray should be empty in plain mode" "Got: ${ZBUTO_STDERR}" ;;
  esac
  case "${ZBUTO_STDERR}" in
    *$'\033'*) buto_fatal "ESC byte in plain-mode gray" "Got: ${ZBUTO_STDERR}" ;;
    *) ;;
  esac
}

butcym_strip_cmd_tcase() {
  buto_trace "buyf_strip_yawp: CMD marker strips to bare text, ignores color mode"
  zbuto_invoke zbutcym_strip_cmd
  buto_fatal_on_error "${ZBUTO_STATUS}" "strip cmd failed" "STDERR: ${ZBUTO_STDERR}"
  case "${ZBUTO_STDERR}" in
    *"Run git status now"*) ;;
    *) buto_fatal "Stripped text not found" "Got: ${ZBUTO_STDERR}" ;;
  esac
  case "${ZBUTO_STDERR}" in
    *$'\033'*) buto_fatal "ESC byte in stripped output (must ignore color mode)" "Got: ${ZBUTO_STDERR}" ;;
    *) ;;
  esac
  case "${ZBUTO_STDERR}" in
    *$'\x02'*) buto_fatal "Diastema byte survived strip" "Got: ${ZBUTO_STDERR}" ;;
    *) ;;
  esac
}

butcym_strip_link_tcase() {
  buto_trace "buyf_strip_yawp: LINK degrades to 'text <url>' with no ANSI/OSC-8"
  zbuto_invoke zbutcym_strip_link
  buto_fatal_on_error "${ZBUTO_STATUS}" "strip link failed" "STDERR: ${ZBUTO_STDERR}"
  case "${ZBUTO_STDERR}" in
    *"See Depot <https://example.com#Depot>."*) ;;
    *) buto_fatal "Stripped link form not found" "Got: ${ZBUTO_STDERR}" ;;
  esac
  local z_osc
  z_osc=$(printf '\033]8;;')
  case "${ZBUTO_STDERR}" in
    *"${z_osc}"*) buto_fatal "OSC-8 should not appear in strip" "Got: ${ZBUTO_STDERR}" ;;
    *) ;;
  esac
  case "${ZBUTO_STDERR}" in
    *$'\033'*) buto_fatal "ESC byte in stripped link output" "Got: ${ZBUTO_STDERR}" ;;
    *) ;;
  esac
}

butcym_strip_href_tcase() {
  buto_trace "buyf_strip_yawp: HREF degrades to 'text <url>'"
  zbuto_invoke zbutcym_strip_href
  buto_fatal_on_error "${ZBUTO_STATUS}" "strip href failed" "STDERR: ${ZBUTO_STDERR}"
  case "${ZBUTO_STDERR}" in
    *"Docs <https://example.com>"*) ;;
    *) buto_fatal "Stripped href form not found" "Got: ${ZBUTO_STDERR}" ;;
  esac
  case "${ZBUTO_STDERR}" in
    *$'\033'*) buto_fatal "ESC byte in stripped href output" "Got: ${ZBUTO_STDERR}" ;;
    *) ;;
  esac
}

butcym_strip_fast_path_tcase() {
  buto_trace "buyf_strip_yawp: no diastema markers takes fast path"
  zbuto_invoke zbutcym_strip_fast_path
  buto_fatal_on_error "${ZBUTO_STATUS}" "strip fast path failed" "STDERR: ${ZBUTO_STDERR}"
  case "${ZBUTO_STDERR}" in
    *"plain text no markers"*) ;;
    *) buto_fatal "Plain text not found" "Got: ${ZBUTO_STDERR}" ;;
  esac
}

butcym_cold_die_tcase() {
  buto_trace "buc_die cold path: lazy-kindles buym, renders gray sigil, no unbound crash"
  zbuto_invoke zbutcym_cold_die
  buto_fatal_on_error "${ZBUTO_STATUS}" "cold die helper did not survive" "STDERR: ${ZBUTO_STDERR}"
  # Helper reached its marker — buc_die's exit was contained, no shell crash
  case "${ZBUTO_STDERR}" in
    *"survived"*) ;;
    *) buto_fatal "Helper did not survive buc_die" "Got: ${ZBUTO_STDERR}" ;;
  esac
  # The cold BUYC_* dereference did not trip set -u
  case "${ZBUTO_STDERR}" in
    *"unbound variable"*) buto_fatal "Cold buc_die threw unbound variable" "Got: ${ZBUTO_STDERR}" ;;
    *) ;;
  esac
  # Error body rendered
  case "${ZBUTO_STDERR}" in
    *"ERROR:"*"cold boom"*) ;;
    *) buto_fatal "buc_die error body not rendered" "Got: ${ZBUTO_STDERR}" ;;
  esac
  # Gray operation sigil resolved from the lazy kindle (BUYC_GRAY -> \033[90m)
  local z_gray
  z_gray=$(printf '\033[90m')
  case "${ZBUTO_STDERR}" in
    *"${z_gray}cold-ctx"*) ;;
    *) buto_fatal "Gray context sigil not rendered from cold kindle" "Got: ${ZBUTO_STDERR}" ;;
  esac
}

butcym_cold_die_plain_tcase() {
  buto_trace "buc_die cold path under buyc_plain: gray sigil suppressed (NO_COLOR-aware)"
  zbuto_invoke zbutcym_cold_die_plain
  buto_fatal_on_error "${ZBUTO_STATUS}" "cold die plain helper did not survive" "STDERR: ${ZBUTO_STDERR}"
  case "${ZBUTO_STDERR}" in
    *"survived"*) ;;
    *) buto_fatal "Helper did not survive buc_die (plain)" "Got: ${ZBUTO_STDERR}" ;;
  esac
  case "${ZBUTO_STDERR}" in
    *"ERROR:"*"cold boom"*) ;;
    *) buto_fatal "buc_die error body not rendered (plain)" "Got: ${ZBUTO_STDERR}" ;;
  esac
  # Gray sigil must be absent in plain mode — the terminal-awareness fix
  local z_gray
  z_gray=$(printf '\033[90m')
  case "${ZBUTO_STDERR}" in
    *"${z_gray}"*) buto_fatal "Gray sigil ANSI present under buyc_plain" "Got: ${ZBUTO_STDERR}" ;;
    *) ;;
  esac
}

# eof
