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
# rbcr_render.sh - Backward compatibility wrapper
#
# This module has moved to Tools/buk/bupr_regime.sh
# This wrapper provides old rbcr_* function names for existing consumers.

set -euo pipefail

# Source the actual module from BUK
ZRBCR_WRAPPER_DIR="${BASH_SOURCE[0]%/*}"
source "${BURD_BUK_DIR}/bupr_regime.sh"

# Backward-compatible function aliases
zrbcr_kindle()       { zbupr_kindle "$@"; }
zrbcr_sentinel()     { zbupr_sentinel "$@"; }
rbcr_section_begin() { bupr_section_begin "$@"; }
rbcr_section_end()   { bupr_section_end "$@"; }
rbcr_section_item()  { bupr_section_item "$@"; }
rbcr_item()          { bupr_item "$@"; }

# eof
