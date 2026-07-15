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
# Bash Utility Yelp Module — Diastema wire format with yawp functions
#
# Yelp yawp functions are inert marker-stampers.  They embed non-printing
# diastema byte markers via pure string assignment into a shared group
# return variable (z_buym_yelp).  No subshells, no stdout, no stderr,
# cannot fail.
#
# All terminal capability decisions are deferred to buyf_format_yawp,
# which resolves diastema markers into ANSI color sequences and OSC-8
# hyperlinks at display time.
#
# Namespace:
#   buyy_  — yelp yawp functions (set z_buym_yelp)
#   buyc_  — configurators (set ZBUYM_CONFIG_MODE before kindle)
#   buyf_  — format yawp (set z_buym_format)
#   buym_  — module infrastructure (kindle, sentinel)
#
# Usage pattern — yawp+capture on one line via semicolon:
#   buyy_cmd_yawp "git status";            local -r z_cmd="${z_buym_yelp}"
#   buyy_link_yawp "${z_docs}" "Depot";    local -r z_depot="${z_buym_yelp}"
#   buh_line "Run ${z_cmd} to see your ${z_depot} status."
#
# Never use z_buym_yelp directly in buh_line — the semicolon form
# captures immediately, but the slot is still overwritten by the
# next yawp.  See buyy_* section for details.

set -euo pipefail

# Multiple inclusion guard
test -z "${ZBUYM_SOURCED:-}" || return 0
ZBUYM_SOURCED=1

######################################################################
# Configurators (buyc_*)
#
# Called before kindle.  Each sets ZBUYM_CONFIG_MODE flag.
# Kindle reads the mode and defines readonly BUYC_* palette.

ZBUYM_CONFIG_MODE="dispatch"

buyc_dispatch()      { ZBUYM_CONFIG_MODE="dispatch"; }
buyc_unconditional() { ZBUYM_CONFIG_MODE="unconditional"; }
buyc_plain()         { ZBUYM_CONFIG_MODE="plain"; }

######################################################################
# Module kindle — defines all constants and initializes mutable state

zbuym_kindle() {
  test -z "${ZBUYM_KINDLED:-}" || return 0

  local z_use_color=0

  case "${ZBUYM_CONFIG_MODE}" in
    unconditional)
      z_use_color=1
      ;;
    plain)
      z_use_color=0
      ;;
    dispatch|*)
      if test -z "${NO_COLOR:-}" && test -n "${TERM:-}" && test "${TERM}" != "dumb"; then
        z_use_color=1
      fi
      ;;
  esac

  # --- ESC byte constant (ANSI-C quoting) ---
  # Real ESC byte (0x1B) via $'\033'.  Avoids "\033" literal strings that
  # break under bash 5.2+ where ${var/pat/rep} interprets \\ in the
  # replacement, collapsing adjacent backslashes and corrupting ANSI
  # sequences that follow OSC-8 String Terminators.
  readonly ZBUYM_ESC=$'\033'

  # --- Public color constants (BUYC_*) ---
  if test "${z_use_color}" = "1"; then
    readonly BUYC_RESET="${ZBUYM_ESC}[0m"
    readonly BUYC_CYAN="${ZBUYM_ESC}[36m"
    readonly BUYC_MAGENTA="${ZBUYM_ESC}[35m"
    readonly BUYC_BRIGHT_YELLOW="${ZBUYM_ESC}[1;33m"
    readonly BUYC_BRIGHT_RED="${ZBUYM_ESC}[1;31m"
    readonly BUYC_BRIGHT_WHITE="${ZBUYM_ESC}[1;37m"
    readonly BUYC_LINK="${ZBUYM_ESC}[97;4m"
    readonly BUYC_HREF="${ZBUYM_ESC}[34;4m"
    readonly BUYC_GREEN="${ZBUYM_ESC}[32m"
    readonly BUYC_ORANGE="${ZBUYM_ESC}[33m"
    readonly BUYC_GRAY="${ZBUYM_ESC}[90m"
  else
    readonly BUYC_RESET=""
    readonly BUYC_CYAN=""
    readonly BUYC_MAGENTA=""
    readonly BUYC_BRIGHT_YELLOW=""
    readonly BUYC_BRIGHT_RED=""
    readonly BUYC_BRIGHT_WHITE=""
    readonly BUYC_LINK=""
    readonly BUYC_HREF=""
    readonly BUYC_GREEN=""
    readonly BUYC_ORANGE=""
    readonly BUYC_GRAY=""
  fi

  # --- Hyperlink mode ---
  local z_hyperlinks=0
  if test "${z_use_color}" = "1" && test -z "${BURD_NO_HYPERLINKS:-}"; then
    z_hyperlinks=1
  fi
  readonly ZBUYM_USE_HYPERLINKS="${z_hyperlinks}"

  # --- Diastema markers (non-printing byte sequences) ---
  # Each marker is a unique non-printing sequence that yelp yawp functions
  # stamp into strings.  buyf_format_yawp resolves them at display time.
  # Prefix byte is \x02 (STX) — \x01 (SOH) is reserved by bash internally
  # for BASH_REMATCH group delimiting and gets silently dropped from matches.
  readonly ZBUYM_DIASTEMA_CMD=$'\x02\x11'
  readonly ZBUYM_DIASTEMA_UI=$'\x02\x12'
  readonly ZBUYM_DIASTEMA_HREF_URL=$'\x02\x13'
  readonly ZBUYM_DIASTEMA_HREF_TEXT=$'\x02\x14'
  readonly ZBUYM_DIASTEMA_LINK_URL=$'\x02\x15'
  readonly ZBUYM_DIASTEMA_LINK_TEXT=$'\x02\x16'
  readonly ZBUYM_DIASTEMA_TT=$'\x02\x17'
  readonly ZBUYM_DIASTEMA_END=$'\x02\x18'
  readonly ZBUYM_DIASTEMA_PASS=$'\x02\x19'
  readonly ZBUYM_DIASTEMA_WARN=$'\x02\x1a'
  readonly ZBUYM_DIASTEMA_FAIL=$'\x02\x1b'

  # --- Mutable kindle state for yawp groups ---
  z_buym_yelp=""
  z_buym_format=""
  z_buym_tt_path=""

  readonly ZBUYM_KINDLED=1
}

zbuym_sentinel() {
  test "${ZBUYM_KINDLED:-}" = "1" || { zbuym_kindle; }
}


######################################################################
# Yelp yawp functions (buyy_*)
#
# Pure assignment to z_buym_yelp.  No stdout, no stderr, cannot fail.
# Caller MUST capture on the same line via semicolon — next yawp
# overwrites the slot.  See module header for usage pattern.

# buyy_cmd_yawp text;  local -r z_cmd="${z_buym_yelp}"
buyy_cmd_yawp() {
  zbuym_sentinel
  z_buym_yelp="${ZBUYM_DIASTEMA_CMD}${1:-}${ZBUYM_DIASTEMA_END}"
}

# buyy_ui_yawp text;  local -r z_ui="${z_buym_yelp}"
buyy_ui_yawp() {
  zbuym_sentinel
  z_buym_yelp="${ZBUYM_DIASTEMA_UI}${1:-}${ZBUYM_DIASTEMA_END}"
}

# buyy_href_yawp url display;  local -r z_href="${z_buym_yelp}"
buyy_href_yawp() {
  zbuym_sentinel
  z_buym_yelp="${ZBUYM_DIASTEMA_HREF_URL}${1:-}${ZBUYM_DIASTEMA_HREF_TEXT}${2:-}${ZBUYM_DIASTEMA_END}"
}

# buyy_link_yawp base_url anchor [display];  local -r z_link="${z_buym_yelp}"
buyy_link_yawp() {
  zbuym_sentinel
  local -r z_url="${1:-}#${2:-}"
  local -r z_display="${3:-${2:-}}"
  z_buym_yelp="${ZBUYM_DIASTEMA_LINK_URL}${z_url}${ZBUYM_DIASTEMA_LINK_TEXT}${z_display}${ZBUYM_DIASTEMA_END}"
}

# zbuym_tt_path colophon [imprint];  matched path -> z_buym_tt_path (empty on no match)
# The single colophon->tabtarget-filename glob for the kit.  Callers own the
# no-match policy (placeholder vs die) by inspecting the empty result.
zbuym_tt_path() {
  zbuym_sentinel
  local -r z_colophon="${1:-}"
  local z_matches
  if test -n "${2:-}"; then
    z_matches=("${BURD_TABTARGET_DIR}/${z_colophon}."*".${2}.sh")
  else
    z_matches=("${BURD_TABTARGET_DIR}/${z_colophon}."*)
  fi
  test -e "${z_matches[0]}" && z_buym_tt_path="${z_matches[0]}" || z_buym_tt_path=""
}

# buyy_tt_yawp colophon [imprint] [args];  local -r z_tt="${z_buym_yelp}"
buyy_tt_yawp() {
  zbuym_sentinel
  local -r z_colophon="${1:-}"
  zbuym_tt_path "${z_colophon}" "${2:-}"
  local z_path="${z_buym_tt_path}"
  if test -z "${z_path}"; then
    test -n "${2:-}" && z_path="??${z_colophon}.${2}??" || z_path="??${z_colophon}??"
  fi
  z_buym_yelp="${ZBUYM_DIASTEMA_TT}${z_path}${3:-}${ZBUYM_DIASTEMA_END}"
}

# buyy_pass_yawp text;  local -r z_pass="${z_buym_yelp}"
buyy_pass_yawp() {
  zbuym_sentinel
  z_buym_yelp="${ZBUYM_DIASTEMA_PASS}${1:-}${ZBUYM_DIASTEMA_END}"
}

# buyy_warn_yawp text;  local -r z_warn="${z_buym_yelp}"
buyy_warn_yawp() {
  zbuym_sentinel
  z_buym_yelp="${ZBUYM_DIASTEMA_WARN}${1:-}${ZBUYM_DIASTEMA_END}"
}

# buyy_fail_yawp text;  local -r z_fail="${z_buym_yelp}"
buyy_fail_yawp() {
  zbuym_sentinel
  z_buym_yelp="${ZBUYM_DIASTEMA_FAIL}${1:-}${ZBUYM_DIASTEMA_END}"
}

######################################################################
# Format yawp (buyf_*)
#
# buyf_format_yawp color string
#   The single intelligence point.  Takes a BUYC_* color constant
#   (the line's ambient color) and a diastema-marked string.
#   Sets z_buym_format with the resolved string.
#
# Resolution:
#   1. Simple markers (CMD, UI, TT) → corresponding BUYC_* color
#   2. Structured markers (HREF, LINK) → OSC-8 or fallback
#   3. All DIASTEMA_END → ambient color
#   4. Prepend ambient, append BUYC_RESET

buyf_format_yawp() {
  zbuym_sentinel
  local z_ambient="${1:-}"
  local z_str="${2:-}"

  # If string has no diastema markers, fast path
  case "${z_str}" in
    *$'\x02'*) ;;
    *)
      z_buym_format="${z_ambient}${z_str}${BUYC_RESET}"
      return 0
      ;;
  esac

  # --- Resolve structured markers first (HREF and LINK) ---
  # These have URL data between opener and text marker, so they need
  # regex extraction before simple replacement can work.

  # Process HREF markers
  local z_href_pattern="${ZBUYM_DIASTEMA_HREF_URL}([^${ZBUYM_DIASTEMA_HREF_TEXT}]*)${ZBUYM_DIASTEMA_HREF_TEXT}([^${ZBUYM_DIASTEMA_END}]*)${ZBUYM_DIASTEMA_END}"
  while [[ "${z_str}" =~ ${z_href_pattern} ]]; do
    local z_href_url="${BASH_REMATCH[1]}"
    local z_href_text="${BASH_REMATCH[2]}"
    local z_href_full="${BASH_REMATCH[0]}"
    local z_href_replacement=""
    if test "${ZBUYM_USE_HYPERLINKS}" = "1"; then
      z_href_replacement="${BUYC_HREF}${ZBUYM_ESC}]8;;${z_href_url}${ZBUYM_ESC}\\${z_href_text}${ZBUYM_ESC}]8;;${ZBUYM_ESC}\\${BUYC_RESET}${z_ambient}"
    elif test -n "${BUYC_HREF}"; then
      z_href_replacement="${BUYC_HREF}${z_href_text}${BUYC_RESET}${z_ambient} <${z_href_url}>"
    else
      z_href_replacement="${z_href_text}"
    fi
    z_str="${z_str/${z_href_full}/${z_href_replacement}}"
  done

  # Process LINK markers
  local z_link_pattern="${ZBUYM_DIASTEMA_LINK_URL}([^${ZBUYM_DIASTEMA_LINK_TEXT}]*)${ZBUYM_DIASTEMA_LINK_TEXT}([^${ZBUYM_DIASTEMA_END}]*)${ZBUYM_DIASTEMA_END}"
  while [[ "${z_str}" =~ ${z_link_pattern} ]]; do
    local z_link_url="${BASH_REMATCH[1]}"
    local z_link_text="${BASH_REMATCH[2]}"
    local z_link_full="${BASH_REMATCH[0]}"
    local z_link_replacement=""
    if test "${ZBUYM_USE_HYPERLINKS}" = "1"; then
      z_link_replacement="${BUYC_LINK}${ZBUYM_ESC}]8;;${z_link_url}${ZBUYM_ESC}\\${z_link_text}${ZBUYM_ESC}]8;;${ZBUYM_ESC}\\${BUYC_RESET}${z_ambient}"
    elif test -n "${BUYC_LINK}"; then
      z_link_replacement="${BUYC_LINK}${z_link_text}${BUYC_RESET}${z_ambient} <${z_link_url}>"
    else
      z_link_replacement="${z_link_text}"
    fi
    z_str="${z_str/${z_link_full}/${z_link_replacement}}"
  done

  # --- Resolve simple markers ---
  z_str="${z_str//${ZBUYM_DIASTEMA_CMD}/${BUYC_CYAN}}"
  z_str="${z_str//${ZBUYM_DIASTEMA_UI}/${BUYC_MAGENTA}}"
  z_str="${z_str//${ZBUYM_DIASTEMA_TT}/${BUYC_CYAN}}"
  z_str="${z_str//${ZBUYM_DIASTEMA_PASS}/${BUYC_GREEN}}"
  z_str="${z_str//${ZBUYM_DIASTEMA_WARN}/${BUYC_ORANGE}}"
  z_str="${z_str//${ZBUYM_DIASTEMA_FAIL}/${BUYC_BRIGHT_RED}}"
  z_str="${z_str//${ZBUYM_DIASTEMA_END}/${z_ambient}}"

  z_buym_format="${z_ambient}${z_str}${BUYC_RESET}"
}

# buyf_strip_yawp string
#   Plain-text sibling of buyf_format_yawp.  Takes a diastema-marked
#   string and resolves it to bare text — no ANSI color, no OSC-8
#   hyperlinks.  HREF and LINK degrade to "text <url>"; all other
#   markers vanish.  Independent of terminal mode (the kindle's color
#   decision does not gate this path), so a transcript carries neither
#   ANSI nor diastema bytes regardless of TERM.  Sets z_buym_format.

buyf_strip_yawp() {
  zbuym_sentinel
  local z_str="${1:-}"

  # If string has no diastema markers, fast path
  case "${z_str}" in
    *$'\x02'*) ;;
    *)
      z_buym_format="${z_str}"
      return 0
      ;;
  esac

  # --- Resolve structured markers first (HREF and LINK) ---
  # Degrade to "text <url>" — same regex extraction as the color path,
  # but no ANSI bracketing around the result.

  local z_href_pattern="${ZBUYM_DIASTEMA_HREF_URL}([^${ZBUYM_DIASTEMA_HREF_TEXT}]*)${ZBUYM_DIASTEMA_HREF_TEXT}([^${ZBUYM_DIASTEMA_END}]*)${ZBUYM_DIASTEMA_END}"
  while [[ "${z_str}" =~ ${z_href_pattern} ]]; do
    local z_href_url="${BASH_REMATCH[1]}"
    local z_href_text="${BASH_REMATCH[2]}"
    local z_href_full="${BASH_REMATCH[0]}"
    z_str="${z_str/${z_href_full}/${z_href_text} <${z_href_url}>}"
  done

  local z_link_pattern="${ZBUYM_DIASTEMA_LINK_URL}([^${ZBUYM_DIASTEMA_LINK_TEXT}]*)${ZBUYM_DIASTEMA_LINK_TEXT}([^${ZBUYM_DIASTEMA_END}]*)${ZBUYM_DIASTEMA_END}"
  while [[ "${z_str}" =~ ${z_link_pattern} ]]; do
    local z_link_url="${BASH_REMATCH[1]}"
    local z_link_text="${BASH_REMATCH[2]}"
    local z_link_full="${BASH_REMATCH[0]}"
    z_str="${z_str/${z_link_full}/${z_link_text} <${z_link_url}>}"
  done

  # --- Strip simple markers and ambient-restore markers to nothing ---
  z_str="${z_str//${ZBUYM_DIASTEMA_CMD}/}"
  z_str="${z_str//${ZBUYM_DIASTEMA_UI}/}"
  z_str="${z_str//${ZBUYM_DIASTEMA_TT}/}"
  z_str="${z_str//${ZBUYM_DIASTEMA_PASS}/}"
  z_str="${z_str//${ZBUYM_DIASTEMA_WARN}/}"
  z_str="${z_str//${ZBUYM_DIASTEMA_FAIL}/}"
  z_str="${z_str//${ZBUYM_DIASTEMA_END}/}"

  z_buym_format="${z_str}"
}

# eof
