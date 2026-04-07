# Doll 1 — PolyNode + MayItem — Quick Reference

> See [Deep Dive](block1_deepdive.md) for diagrams, examples, and extended explanations.

---

You get:

- Items that travel.
- Ownership that is visible.
- A factory that creates and destroys.

No threads. No queues. No pools.

Just clean ownership in one thread.

---

## PolyNode — the traveling struct

<!-- snippet: polynode.odin:16-52 -->
```odin
PolyTag :: struct {
    _: u8,
}

PolyNode :: struct {
    using node: list.Node, // intrusive link — .prev, .next
    tag:        rawptr,    // type discriminator, must be != nil
}
```

Every type that travels through matryoshka embeds `PolyNode` at **offset 0** via `using`:

<!-- snippet: examples/block1/types.odin:33-37 -->
```odin
Event :: struct {
    using poly: PolyNode, // offset 0 — required for safe cast
    code:       int,
    message:    string,
}
```

### Offset 0 rule

The cast `(^Event)(node)` is valid only if `PolyNode` is first.

- This is a convention.
- You follow it.
- Matryoshka has no compile-time check for this.

### Tag rules

- `tag` must be != nil.
- nil is the zero value of `rawptr`.
- An uninitialized `PolyNode` has `tag == nil`.

That is how you catch missing initialization — immediately.

Set `tag` once at creation using a static tag address.

Define one tag per type:

<!-- snippet: examples/block1/types.odin:14-30 -->
```odin
@(private)
event_tag: PolyTag = {}

@(private)
sensor_tag: PolyTag = {}

EVENT_TAG: rawptr = &event_tag
SENSOR_TAG: rawptr = &sensor_tag

event_is_it_you :: #force_inline proc(tag: rawptr) -> bool {return tag == EVENT_TAG}
sensor_is_it_you :: #force_inline proc(tag: rawptr) -> bool {return tag == SENSOR_TAG}
```

---

## MayItem — who owns this item

```
m: MayItem

m^ == nil                       m^ != nil
┌───────────┐                   ┌───────────┐
│    nil    │  ← not yours      │   ptr ────┼──► [ PolyNode | your fields ]
└───────────┘                   └───────────┘
                                     you own this — must transfer, recycle, or dispose
```

**Core Ownership Rule:** `m^ == nil` means the item is not yours (e.g., empty or transferred). `m^ != nil` means you own the item and must transfer, recycle, or dispose of it.

### The Ownership Deal

All Matryoshka functions pass items using `^MayItem`.

```odin
m: MayItem

// m^ != nil  →  you own it. You must transfer, recycle, or dispose it.
// m^ == nil  →  not yours. Transfer complete, or nothing here.
// m == nil   →  nil handle. This is a bug. Function returns error.
```

**What you send:**

| `m` value | Meaning | What happens |
|-----------|---------|--------------|
| `m == nil` | nil handle | error |
| `m^ == nil` | you hold nothing | depends on function |
| `m^ != nil` | you own the item | proceed |

**What you get back:**

| Event | `m^` after return |
|-------|------------------|
| success (you gave it) | `nil` — you no longer hold it |
| success (you received it) | `non-nil` — you hold it now |
| failure | unchanged — you still hold it |

**Honest notes:**

- `Maybe` is a convention, not a guarantee.
- `MayItem` is a who-holds-this handle — one item, one holder.
- Copying without clearing the original is aliasing. Aliasing is forbidden.
- Nothing stops you from doing it — Odin has no borrow checker.
- Matryoshka makes who-holds-what visible.
- Following it is on you.

---

## Builder — create and destroy by tag

Builder stores an allocator and provides `ctor` / `dtor` procs:

<!-- snippet: examples/block1/builder.odin:7-15 -->
```odin
Builder :: struct {
    alloc: mem.Allocator,
}

make_builder :: proc(alloc: mem.Allocator) -> Builder {
    return Builder{alloc = alloc}
}
```

`ctor(b: ^Builder, tag: rawptr) -> MayItem`:

- Allocates the correct type for `tag` using `b.alloc`.
- Sets `poly.tag`.
- Wraps the result in `MayItem`.
- Returns nil for unknown tags or allocation failure.

`dtor(b: ^Builder, m: ^MayItem)`:

- Frees the item using `b.alloc`.
- Sets `m^ = nil`.
- Safe to call with `m == nil` or `m^ == nil` — no-op.
- Panics on unknown tag — a programming error.

