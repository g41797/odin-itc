// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

package pool

import wakeup "../wakeup"
import "base:intrinsics"
import list "core:container/intrusive/list"
import "core:mem"
import "core:sync"
import "core:time"

// _PoolNode, _PoolMutex, _PoolAllocator, _PoolEvent, _PoolDuration, _PoolWaker keep -vet happy — it does not count generic field types as import usage.
@(private)
_PoolNode :: list.Node
@(private)
_PoolMutex :: sync.Mutex
@(private)
_PoolAllocator :: mem.Allocator
@(private)
_PoolEvent :: Pool_Event
@(private)
_PoolDuration :: time.Duration
@(private)
_PoolWaker :: wakeup.WakeUper

// Pool_State is the internal lifecycle of a pool.
Pool_State :: enum {
	Uninit, // zero value — init not yet called
	Active, // running
	Closed, // destroyed or init failed
}

// Pool_Status is returned by init and get.
Pool_Status :: enum {
	Ok, // success
	Pool_Empty, // free-list empty, strategy = .Pool_Only
	Out_Of_Memory, // allocator returned nil
	Closed, // pool is Closed or Uninit
}

// Pool_Event tells the reset proc why it was called.
Pool_Event :: enum {
	Get, // message is about to be returned to caller
	Put, // message is about to return to free-list (or be freed)
}

// Allocation_Strategy controls get() behavior when the pool is empty.
Allocation_Strategy :: enum {
	Pool_Only, // return nil if pool is empty
	Always, // allocate new if pool is empty (default)
}

// T_Procs holds optional hooks for message lifecycle.
// All three fields are optional. nil = default behavior.
// factory: called for every fresh allocation. nil = new(T, allocator).
// reset:   called on get (recycled) and put (before free-list or freed). nil = no-op.
// dispose: called when permanently destroying a message. nil = free(msg, allocator).
T_Procs :: struct($T: typeid) {
	factory: proc(allocator: mem.Allocator) -> (^T, bool),
	reset:   proc(msg: ^T, e: Pool_Event),
	dispose: proc(msg: ^Maybe(^T)),
}

// Pool is a thread-safe free-list for reusable message objects.
//
// Uses the same "node" field as mbox. A message is never in both at once.
// T must have a field named "node" of type list.Node and "allocator" of type mem.Allocator.
Pool :: struct($T: typeid) {
	allocator:          mem.Allocator,
	mutex:              sync.Mutex,
	cond:               sync.Cond, // wakes waiting get(.Pool_Only) calls
	list:               list.List,
	curr_msgs:          int,
	max_msgs:           int, // 0 = unlimited
	state:              Pool_State, // lifecycle state
	procs:              T_Procs(T), // optional hooks; zero value = all nil = defaults
	waker:              wakeup.WakeUper, // optional — notify non-blocking callers; pass {} for none
	empty_was_returned: bool, // true when get(.Pool_Only,0) found empty; cleared on next put
}

// init prepares the pool and pre-allocates initial_msgs messages.
// max_msgs sets a cap on the free-list size. 0 = unlimited.
// procs: optional table of factory/reset/dispose hooks. nil = all defaults.
// Returns (true, .Ok) on success; (false, .Out_Of_Memory) if any pre-allocation fails.
// On failure all already-allocated messages are freed and state is set to .Closed.
// Note: when factory is nil, pre-allocated messages have msg.allocator unset; get sets it on retrieval.
// Note: when factory is not nil, it must set msg.allocator itself.
init :: proc(
	p: ^Pool($T),
	initial_msgs := 0,
	max_msgs := 0,
	procs: ^T_Procs(T), // nil = use all defaults (new/skip/free)
	waker: wakeup.WakeUper = {},
	allocator := context.allocator,
) -> (
	bool,
	Pool_Status,
) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") ==
	list.Node,
	intrinsics.type_has_field(T, "allocator"),
	intrinsics.type_field_type(T, "allocator") ==
	mem.Allocator {
	if p.state == .Active {
		return false, .Closed
	}
	p.allocator = allocator
	p.max_msgs = max_msgs
	if procs != nil {
		p.procs = procs^
	} else {
		p.procs = {}
	}
	p.waker = waker

	for _ in 0 ..< initial_msgs {
		msg: ^T
		if p.procs.factory != nil {
			ok: bool
			msg, ok = p.procs.factory(allocator)
			if !ok {
				// factory cleans up after itself on failure; free already-allocated messages.
				_destroy_list(p, allocator)
				p.state = .Closed
				return false, .Out_Of_Memory
			}
		} else {
			msg = new(T, allocator)
			if msg == nil {
				_destroy_list(p, allocator)
				p.state = .Closed
				return false, .Out_Of_Memory
			}
		}
		list.push_back(&p.list, &msg.node)
		p.curr_msgs += 1
	}

	p.state = .Active
	return true, .Ok
}

// _destroy_list frees all messages in p.list using dispose or free.
@(private)
_destroy_list :: proc(p: ^Pool($T), allocator: mem.Allocator) {
	for {
		raw := list.pop_front(&p.list)
		if raw == nil {
			break
		}
		m := container_of(raw, T, "node")
		p.curr_msgs -= 1
		if p.procs.dispose != nil {
			m_opt: Maybe(^T) = m
			p.procs.dispose(&m_opt)
		} else {
			free(m, allocator)
		}
	}
}

// get returns a message from the free-list.
// .Always (default): allocates a new one if the pool is empty. timeout is ignored.
// .Pool_Only + timeout==0: returns (nil, .Pool_Empty) immediately if empty (default behavior).
// .Pool_Only + timeout<0: waits forever until put or destroy.
// .Pool_Only + timeout>0: waits up to that duration; returns (nil, .Pool_Empty) on expiry.
// Returns (nil, .Closed) if the pool state is not Active (including destroy while waiting).
// Sets msg.allocator on every returned message (when factory is nil). Calls reset(.Get) only for recycled messages.
get :: proc(
	p: ^Pool($T),
	strategy := Allocation_Strategy.Always,
	timeout: time.Duration = 0,
) -> (
	^T,
	Pool_Status,
) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") ==
	list.Node,
	intrinsics.type_has_field(T, "allocator"),
	intrinsics.type_field_type(T, "allocator") ==
	mem.Allocator {
	sync.mutex_lock(&p.mutex)

	if p.state != .Active {
		sync.mutex_unlock(&p.mutex)
		return nil, .Closed
	}

	raw := list.pop_front(&p.list)
	if raw == nil && strategy == .Pool_Only {
		if timeout == 0 {
			p.empty_was_returned = true
			sync.mutex_unlock(&p.mutex)
			return nil, .Pool_Empty
		}
		// Block until a message is available, the pool is closed, or timeout expires.
		for p.list.head == nil {
			if p.state != .Active {
				sync.mutex_unlock(&p.mutex)
				return nil, .Closed
			}
			ok: bool
			if timeout < 0 {
				sync.cond_wait(&p.cond, &p.mutex)
				ok = true
			} else {
				ok = sync.cond_wait_with_timeout(&p.cond, &p.mutex, timeout)
			}
			if p.state != .Active {
				sync.mutex_unlock(&p.mutex)
				return nil, .Closed
			}
			if !ok {
				sync.mutex_unlock(&p.mutex)
				return nil, .Pool_Empty // timeout expired
			}
		}
		raw = list.pop_front(&p.list)
	}

	if raw != nil {
		p.curr_msgs -= 1
		alloc := p.allocator
		sync.mutex_unlock(&p.mutex)
		msg := container_of(raw, T, "node")
		msg.node = {}
		msg.allocator = alloc
		if p.procs.reset != nil {
			// reset clears the message and exposes stale-pointer bugs early.
			p.procs.reset(msg, .Get)
		}
		return msg, .Ok
	}

	// strategy == .Always and pool was empty: fresh allocation — do not call reset.
	alloc := p.allocator
	sync.mutex_unlock(&p.mutex)

	if p.procs.factory != nil {
		msg, ok := p.procs.factory(alloc)
		if !ok {
			return nil, .Out_Of_Memory
		}
		return msg, .Ok
	}

	msg := new(T, alloc)
	if msg == nil {
		return nil, .Out_Of_Memory
	}
	msg.allocator = alloc
	return msg, .Ok
}

// put returns msg to the free-list.
// nil inner (msg^ == nil) → (nil, true) no-op.
// own message: msg^ = nil, returned to free-list or freed → (nil, true).
// foreign message (allocator differs): msg^ = nil, returns (ptr, false) — caller must free or dispose ptr.
// Calls reset(.Put) before recycling, outside the mutex.
put :: proc(
	p: ^Pool($T),
	msg: ^Maybe(^T),
) -> (
	^T,
	bool,
) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") ==
	list.Node,
	intrinsics.type_has_field(T, "allocator"),
	intrinsics.type_field_type(T, "allocator") ==
	mem.Allocator {
	if msg^ == nil {
		return nil, true // nil inner — no-op
	}
	ptr := (msg^).?

	// Foreign message: wrong allocator — nil caller's var, return ptr.
	if ptr.allocator != p.allocator {
		msg^ = nil
		return ptr, false
	}

	if p.procs.reset != nil {
		p.procs.reset(ptr, .Put)
	}

	sync.mutex_lock(&p.mutex)

	if p.state != .Active || (p.max_msgs > 0 && p.curr_msgs >= p.max_msgs) {
		sync.mutex_unlock(&p.mutex)
		if p.procs.dispose != nil {
			p.procs.dispose(msg)
		} else {
			free(ptr, ptr.allocator)
			msg^ = nil
		}
		return nil, true
	}

	pool_was_empty := p.list.head == nil // capture before push (Zig-aligned: only wake on empty→non-empty)
	ptr.node = {}
	list.push_back(&p.list, &ptr.node)
	p.curr_msgs += 1
	sync.cond_signal(&p.cond) // wake one waiting get(.Pool_Only)
	was_flag := p.empty_was_returned
	p.empty_was_returned = false // always clear
	waker := p.waker
	sync.mutex_unlock(&p.mutex)
	// Call wake outside mutex to avoid deadlock if wake acquires a lock.
	if pool_was_empty && was_flag && waker.wake != nil {
		waker.wake(waker.ctx)
	}
	msg^ = nil
	return nil, true
}

// destroy_msg frees msg^ using the pool's allocator (or dispose hook) and sets msg^ = nil.
// No-op if msg^ is nil. Use when send fails and the unsent message must be freed.
destroy_msg :: proc(p: ^Pool($T), msg: ^Maybe(^T)) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node,
	intrinsics.type_has_field(T, "allocator"),
	intrinsics.type_field_type(T, "allocator") == mem.Allocator {
	if msg^ == nil {
		return
	}
	if p.procs.dispose != nil {
		p.procs.dispose(msg)
	} else {
		ptr := (msg^).?
		free(ptr, p.allocator)
		msg^ = nil
	}
}

// destroy frees all messages in the free-list and marks the pool Closed.
// After destroy: get returns (nil, .Closed), put frees own messages.
// Safe to call more than once.
// Call after all threads have stopped using the pool.
destroy :: proc(p: ^Pool($T)) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node,
	intrinsics.type_has_field(T, "allocator"),
	intrinsics.type_field_type(T, "allocator") == mem.Allocator {
	sync.mutex_lock(&p.mutex)

	if p.state == .Closed {
		sync.mutex_unlock(&p.mutex)
		return
	}
	p.state = .Closed

	// Use p.allocator because pre-allocated messages (factory == nil) have msg.allocator unset.
	alloc := p.allocator
	_destroy_list(p, alloc)
	sync.cond_broadcast(&p.cond) // wake all waiting get(.Pool_Only) calls
	waker := p.waker
	sync.mutex_unlock(&p.mutex)
	// Free waker resources. Do not call wake — callers polling with get(.Pool_Only,0) will get .Closed on next call.
	if waker.close != nil {
		waker.close(waker.ctx)
	}
}

// length returns the number of messages currently in the free-list.
// Thread-safe. Reads curr_msgs under mutex.
length :: proc(p: ^Pool($T)) -> int where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node,
	intrinsics.type_has_field(T, "allocator"),
	intrinsics.type_field_type(T, "allocator") == mem.Allocator {
	sync.mutex_lock(&p.mutex)
	n := p.curr_msgs
	sync.mutex_unlock(&p.mutex)
	return n
}
