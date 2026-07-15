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
// RBTDTB — tests for precondition-probe helper

use super::rbtdrb_probe::*;
use super::rbtdre_engine::rbtdre_Verdict;

fn rbtdtb_check_ok() -> Result<(), String> {
    Ok(())
}

fn rbtdtb_check_err() -> Result<(), String> {
    Err("observed state X".to_string())
}

#[test]
fn rbtdtb_assert_returns_ok_when_precondition_holds() {
    let probe = rbtdrb_Probe {
        name: "test-precondition",
        check: rbtdtb_check_ok,
        remediation: "no action needed",
    };
    assert!(rbtdrb_assert(&probe).is_ok());
}

#[test]
fn rbtdtb_assert_returns_fail_verdict_when_precondition_unmet() {
    let probe = rbtdrb_Probe {
        name: "depot-levied",
        check: rbtdtb_check_err,
        remediation: "run rbtdrp_depot_stand_up first",
    };
    match rbtdrb_assert(&probe) {
        Err(rbtdre_Verdict::Fail(detail)) => {
            assert!(detail.contains("depot-levied"));
            assert!(detail.contains("observed state X"));
            assert!(detail.contains("run rbtdrp_depot_stand_up first"));
        }
        Err(_) => panic!("expected Fail verdict, got non-Fail"),
        Ok(()) => panic!("expected Err, got Ok"),
    }
}
