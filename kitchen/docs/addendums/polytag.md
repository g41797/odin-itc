# 0006 — PolyTag Pattern for Identity

## Update

Introduce a minimal tag type in `polynode.odin`:

```odin
PolyTag :: struct {
    _: u8,
}

PolyNode :: struct {
    using node: list.Node,
    tag:        rawptr,
}
```

---

## Reason

* Keep `tag` flexible (`rawptr`)
* Provide a **convention** for safe usage
* Avoid forcing structure on users
* Ensure stable and unique identities

---

## Recommended Pattern per Type

For every item or component (`ABC`), define:

### 1. Private static tag instance

```odin
@(private)
abc_tag: PolyTag = {}
```

✔ This is correct Odin syntax
✔ File-local
✔ Has stable address

---

### 2. Public identity variable

```odin
ABC_TAG: rawptr = &abc_tag
```

✔ Package-level variable
✔ Safe to compare
✔ No allocation

---

### 3. Helper function

```odin
abc_is_it_you :: proc(tag: rawptr) -> bool {
    return tag == ABC_TAG
}
```

Optional inline:

```odin
abc_is_it_you :: #force_inline proc(tag: rawptr) -> bool {
    return tag == ABC_TAG
}
```

---

## Usage

### Assign tag

```odin
node.tag = ABC_TAG
```

---

### Check type

```odin
if abc_is_it_you(node.tag) {
    // handle ABC
}
```

---

## Notes

### Static lifetime (important)

This is correct:

```odin
@(private)
abc_tag: PolyTag = {}
```

Do NOT use:

```odin
proc f() {
    t := PolyTag{}
    node.tag = &t // ❌ invalid (stack)
}
```

---

### Uniqueness

Each type must have its own tag.
`PolyTag` has `_: u8` — each instance has a unique address:

```odin
@(private) event_tag:  PolyTag = {}
@(private) sensor_tag: PolyTag = {}
```

---

### Why `PolyTag` exists

* documents intent
* prevents accidental misuse
* allows future extension if needed

---

### Why `rawptr` is still used

* allows alternative patterns:

  * descriptor pointer
  * function pointer
* does not restrict users

---

## Alternative (advanced)

User may bypass `PolyTag`:

```odin
node.tag = cast(rawptr)event_dtor
```

or:

```odin
node.tag = &event_desc
```

Matryoshka does not depend on interpretation.

---

## AI Refactoring Rules

When replacing `id: int`:

1. Replace field:

```odin
id: int
```

→

```odin
tag: rawptr
```

---

2. For each type:

* add private tag instance
* add `*_TAG` package-level variable
* replace all `id` assignments

---

3. Replace checks:

```odin
if node.id == EVENT_ID
```

→

```odin
if node.tag == EVENT_TAG
```

or:

```odin
if event_is_it_you(node.tag)
```

---

## Summary

* `PolyTag` provides a minimal convention
* `rawptr` preserves flexibility
* static tag instance ensures uniqueness
* pattern is safe, simple, and scalable

