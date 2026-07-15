## RBK Agent Conduct

Token- and task-triggered conduct rules for working in the RBK codebase: "when you
encounter X while editing, do — or never do — Y." Each is a membrane against a
recurring failure mode. The genre is distinct from the acronym lookup table
(`claude-rbk-acronyms.md`), which answers "what file is RBFLA?" — not "how do I
behave when I see this." An entry belongs here when it is behavioral, not
referential.

### `RBr_` markers — never restate, never simplify

An `RBr_<tail>` token in bash/sh or any source marks a load-bearing — often
security-critical — decision. The token is opaque by construction: it carries no
meaning on its face, and the reasoning behind the decision it marks is
deliberately not recorded in the code.

**Never restate or "helpfully" re-explain the decision beside the marker, and
never "clean up" or simplify the odd-looking code it guards** — the code reads as
wrong precisely because the correct form does, and a guessed comment becomes a
wrong second source. The marker is the whole comment the code is owed.

In a jailer script (no comments by dialect) the marker rides the execution-time
announcement instead.

### Shellcheck

Lint bash with `tt/rbw-tl.Shellcheck.sh`; never run `shellcheck` directly. Suppressions and the inline-directive policy live in `Tools/buk/busc_shellcheckrc`.

### Build-Generated Files (do not hand-edit)

Two committed files are **regenerated from the zipper registry** (`rbz_zipper.sh`
→ `rbz_generate_consts` / `rbz_generate_context`) by the theurge build —
`tt/rbw-tb.Build.sh`, and the build step inside `tt/rbw-ts.*`. Change the
**zipper**, then build; never hand-edit these:

- `Tools/rbk/rbtd/src/rbtdgc_consts.rs` — theurge colophon constants (`RBTDGC_*`).
- `Tools/rbk/claude-rbk-tabtarget-context.md` — the tabtarget Command Reference.

Both carry a "Do not edit — regenerate via the build" header. **If they show as
modified in `git status` after you edited the zipper and ran a build, that is
expected** — they re-derived from your zipper change; they are *yours* to commit,
not another officium's work. `rbq_qualify` (`rbw-tl` / `rbw-tr`) only *checks*
their freshness and fails loud if the build wasn't re-run.

### Scry — bounded capture for crucible network debugging

To debug a *charged* crucible's traffic (mislabeling, off-path delivery, containment
leaks), reach for scry: `tt/rbw-cs.Scry.sh <moniker> <duration> [filter]`. With a
duration it captures the pentacle and both sentry legs (enclave + uplink), shows L2
MACs, and exits 0 — drivable from one tool call, read back from `../logs-buk/`.
**Never call the bare `rbw-cs <moniker>` form (no duration) from a tool call** — it
runs until Ctrl+C and hangs until your tool times out. Needs a charged crucible; not
a cold-start probe.
