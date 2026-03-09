// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

package mbox

import "base:intrinsics"
import list "core:container/intrusive/list"
import "core:sync"
import "core:time"

// _Node and _Mutex ensure imports are used — required by -vet for generic code.
@(private)
_Node :: list.Node
@(private)
_Mutex :: sync.Mutex
@(private)
_Duration :: time.Duration

Mailbox_Error :: enum {
	None,
	Timeout,
	Closed,
	Interrupted,
}

// Mailbox is for worker threads. It blocks using a condition variable.
// T must have a field named "node" of type list.Node.
Mailbox :: struct($T: typeid) {
	mutex:       sync.Mutex,
	cond:        sync.Cond,
	list:        list.List,
	len:         int,
	closed:      bool,
	interrupted: bool,
}

// send adds msg to the mailbox and wakes one waiting thread.
// Returns false if the mailbox is closed.
send :: proc(m: ^Mailbox($T), msg: ^T) -> bool where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	sync.mutex_lock(&m.mutex)
	defer sync.mutex_unlock(&m.mutex)
	if m.closed {
		return false
	}
	list.push_back(&m.list, &msg.node)
	m.len += 1
	sync.cond_signal(&m.cond)
	return true
}

// try_receive returns a message if one is available, without blocking.
try_receive :: proc(
	m: ^Mailbox($T),
) -> (
	msg: ^T,
	ok: bool,
) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") ==
	list.Node {
	sync.mutex_lock(&m.mutex)
	defer sync.mutex_unlock(&m.mutex)
	if m.len == 0 {
		return nil, false
	}
	return _pop(m), true
}

// wait_receive blocks until a message arrives, the mailbox closes, or timeout.
// Use timeout < 0 for infinite wait.
wait_receive :: proc(
	m: ^Mailbox($T),
	timeout: time.Duration = -1,
) -> (
	msg: ^T,
	err: Mailbox_Error,
) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") ==
	list.Node {
	sync.mutex_lock(&m.mutex)
	defer sync.mutex_unlock(&m.mutex)

	if m.len > 0 {
		return _pop(m), .None
	}
	if m.closed {
		return nil, .Closed
	}
	if m.interrupted {
		return nil, .Interrupted
	}
	if timeout == 0 {
		return nil, .Timeout
	}

	for m.len == 0 {
		ok: bool
		if timeout < 0 {
			sync.cond_wait(&m.cond, &m.mutex)
			ok = true
		} else {
			ok = sync.cond_wait_with_timeout(&m.cond, &m.mutex, timeout)
		}
		if m.closed {
			return nil, .Closed
		}
		if m.interrupted {
			return nil, .Interrupted
		}
		if !ok {
			return nil, .Timeout
		}
	}

	return _pop(m), .None
}

// interrupt wakes all waiting threads. They return .Interrupted.
interrupt :: proc(m: ^Mailbox($T)) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	sync.mutex_lock(&m.mutex)
	m.interrupted = true
	sync.mutex_unlock(&m.mutex)
	sync.cond_broadcast(&m.cond)
}

// close prevents new messages and wakes all waiting threads.
close :: proc(m: ^Mailbox($T)) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	sync.mutex_lock(&m.mutex)
	m.closed = true
	sync.mutex_unlock(&m.mutex)
	sync.cond_broadcast(&m.cond)
}

// reset clears the closed and interrupted flags so the mailbox can be reused.
reset :: proc(m: ^Mailbox($T)) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	sync.mutex_lock(&m.mutex)
	m.interrupted = false
	m.closed = false
	sync.mutex_unlock(&m.mutex)
}

// _pop removes and returns the front message. Caller must hold m.mutex.
@(private)
_pop :: proc(m: ^Mailbox($T)) -> ^T where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	raw := list.pop_front(&m.list)
	m.len -= 1
	return container_of(raw, T, "node")
}
