// Copyright 2026 Scale Invariant, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Author: Brad Hyslop <bhyslop@scaleinvariant.org>
//
// RBTD Theurge — crucible test orchestrator for Recipe Bottle

#![deny(warnings)]
#![allow(non_camel_case_types)]
#![allow(private_interfaces)]

/// Vessels directory as a compile-time literal, for the `concat!` sites that
/// compose `<vessels>/rbev-*` const paths (their leaf names are Rust-local, so
/// nothing in bash composes them). `concat!` rejects a const *identifier* but
/// eagerly expands a `macro_rules!` invocation, consuming the literal token it
/// produces — the codebase's established zero-dependency idiom for compile-time
/// path composition. This literal is the one mooring/vessel path NOT taken from
/// the generated `RBTDGC_*` consts; `rbtdtm_vessels_dir_matches_generated` pins
/// it to `RBTDGC_MOORINGS_DIR`/`RBTDGC_VESSELS_SUBDIR` so any drift from the
/// bash source of truth is a test failure. Runtime `Path::join` sites that take
/// a value (not a literal) use `RBTDGC_MOORINGS_DIR` directly.
#[macro_export]
macro_rules! rbtd_vessels_dir {
    () => {
        "rbmm_moorings/rbmv_vessels"
    };
}

pub mod rbtdgc_consts;
pub mod rbtdra_almanac;
pub mod rbtdrb_probe;
pub mod rbtdrc_crucible;
pub mod rbtdrd_dogfight;
pub mod rbtdre_engine;
pub mod rbtdrf_fast;
pub mod rbtdrf_handbook;
pub mod rbtdrg_log;
pub mod rbtdrh_chain;
pub mod rbtdri_invocation;
pub mod rbtdrj_touchstone;
pub mod rbtdrk_depot;
pub mod rbtdrk_freehold;
pub mod rbtdrl_calibrant;
pub mod rbtdrm_manifest;
pub mod rbtdrn_conformance;
pub mod rbtdro_onboarding;
pub mod rbtdrp_attest;
pub mod rbtdrp_lifecycle;
pub mod rbtdrq_damnatio;
pub mod rbtdrq_loupe;
pub mod rbtdrq_perambulation;
pub mod rbtdrq_pyx;
pub mod rbtdrs_poison;
pub mod rbtdru_bash;
pub mod rbtdru_cupel;
pub mod rbtdru_python;
pub mod rbtdrv_patrol;
pub mod rbtdrw_dowse;
pub mod rbtdrx_platform;

#[cfg(test)]
mod rbtdth_helpers;
#[cfg(test)]
mod rbtdtb_probe;
#[cfg(test)]
mod rbtdtc_crucible;
#[cfg(test)]
mod rbtdte_engine;
#[cfg(test)]
mod rbtdti_invocation;
#[cfg(test)]
mod rbtdtk_freehold;
#[cfg(test)]
mod rbtdtl_calibrant;
#[cfg(test)]
mod rbtdtm_manifest;
#[cfg(test)]
mod rbtdto_onboarding;
#[cfg(test)]
mod rbtdtu_cupel;
#[cfg(test)]
mod rbtdtw_dowse;
#[cfg(test)]
mod rbtdtx_platform;
