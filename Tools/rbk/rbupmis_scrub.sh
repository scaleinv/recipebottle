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

# Podman Machine Init Scrubber
#
#  This project builds confidence that the default podman VM image
#  retrieved by podman is the same as the one selected by this project
#  as determined from other means.  This script here removes the
#  accidental aspects so that we can compare the big sha that is
#  displayed to tag the VM version in use precisely.

# Reference stdout from podman machine init, below:
#
# Looking up Podman Machine image at quay.io/podman/machine-os-wsl:5.5 to create VM
# 35e8036263febe8a2a7250dc83581a85f1771e9e49c4ccddfc0d7989473802fc
# Importing operating system into WSL (this may take a few minutes on a new WSL install)...
# The operation completed successfully.
# Configuring system...
# Machine init complete
# To start your machine run:
#
#         podman machine start rbw-example
#

set -euo pipefail

outfile="$1"

# Ensure output file is empty
: > "$outfile"

while IFS= read -r line || [[ -n "$line" ]]; do
  # Strip nulls from line
  clean_line="${line//$'\x00'/}"

  # Skip lines matching...
  [[ "$clean_line" != "Looking up Podman Machine image at"* ]] || continue
  [[ "$clean_line" != *"podman machine start"*              ]] || continue

  echo "$clean_line" >> "$outfile"
done

# eof
