# odin-mbox

Inter-thread mailbox library for Odin. Intrusive. Thread-safe. Zero-allocation.

Port of [mailbox](https://github.com/g41797/mailbox) (Zig). Used by [otofu](https://github.com/g41797/otofu).

---

## Two mailbox types

| Type | For | How it waits |
|---|---|---|
| `Mailbox($T)` | Worker threads | `sync.Cond` — blocks the thread |
| `Loop_Mailbox($T)` | nbio event loops | `nbio.wake_up` — wakes the loop |

Both are thread-safe. Both do zero allocations inside mailbox operations.

---

## User struct contract

Your struct must have a field named `node` of type `list.Node`.

The field name is fixed. It is not configurable.

```odin
import list "core:container/intrusive/list"

My_Msg :: struct {
    node: list.Node,  // required — name must be "node", type must be list.Node
    data: int,
}
```

The compiler enforces this at compile time. If your struct does not have the right `node` field, you get a compile error.

---

## Quick start — worker thread mailbox

```odin
import mbox "path/to/odin-mbox"
import list "core:container/intrusive/list"

My_Msg :: struct {
    node: list.Node,
    data: int,
}

// sender thread:
msg := My_Msg{data = 42}
mbox.send(&mb, &msg)

// receiver thread (blocks until message arrives):
got, err := mbox.wait_receive(&mb)
```

## Quick start — nbio loop mailbox

```odin
// setup (once, on the loop thread):
loop_mb: mbox.Loop_Mailbox(My_Msg)
loop_mb.loop = nbio.current_thread_event_loop()

// sender thread:
mbox.send_to_loop(&loop_mb, &msg)

// nbio loop — drain on wake:
for {
    msg, ok := mbox.try_receive_loop(&loop_mb)
    if !ok { break }
    // process msg
}
```

---

## API

### `Mailbox($T)` — worker thread mailbox

| Proc | Returns | Description |
|---|---|---|
| `send(&mb, &msg)` | `bool` | Add message. Returns false if closed. |
| `try_receive(&mb)` | `(^T, bool)` | Return message if available. Never blocks. |
| `wait_receive(&mb, timeout?)` | `(^T, Mailbox_Error)` | Block until message, timeout, or interrupt. |
| `interrupt(&mb)` | — | Wake all waiters with `.Interrupted`. |
| `close(&mb)` | — | Block new sends. Wake all waiters with `.Closed`. |
| `reset(&mb)` | — | Clear closed and interrupted flags. |

`Mailbox_Error` values: `None`, `Timeout`, `Closed`, `Interrupted`.

### `Loop_Mailbox($T)` — nbio loop mailbox

| Proc | Returns | Description |
|---|---|---|
| `send_to_loop(&mb, &msg)` | `bool` | Add message, wake the loop. Returns false if closed. |
| `try_receive_loop(&mb)` | `(^T, bool)` | Return message if available. Never blocks. |
| `close_loop(&mb)` | — | Block new sends. Wake the loop one last time. |
| `stats(&mb)` | `int` | Approximate pending message count. |

---

## Build and test

```sh
./build_and_test.sh
```

Runs 5 optimization levels: `none`, `minimal`, `size`, `speed`, `aggressive`.

Each level builds the root lib, builds examples, runs tests, and runs doc checks.

---

## Folder structure

```
odin-mbox/
  mbox.odin          # Mailbox — worker thread mailbox
  loop_mbox.odin     # Loop_Mailbox — nbio loop mailbox
  doc.odin           # Package doc and usage examples
  examples/          # Runnable examples (negotiation, stress)
  tests/             # @test procs
  design/            # Design docs and STATUS.md
  _orig/             # Original files before overhaul (not compiled)
```

---

## Design docs

- [STATUS.md](design/STATUS.md) — current status, decisions, session log
- [mailbox_design.md](design/mailbox_design.md) — architecture notes
- [mbox_examples.md](design/mbox_examples.md) — usage patterns

---

## License

MIT
