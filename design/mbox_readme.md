# mbox — Inter-thread mailbox for Odin

Inter-thread mailbox library for Odin. Intrusive. Thread-safe. Zero-allocation.

Port of [mailbox](https://github.com/g41797/mailbox) (Zig).

---

## Background

Mailboxes come from the Actor Model (1973). A mailbox is a thread-safe FIFO queue. Threads send messages into it. Other threads receive from it.

This design is inspired by iRMX 86 (Intel, 1980), where tasks communicated by posting to mailboxes and waiting for objects.

---

## User struct contract

Your struct must embed a `node` field of type `list.Node`.

```odin
import list "core:container/intrusive/list"

My_Msg :: struct {
    node: list.Node,  // required — name must be "node"
    data: int,
}
```

- The field name is fixed: `node`.
- The field type is fixed: `list.Node` from `core:container/intrusive/list`.
- The compiler checks this at compile time via `where` clause.

---

## Two mailbox types

### `Mailbox($T)` — for worker threads

Blocks using a condition variable. The thread sleeps until a message arrives.

```odin
mb: mbox.Mailbox(My_Msg)

// sender:
mbox.send(&mb, &msg)

// receiver (blocks):
got, err := mbox.wait_receive(&mb)

// receiver (non-blocking):
got, ok := mbox.try_receive(&mb)
```

Error values: `None`, `Timeout`, `Closed`, `Interrupted`.

### `Loop_Mailbox($T)` — for nbio event loops

Non-blocking. Wakes the nbio event loop using `nbio.wake_up`.

```odin
loop_mb: mbox.Loop_Mailbox(My_Msg)
loop_mb.loop = nbio.current_thread_event_loop()

// sender (from any thread):
mbox.send_to_loop(&loop_mb, &msg)

// receiver (inside nbio loop, drain on wake):
for {
    msg, ok := mbox.try_receive_loop(&loop_mb)
    if !ok { break }
    // handle msg
}
```

---

## Intrusive design

The message is the node. No heap allocation per message.

The user owns the message memory. The mailbox just links messages together.

```odin
msg := My_Msg{data = 42}
mbox.send(&mb, &msg)   // links &msg.node into the list
```

The caller must keep `msg` alive until it is received.

---

## API summary

### `Mailbox($T)`

| Proc | Description |
|---|---|
| `send(&mb, &msg)` | Add message. Returns false if closed. |
| `try_receive(&mb)` | Return message if available. Never blocks. |
| `wait_receive(&mb, timeout?)` | Block until message, timeout, or interrupt. |
| `interrupt(&mb)` | Wake all waiters with `.Interrupted`. |
| `close(&mb)` | Block new sends. Wake all waiters with `.Closed`. |
| `reset(&mb)` | Clear closed and interrupted flags. Allow reuse. |

### `Loop_Mailbox($T)`

| Proc | Description |
|---|---|
| `send_to_loop(&mb, &msg)` | Add message. Wake loop if it was empty. Returns false if closed. |
| `try_receive_loop(&mb)` | Return message if available. Never blocks. |
| `close_loop(&mb)` | Block new sends. Wake loop one last time. |
| `stats(&mb)` | Approximate pending count (not locked). |

---

## Notes

- Producers do not block. The list grows as needed (no capacity limit).
- No allocator dependency. No `context` required inside mailbox ops.
- The `where` clause prevents misuse at compile time. Wrong struct = compile error.
