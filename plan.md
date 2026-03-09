
# Test & Example Generation Plan

## 1. Objective
Create a suite of multithreaded tests and examples to verify the **Otofu** messaging system. This ensures the **Standard Mailbox** (Blocking) and the **Loop Mailbox** (Waking) work together across thread boundaries without deadlocks or race conditions.

---

## 2. Test Suites

### A. Standard Mailbox Suite (`mbox_test.odin`)
* **Stress Test:** 10 Producer threads sending 1,000 messages each to 1 Consumer thread.
* **Timeout Test:** Verify `wait_receive` returns `.Timeout` when the mailbox is empty.
* **Interrupt Test:** Verify all waiting threads wake up with `.Interrupted` when `interrupt()` is called.
* **Close Test:** Verify threads cannot `send()` to a closed mailbox.

### B. Loop Mailbox Suite (`loop_mbox_test.odin`)
* **Waker Test:** Verify that `send_to_loop` triggers an `nbio` wake event.
* **Single-Receiver Drain:** Verify the `nbio` thread can pull multiple messages pushed by many threads in a single tick.
* **Congestion Test:** Push messages faster than the loop can process to verify the `was_empty` waker logic.

### C. Integration (The "Negotiation") Suite (`negotiation_test.odin`)
* **Round-Trip Test:** 1.  **Worker** creates a `Request` node and pushes it to the **Loop_Mailbox**.
    2.  **Worker** calls `wait_receive` on its own **Mailbox**.
    3.  **NBIO Thread** wakes up, processes the request, and pushes a `Response` back to the **Worker's Mailbox**.
    4.  **Worker** wakes up and verifies the data.

---

## 3. Reference Design



### Shared Node Structure
All tests use an intrusive node structure.
```odin
Node :: struct {
    next: ^Node,
    data: int,
}

```

---

## 4. Source: `mbox.odin` (Standard Blocking)

```odin
package mbox

import "core:sync"
import "core:time"

Mailbox_Error :: enum {
	None,
	Timeout,
	Closed,
	Interrupted,
}

Mailbox :: struct($T: typeid) {
	mutex:       sync.Mutex,
	cond:        sync.Cond,
	head:        ^T,
	tail:        ^T,
	len:         int,
	closed:      bool,
	interrupted: bool,
}

send :: proc(m: ^Mailbox($T), node: ^T) -> bool {
	sync.mutex_lock(&m.mutex)
	defer sync.mutex_unlock(&m.mutex)
	if m.closed do return false
	node.next = nil
	if m.tail != nil { m.tail.next = node } 
	else { m.head = node }
	m.tail = node
	m.len += 1
	sync.cond_signal(&m.cond)
	return true
}

wait_receive :: proc(m: ^Mailbox($T), timeout: time.Duration = -1) -> (node: ^T, err: Mailbox_Error) {
	sync.mutex_lock(&m.mutex)
	defer sync.mutex_unlock(&m.mutex)
	for m.len == 0 {
		if m.closed      do return nil, .Closed
		if m.interrupted do return nil, .Interrupted
		if timeout == 0  do return nil, .Timeout
		ok: bool
		if timeout < 0 { sync.cond_wait(&m.cond, &m.mutex); ok = true } 
		else { ok = sync.cond_timedwait(&m.cond, &m.mutex, timeout) }
		if !ok do return nil, .Timeout
	}
	node = m.head
	m.head = m.head.next
	if m.head == nil { m.tail = nil }
	m.len -= 1
	node.next = nil
	return node, .None
}

interrupt :: proc(m: ^Mailbox($T)) {
	sync.mutex_lock(&m.mutex); m.interrupted = true; sync.mutex_unlock(&m.mutex)
	sync.cond_broadcast(&m.cond)
}

close :: proc(m: ^Mailbox($T)) {
	sync.mutex_lock(&m.mutex); m.closed = true; sync.mutex_unlock(&m.mutex)
	sync.cond_broadcast(&m.cond)
}

```

---

## 5. Source: `loop_mbox.odin` (NBIO Waking)

```odin
package mbox

import "core:sync"
import "nbio"

Loop_Mailbox :: struct($T: typeid) {
	mutex:  sync.Mutex,
	head:   ^T,
	tail:   ^T,
	len:    int,
	loop:   ^nbio.Event_Loop,
	closed: bool,
}

send_to_loop :: proc(m: ^Loop_Mailbox($T), node: ^T) -> bool {
	sync.mutex_lock(&m.mutex)
	defer sync.mutex_unlock(&m.mutex)
	if m.closed do return false
	node.next = nil
	was_empty := m.len == 0
	if m.tail != nil { m.tail.next = node } 
	else { m.head = node }
	m.tail = node
	m.len += 1
	if was_empty do nbio.wake_up(m.loop)
	return true
}

try_receive :: proc(m: ^Loop_Mailbox($T)) -> (node: ^T, ok: bool) {
	sync.mutex_lock(&m.mutex)
	defer sync.mutex_unlock(&m.mutex)
	if m.len == 0 do return nil, false
	node = m.head
	m.head = m.head.next
	if m.head == nil { m.tail = nil }
	m.len -= 1
	node.next = nil
	return node, true
}

```

---

## 6. Implementation Task for AI Agent

**Task:** Create `negotiation_example.odin`.

1. Initialize one `nbio.Event_Loop`.
2. Create a `Loop_Mailbox` (Target: nbio loop).
3. Create a `Mailbox` (Target: Worker thread).
4. Spawn a thread that:
* Sends a node to `Loop_Mailbox`.
* Calls `wait_receive` on its own `Mailbox`.


5. In the `nbio` loop:
* On wake, call `try_receive`.
* Increment node data.
* Call `send` back to the Worker's `Mailbox`.


6. Print success when Worker receives the incremented data.
