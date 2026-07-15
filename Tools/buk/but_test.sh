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
# Bash Test Utility Library - COMPATIBILITY SHIM
#
# Sources buto_operations.sh and aliases buto_* back to but_* names.
# Callers not yet migrated to buto_ can continue using but_ names.

# Multiple inclusion guard
test -z "${ZBUT_INCLUDED:-}" || return 0
ZBUT_INCLUDED=1

# Source the real implementation
ZBUT_SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
source "${ZBUT_SCRIPT_DIR}/bute_engine.sh"

# Legacy color variables
ZBUT_WHITE="${ZBUTO_WHITE}"
ZBUT_RED="${ZBUTO_RED}"
ZBUT_GREEN="${ZBUTO_GREEN}"
ZBUT_RESET="${ZBUTO_RESET}"

# Legacy function aliases
but_color()                { buto_color "$@"; }
but_section()              { buto_section "$@"; }
but_info()                 { buto_info "$@"; }
but_trace()                { buto_trace "$@"; }
but_fatal()                { buto_fatal "$@"; }
but_fatal_on_error()       { buto_fatal_on_error "$@"; }
but_fatal_on_success()     { buto_fatal_on_success "$@"; }
zbut_invoke()              { zbuto_invoke "$@"; }
but_unit_expect_ok_stdout(){ buto_unit_expect_ok_stdout "$@"; }
but_unit_expect_ok()       { buto_unit_expect_ok "$@"; }
but_unit_expect_fatal()    { buto_unit_expect_fatal "$@"; }
zbut_resolve_tabtarget()   { zbuto_resolve_tabtarget "$@"; }
but_tt_expect_ok()         { buto_tt_expect_ok "$@"; }
but_tt_expect_fatal()      { buto_tt_expect_fatal "$@"; }
but_launch_expect_ok()     { buto_launch_expect_ok "$@"; }
but_launch_expect_fatal()  { buto_launch_expect_fatal "$@"; }
zbut_case()                { zbute_tcase "$@"; }

# Legacy globals — callers may reference these after zbut_invoke
ZBUT_STDOUT=""
ZBUT_STDERR=""
ZBUT_STATUS=""

# Sync legacy globals after each invoke via wrapper
zbut_invoke() {
  zbuto_invoke "$@"
  ZBUT_STDOUT="${ZBUTO_STDOUT}"
  ZBUT_STDERR="${ZBUTO_STDERR}"
  ZBUT_STATUS="${ZBUTO_STATUS}"
}

# eof
