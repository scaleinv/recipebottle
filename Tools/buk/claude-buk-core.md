## File Acronym Mappings — BUK Subdirectory (`Tools/buk/`)

- **BUC**  → `buk/buc_command.sh` (command utilities, buc_* functions)
- **BUD**  → `buk/bud_dispatch.sh` (dispatch utilities, zbud_* functions)
- **BUG**  → `buk/bug_git.sh` (bash git utilities, bug_* functions — home of the "tools never commit, gate on a clean tree" gate `bug_require_clean_tree_creed`)
- **BUH**  → `buk/buh_handbook.sh` (handbook utilities, buh_* functions - always-visible user interaction)
- **BUT**  → `buk/but_test.sh` (test utilities, but_* functions)
- **BUYM** → `buk/buym_yelp.sh` (yelp module — diastema wire format, yawp functions, format resolver, legacy captures)
- **BUV**  → `buk/buv_validation.sh` (validation utilities, buv_* functions)
- **BUW**  → `buk/buw_workbench.sh` (workbench utilities, buw_* functions)
- **BUTT** → `buk/butt_testbench.sh` (BUK test framework self-test — kick-tires + bure-tweak, 9 cases)
- **BURC** → `buk/burc_cli.sh`, `buk/burc_regime.sh` (regime configuration)
- **BURS** → `buk/burs_cli.sh`, `buk/burs_regime.sh` (regime station)

## Bash Utility Kit (BUK) Concepts

BUK provides tabtarget/launcher infrastructure for bash-based tooling.

### TabTarget System

TabTargets are lightweight shell scripts in `tt/` that serve as the CLI entry point for all operations. They delegate to workbenches via launchers — no business logic lives in tabtargets.

**Discoverability**: `ls tt/` shows all available commands. Tab completion narrows by prefix: `tt/rbw-<TAB>`.

**Naming pattern**: `{colophon}.{frontispiece}[.{imprint}].sh`

| Part | Purpose | Example |
|------|---------|---------|
| **Colophon** | Routing identifier (includes hyphen, workbench matches on this) | `rbw-cC`, `buw-tt-ll` |
| **Frontispiece** | Human-readable description (PascalCase) | `Charge` |
| **Imprint** | Optional target parameter (nameplate moniker, fixture name, etc.) | `tadmor` |

- The `.` is the delimiter between parts
- The hyphen is part of the colophon (not a separator)

Example: `tt/rbw-cC.Charge.tadmor.sh` — colophon `rbw-cC` routes to the crucible charge command, frontispiece tells you what it does, imprint `tadmor` selects the nameplate.

Multiple tabtargets can share the same colophon but differ by imprint:
```
tt/rbw-cC.Charge.tadmor.sh
tt/rbw-cC.Charge.srjcl.sh
tt/rbw-cC.Charge.pluml.sh
```

### BUK Vocabulary

| Term | Definition |
|------|------------|
| **Zipper** | Module kindling colophon→module→command array constants |
| **Workbench** | Routes commands: `{prefix}w_workbench.sh` |
| **Testbench** | Routes tests: `{prefix}t_testbench.sh` |
| **Folio** | Runtime target value (`BUZ_FOLIO`) passed to a command — nameplate moniker, role name, etc. How it arrives depends on the channel |
| **Channel** | Enrollment-time declaration of how a colophon receives its folio: `imprint` (from filename — one tabtarget per target), `param1` (command-line argument — single tabtarget), or empty (no folio needed) |

**Key files:**
- `Tools/buk/buc_command.sh` — command utilities
- `Tools/buk/bud_dispatch.sh` — dispatch utilities
- `Tools/buk/buw_workbench.sh` — workbench

Full spec: `Tools/buk/README.md`

## Forbidden Shell Operations

**Never use `cd` in Bash commands — NO exceptions.**

The working directory persists between Bash tool calls. A single `cd` corrupts ALL subsequent commands that use relative paths, including every `./tt/` tabtarget.

- Use absolute paths instead of cd'ing

**There is no safe cd.** Do not reason that "I'll cd back" — the next tool call may be yours or another Claude Code session's, and it will break.

## Tool Git Discipline

Tools never commit in the consumer's codebase. A tool MAY presume git and refuse downstream steps on a dirty tree, but it never stages or commits — the operator commits with their usual workflow. The uniform gate is `bug_require_clean_tree_creed "<creed>"` (BUG module) — a precision-band deliberate-rejection gate; BUG stays kit-agnostic and the caller supplies its rationale (a creed) for demanding a clean tree. A verb that installs into tracked config calls it first, so an install-then-forgot-to-commit cannot silently ride into a later build.

## TabTarget Invocation Discipline

**Never wrap tabtarget invocations with `tee`, `tail`, `head`, `grep`, `2>&1`, or any other pipe — NO exceptions.**

Tabtargets self-log to `../logs-buk/`:
- `last.txt` — most recent invocation across all tabtargets
- `same-{cmd}.txt` — most recent invocation of this specific tabtarget
- `hist-{cmd}-{timestamp}.txt` — historical invocations

Both stdout and stderr are captured. Adding your own `tee` or `2>&1` duplicates work the tool already did. The real hazard is piping a tabtarget into `tail`/`head`/`grep`: zsh defaults `pipefail` OFF, so the pipeline returns the last command's exit status — usually 0. **A failing test reports as success.**

- Run the tabtarget directly, then read from `../logs-buk/` in a separate command
- Environment variables before the command are fine: `BURE_CONFIRM=skip ./tt/rbw-cQ.Quench.tadmor.sh`
- If you genuinely must pipe live output (rare — usually you can read the log instead), set `-o pipefail` on the same line, or check `${PIPESTATUS[0]}` (bash) / `${pipestatus[1]}` (zsh)

```
# Wrong — exit code is from `tail`, not the tabtarget; failures masked
./tt/rbw-ts.TestSuite.gauntlet.sh 2>&1 | tee /tmp/log | tail -80

# Wrong — even a bare `| head` discards the real signal
./tt/rbw-ts.TestSuite.reveille.sh | head -50

# Right — separate commands; exit code preserved
./tt/rbw-ts.TestSuite.gauntlet.sh
tail -80 ../logs-buk/last.txt
```

**There is no safe `tee | tail`.** Do not reason "I'll just truncate the output for readability" — the truncation and the exit-code-eating are inseparable. Truncate by reading the log file afterward.

## Test Execution Discipline

Run test fixture tabtargets **sequentially, never in parallel**. Test fixtures share regime state and container/network namespaces — parallel execution causes resource conflicts and false failures.

```
# Correct: run one at a time
tt/rbw-tf.FixtureRun.sh regime-validation
tt/rbw-tf.FixtureRun.sh tadmor

# Wrong: never run fixtures concurrently
tt/rbw-tf.FixtureRun.sh regime-validation & tt/rbw-tf.FixtureRun.sh tadmor &
```
