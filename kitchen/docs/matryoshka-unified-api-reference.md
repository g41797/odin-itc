# matryoshka — Unified API Reference

> One ownership model for everything.
> Data and infrastructure follow the same rules.

---

## Core Types

### PolyTag

The type for unique type identifiers.

```odin
PolyTag :: struct {
    _: u8,
}
```

Each item type defines one private static instance at file scope.
The address of that instance is the unique tag for that type.

### PolyNode

The header at **offset 0** in every item.

```odin
PolyNode :: struct {
    using node: list.Node,
    tag:        rawptr, // must be != nil
}
```

All items — user data and infrastructure — embed this first.

---

### MayItem

```odin
MayItem :: Maybe(^PolyNode)
```

The ownership handle.

* `m^ == nil` → not yours
* `m^ != nil` → yours

You must:

* transfer it
* or dispose it

---

## Tag Rules

One field.
One rule: nil is always invalid.

```odin
// Define one tag per type:
@(private)
my_tag: PolyTag = {}

MY_TAG: rawptr = &my_tag

my_is_it_you :: #force_inline proc(tag: rawptr) -> bool { return tag == MY_TAG }
```

Infrastructure tags:

```odin
MAILBOX_TAG: rawptr  // address of internal mailbox_tag
POOL_TAG:    rawptr  // address of internal pool_tag
```

User tags and infrastructure tags never collide.
Each is a unique file-scope address.

---

## Lifecycle

No central factory.

Create directly.
Dispose through one entry.

All infrastructure items store their allocator internally.

---

### Creation

```odin
mbox_new :: proc(alloc: mem.Allocator) -> Mailbox
pool_new :: proc(alloc: mem.Allocator) -> Pool
```

---

### Disposal

```odin
matryoshka_dispose :: proc(m: ^MayItem)
```

Entry:

| Condition   | Result |
| ----------- | ------ |
| `m == nil`  | no-op  |
| `m^ == nil` | no-op  |

Algorithm:

* read `m^.tag`
* cast to internal type
* check state

| State  | Action      |
| ------ | ----------- |
| closed | free memory |
| open   | panic       |

Exit:

* `m^ = nil` on success

---

## Mailbox API

Moves ownership between threads.

---

### Handle

```odin
Mailbox :: ^PolyNode
```

**Common behavior:** All mailbox operations validate the handle's tag. If the tag is not `MAILBOX_TAG`, the operation will `panic`.

---

### Operations

```odin
SendResult :: enum {
    Ok,
    Closed,
    Invalid,
}

mbox_send :: proc(mb: Mailbox, m: ^MayItem) -> SendResult

RecvResult :: enum {
    Ok,
    Closed,
    Interrupted,
    Already_In_Use,
    Invalid,
    Timeout,
}

mbox_wait_receive :: proc(
    mb: Mailbox,
    m: ^MayItem,
    timeout: time.Duration = -1,
) -> RecvResult

IntrResult :: enum {
    Ok,
    Closed,
    Already_Interrupted,
}

mbox_interrupt :: proc(mb: Mailbox) -> IntrResult

// Marks mailbox closed.
// Wakes all waiters.
// Returns remaining items. Caller must process remaining.
mbox_close :: proc(mb: Mailbox) -> list.List

// Non-blocking recv. Returns (.Interrupted, empty) if flag set — clears flag.
try_receive_batch :: proc(mb: Mailbox) -> (list.List, RecvResult)
```

---

### Ownership rules

Send:

| Result | `m^` after |
| ------ | ---------- |
| `.Ok`  | nil        |
| other  | unchanged  |

Receive:

| Result | `out^` after |
| ------ | ------------ |
| `.Ok`  | non-nil      |
| other  | unchanged    |

---

### Notes

* Mailbox is an item
* Mailbox can be sent
* Mailbox must be closed before dispose

---

## Pool API

Provides reuse and policy.

---

### Handle

```odin
Pool :: ^PolyNode
```

**Common behavior:** All pool operations validate the handle's tag. If the tag is not `POOL_TAG`, the operation will `panic`.

---

### Initialization

```odin
pool_init :: proc(p: Pool, hooks: ^PoolHooks)
```

Hooks must outlive the pool.

---

### Operations

```odin
pool_close :: proc(p: Pool) -> (list.List, ^PoolHooks)

Pool_Get_Mode :: enum {
    Available_Or_New,  // use stored item or create
    New_Only,          // always create
    Available_Only,    // stored only — no creation; on_get never called
}

Pool_Get_Result :: enum {
    Ok,             // item returned in m^
    Not_Available,  // Available_Only: nothing stored
    Not_Created,    // on_get returned nil
    Closed,         // pool is closed
    Already_In_Use, // m^ != nil on entry
}

pool_get :: proc(
    p: Pool,
    tag: rawptr,
    mode: Pool_Get_Mode,
    m: ^MayItem,
) -> Pool_Get_Result

// Wait for stored item only.
// Does not call on_get.
pool_get_wait :: proc(
    p: Pool,
    tag: rawptr,
    m: ^MayItem,
    timeout: time.Duration,
) -> Pool_Get_Result

// Return item to pool.
// Calls on_put.
pool_put :: proc(p: Pool, m: ^MayItem)

// Return chain of items.
pool_put_all :: proc(p: Pool, m: ^MayItem)
```

---

### Ownership rules

Get:

| Result | `m^` after |
| ------ | ---------- |
| `.Ok`  | non-nil    |
| other  | unchanged  |

Put:

| State       | Result         |
| ----------- | -------------- |
| open pool   | `m^ = nil`     |
| closed pool | `m^` unchanged |

---

### PoolHooks

```odin
PoolHooks :: struct {
    ctx:    rawptr,
    tags:   [dynamic]rawptr,  // all != nil
    on_get: proc(ctx: rawptr, tag: rawptr, in_pool_count: int, m: ^MayItem),
    on_put: proc(ctx: rawptr, in_pool_count: int, m: ^MayItem),
}
```

---

### Hook rules

on_get:

* `m^ == nil` → create new item, set `node.tag = tag`
* `m^ != nil` → reinitialize

on_put:

* `m^ == nil` → already disposed
* `m^ != nil`:

  * keep → pool stores
  * dispose → set `m^ = nil`

---

## Infrastructure rules

* Infrastructure uses reserved tags (`MAILBOX_TAG`, `POOL_TAG`)
* Infrastructure is not pooled
* Infrastructure must be closed before dispose

---

## Summary

* One handle → `MayItem`
* One movement → Mailbox
* One reuse → Pool
* One teardown → `matryoshka_dispose`

Everything follows the same rules.
