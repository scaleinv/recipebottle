# Bash Utility Kit (BUK)

A portable, graftable bash infrastructure for building maintainable command-line tools with configuration management, dispatch routing, and validation.

## Table of Contents

- [Overview](#overview)
- [Core Concepts](#core-concepts)
  - [Launchers](#launchers)
  - [Workbenches](#workbenches)
  - [Testbenches](#testbenches)
  - [Zipper](#zipper)
  - [TabTargets](#tabtargets)
  - [Config Regimes](#config-regimes)
- [Architecture](#architecture)
- [Installation](#installation)
- [BUK Components](#buk-components)
  - [Module Prefix Registry](#module-prefix-registry)
- [Creating a New Workbench](#creating-a-new-workbench)
- [Reference Implementation: BURC/BURS](#reference-implementation-burcburs)

---

## Overview

BUK provides a three-layer architecture for bash-based CLI tools:

1. **BUK Core** (`Tools/buk/*.sh`) - Portable utilities with no project-specific knowledge
2. **BURC** (`.buk/burc.env`) - Project-level configuration defining repository structure
3. **BURS** (`../station-files/burs.env`) - Developer/machine-level configuration (not in git)

This separation allows BUK to be copied wholesale into any project and configured through regime files rather than code modification.

---

## Core Concepts

### Launchers

**Definition**: A launcher is a bootstrap script that validates configuration, loads regime files, and delegates to BUD (Bash Dispatch Utility). It serves as an **environment gate**—establishing a clean, validated execution context.

**Naming Pattern**: `launcher.{workbench_name}.sh`

**Location**: `.buk/` directory at project root

**Examples**:
- `.buk/launcher.buw_workbench.sh` - BUK workbench launcher
- `.buk/launcher.cccw_workbench.sh` - CCCK workbench launcher
- `.buk/launcher.rbw_workbench.sh` - RBW workbench launcher

**Creation**: Use `tt/buw-tt-cl.CreateLauncher.sh` to create new launchers.

**Environment Gate Role**:

The launcher's environment gate function is critical for testbench isolation. When a testbench invokes a tabtarget under test, that tabtarget passes through its own launcher, which:
- Revalidates regime configuration
- Establishes fresh BUD environment
- Prevents testbench state from bleeding into the code under test

This ensures tests exercise real dispatch paths with proper isolation.

**Design Rationale**:
- Launchers catch configuration errors before BUD starts
- Environment gate guarantees isolation between dispatch layers
- Clear naming ties launcher to its workbench
- Shared logic in `launcher_common.sh` eliminates boilerplate

---

### Workbenches

**Definition**: A workbench is a multi-call bash script that routes commands to their implementations.

**Naming Pattern**: `{prefix}w_workbench.sh`

**Location**: `Tools/{toolkit}/` subdirectory

**Examples**:
- `Tools/buk/buw_workbench.sh` - BUK workbench (manages BUK itself)
- `Tools/ccck/cccw_workbench.sh` - CCCK workbench (container control)
- `Tools/rbk/rbw_workbench.sh` - RBW workbench (recipe bottle management)

**Structure**:

```bash
#!/bin/bash
set -euo pipefail

# Route function
workbench_route() {
  local z_command="$1"
  shift

  case "${z_command}" in
    cmd1) workbench_cmd1 "$@" ;;
    cmd2) workbench_cmd2 "$@" ;;
    *)
      echo "ERROR: Unknown command: ${z_command}" >&2
      exit 1
      ;;
  esac
}

# Command implementations
workbench_cmd1() {
  # Implementation
}

workbench_cmd2() {
  # Implementation
}

# Main entry point
workbench_main() {
  local z_command="${1:-}"
  shift || true

  if [ -z "${z_command}" ]; then
    echo "ERROR: No command specified" >&2
    exit 1
  fi

  workbench_route "${z_command}" "$@"
}

workbench_main "$@"
```

**Key Characteristics**:
- Single-file router that routes commands
- Follows multi-call pattern (single script, multiple commands via case routing)
- Loads configuration (BURC/BURS) as needed
- Can delegate to other scripts for complex operations
- Crash-fast error handling (`set -euo pipefail`)

---

### Testbenches

**Definition**: A testbench orchestrates test scenarios—invoking tabtargets under test and assessing their behavior.

**Naming Pattern**: `{prefix}t_testbench.sh`

**Two-Layer Dispatch**:

```
tt/jjt-f.TestFavor.sh → Launcher → BUD → jjt_testbench.sh
                                              │
                                              ▼ invokes
                                    tt/jjw-tfP1.ProvisionPhase1.sh → Launcher → BUD → jjw_workbench.sh
                                              │                           ▲
                                              ▼ assesses                  │
                                         [pass/fail]                 environment
                                                                        gate
```

**Critical**: Each tabtarget under test passes through its own launcher. The launcher acts as an **environment gate**—testbench configuration cannot bleed into workbench execution. This isolation ensures tests exercise real dispatch paths.

**Structure**: Setup preconditions → invoke tabtarget → assess results → report

**Examples**:
- `Tools/jjk/jjt_testbench.sh` - Job Jockey test scenarios

---

### Zipper

**Definition**: A zipper is a BCG-compliant module that kindles array constants mapping colophons to their implementing modules and commands. Testbenches use symbolic constants instead of hardcoded colophon strings.

**Naming Pattern**: `{prefix}z_zipper.sh`

**Location**: `Tools/{toolkit}/` subdirectory

**Examples**:
- `Tools/buk/buz_zipper.sh` - BUK zipper (base registry infrastructure)
- `Tools/rbk/rbz_zipper.sh` - RBW zipper (Recipe Bottle colophon registry)

**Key Functions**:
- `buz_register(colophon, module, command)` — Register a tuple, sets `z1z_buz_colophon`

**Design Rationale**:
- Symbolic constants eliminate hardcoded colophon strings in tests
- Parallel arrays provide O(1) lookup by index
- Each toolkit's zipper owns its colophon registry

---

### TabTargets

#### The TabTarget Pattern

A TabTarget is a design pattern for CLI discoverability that trades argument flexibility for command visibility. The key insight: `ls tt/` shows all available commands; `tt/prefix-<TAB>` narrows to a category.

**Essential characteristics** (implementation-independent):

- Shell scripts in a dedicated directory (conventionally `tt/`)
- Filename encodes command identity and embedded parameters
- Tokens parsed by a configurable delimiter (typically `.`)
- Delegates immediately to a dispatch mechanism
- Contains no business logic—purely a routing layer

**Implementation variants**:

| Variant | Flow | Execution Target |
|---------|------|------------------|
| **Bash dispatch** (BUK) | TabTarget → Launcher → BDU → Workbench | Bash script |
| **Makefile dispatch** (MBC) | TabTarget → Dispatch Script → Make | Makefile rules |

BUK implements the bash dispatch variant. The remainder of this section describes that implementation.

#### BUK TabTarget Implementation

**Definition**: In BUK, TabTargets are lightweight shell scripts in the `tt/` directory that delegate to workbenches via launchers.

**Naming Pattern**: `{colophon}.{frontispiece}[.{imprint}...].sh`

**Location**: `tt/` directory at project root (configurable via `BURC_TABTARGET_DIR`)

**Token Delimiter**: Configurable via `BURC_TABTARGET_DELIMITER` (typically `.`)

#### TabTarget Anatomy

TabTarget filenames encode structured information using publishing terminology:

| Token | Term | Purpose | Example |
|-------|------|---------|---------|
| 1 | **Colophon** | Routing identifier—what the workbench matches on | `rbw-cr` |
| 2 | **Frontispiece** | Human-readable description | `Rack` |
| 3+ | **Imprint** | Embedded parameter(s)—target/instance specifier | `tadmor` |

**Simple example** (no imprint):
```
buw-tt-ll.ListLaunchers.sh
├── Colophon: buw-tt-ll      (workbench routes on this)
├── Frontispiece: ListLaunchers (human reads this)
└── Extension: sh
```

**Parameterized example** (with imprint):
```
rbw-cr.Rack.tadmor.sh
├── Colophon: rbw-cr         (workbench routes on this)
├── Frontispiece: Rack        (human reads this)
├── Imprint: tadmor          (passed to implementation)
└── Extension: sh
```

Multiple tabtargets can share the same colophon and frontispiece but differ by imprint:
```
rbw-cC.Charge.tadmor.sh    → same command, different targets
rbw-cC.Charge.srjcl.sh
rbw-cC.Charge.pluml.sh
```

**Examples**:
- `tt/buw-tt-ll.ListLaunchers.sh` - List launchers (no imprint)
- `tt/buw-rv.ValidateRegimes.sh` - Validate regimes (no imprint)
- `tt/rbw-cr.Rack.tadmor.sh` - Rack bottle on tadmor (with imprint)

**Creation**: Use the `buw-tt-*` commands to create tabtargets:
- `buw-tt-cbl` - Batch + logging (default)
- `buw-tt-cbn` - Batch + nolog (for secret-handling operations)
- `buw-tt-cil` - Interactive + logging (for shells)
- `buw-tt-cin` - Interactive + nolog (for secret entry)

**Token Parsing**:

BUD parses the filename into tokens using `BURC_TABTARGET_DELIMITER`:

| Filename | Colophon | Frontispiece | Imprint(s) |
|----------|----------|--------------|------------|
| `buw-ll.ListLaunchers.sh` | `buw-ll` | `ListLaunchers` | *(none)* |
| `rbw-cr.Rack.tadmor.sh` | `rbw-cr` | `Rack` | `tadmor` |

BUD extracts the colophon using `${filename%%${BURC_TABTARGET_DELIMITER}*}` and passes it to the workbench.

**Key Benefits**:
1. **Tab completion**: Type `tt/buw-` then press TAB to see all BUK commands
2. **Self-documenting**: Frontispiece describes what the command does
3. **Discoverability**: `ls tt/` shows all available commands
4. **Parameterization**: Imprints encode target-specific variants
5. **Lightweight**: No logic in tabtargets, just delegation

**Design Rationale**:
- Colophons route through the workbench to implementations
- Frontispieces serve as inline documentation for humans
- Imprints allow the same command to target different instances
- Delegating to launchers ensures validation happens on every invocation

---

### Config Regimes

**Definition**: A Config Regime is a structured configuration system consisting of:
- **Specification** - Markdown document defining variables, types, and constraints
- **Assignment** - Shell-sourceable file (`.env`) containing actual values
- **Validator** - Script that enforces type rules and constraints
- **Renderer** - Script that displays configuration in human-readable format

**Namespace Identity**: Unique uppercase prefix (e.g., `BURC_`, `BURS_`, `RBRN_`, `RBRR_`) prevents variable collisions.

**Core Components**:

1. **Assignment File** (`{regime}.env`)
   - Concise filename (frequently sourced)
   - Shell-sourceable: `VAR=value` syntax, no spaces around `=`
   - Can use `${VAR}` expansion for derived values
   - Example: `.buk/burc.env`

2. **Specification File** (`{regime}_specification.md`)
   - Documents all variables, types, and constraints
   - Self-documenting, readable
   - Example: `Tools/buk/burc_specification.md`

3. **Regime Script** (`{regime}_regime.sh`)
   - Multi-call script with subcommands
   - Subcommands: `validate`, `render`, `info`
   - Example: `Tools/buk/burc_regime.sh`

**File Naming Pattern**:
- **Assignment**: `{regime}.env` (concise, frequently sourced)
- **Support files**: `{regime}_{full_word}.{ext}` (readable, self-documenting)

**Examples**:

| Regime | Assignment | Specification | Validator/Renderer |
|--------|-----------|---------------|-------------------|
| BURC | `.buk/burc.env` | `Tools/buk/burc_specification.md` | `Tools/buk/burc_regime.sh` |
| BURS | `../station-files/burs.env` | `Tools/buk/burs_specification.md` | `Tools/buk/burs_regime.sh` |

**Type System**:

BUK provides validation functions in `buv_validation.sh`:
- **Atomic types**: `string`, `xname`, `fqin`, `bool`, `decimal`, `ipv4`, `cidr`, `domain`, `port`
- **List types**: `ipv4_list`, `cidr_list`, `domain_list`
- Each type validated with min/max constraints

**Why Config Regimes?**

1. **Separation of concerns**: Code is portable, configuration adapts it
2. **Type safety**: Validation catches errors early
3. **Documentation**: Specifications are authoritative and version-controlled
4. **Tooling**: Generic validators and renderers reduce boilerplate
5. **Scalability**: Multiple regimes can coexist without conflicts

---

## Architecture

```
Project Root/
├── .buk/                              # Launcher directory (project-specific bootstrap)
│   ├── burc.env                       # BURC assignment (project structure config)
│   ├── launcher.buw_workbench.sh      # BUK launcher (with validation)
│   ├── launcher.cccw_workbench.sh     # CCCK launcher (with validation)
│   └── launcher.rbw_workbench.sh      # RBW launcher (with validation)
│
├── tt/                                # TabTargets (tab-completion-friendly commands)
│   ├── buw-ll.ListLaunchers.sh        # List all launchers
│   ├── buw-rv.ValidateRegimes.sh      # Validate BURC/BURS
│   └── ccck-ps.ProcessStatus.sh       # Container status
│
├── Tools/                             # Tool scripts (portable, reusable)
│   ├── buk/                           # BUK core utilities (graftable module)
│   │   ├── bud_dispatch.sh # Dispatch system
│   │   ├── buc_command.sh  # Command utilities
│   │   ├── but_test.sh     # Test utilities
│   │   ├── buv_validation.sh # Validation (type system)
│   │   ├── buw_workbench.sh           # BUK workbench
│   │   ├── burc_specification.md      # BURC spec
│   │   ├── burc_regime.sh             # BURC validator/renderer
│   │   ├── burs_specification.md      # BURS spec
│   │   ├── burs_regime.sh             # BURS validator/renderer
│   │   └── README.md                  # This file
│   │
│   ├── ccck/                          # CCCK workbench
│   │   └── cccw_workbench.sh
│   │
│   └── rbk/                           # RBW workbench
│       └── rbw_workbench.sh
│
└── ../station-files/                  # Developer machine configs (NOT in git)
    └── burs.env                       # BURS assignment (station config)
```

**Execution Flow**:

```
User invokes TabTarget:
  $ tt/buw-ll.ListLaunchers.sh
       ├── Colophon: buw-ll
       └── Frontispiece: ListLaunchers

1. TabTarget delegates to Launcher
   → .buk/launcher.buw_workbench.sh buw-ll

2. Launcher validates regimes
   → burc_regime.sh validate .buk/burc.env
   → burs_regime.sh validate ../station-files/burs.env
   → (If validation fails, display info and exit)

3. Launcher delegates to BURD
   → bud_dispatch.sh buw-ll

4. BURD sets up environment
   → Parses colophon, frontispiece, imprint(s) from filename
   → Creates temp/output directories
   → Sources BURS (station config)
   → Sets up logging

5. BURD invokes Workbench
   → buw_workbench.sh buw-ll [imprints...]
   → Passes colophon as command, imprints as arguments

6. Workbench routes colophon
   → Case statement routes colophon "buw-ll" to implementation
   → Passes imprints to implementation
   → Executes command logic
   → Returns exit status

7. BURD cleans up
   → Writes transcript
   → Propagates exit status
```

---

## Installation

### Quick Start: Copy BUK into Your Project

1. **Copy BUK directory**:
   ```bash
   cp -r /path/to/source/Tools/buk ./Tools/
   ```

2. **Create `.buk` directory and BURC file**:
   ```bash
   mkdir -p .buk
   cat > .buk/burc.env <<'EOF'
   # Bash Utility Regime Configuration (BURC)
   # Project-level configuration for BUK

   BURC_STATION_FILE=../station-files/burs.env
   BURC_TABTARGET_DIR=tt
   BURC_TABTARGET_DELIMITER=.
   BURC_TOOLS_DIR=Tools
   BURC_TEMP_ROOT_DIR=../temp-buk
   BURC_OUTPUT_ROOT_DIR=../output-buk
   BURC_LOG_LAST=last
   BURC_LOG_EXT=txt
   EOF
   ```

3. **Create TabTarget directory**:
   ```bash
   mkdir -p tt
   ```

4. **Create station file location**:
   ```bash
   mkdir -p ../station-files
   cat > ../station-files/burs.env <<'EOF'
   # Bash Utility Regime Station (BURS)
   # Developer/machine-level configuration for BUK

   BURS_LOG_DIR=../_logs_buk
   EOF
   ```

5. **Validate installation**:
   ```bash
   Tools/buk/burc_regime.sh validate .buk/burc.env
   Tools/buk/burs_regime.sh validate ../station-files/burs.env
   ```

---

## BUK Components

### Module Prefix Registry

BUK modules use `bu{x}_` prefixes where `{x}` identifies the module.

| Prefix | Name | Status | Purpose |
|--------|------|--------|---------|
| `buc_` | command | Active | Command utilities, output formatting |
| `burd_` | dispatch | Active | Environment setup, invokes workbench |
| `buh_` | handbook | Active | Always-visible user interaction |
| `burc_` | regime-config | Active | Project-level Config Regime |
| `burs_` | regime-station | Active | Station-level Config Regime |
| `but_` | test | Active | Testing framework |
| `buut_` | tabtarget | Active | TabTarget/launcher creation |
| `buv_` | validation | Active | Type system, input validation |
| `buw_` | workbench | Active | BUK self-management workbench |
| `buz_` | zipper | Active | Colophon registry via parallel arrays |

**Conventions**:
- Three-letter: core modules (`buc_`, `bud_`)
- Four-letter: specialized modules (`burc_`, `buut_`)
- Reserved: planned but not yet implemented

---

### BURD - Bash Dispatch Utility

**File**: `Tools/buk/bud_dispatch.sh`

**Purpose**: Central dispatch system that sets up execution environment and invokes the workbench.

**Key Responsibilities**:
- Parse tabtarget filename into tokens
- Environment setup (temp dirs, output dirs, logging)
- Source BURS (station configuration)
- Resolve color policy
- Invoke workbench with proper context
- Capture and propagate exit status
- Generate execution transcript

#### Execution Context (Exported Variables)

BURD exports the following environment variables for workbench access:

**Invocation Identity**:

| Variable | Example | Description |
|----------|---------|-------------|
| `BURD_NOW_STAMP` | `20250101-143022-1234-567` | Unique timestamp: `YYYYMMDD-HHMMSS-PID-RANDOM` |
| `BURD_GIT_CONTEXT` | `v1.2.3-5-gabc123-dirty` | Output of `git describe --always --dirty --tags --long` |

**Token Explosion**:

TabTarget filenames are parsed into tokens using `BURC_TABTARGET_DELIMITER`. Each token is exported for workbench access:

| Variable | Semantic Role | For `rbw-cr.Rack.tadmor.sh` |
|----------|---------------|--------------------------------------|
| `BURD_TOKEN_1` | **Colophon** | `rbw-cr` |
| `BURD_TOKEN_2` | **Frontispiece** | `Rack` |
| `BURD_TOKEN_3` | **Imprint** | `tadmor` |
| `BURD_TOKEN_4` | Imprint (2nd) | *(empty)* |
| `BURD_TOKEN_5` | Imprint (3rd) | *(empty)* |
| `BURD_COMMAND` | Colophon | `rbw-cr` *(legacy, same as TOKEN_1)* |
| `BURD_TARGET` | Full filename | `rbw-cr.Rack.tadmor.sh` |
| `BURD_CLI_ARGS` | CLI arguments | *(extra arguments passed to tabtarget)* |

The workbench receives the colophon for routing and imprints as target parameters. The frontispiece is for human readability and typically not used at runtime.

This mirrors MBC's `MBC_TTPARAM__FIRST` through `MBC_TTPARAM__FIFTH` pattern.

**Directories**:

| Variable | Description |
|----------|-------------|
| `BURD_TEMP_DIR` | Ephemeral temp directory, unique per invocation; safe for intermediate files |
| `BURD_OUTPUT_DIR` | Output directory; cleared and recreated each run |
| `BURD_TRANSCRIPT` | Path to transcript file in temp directory |

**Logging** (paths, not file handles):

| Variable | Description |
|----------|-------------|
| `BURD_LOG_LAST` | Path to "last run" log |
| `BURD_LOG_SAME` | Path to same-name log |
| `BURD_LOG_HIST` | Path to historical log (timestamped) |

**Display**:

| Variable | Values | Description |
|----------|--------|-------------|
| `BURE_COLOR` | `0` or `1` | Color policy after terminal detection; respects `NO_COLOR` |

#### Control Variables

Set these *before* invoking a tabtarget to modify dispatch behavior:

| Variable | Values | Effect |
|----------|--------|--------|
| `BURE_VERBOSE` | `0`, `1`, `2`, `3` | `0`=quiet, `1`=debug output, `2`=bash trace (`set -x`), `3`=trace + deep diagnostics |
| `BURD_NO_LOG` | any value | Disables all logging |
| `BURD_INTERACTIVE` | any value | Line-buffered output mode for interactive commands |

#### The Three-Log Pattern

BURD maintains three views of execution output to support different debugging scenarios:

| Log | Variable | Lifecycle | Purpose |
|-----|----------|-----------|---------|
| **Historical** | `BURD_LOG_HIST` | Never overwritten | Timestamped archive; enables audit trail and post-hoc debugging |
| **Latest** | `BURD_LOG_LAST` | Overwritten each invocation | Quick access to most recent run, regardless of command |
| **Same-name** | `BURD_LOG_SAME` | Overwritten per-command | Preserves last run of *this specific* tabtarget |

**Rationale**: Different debugging scenarios need different log access patterns:

- "What just happened?" → Latest log (`BURD_LOG_LAST`)
- "What happened last time I ran *this* command?" → Same-name log (`BURD_LOG_SAME`)
- "What happened at 3pm yesterday?" → Historical log (`BURD_LOG_HIST`)

**Filename Conventions**:

- Historical: `hist-{tabtarget}-{timestamp}.{ext}` (e.g., `hist-buw-ll-sh-20250101-143022.txt`)
- Latest: `{BURC_LOG_LAST}.{ext}` (e.g., `last.txt`)
- Same-name: `same-{tabtarget}.{ext}` (e.g., `same-buw-ll-sh.txt`)

The log directory is specified by `BURS_LOG_DIR` in the station configuration.

---

### BUC - Bash Utility Command

**File**: `Tools/buk/buc_command.sh`

**Purpose**: Common command-line utilities and helpers.

**Key Functions**:
- Command execution helpers
- Output formatting
- Error handling patterns

---

### BUT - Bash Utility Test

**File**: `Tools/buk/but_test.sh`

**Purpose**: Testing framework for bash scripts.

**Key Functions**:
- Test case definition
- Assertion helpers
- Test runner

---

### BUV - Bash Utility Validation

**File**: `Tools/buk/buv_validation.sh`

**Purpose**: Type system for Config Regime validation.

**Validation Functions**:

BUV provides three function categories:

| Prefix | Purpose | Example |
|--------|---------|---------|
| `buv_val_*` | Core validators (take value directly) | `buv_val_string "$val" 1 255` |
| `buv_env_*` | Environment variable validators | `buv_env_string "VAR_NAME" 1 255` |
| `buv_opt_*` | Optional validators (allow empty) | `buv_opt_bool "OPTIONAL_FLAG"` |

**Atomic Types**:
- `string` - String with length constraints
- `xname` - System-safe identifier (xname = cross-platform name)
- `gname` - Group name identifier
- `fqin` - Fully Qualified Image Name
- `bool` - Boolean (`true`/`false`)
- `decimal` - Decimal number with range constraints
- `ipv4` - IPv4 address
- `cidr` - CIDR notation
- `domain` - Domain name
- `port` - Port number (1-65535)
- `odref` - Output directory reference

**List Types**:
- `list_ipv4` - Comma-separated IPv4 addresses
- `list_cidr` - Comma-separated CIDR blocks
- `list_domain` - Comma-separated domains

**Usage Example**:

```bash
# Validate an environment variable (most common usage)
buv_env_string "BURC_TABTARGET_DIR" 1 255 || exit 1
buv_env_xname  "BURC_LOG_LAST"            || exit 1

# Validate a value directly
buv_val_port "${some_port}" || exit 1

# Validate an optional variable (empty is OK)
buv_opt_bool "OPTIONAL_DEBUG_FLAG" || exit 1
```

---

### BUW - BUK Workbench

**File**: `Tools/buk/buw_workbench.sh`

**Purpose**: Self-management workbench for BUK itself.

**Commands**:

**TabTarget Subsystem** (`buw-tt-*`):
- `buw-tt-ll` - List launchers in `.buk/`
- `buw-tt-cbl <launcher> <name>...` - Create batch+logging tabtarget (default)
- `buw-tt-cbn <launcher> <name>...` - Create batch+nolog tabtarget
- `buw-tt-cil <launcher> <name>...` - Create interactive+logging tabtarget
- `buw-tt-cin <launcher> <name>...` - Create interactive+nolog tabtarget
- `buw-tt-cl <workbench> <name>` - Create launcher

**Regime Management**:
- `buw-rv` - Validate BURC and BURS regimes
- `buw-rr` - Render BURC and BURS configurations
- `buw-ri` - Show regime specification info

---

## Creating a New Workbench

To create a new workbench:

1. **Study existing workbenches** as templates:
   - `Tools/buk/buw_workbench.sh` - Simple routing example
   - `Tools/rbk/rbw_workbench.sh` - Module delegation pattern

2. **Create the workbench script** in `Tools/{prefix}/`

3. **Create the launcher** using `buw-tt-cl`:
   ```bash
   tt/buw-tt-cl.CreateLauncher.sh Tools/myw/myw_workbench.sh myw_workbench
   ```

4. **Create tabtargets** using `buw-tt-cbl` (or appropriate variant):
   ```bash
   tt/buw-tt-cbl.CreateTabTargetBatchLogging.sh .buk/launcher.myw_workbench.sh myw-cmd.CommandName
   ```

---

## Reference Implementation: BURC/BURS

BURC and BURS are BUK's own Config Regimes, serving as both:
1. **Implementation** - Working regimes for BUK's operation
2. **Example** - Canonical demonstration of the Config Regime pattern

### BURC - Bash Utility Regime Configuration

**Purpose**: Project-level configuration defining repository structure.

**Assignment File**: `.buk/burc.env`

**Variables**:

| Variable | Type | Purpose |
|----------|------|---------|
| `BURC_STATION_FILE` | string | Path to developer's BURS file (relative to project root) |
| `BURC_TABTARGET_DIR` | string | Directory containing tabtarget scripts |
| `BURC_TABTARGET_DELIMITER` | string | Token separator in tabtarget filenames |
| `BURC_TOOLS_DIR` | string | Directory containing tool scripts |
| `BURC_TEMP_ROOT_DIR` | string | Parent directory for temp directories |
| `BURC_OUTPUT_ROOT_DIR` | string | Parent directory for output directories |
| `BURC_LOG_LAST` | xname | Basename for "last run" log file |
| `BURC_LOG_EXT` | xname | Extension for log files (without dot) |

**Example**:
```bash
BURC_STATION_FILE=../station-files/burs.env
BURC_TABTARGET_DIR=tt
BURC_TABTARGET_DELIMITER=.
BURC_TOOLS_DIR=Tools
BURC_TEMP_ROOT_DIR=../temp-buk
BURC_OUTPUT_ROOT_DIR=../output-buk
BURC_LOG_LAST=last
BURC_LOG_EXT=txt
```

**Key Insight**: BURC allows projects to organize directories differently while using the same BUK utilities.

---

### BURS - Bash Utility Regime Station

**Purpose**: Developer/machine-level configuration for personal preferences.

**Assignment File**: `../station-files/burs.env` (location defined by `BURC_STATION_FILE`)

**Variables**:

| Variable | Type | Purpose |
|----------|------|---------|
| `BURS_LOG_DIR` | string | Where this developer stores logs |

**Example**:
```bash
BURS_LOG_DIR=../_logs_buk
```

**Key Insight**: BURS is NOT checked into git. Each developer can have different logging preferences, parallelism settings, etc.

---

## Design Philosophy

### Portability

BUK is designed to be **graftable**: copy `Tools/buk/` into any project, configure via regime files, and it works. No modification to BUK code is needed.

### Immutability

The `Tools/buk/` directory remains unchanged across projects. All project-specific behavior comes from configuration, not code changes.

### Configuration as Data

Config Regimes treat configuration as structured data with types, validation, and documentation. This eliminates an entire class of runtime errors.

### Discoverability

TabTargets + tab completion make commands discoverable. Type `tt/buw-<TAB>` to see all BUK commands.

### Fail Fast

Launchers validate regimes before execution. This catches configuration errors immediately, with helpful error messages.

### Exit Status Propagation

TabTarget systems must faithfully propagate exit status from the executed command back to the invoking shell. This is critical for:

- **CI/CD pipelines** that rely on exit codes to determine success/failure
- **Shell scripts** that chain commands with `&&` or check `$?`
- **Make rules** that depend on prerequisite command success

BUK achieves reliable status propagation through:

1. **`exec` in TabTargets**: Replaces the shell process entirely, so exit status flows directly to the caller without intermediate shell interference.

2. **`exec` in Launchers**: Same benefit at the launcher layer—no wrapper shell to mask the exit code.

3. **Pipeline status capture in BDU**: When output is piped through `tee` for logging, BDU explicitly captures `PIPESTATUS[0]` (the command's exit code) rather than the pipeline's final status (which would be `tee`'s exit code).

**Anti-patterns to avoid**:

```bash
# BAD: semicolon masks exit status
command; echo "done"

# BAD: final command in pipeline determines status
command | tee logfile  # Returns tee's status, not command's

# GOOD: capture pipeline status explicitly
command | tee logfile; exit ${PIPESTATUS[0]}
```

### Coding Standards

All BUK utilities follow these enterprise bash patterns:

- **Bash 3.2 compatibility** - Works with macOS default shell
- **Multi-call script pattern** - Single script handles multiple commands via case routing
- **Crash-fast error handling** - Use `set -euo pipefail` at script start
- **Braced, quoted variable expansion** - Always `"${var}"`, never `$var`
- **Kindle/sentinel boilerplate** - Guard against multiple source inclusion

---

## Future Directions

BUK's current scope covers portable CLI infrastructure and configuration management. The following directions represent potential extensions that maintain portability while addressing enterprise development patterns and standards enforcement.

### Standards Installation & Awareness

Vision: Inject enterprise bash practices into development workflows from session start, leveraging patterns like BCG as anchor standards. Rather than relying on LLM training defaults, developers work with pre-configured awareness of anti-patterns and best practices. This prevents bad suggestions before they appear.

May eventually involve:
- Integration with CLAUDE.md to document enterprise bash standards
- Session initialization that establishes standards context
- Real-time guidance on pattern compliance

### Hidden Configuration Workbench

Vision: A wholly internal workbench (separate from the portable BUK toolkit) that manages Claude Code-specific configuration and behavior using BUK's tabtarget/dispatch/regime infrastructure internally. Follows the Job Jockey installation model: detect, modify CLAUDE.md, register capabilities.

May eventually involve:
- Project-specific hooks and configuration management
- Behavior tuning that adjusts tool proclivities without per-session instruction
- Hidden config files and internal tools not published with the portable BUK toolkit

### Code Validation Skills

Vision: Skills that validate bash code against enterprise standards in real-time, catching deviations early. Anchored by BCG anti-patterns and best practices.

May eventually involve:
- Skills like `/validate-bash`, `/check-bcg-compliance`
- Integration with workbench validation functions
- Forensic output for code review and standards enforcement

---

## Contributing

When extending BUK:

1. **Follow coding standards** - See the "Coding Standards" section above
2. **Maintain portability** - No project-specific logic in `Tools/buk/`
3. **Use Config Regimes** - Configuration belongs in regime files, not code
4. **Write specifications** - Document new regimes in `{regime}_specification.md`
5. **Add validation** - Use BVU type system for all config variables
6. **Update README** - Keep this file as the authoritative source

---

## License

Copyright 2025 Scale Invariant, Inc.

Licensed under the Apache License, Version 2.0.

---

## Author

Brad Hyslop <bhyslop@scaleinvariant.org>
