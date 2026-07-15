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
# RBLM Sterilize - lustrate a tree and regenerate its derived files, IN PLACE.
#
# Run as a whole process against one tree, never sourced. Expede invokes THE
# CANDIDATE'S OWN COPY of this script — the clone runs itself — and that is the
# whole design:
#
#   The freehold subject lives in two homes: rbpc_constants.sh, and the Rust the
#   build GENERATES from it. Regenerating the derived files from the maintainer's
#   live values would therefore write the operator's Entra oid into the candidate's
#   generated Rust no matter how thoroughly the tree was lustrated first. The
#   proscription says as much: regeneration comes AFTER lustration, and it must
#   read the lustrated values.
#
#   A process cannot read the lustrated values unless its modules ARE the lustrated
#   modules. So this script resolves every module it sources relative to its own
#   BASH_SOURCE, and works the tree that contains it. Invoked as the clone's copy,
#   it is structurally incapable of reaching the maintainer's rbpc_constants.sh —
#   the guarantee is a property of where the file sits, not of a rule someone
#   remembered to follow.
#
# The candidate clone gets NO station and NO secrets directory. It never needed
# one: rbz_generate_context and rbz_generate_consts both take explicit target
# paths, so the derived files can be rewritten without a build, without a
# launcher, and without a credential anywhere near the one tree whose entire
# charter is to carry none of the operator.
#
# Proof of erasure remains damnatio's alone. This script asserts nothing about its
# own result — a verb that grades itself is not a gate.

set -euo pipefail

# The tree this script belongs to. Every path below is resolved from here, so the
# script works the tree it sits in and no other. A whole process of its own, so the
# directory change cannot leak into a caller.
ZRBLM_STERILIZE_KIT_DIR="${BASH_SOURCE[0]%/*}"
cd "${ZRBLM_STERILIZE_KIT_DIR}/../.." || exit 1
ZRBLM_STERILIZE_ROOT="${PWD}"

test -n "${BURD_TEMP_DIR:-}" || { echo "rblm_sterilize: BURD_TEMP_DIR not set" >&2; exit 1; }
test -n "${BURD_BUK_DIR:-}"  || { echo "rblm_sterilize: BURD_BUK_DIR not set"  >&2; exit 1; }

# The kit this process will source from must be the one beneath the tree it is
# about to rewrite. Named plainly rather than assumed: this is the assertion that
# the maintainer's modules are out of reach.
test -f "${ZRBLM_STERILIZE_ROOT}/Tools/rbk/rbpc_constants.sh" \
  || { echo "rblm_sterilize: no rbpc_constants.sh beneath ${ZRBLM_STERILIZE_ROOT}" >&2; exit 1; }

source "${BURD_BUK_DIR}/buc_command.sh"
source "${BURD_BUK_DIR}/buym_yelp.sh"
source "${BURD_BUK_DIR}/buh_handbook.sh"
source "${BURD_BUK_DIR}/bubc_constants.sh"
source "${BURD_BUK_DIR}/buz_zipper.sh"
source "${BURD_BUK_DIR}/buwz_zipper.sh"

source "${ZRBLM_STERILIZE_ROOT}/Tools/rbk/rbcc_constants.sh"
source "${ZRBLM_STERILIZE_ROOT}/Tools/rbk/rbgc_constants.sh"
source "${ZRBLM_STERILIZE_ROOT}/Tools/rbk/rbz_zipper.sh"
source "${ZRBLM_STERILIZE_ROOT}/Tools/rbk/rblm_lustrate.sh"

zbuz_kindle
zrbz_kindle
zbuwz_kindle
zrbgc_kindle

buc_step "Lustrating ${ZRBLM_STERILIZE_ROOT}"
rblm_lustrate_apply

# rbpc is sourced HERE, after lustration and not before, because lustration
# rewrites its file. The generated Rust carries the freehold subject, so the value
# this process holds when it regenerates must be the value lustration just wrote —
# not the one that was in the file when the process started. Sourcing late is the
# whole mechanism: there is no re-read, no second copy, and no way to regenerate
# from a live subject even by mistake.
source "${ZRBLM_STERILIZE_ROOT}/Tools/rbk/rbpc_constants.sh"

# Repo-relative targets: this process already stands at the tree's root, and the
# generators resolve from where they stand. The context generator reads the
# tabtarget directory it is handed, so pointing it at THIS tree's tabtargets is
# what makes the delivered reference document the delivered tabtargets — the
# withheld families are absent from it because they are absent from the tree, not
# because a list said to drop them.
#
# The tabtarget directory is the dispatch-provided BURD_TABTARGET_DIR, and it must
# be RELATIVE: an absolute one would resolve out of this tree and back into the
# maintainer's, and the whole point of this process is that it cannot reach there.
buc_step "Regenerating derived files"

test -n "${BURD_TABTARGET_DIR:-}" || buc_die "BURD_TABTARGET_DIR not set - launch via tabtarget"
case "${BURD_TABTARGET_DIR}" in
  /*) buc_die "BURD_TABTARGET_DIR is absolute (${BURD_TABTARGET_DIR}) — it would resolve outside the tree being sterilized" ;;
esac

rbz_generate_context "${BURD_TABTARGET_DIR}" "${RBCC_tabtarget_context_file}" \
  || buc_die "Failed to regenerate tabtarget context"
rbz_generate_consts  "${RBCC_rbtdgc_consts_file}" \
  || buc_die "Failed to regenerate colophon consts"

buc_success "Tree lustrated and derived files regenerated"

# eof
