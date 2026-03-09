# odin-mbox STATUS

## Rules

### Project Rules (MUST)
- Read ## Session Log first. It tells you where we are and what is next.
- Update ## Session Log at the end of every stage.
- Do not use git directly. All git operations go through the human owner.
- Do not skip stages. Each stage must pass before the next starts.
- Do not write real code before infrastructure is verified.
- Do not start work without reading this file first.

### Document Rules (MUST)
- Simple English. Not everyone speaks English as first language.
- No smart AI words. Write like a human.
- No flowery or pathetic language.
- Short sentences.
- Use bullet lists. Replace long sentences with bullets.
- One idea per sentence.
- Be human.

## Sources of Truth

- Zig mailbox implementation: `/home/g41797/dev/root/github.com/g41797/mailbox/`
  - `src/mailbox.zig`
  - `src/mailbox_tests.zig`
- Odin nbio library: `/home/g41797/odin-lang/Odin/core/nbio/`
- Odin intrusive list: `/home/g41797/odin-lang/Odin/core/container/intrusive/list/`
- This file (`design/STATUS.md`) — decisions, status, session history

## Participants

- **Owner**: g41797 (human)
- **Claude**: architecture, implementation, tests
- **Gemini**: review, documentation

## Project

Inter-thread mailbox library for Odin.
Port of Zig mailbox (github.com/g41797/mailbox).
Will be used in otofu — Odin port of tofu messaging.

## Architecture

Two mailbox types:

- `Mailbox($T)` — blocks thread, uses condition variable, for worker threads
- `Loop_Mailbox($T)` — non-blocking, uses `nbio.wake_up`, for nbio event loops

Both types:
- Use `core:container/intrusive/list` as internal storage.
- Thread-safe.
- Zero allocations inside mailbox operations.

User struct contract:
- Must have a field named `node` of type `list.Node`.
- Field name is fixed. Not configurable.
- Enforced at compile time via `where` clause on all procs.

```odin
import list "core:container/intrusive/list"

My_Msg :: struct {
    node: list.Node,  // required
    data: int,
}
```

## Folder Structure

- root: `package mbox` — implementation + `doc.odin`
- `examples/`: `package examples` — callable demo procs
- `tests/`: `package tests` — @test procs that call examples
- `design/`: all documentation including this file
- `_orig/`: backup of original files (not compiled)

## Decisions

- Folder structure: Variant A — 3 separate packages
- No type-erased mailbox variant
- Real nbio event loop in tests (not mocked)
- Infrastructure first: mocks before real code
- STATUS.md created first, updated after every stage
- Document rules apply to all markdown files
- Session Log: newest entry at top
- Internal storage: `core:container/intrusive/list`
- User struct field: must be named `node`, type `list.Node` — fixed, documented
- `where` clause enforces field contract on all procs at compile time

## Open Questions

(none)

## Session Log

### 2026-03-09 — Session 1
**Participants**: human + Claude

**Done**:
- Explored Zig mailbox (source of truth)
- Explored Odin nbio API
- Explored Odin intrusive list (`core:container/intrusive/list`)
- Explored current odin-mbox state
- Decided folder structure (Variant A)
- Decided infrastructure-first approach
- Decided to use `list.List` as internal storage
- Decided fixed field name `node: list.Node` — enforced by `where` clause
- Created overhaul plan
- Stage 0: Created design/STATUS.md
- Stage 1: Created folders (`examples/`, `tests/`, `_orig/`), moved originals to `_orig/`
- Stage 2: Created mock files (`doc.odin`, `mbox.odin`, `loop_mbox.odin`, `examples/negotiation.odin`, `examples/stress.odin`, `tests/all_test.odin`)
- Stage 3: Fixed `build_and_test.sh` and `build_and_test.cmd` — all 5 opt levels pass locally
- Stage 4: Fixed `.github/workflows/ci.yml` — 15 jobs (3 OS × 5 opt), fail-fast disabled
- Stage 5: All 15 CI jobs green (3 OS × 5 opt)
- Fix: `odin doc` step changed from `-all-packages` to 3 separate calls per package
- Stage 6: Real implementation in `mbox.odin` and `loop_mbox.odin` — all 5 opt levels pass locally
- Stage 7: Real examples in `examples/negotiation.odin` and `examples/stress.odin` — all 5 opt levels pass locally
- Fix: `sync.cond_timedwait` does not exist — correct name is `sync.cond_wait_with_timeout`
- Stage 8: Real tests in `tests/all_test.odin` — 12 tests, all 5 opt levels pass locally
- Fix: test `Msg` type must import `list "core:container/intrusive/list"` directly — `mbox.list` does not work
- Stage 9: Rewrote README.md. Updated design/mailbox_design.md, design/mbox_readme.md, design/mbox_examples.md

**Note**:
- `-vet` with generic structs does not count struct field types as import usage.
- Workaround: private type aliases at file scope force import registration.
- Example: `@(private) _Node :: list.Node`
- `odin doc ./ -all-packages` dumps entire stdlib. Use `odin doc ./` per package instead.

**Next**:
- Push to GitHub — verify all 15 CI jobs green
- Project complete
