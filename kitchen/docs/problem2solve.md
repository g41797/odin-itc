# The problem this solves

## Problem 1 — is it gone or still mine?

You have a thing. You call an exchange function — a point where ownership may transfer to another thread.
May. Not always. The other side might be closed. Full. Not ready.

After the call: is your thing gone? Or is it still yours?

In single-threaded code this question doesn't exist — functions are deterministic.
At thread boundaries, it does.

You need one check at the call site. No flags. No separate state.

`^Maybe(^T)` fits:

- `m^ != nil` → still yours
- `m^ == nil` → went through

One rule. Visible at every call site.

This idea was written up on the Odin forum first:
[`^Maybe(^T)` — visible pointer transfer in Odin](https://forum.odin-lang.org/t/maybe-t-visible-pointer-transfer-in-odin/1679/1)

The first version of this project was built on `^Maybe($T)`.

---

## Problem 2 — real applications exchange many types

`^Maybe($T)` is generic and type-safe. One type per exchange point.

Then came a real application: events, commands, responses — all through the same exchange point.
`^Maybe($T)` locks you to one type. You need a second exchange point for the next type, a third for the next.
Infrastructure multiplies. Code duplicates.

`PolyNode` — one base, one exchange point. Works for everything. Suitable not for everyone — see [Doll 1](layer1_quickref.md).

---

## Together: `^Maybe(^PolyNode)`

`^Maybe(^PolyNode)` combines both solutions:

- `^Maybe(^...)` — `m^ != nil` means yours, `m^ == nil` means gone
- `^PolyNode` — one infrastructure for every type that embeds `PolyNode`

One ownership rule. One infrastructure. All your types.
