# Pool Redesign — for review

> Session 101, 2026-03-22.
> This doc captures decisions from the design discussion.
> It is a draft for review — not yet merged into `design.md`.

---

## Author notes

---

## What changed and why

Old design:
- `pool_init` received an allocator.
- `PoolHooks` had 4 procs: `factory`, `on_get`, `on_put`, `dispose`.
- Each hook received `alloc mem.Allocator`.
- Pool owned the hooks by value.

New design:
- Pool allocates and frees nothing. Hooks own all lifecycle.
- Hooks do not receive `alloc`. They get an allocator from `ctx` if needed.
- `factory` and `on_get` merge into one proc — `on_get`.
- `dispose` is removed from `PoolHooks`. User disposes in `on_put` and after `pool_close`.
- Pool borrows `^PoolHooks` — user owns the struct.
- `pool_destroy` renamed to `pool_close`. Returns stored items and hooks pointer back to user.
- `pool_recycle_wait` renamed to `pool_get_wait`.
- `Pool_Get_Mode` values renamed to clearer names.

---

## Reminder: WTH is ^Maybe(^PolyNode)

User has many types: Chunk, Progress, Token, ...
Service (queue, pool, mailbox) must work with all of them.
Service cannot import user types — that creates dependencies.

Solution: user embeds `PolyNode` in their struct. Service works with `^PolyNode` only.
No user types in service code. No dependencies.

```odin
PolyNode :: struct {
    using node: list.Node,  // the link — service chains items through this
    id:         int,        // which user type is behind this pointer — never 0
}
```

**node** — the link that lets the service chain items into a list.
User gets this for free by embedding `PolyNode`. No separate allocation needed.

**id** — user sets it once at creation. Service uses it to hand the item back.
User reads `id`, casts to the right type, done.

**Maybe(^PolyNode)** — who owns this item right now?
- `m^ != nil` — you own it. You must return, send, or free it.
- `m^ == nil` — you don't own it. Don't touch it.

No flags. No return codes. One look at `m^`.

**^Maybe** at APIs — service writes `nil` into your variable when it takes the item.
You check `m^` after the call. nil = gone. non-nil = still yours.

---

## PoolHooks

```odin
PoolHooks :: struct {
    ctx:    rawptr,
    on_get: proc(ctx: rawptr, id: int, in_pool_count: int, m: ^Maybe(^PolyNode)),
    on_put: proc(ctx: rawptr, in_pool_count: int, m: ^Maybe(^PolyNode)),
}
```

Two procs only. Both communicate through `m`.

Both procs are required.

`ctx` may be nil. Pool passes it as-is. Hook is responsible for handling nil `ctx` safely.

---

## on_get contract

Pool calls `on_get` on every `pool_get` — except `Available_Only` when no item is stored.

Pool passes `m^` as-is. Hook decides what to do.

| Entry state | Meaning | Hook must |
|-------------|---------|-----------|
| `m^ == nil` | no item available | create a new item, set `node.id = id`, set `m^` |
| `m^ != nil` | recycled item | reinitialize for reuse |

`in_pool_count`: number of items with this `id` currently idle (stored) in the pool — not total live objects. Hook may use it to decide whether to create or not.

After `on_get`:

| Exit state | Meaning |
|------------|---------|
| `m^ != nil` | item ready — pool returns it to caller |
| `m^ == nil` | pool returns `.Not_Created` to caller |

`.Not_Created` is not always an error. Hook may return nil on purpose — for example, when it decides not to create more items.

`id` is always passed. Needed for creation. Can be read from `node.id` on recycle — but passing it avoids the cast.

---

## on_put contract

Pool calls `on_put` during `pool_put`, outside the lock.

`in_pool_count`: number of items with this `id` currently idle (stored) in the pool — not total live objects.

After `on_put`:

| Exit state | Meaning |
|------------|---------|
| `m^ == nil` | hook disposed it — pool discards |
| `m^ != nil` | pool stores it |

---

## Pool API

```odin
pool_init     :: proc(p: ^Pool, hooks: ^PoolHooks, ids: []int)
pool_close    :: proc(p: ^Pool) -> (list.List, ^PoolHooks)
pool_get      :: proc(p: ^Pool, id: int, mode: Pool_Get_Mode, out: ^Maybe(^PolyNode)) -> Pool_Get_Result
pool_put      :: proc(p: ^Pool, m: ^Maybe(^PolyNode))
pool_get_wait :: proc(p: ^Pool, id: int, out: ^Maybe(^PolyNode), timeout: time.Duration) -> Pool_Get_Result
```

---

## Pool_Get_Mode

```odin
Pool_Get_Mode :: enum {
    Available_Or_New,  // existing item if available, otherwise create
    New_Only,          // always create
    Available_Only,    // existing item only — no creation, on_get not called if none stored
}
```

`pool_get_wait` with timeout = 0 is the same as `pool_get` with `Available_Only`.

---

## Pool_Get_Result

```odin
Pool_Get_Result :: enum {
    Ok,            // item returned in out^
    Not_Available, // Available_Only: no item stored — on_get was not called
    Not_Created,   // on_get ran and returned nil — may be deliberate or failure
    Closed,        // pool is closed
}
```

Caller always knows what to do:
- `.Ok` — use the item.
- `.Not_Available` — no item stored right now. Retry later or call `pool_get_wait`.
- `.Not_Created` — `on_get` ran but returned nil. May be policy or failure — caller decides.
- `.Closed` — pool is shut down. Do not retry.

---

## pool_put contract

- Foreign `id` (not in `ids[]`) → **panic**. Always. Closed or open.
- Closed pool + valid id → `m^` stays non-nil on return. Caller owns the item. Must dispose manually.
- Open pool → `on_put` decides: hook sets `m^=nil` (disposed) or leaves `m^!=nil` (stored).

`pool_put` has no return value. `m^` nil/non-nil after the call is the only signal.

---

## pool_close contract

```odin
nodes, h := pool_close(&p)
```

- Returns all items currently stored in the pool as `list.List`.
- Returns `^PoolHooks` — the pointer passed to `pool_init`.
- Post-close `pool_get`/`pool_put` are safe to call — they return `.Closed` or no-op.

Pool does not call `on_put` during close. User drains manually.

---

## Pool borrows hooks

`pool_init` takes `^PoolHooks`. Pool stores the pointer. User keeps the struct.

`Master` is always heap-allocated. `newMaster` and `freeMaster` are always written together — they are a pair. Both belong to the user's Master package.

```odin
Master :: struct {
    pool:  Pool,
    hooks: PoolHooks,
    alloc: mem.Allocator,  // allocator used to create Master — stored here for freeMaster
    ...
}

newMaster :: proc(alloc: mem.Allocator) -> ^Master {
    m := new(Master, alloc)
    m.alloc = alloc
    m.hooks = PoolHooks{
        ctx    = m,            // ctx points to heap Master
        on_get = master_on_get,
        on_put = master_on_put,
    }
    pool_init(&m.pool, &m.hooks, ids)
    return m
}

freeMaster :: proc(master: ^Master) {
    // 1. close pool — get back stored items
    nodes, _ := pool_close(&master.pool)

    // 2. drain and dispose all returned items
    // NOTE: dispose nodes before freeing other Master resources — dispose code may use Master fields.
    for {
        raw := list.pop_front(&nodes)
        if raw == nil { break }
        // dispose node — master knows how
    }

    // 3. clean up other Master resources
    // ...

    // 4. free Master last — save alloc first, struct is gone after free
    alloc := master.alloc
    free(master, alloc)
}
```

`freeMaster` owns the full teardown. Nothing outside it should call `free` on `^Master` directly.

`ctx` is set at runtime. Do not set it in a compile-time constant.

---

## Hook skeletons

```odin
master_on_get :: proc(ctx: rawptr, id: int, in_pool_count: int, m: ^Maybe(^PolyNode)) {
    master := (^Master)(ctx)
    if m^ == nil {
        // no item available — create new one using master.alloc
    } else {
        // recycled item — reinitialize using master fields
    }
}

master_on_put :: proc(ctx: rawptr, in_pool_count: int, m: ^Maybe(^PolyNode)) {
    master := (^Master)(ctx)
    // use master fields to decide: store or dispose
    // set m^ = nil to dispose, leave non-nil to store
}
```

---

## Rules

- Hooks are called **outside the pool mutex** — guaranteed.
- Hooks may safely take their own locks without deadlock risk.
- Hooks must NOT call `pool_get` or `pool_put` — that would re-enter the pool and deadlock.
- Allocator stored in `ctx` must be thread-safe. Arena is single-threaded — wrong choice.
- `ctx` may be nil. Pool passes it as-is. Hook must handle nil `ctx` safely.
- `ctx` must outlive the pool. Do not tie `ctx` to a stack object or any resource freed before `pool_close`.

---

## Why still called Pool

"Cache", "Store", "Depot" lose the concurrency and reuse meaning.
Pool = items are obtained, used, and returned. That contract is unchanged.
The recycling policy is now pluggable, but it is still a pool.

---

## Open questions


### Pending

(none)
