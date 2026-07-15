#!/bin/bash
#
# buw-SI.StationInit — Create default station regime file
#
# Standalone script (no launcher/dispatch) — BUD requires the station
# regime to exist, so this cannot go through dispatch.
#
# Reads BURC_STATION_FILE from rbmm_moorings/burc.env, creates the directory,
# writes a minimal burs.env with BURS_LOG_DIR.
#
# Idempotent: overwrites any existing station file.

set -euo pipefail

z_script_dir="${BASH_SOURCE[0]%/*}"
z_burc="${z_script_dir}/../rbmm_moorings/burc.env"

test -f "${z_burc}" || { echo "FATAL: rbmm_moorings/burc.env not found: ${z_burc}" >&2; exit 1; }

z_station_file="$(grep '^BURC_STATION_FILE=' "${z_burc}" | cut -d= -f2)"
test -n "${z_station_file}" || { echo "FATAL: BURC_STATION_FILE not set in ${z_burc}" >&2; exit 1; }

# Resolve relative to project root (rbmm_moorings parent)
z_project_root="${z_script_dir}/.."
z_station_path="${z_project_root}/${z_station_file}"

mkdir -p "$(dirname "${z_station_path}")"

# Subshell $(whoami) permitted: BUK environment not available in bootstrap tabtarget
printf '%s\n' "BURS_USER=$(whoami)" > "${z_station_path}"
printf '%s\n' 'BURS_LOG_DIR=../logs-buk' >> "${z_station_path}"

echo "Station regime created: ${z_station_path}"
