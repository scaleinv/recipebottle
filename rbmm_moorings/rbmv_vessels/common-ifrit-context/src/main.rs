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
// RBID Ifrit — in-bottle attack binary for crucible testing
//
// Receives an attack selector argument, executes one attack, prints a verdict
// line to stdout, and exits 0 (PASS/SECURE) or nonzero (FAIL).
//
// Wire protocol (consumed by theurge's rbtdri_parse_ifrit_verdict):
//   stdout: "IFRIT_VERDICT: PASS [detail]" or "IFRIT_VERDICT: FAIL <detail>"
//   exit:   0 for pass, 1 for fail

use std::process::ExitCode;

use rbid::rbida_attacks::{rbida_Attack, rbida_run};

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().collect();

    match args.get(1).map(|s| s.as_str()) {
        Some("--list") => {
            for selector in rbida_Attack::all_selectors() {
                println!("{}", selector);
            }
            ExitCode::SUCCESS
        }
        Some(selector) => {
            let attack = match rbida_Attack::from_selector(selector) {
                Some(a) => a,
                None => {
                    eprintln!("rbid: unknown attack selector: {}", selector);
                    eprintln!("rbid: use --list to see available attacks");
                    return ExitCode::FAILURE;
                }
            };
            let extra_args: Vec<&str> = args[2..].iter().map(|s| s.as_str()).collect();
            let result = rbida_run(&attack, &extra_args);
            if result.passed {
                println!("IFRIT_VERDICT: PASS {}", result.detail);
                ExitCode::SUCCESS
            } else {
                println!("IFRIT_VERDICT: FAIL {}", result.detail);
                ExitCode::FAILURE
            }
        }
        None => {
            eprintln!("rbid: no attack selector argument");
            eprintln!("rbid: usage: rbid <attack-selector>");
            eprintln!("rbid: use --list to see available attacks");
            ExitCode::FAILURE
        }
    }
}
