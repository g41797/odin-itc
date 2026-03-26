# matryoshka — Unified API Reference

> This document defines the consolidated API signatures and descriptions for the Matryoshka system, covering Core Types, Lifecycle/Management, Mailbox, and Pool.
>
> **Design Principle:** One ownership model (`Maybe(^PolyNode)`) for both data and infrastructure.

---

## Core Types

### PolyNode
The intrusive header embedded at **offset 0** in every system and user item.
```odin
PolyNode :: struct {
    using node: list.Node, // intrusive link — .prev, .next
    id:         int,       // type discriminator, must be != 0
}
```

### Maybe(^PolyNode)
The universal handle representing exclusive ownership.
- `m^ == nil` → Not yours.
- `m^ != nil` → Yours. You are responsible for its lifecycle (transfer or dispose).

### System IDs
Infrastructure items use extreme negative IDs to avoid collisions with user data (`id > 0`).
```odin
SystemId :: enum int {
    Invalid = 0,
    Mailbox = min(int),
    Pool    = min(int) + 1,
 }
```

---

## Lifecycle & Management (The Unified Factory)

The Matryoshka factory system handles the creation and destruction of system-level items like Mailboxes and Pools.

### Infrastructure Creation (The Two Variants)
You can birth infrastructure items either surgically with an explicit allocator or contextually through a Manager. Both variants store the allocator inside the new item for later suicide disposal.

#### Variant B: Surgical Creation (Create)
```odin
// The absolute primitive. Allocates internal _Mbox or _Pool based on id.
// Sets m^ to the new item's PolyNode header on success.
matryoshka_create :: proc(alloc: mem.Allocator, id: int, m: ^Maybe(^PolyNode)) -> CreateResult
```

### Unified Disposal (Self-Destruction)
Destroys internal sync primitives and frees the memory using the stored internal allocator. Symmetric with `pool_put`.
```odin
// m^ must be non-nil on entry.
// Checks if the item is CLOSED.
// Sets m^ = nil on success.
matryoshka_dispose :: proc(m: ^Maybe(^PolyNode))
```

---

## Mailbox API (Usage Handles)

Moves `^PolyNode` ownership between Masters. Supports blocking, timeout, interrupt, and close.

### Handles
```odin
Mailbox :: distinct ^PolyNode
```

### Operations
```odin
// Transfer ownership of 'm' to the mailbox. m^ becomes nil on success.
mbox_send :: proc(mb: Mailbox, m: ^Maybe(^PolyNode)) -> SendResult

// Wait for an item. out^ becomes non-nil on success.
mbox_wait_receive :: proc(mb: Mailbox, out: ^Maybe(^PolyNode), timeout: time.Duration = -1) -> RecvResult

// Wake one waiter with .Interrupted.
mbox_interrupt :: proc(mb: Mailbox) -> IntrResult

// Mark as closed and wake all waiters with .Closed.
// Returns a list of remaining items. Caller must drain.
mbox_close :: proc(mb: Mailbox) -> list.List

// Non-blocking drain of all currently available items.
try_receive_batch :: proc(mb: Mailbox) -> list.List
```

---

## Pool API (Usage Handles)

Provides resource reuse and policy control. Supports recycling through `PoolHooks`.

### Handles
```odin
Pool :: distinct ^PolyNode
```

### Operations
```odin
// Initialize the pool with hooks. User keeps hooks alive.
pool_init :: proc(p: Pool, hooks: ^PoolHooks)

// Mark closed, return remaining items and the hooks pointer.
pool_close :: proc(p: Pool) -> (list.List, ^PoolHooks)

// Acquire an item. calls on_get hook.
pool_get :: proc(p: Pool, id: int, mode: Pool_Get_Mode, m: ^Maybe(^PolyNode)) -> Pool_Get_Result

// Block until an item is available in the free-list. Does NOT call on_get.
pool_get_wait :: proc(p: Pool, id: int, m: ^Maybe(^PolyNode), timeout: time.Duration) -> Pool_Get_Result

// Return an item to the pool. calls on_put hook. m^ becomes nil on success.
pool_put :: proc(p: Pool, m: ^Maybe(^PolyNode))

// Walk a chain and return all items to the pool.
pool_put_all :: proc(p: Pool, m: ^Maybe(^PolyNode))
```

### PoolHooks
User-defined policy for recycling and creation.
```odin
PoolHooks :: struct {
    ctx:    rawptr,         // User context
    ids:    [dynamic]int,   // Registered IDs (all > 0)
    on_get: proc(ctx: rawptr, id: int, in_pool_count: int, m: ^Maybe(^PolyNode)),
    on_put: proc(ctx: rawptr, in_pool_count: int, m: ^Maybe(^PolyNode)),
}
```
**Contract:**
- `on_get`: Allocate if `m^ == nil`, or reinitialize if `m^ != nil`.
- `on_put`: Sanitization or backpressure disposal (set `m^ = nil` to dispose).
