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
# Bash Utility Handbook - Always-visible user interaction output
#
# This module provides formatted output for interactive procedures where
# the user MUST see the output to proceed (OAuth flows, manual steps, etc).
# All output goes to stderr and is NOT subject to verbosity control.
#
# All display is routed through yelp-aware functions:
#   buh_line   — prose (BUYC_RESET ambient)
#   buh_code   — command/code (BUYC_CYAN ambient)
#   buh_warn   — warning (BUYC_BRIGHT_YELLOW ambient)
#   buh_error  — error (BUYC_BRIGHT_RED ambient)
#   buh_link   — OSC-8 hyperlink with prefix/suffix
#   buh_tt     — resolved tabtarget display
#
# Callers compose lines from yelp yawp captures (buyy_*_yawp)
# and pass the pre-rendered string to buh_line:
#   buyy_cmd_yawp "gcloud"; local -r z_cmd="${z_buym_yelp}"
#   buh_line "Run ${z_cmd} to authenticate."

set -euo pipefail

# Multiple inclusion guard
test -z "${ZBUH_INCLUDED:-}" || return 0
ZBUH_INCLUDED=1

######################################################################
# Internal: Kindle and Sentinel

zbuh_kindle() {
  test -z "${ZBUH_KINDLED:-}" || return 0

  # Ensure yelp module is kindled — buh_section/buh_line/buh_code use BUYC_* constants
  zbuym_sentinel

  # Color support detection
  local z_use_color=0
  if test -z "${NO_COLOR:-}" && test -n "${TERM:-}" && test "${TERM}" != "dumb"; then
    z_use_color=1
  fi

  if test "${z_use_color}" = "1"; then
    readonly ZBUH_R="${ZBUYM_ESC}[0m"          # Reset
    readonly ZBUH_E="${ZBUYM_ESC}[1;31m"       # Error (bright red)
    readonly ZBUH_S="${ZBUYM_ESC}[1;37m"       # Section (bright white)
  else
    readonly ZBUH_R=""
    readonly ZBUH_E=""
    readonly ZBUH_S=""
  fi

  # Mutable kindle state — step counters, body indent, step format
  z_buh_step1_n=0
  z_buh_step2_n=0
  z_buh_body_indent=""
  z_buh_step_prefix=""
  z_buh_step_separator=". "

  readonly ZBUH_KINDLED=1
}

zbuh_sentinel() {
  test "${ZBUH_KINDLED:-}" = "1" || { zbuh_kindle; }
}

######################################################################
# Public: Section headers and numbered steps

buh_section() { zbuh_sentinel; z_buh_body_indent=""; buyf_format_yawp "${BUYC_BRIGHT_WHITE}" "${1:-}"; printf '%s\n' "${z_buym_format}" >&2; }
buh_e()       { echo "" >&2; }

buh_step_style() {
  zbuh_sentinel
  z_buh_step_prefix="${1:-}"
  z_buh_step_separator="${2:-". "}"
}

buh_step1() {
  zbuh_sentinel
  z_buh_step1_n=$((z_buh_step1_n + 1))
  z_buh_step2_n=0
  z_buh_body_indent="   "
  buyf_format_yawp "${BUYC_BRIGHT_WHITE}" "${1:-}"
  printf '%s\n' "${ZBUH_S}${z_buh_step_prefix}${z_buh_step1_n}${z_buh_step_separator}${z_buym_format}" >&2
}

buh_step2() {
  zbuh_sentinel
  z_buh_step2_n=$((z_buh_step2_n + 1))
  z_buh_body_indent="      "
  buyf_format_yawp "${BUYC_BRIGHT_WHITE}" "${1:-}"
  printf '%s\n' "   ${ZBUH_S}${z_buh_step_prefix}${z_buh_step1_n}.${z_buh_step2_n}${z_buh_step_separator}${z_buym_format}" >&2
}

######################################################################
# Public: Hyperlinks
#
# buh_link "prefix text" "link text" "url" "suffix text"
# Renders clickable hyperlink with OSC-8 escape sequences

buh_link() {
  zbuh_sentinel
  local z_prefix="${1:-}"
  local z_text="${2:-}"
  local z_url="${3:-}"
  local z_suffix="${4:-}"

  # Blue + underline style
  local z_link_style="${ZBUYM_ESC}[34;4m"

  if test -n "${BURD_NO_HYPERLINKS:-}"; then
    # Fallback: styled text with URL in angle brackets
    printf '%s%s%s%s%s <%s>%s\n' \
      "${z_buh_body_indent}" "${z_prefix}" "${z_link_style}" "${z_text}" "${ZBUH_R}" "${z_url}" "${z_suffix}" >&2
  else
    # OSC-8 hyperlink with styling
    printf '%s%s%s\033]8;;%s\033\\%s\033]8;;\033\\%s%s\n' \
      "${z_buh_body_indent}" "${z_prefix}" "${z_link_style}" "${z_url}" "${z_text}" "${ZBUH_R}" "${z_suffix}" >&2
  fi
}

######################################################################
# Public: Yelp-aware tabtarget display
#
# buh_tt prefix colophon [imprint] [args]
#   Resolves tabtarget via yawp, displays with prefix.

buh_tt() {
  zbuh_sentinel
  buyy_tt_yawp "${2:-}" "${3:-}" "${4:-}"
  local -r z_tt="${z_buym_yelp}"
  buh_line "${1:-}${z_tt}"
}

######################################################################
# Public: Pre-composed line output
#
# buh_line string
#   Indent-aware (respects z_buh_body_indent from step context).
#   Designed for lines pre-composed from yelp capture fragments
#   via direct bash variable interpolation:
#     buh_line "A ${RBYC_DEPOT} is where images live."
#   Yelps are pre-rendered (literal ESC bytes) and must not contain %.

buh_line() {
  zbuh_sentinel
  buyf_format_yawp "${BUYC_RESET}" "${1:-}"
  printf '%s\n' "${z_buh_body_indent}${z_buym_format}" >&2
}

######################################################################
# Public: Semantic line functions
#
# Each routes through buyf_format_yawp with a BUYC_* ambient color,
# then prints via indent-aware printf.  Diastema markers in the string
# are resolved to ANSI/OSC-8 at display time.
#
# buh_line   — prose default (BUYC_RESET ambient)
# buh_code   — command/code (BUYC_CYAN ambient)
# buh_warn   — warning (BUYC_BRIGHT_YELLOW ambient)
# buh_error  — error (BUYC_BRIGHT_RED ambient)

buh_code() {
  zbuh_sentinel
  buyf_format_yawp "${BUYC_CYAN}" "${1:-}"
  printf '%s\n' "${z_buh_body_indent}${z_buym_format}" >&2
}

buh_warn() {
  zbuh_sentinel
  buyf_format_yawp "${BUYC_BRIGHT_YELLOW}" "${1:-}"
  printf '%s\n' "${z_buh_body_indent}${z_buym_format}" >&2
}

buh_error() {
  zbuh_sentinel
  buyf_format_yawp "${BUYC_BRIGHT_RED}" "${1:-}"
  printf '%s\n' "${z_buh_body_indent}${z_buym_format}" >&2
}

######################################################################
# Public: Conditional display
#
# buh_ternary condition yelp-string-if-true yelp-string-if-false
#   Displays one of two pre-composed yelp strings based on condition.
#   Condition follows test semantics: "1" is true, anything else is false.

buh_ternary() {
  zbuh_sentinel
  if test "${1:-}" = "1"; then
    buh_line "${2:-}"
  else
    buh_line "${3:-}"
  fi
}

######################################################################
# Public: User prompts
#
# Every prompt below is newline-terminated by necessity: the non-interactive
# dispatch relay forwards this stream a whole line at a time, so a partial line
# never reaches the terminal — the operator would face a blocked read with no
# visible prompt. Input is typed on the line beneath. Do not rejoin them.

# buh_prompt "prompt text"
# Displays prompt and reads user input, returns via stdout
buh_prompt() {
  zbuh_sentinel
  printf '%s\n' "${1:-}" >&2
  local z_input
  read -r z_input
  printf '%s' "${z_input}"
}

# buh_prompt_secret "prompt text"
# Like buh_prompt but suppresses terminal echo of typed/pasted input.
# Emits a trailing newline to stderr so subsequent output starts on a fresh line.
buh_prompt_secret() {
  zbuh_sentinel
  printf '%s\n' "${1:-}" >&2
  local z_input
  read -rs z_input
  printf '\n' >&2
  printf '%s' "${z_input}"
}

# buh_prompt_required "prompt text" "error message"
# Like buh_prompt but dies if input is empty
buh_prompt_required() {
  local z_input
  z_input=$(buh_prompt "${1:-}")
  if test -z "${z_input}"; then
    printf '%s\n' "${z_buh_body_indent}${ZBUH_E}ERROR:${ZBUH_R} ${2:-Input required}" >&2
    return 1
  fi
  printf '%s' "${z_input}"
}

######################################################################
# Public: Critical warnings (box format)

buh_critical() {
  zbuh_sentinel
  printf '\n' >&2
  printf '%s\n' "${z_buh_body_indent}${ZBUH_E}===============================================${ZBUH_R}" >&2
  printf '%s\n' "${z_buh_body_indent}${ZBUH_E}  CRITICAL: ${1}${ZBUH_R}" >&2
  printf '%s\n' "${z_buh_body_indent}${ZBUH_E}===============================================${ZBUH_R}" >&2
  printf '\n' >&2
}

# eof
