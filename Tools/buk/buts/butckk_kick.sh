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
# BUTCKK - Kick-tires test cases for BUK test framework self-test

set -euo pipefail

######################################################################
# Kick-tires cases — trivial tests proving end-to-end framework works

butckk_true_tcase() {
  buto_trace "Kick-tires: verifying true returns success"
  buto_unit_expect_ok true
}

butckk_false_tcase() {
  buto_trace "Kick-tires: verifying false returns failure"
  buto_unit_expect_fatal false
}

# eof
