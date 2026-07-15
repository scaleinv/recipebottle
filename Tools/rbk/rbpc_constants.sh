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
# Recipe Bottle Proving Constants - freehold test-rig constants

set -euo pipefail

# Multiple inclusion detection
test -z "${ZRBPC_SOURCED:-}" || buc_die "Module rbpc multiply sourced - check sourcing hierarchy"
ZRBPC_SOURCED=1

# ── Freehold subject ──────────────────────────────────────────────────────
# The single durable freehold subject: the operator's standing Entra `oid` on
# the spike/freehold trust — the one real federated identity the test rig
# exercises day to day. In the identity-layers model this is the PERMANENT,
# pool-independent citizen-definition layer (name → Entra subject + mantle): it
# survives foedus re-mints and depot churn, unlike the EVOLVING foedus instance
# (workforce pool id + provider, rbrf.env) and depot instance (moniker + prefix,
# rbrd.env). A citizen's live admission is pool-scoped — the grantable
# principal:// embeds the live pool id — so a foedus re-mint re-brevets this same
# permanent subject into the new instance; the definition here does not move.
# Recorded at the federation-legs spike. Deliberately segregated in this proving
# module (test gestalt), NOT in RBCC.
RBPC_freehold_subject="unset-freehold-subject"

######################################################################
# Rust const projection (rbpc set → RBTDGC_FREEHOLD_*)

# rbpc_emit_consts() - Emit the rbpc freehold constants as Rust string consts to
# stdout via the shared buz_emit_const primitive (BUK must be kindled). The third
# peer emit source, composed after the colophons and rbcc_emit_consts by
# rbz_emit_consts. Each Rust const is RBTDGC_ + the RBPC stem (RBPC_ prefix
# stripped) uppercased — the same mechanical transform rbcc_emit_consts applies,
# so RBPC_freehold_subject lands as RBTDGC_FREEHOLD_SUBJECT with no per-entry map
# and no drift. Bash stays mixed-case; the generated Rust is SCREAMING per Rust
# convention, that casing the sole transform.
rbpc_emit_consts() {
  printf '%s\n' "// RBPC freehold test constants (rbpc_constants.sh)"

  # A single freehold subject this heat (multi-subject is deferred to the
  # federation-evolution heat), so this emits the one const directly — no loop and
  # no name-transform machinery (rbcc_emit_consts earns those over its many; one
  # const does not, per Load-Bearing Complexity). RBPC_freehold_subject ->
  # RBTDGC_FREEHOLD_SUBJECT keeps the strip-prefix-and-uppercase correspondence by
  # hand; a divergence changes the generated const name and breaks the Rust
  # consumer's compile — loud, not silent. A second const reinstates the loop.
  buz_emit_const "RBTDGC_FREEHOLD_SUBJECT" "${RBPC_freehold_subject}" \
    || buc_die "rbpc_emit_consts: emit failed for RBPC_freehold_subject"
}

# eof
