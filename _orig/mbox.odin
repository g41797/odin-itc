package mbox

import "core:sync"
import "core:time"

// Mailbox_Error defines why a receive operation failed.
Mailbox_Error :: enum {
	None,
	Timeout,
	Closed,
	Interrupted,
}

// Mailbox is for Standard Threads (Workers/Clients).
// It uses a Condition Variable to park the thread.
Mailbox :: struct($T: typeid) {
	mutex:       sync.Mutex,
	cond:        sync.Cond,
	
	head:        ^T,
	tail:        ^T,
	len:         int,

	closed:      bool,
	interrupted: bool,
}

// send adds a node to the mailbox and wakes one waiting thread.
send :: proc(m: ^Mailbox($T), node: ^T) -> bool {
	sync.mutex_lock(&m.mutex)
	defer sync.mutex_unlock(&m.mutex)

	if m.closed do return false

	// Intrusive push
	node.next = nil
	if m.tail != nil {
		m.tail.next = node
	} else {
		m.head = node
	}
	m.tail = node
	m.len += 1

	sync.cond_signal(&m.cond)
	return true
}

// try_receive checks for a node and returns immediately.
try_receive :: proc(m: ^Mailbox($T)) -> (node: ^T, ok: bool) {
	sync.mutex_lock(&m.mutex)
	defer sync.mutex_unlock(&m.mutex)

	if m.len == 0 do return nil, false

	node = m.head
	m.head = m.head.next
	if m.head == nil {
		m.tail = nil
	}
	m.len -= 1
	
	return node, true
}

// wait_receive parks the thread until data arrives, timeout, or interrupt.
// Use timeout < 0 for infinite wait.
wait_receive :: proc(m: ^Mailbox($T), timeout: time.Duration = -1) -> (node: ^T, err: Mailbox_Error) {
	sync.mutex_lock(&m.mutex)
	defer sync.mutex_unlock(&m.mutex)

	// 1. Immediate check before sleeping
	if m.len > 0 {
		return _internal_pop(m), .None
	}

	// 2. State checks
	if m.closed      do return nil, .Closed
	if m.interrupted do return nil, .Interrupted
	if timeout == 0  do return nil, .Timeout

	// 3. The Sleep Loop (Handles spurious wakeups)
	for m.len == 0 {
		ok: bool
		if timeout < 0 {
			sync.cond_wait(&m.cond, &m.mutex)
			ok = true
		} else {
			// Odin's cond_timedwait takes duration
			ok = sync.cond_timedwait(&m.cond, &m.mutex, timeout)
		}

		if m.closed      do return nil, .Closed
		if m.interrupted do return nil, .Interrupted
		if !ok           do return nil, .Timeout
	}

	return _internal_pop(m), .None
}

// interrupt wakes all sleeping threads. They return .Interrupted.
interrupt :: proc(m: ^Mailbox($T)) {
	sync.mutex_lock(&m.mutex)
	m.interrupted = true
	sync.mutex_unlock(&m.mutex)
	sync.cond_broadcast(&m.cond)
}

// close prevents new messages and wakes all sleepers.
close :: proc(m: ^Mailbox($T)) {
	sync.mutex_lock(&m.mutex)
	m.closed = true
	sync.mutex_unlock(&m.mutex)
	sync.cond_broadcast(&m.cond)
}

// reset allows a mailbox to be reused after interrupt/close.
reset :: proc(m: ^Mailbox($T)) {
	sync.mutex_lock(&m.mutex)
	m.interrupted = false
	m.closed = false
	sync.mutex_unlock(&m.mutex)
}
