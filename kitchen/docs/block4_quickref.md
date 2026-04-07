# Doll 4 — Infrastructure as Items — Quick Reference

> **Prerequisite:** [Doll 1](block1_quickref.md) — ownership. [Doll 2](block2_quickref.md) — movement. [Doll 3](block3_quickref.md) — reuse.

---

You get:

* Mailbox and Pool become items.
* Same ownership rules everywhere.
* Same transport for everything.

No new magic.  
Just one model applied everywhere.

---

## Everything is a PolyNode

Mailbox is an item.  
Pool is an item.

They embed `PolyNode` at offset 0.

```odin
_Mbox :: struct {
    using poly: PolyNode,
    alloc: mem.Allocator,
    // private fields
}

_Pool :: struct {
    using poly: PolyNode,
    alloc: mem.Allocator,
    // private fields
}
```

Public handle hides internals:

```odin
Mailbox :: ^PolyNode
Pool    :: ^PolyNode
```

You pass them as `^PolyNode`.  
You cast only inside matryoshka.

---

## Tag rules

One field.
One rule: nil is invalid.

| Value | Meaning |
| ----- | ------- |
| `nil` | invalid |
| `&mailbox_tag` | mailbox infrastructure |
| `&pool_tag` | pool infrastructure |
| any other non-nil | user data |

Examples:

```odin
MAILBOX_TAG: rawptr = &mailbox_tag
POOL_TAG:    rawptr = &pool_tag
```

**Common behavior:** All Mailbox/Pool operations validate the handle's tag. If the tag does not match `MAILBOX_TAG` or `POOL_TAG` respectively, the operation will `panic`.

User tags and infrastructure tags never collide.
Each is a unique file-scope address.

---

## Ownership is unchanged

Same `MayItem`.

Same rules:

* `m^ != nil` → you own it
* `m^ == nil` → not yours

Mailbox follows the same rules.  
Pool follows the same rules.

Nothing special here.

---

## Creation — simple only

Create directly.

```odin
m := mbox_new(alloc)
p := pool_new(alloc)
```

Each item stores its allocator inside.

No central manager.

No global factory.

---

## Dispose — self-destroy

```odin
matryoshka_dispose :: proc(m: ^MayItem)
```

How it works:

* Check `m == nil` → return
* Check `m^ == nil` → return
* Read `m^.tag`
* Cast to internal type
* Check state

| State  | Action                      |
| ------ | --------------------------- |
| closed | free using stored allocator |
| open   | panic                       |

After success:

* `m^ = nil`

You can only dispose closed items.


---

## Mailbox as item

You can send a Mailbox.

### Send side:

* Wrap mailbox pointer as `^PolyNode`
* Put into `Maybe`
* Call `mbox_send`

### Receive side:

* Receive into `Maybe`
* Cast to `Mailbox`
* Use normally

Mailbox is just another item.

---

## Pool as item

Same idea.

* Can be sent
* Can be owned
* Can be matryoshka_disposed

No special path.

---

## Self-send (advanced)

Mailbox can send itself.

Not what the doctor ordered...

But anyway

### Steps:

* Convert mailbox to `^PolyNode`
* Put into `Maybe`
* Send into same mailbox

Result:

* Sender loses ownership
* Receiver gains ownership

This is valid.

This is rare.

Use only if you know why.

---

## Pooling Tools

You cannot do this.  
Do not try to get/put Mailboxes or Pools into a Pool.  
If the pool is open, it will treat them as a "foreign" tag and panic.

