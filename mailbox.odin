// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

package matryoshka

import "base:intrinsics"
import list "core:container/intrusive/list"
import "core:mem"
import "core:sync"
import "core:time"

////////////////////
Mailbox :: ^PolyNode
////////////////////

//////////////////////
MAILBOX_ID: int : -1
//////////////////////


@(private = "file")
_Mbox :: struct {
	using poly:  PolyNode,
	alctr:       mem.Allocator,
	mutex:       sync.Mutex,
	cond:        sync.Cond,
	list:        list.List,
	len:         int,
	closed:      bool,
	interrupted: bool,
}

mbox_new :: proc(alloc: mem.Allocator) -> Mailbox {

	mbx, err := new(_Mbox, alloc)
	if err != .None {
		return nil
	}

	mbx^.alctr = alloc
	mbx^.id = MAILBOX_ID

	return cast(Mailbox)mbx
}

SendResult :: enum {
	Ok,
	Closed,
	Invalid,
}

mbox_send :: proc(mb: Mailbox, m: ^MayItem) -> SendResult {

	if m == nil || m^ == nil {
		return .Invalid
	}

	ptr, ok := m^.?

	if !ok {
		return .Invalid
	}

	if ptr^.id == 0 {
		return .Invalid
	}

	mbx_Ptr := _unwrap(mb)

	if mbx_Ptr^.id != MAILBOX_ID {
		panic("non-mailbox is used for mailbox operations")
	}

	sync.mutex_lock(&mbx_Ptr^.mutex)
	defer sync.mutex_unlock(&mbx_Ptr^.mutex)


	if (mbx_Ptr^.closed) {
		return .Closed
	}

	list.push_back(&mbx_Ptr^.list, &ptr^.node)

	mbx_Ptr^.len += 1

	m^ = nil

	sync.cond_signal(&mbx_Ptr^.cond)


	return .Ok
}

RecvResult :: enum {
	Ok,
	Closed,
	Interrupted,
	Already_In_Use,
	Invalid,
	Timeout,
}

mbox_wait_receive :: proc(mb: Mailbox, m: ^MayItem, timeout: time.Duration = -1) -> RecvResult {

	infinite := timeout < 0
	start := time.now()

	if m == nil {
		return .Invalid
	}

	if m^ != nil {
		return .Already_In_Use
	}

	mbx_Ptr := _unwrap(mb)

	if mbx_Ptr^.id != MAILBOX_ID {
		panic("non-mailbox is used for mailbox operations")
	}


	sync.mutex_lock(&mbx_Ptr^.mutex)
	defer sync.mutex_unlock(&mbx_Ptr^.mutex)

	for mbx_Ptr^.len == 0 {

		if mbx_Ptr^.closed {
			return .Closed
		}

		if mbx_Ptr^.interrupted {
			mbx_Ptr^.interrupted = false
			return .Interrupted
		}

		if infinite {
			sync.cond_wait(&mbx_Ptr^.cond, &mbx_Ptr^.mutex)
			continue
		}

		elapsed := time.since(start)
		if elapsed >= timeout {
			return .Timeout
		}

		remaining := timeout - elapsed
		sync.cond_wait_with_timeout(&mbx_Ptr^.cond, &mbx_Ptr^.mutex, remaining)

	}

	if mbx_Ptr^.closed {
		return .Closed
	}

	if mbx_Ptr^.interrupted {
		mbx_Ptr^.interrupted = false
		return .Interrupted
	}

	m^ = _pop(mbx_Ptr)
	sync.cond_signal(&mbx_Ptr^.cond)
	return .Ok
}

try_receive_batch :: proc(mb: Mailbox) -> (list.List, RecvResult) {

	result := list.List{}

	mbx_Ptr := _unwrap(mb)

	if mbx_Ptr^.id != MAILBOX_ID {
		panic("non-mailbox is used for mailbox operations")
	}


	sync.mutex_lock(&mbx_Ptr^.mutex)
	defer sync.mutex_unlock(&mbx_Ptr^.mutex)

	if mbx_Ptr^.closed {
		return result, .Closed
	}

	if mbx_Ptr^.interrupted {
		mbx_Ptr^.interrupted = false
		return result, .Interrupted
	}

	result = mbx_Ptr^.list
	mbx_Ptr^.list = list.List{}
	mbx_Ptr^.len = 0
	sync.cond_signal(&mbx_Ptr^.cond)
	return result, .Ok

}

IntrResult :: enum {
	Ok,
	Closed,
	Already_Interrupted,
}


mbox_interrupt :: proc(mb: Mailbox) -> IntrResult {

	mbx_Ptr := _unwrap(mb)

	if mbx_Ptr^.id != MAILBOX_ID {
		panic("non-mailbox is used for mailbox operations")
	}


	sync.mutex_lock(&mbx_Ptr^.mutex)
	defer sync.mutex_unlock(&mbx_Ptr^.mutex)

	if mbx_Ptr^.closed {
		return .Closed
	}

	if mbx_Ptr^.interrupted {
		return .Already_Interrupted
	}

	mbx_Ptr^.interrupted = true
	sync.cond_signal(&mbx_Ptr^.cond)

	return .Ok
}


mbox_close :: proc(mb: Mailbox) -> list.List {

	result := list.List{}

	mbx_Ptr := _unwrap(mb)

	if mbx_Ptr^.id != MAILBOX_ID {
		panic("non-mailbox is used for mailbox operations")
	}


	sync.mutex_lock(&mbx_Ptr^.mutex)
	defer sync.mutex_unlock(&mbx_Ptr^.mutex)

	if mbx_Ptr^.closed {
		return result
	}

	result = mbx_Ptr^.list
	mbx_Ptr^.list = list.List{}
	mbx_Ptr^.len = 0

	mbx_Ptr^.closed = true
	sync.cond_broadcast(&mbx_Ptr^.cond)

	return result

}

@(private)
_unwrap :: proc(m: Mailbox) -> ^_Mbox {
	return cast(^_Mbox)m
}

@(private)
_pop :: proc(m: ^_Mbox) -> ^PolyNode {
	raw := list.pop_front(&m^.list)
	m^.len -= 1
	return cast(^PolyNode)raw
}
