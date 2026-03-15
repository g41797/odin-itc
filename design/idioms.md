# Idioms Reference

Quick reference for odin-itc idioms.
Each idiom has a short tag for grep.

---

## Marker scheme

Each idiom has a short tag. The tag appears as a comment at the relevant line in code:

```
// [itc: <tag>]
```

Examples:
```odin
m: Maybe(^Msg) = new(Msg)   // [itc: maybe-container]
defer pool.put(&p, &msg)     // [itc: defer-put]
```

To find all usages of one idiom:
```
grep -r "\[itc: maybe-container\]" examples/ tests/
```

To find all marked lines:
```
grep -r "\[itc:" examples/ tests/
```

Where to find this documentation: `design/idioms.md`

---

## loop_mbox and nbio_mbox

- `loop_mbox` = loop + any wakeup (semaphore, custom, or anything)
- `nbio_mbox` = loop + nbio wakeup (a special case of `loop_mbox`)

`nbio_mbox.init_nbio_mbox` creates a `loop_mbox.Mbox` with an nbio-specific `WakeUper`.
All `loop_mbox` procs work on the returned pointer: `send`, `try_receive_batch`, `close`, `destroy`.

---

## Quick reference

| Tag | Idiom | One line |
|-----|-------|----------|
| `maybe-container` | Idiom 1: Maybe as container | Wrap a heap pointer in `Maybe(^T)` before any ownership-transferring call. |
| `defer-put` | Idiom 2: defer with pool.put | Use `defer pool.put` to return to pool in all paths. |
| `dispose-contract` | Idiom 3: dispose signature contract | A dispose proc takes `^Maybe(^T)`. Nil inner is a no-op. Sets inner to nil on return. |
| `defer-dispose` | Idiom 4: defer with dispose | Use `defer dispose(&m)` so cleanup runs in all paths. |
| `disposable-msg` | Idiom 5: DisposableMsg full lifecycle | Messages with internal heap resources use pool.get, fill, send, receive, pool.put with reset, and a separate dispose for permanent cleanup. |
| `foreign-dispose` | Idiom 6: foreign message with resources | When put returns a foreign pointer, call dispose, not free. |
| `reset-vs-dispose` | Idiom 7: reset vs dispose | reset clears state for reuse. dispose frees internal resources permanently. |
| `dispose-optional` | Idiom 8: dispose is advice | dispose is called by the caller, never by pool or mailbox. |

---

## Idiom details

### Idiom 1: Maybe as container — `maybe-container`

**Problem**: You have a `^T` from `new` or `pool.get`. You want to pass it to `send` or `push` safely.

**Fix**: Wrap it in `Maybe(^T)` before any ownership-transferring call.

```odin
// [itc: maybe-container]
m: Maybe(^Msg) = new(Msg)
mbox.send(&mb, &m)
// m is nil here — the mailbox owns the pointer
```

Why: The `send`/`push`/`put` APIs take `^Maybe(^T)`. On success, they set the inner pointer to nil. This prevents use-after-send. On failure (closed), inner is left unchanged — the caller still owns it.

---

### Idiom 2: defer with pool.put — `defer-put`

**Problem**: You get a message from the pool. You want to return it in all paths, including error paths.

**Fix**: Use `defer pool.put` right after getting the message.

```odin
msg, status := pool.get(&p)
m: Maybe(^Msg) = msg
defer pool.put(&p, &m)  // [itc: defer-put]
// ...
mbox.send(&mb, &m)
// if send succeeded: m is nil, defer put is a no-op
// if send failed: m is non-nil, defer put returns it to pool
```

Why: `pool.put` with nil inner is a no-op. So using defer is safe whether or not send succeeded.

---

### Idiom 3: dispose signature contract — `dispose-contract`

**Problem**: You have a struct with internal heap resources. You need a proc to free them all.

**Fix**: Write a dispose proc that follows the `^Maybe(^T)` contract.

```odin
// [itc: dispose-contract]
disposable_dispose :: proc(msg: ^Maybe(^DisposableMsg)) {
    if msg^ == nil {return}
    ptr := (msg^).?
    if ptr.name != "" {
        delete(ptr.name, ptr.allocator)
    }
    free(ptr, ptr.allocator)
    msg^ = nil
}
```

Contract:
- Takes `^Maybe(^T)`.
- Nil inner is a no-op.
- Sets inner to nil on return.
- Frees all internal resources before freeing the struct itself.

---

### Idiom 4: defer with dispose — `defer-dispose`

**Problem**: You fill a message with internal heap resources, then send it. If send fails, you need to clean up.

**Fix**: Use `defer dispose(&m)` right after filling the message.

```odin
m: Maybe(^DisposableMsg) = msg
defer disposable_dispose(&m)  // [itc: defer-dispose]

m.?.name = strings.clone("hello", m.?.allocator)
if mbox.send(&mb, &m) {
    result = true
}
// if send succeeded: m is nil, defer dispose is a no-op
// if send failed: m is non-nil, defer dispose frees everything
```

Why: `dispose` with nil inner is a no-op. So using defer is safe whether or not send succeeded.

---

### Idiom 5: DisposableMsg full lifecycle — `disposable-msg`

**Problem**: Messages with internal heap resources need careful handling through pool + mailbox.

**Fix**: Use pool.get, fill, send, receive, pool.put with reset, and a separate dispose for permanent cleanup.

```odin
// Producer:
msg, _ := pool.get(&p)
msg.name = strings.clone("hello", msg.allocator)
m: Maybe(^DisposableMsg) = msg
defer disposable_dispose(&m)          // [itc: disposable-msg]
mbox.send(&mb, &m)

// Consumer:
got, _ := mbox.wait_receive(&mb)
_ = got.name                          // use
m2: Maybe(^DisposableMsg) = got
pool.put(&p, &m2)                     // reset clears name automatically
```

reset does NOT free internal resources. It only clears pointers/strings so the recycled slot is clean.
dispose frees internal resources AND the struct itself.

---

### Idiom 6: foreign message with resources — `foreign-dispose`

**Problem**: `pool.put` returns a non-nil pointer when the message is foreign (its allocator does not match the pool). If the foreign message has internal heap resources, `free` alone is not enough.

**Fix**: Call dispose on the returned pointer, not free.

```odin
ptr, recycled := pool.put(&p, &m)
if !recycled && ptr != nil {
    // foreign message — has internal resources
    foreign_opt: Maybe(^DisposableMsg) = ptr
    disposable_dispose(&foreign_opt)  // [itc: foreign-dispose]
}
```

Why: `free(ptr)` only frees the struct. Internal resources (strings, nested heap data) would leak.

---

### Idiom 7: reset vs dispose — `reset-vs-dispose`

**Problem**: It is easy to confuse reset (for reuse) with dispose (for permanent cleanup).

**Fix**: Keep them separate. Never free internal resources in reset.

```odin
// reset: clears state for reuse. Does NOT free internal resources.
// [itc: reset-vs-dispose]
disposable_reset :: proc(msg: ^DisposableMsg, _: pool.Pool_Event) {
    msg.name = ""   // clear the pointer — do NOT call delete here
}

// dispose: frees everything. Call when the message will not be reused.
disposable_dispose :: proc(msg: ^Maybe(^DisposableMsg)) {
    if msg^ == nil {return}
    ptr := (msg^).?
    if ptr.name != "" { delete(ptr.name, ptr.allocator) }
    free(ptr, ptr.allocator)
    msg^ = nil
}
```

Rule: If the message goes back to the pool, reset runs automatically. If it leaves forever, call dispose.

---

### Idiom 8: dispose is advice — `dispose-optional`

**Problem**: The pool and mailbox do not call dispose. Only the caller does. It is easy to forget.

**Fix**: Know when to call dispose. Use defer (Idiom 4) to make it automatic.

```odin
// pool.put calls reset automatically
// mailbox never calls anything on the message
// YOU call dispose when the message will not be recycled  // [itc: dispose-optional]
```

Cases where dispose is needed:
- Error path: send failed, message not in mailbox, must clean up before return.
- Final drain: after `mbox.close`, all returned messages need dispose if they have internal resources.
- Foreign message from `pool.put`: allocator does not match, pool will not free it.

Cases where dispose is NOT needed:
- Message returned to pool via `pool.put` with matching allocator — pool frees it on `destroy`.
- Message successfully sent — receiver is responsible.
