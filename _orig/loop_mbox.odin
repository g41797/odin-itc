package mbox

import "core:sync"
import "core:nbio"

// Loop_Mailbox is for the nbio I/O Engine (The Actor).
// It does NOT use a Condition Variable.
// It uses nbio.wake_up to interrupt the kernel sleep.
Loop_Mailbox :: struct($T: typeid) {
	mutex:  sync.Mutex,
	
	head:   ^T,
	tail:   ^T,
	len:    int,

	// The specific nbio loop that owns this mailbox.
	loop:   ^nbio.Event_Loop,
	
	closed: bool,
}

// send_to_loop adds a node and "kicks" the nbio loop.
// Returns true if the loop was actually kicked (was empty).
send_to_loop :: proc(m: ^Loop_Mailbox($T), node: ^T) -> bool {
	sync.mutex_lock(&m.mutex)
	defer sync.mutex_unlock(&m.mutex)

	if m.closed do return false

	// Intrusive push
	node.next = nil
	was_empty := m.len == 0

	if m.tail != nil {
		m.tail.next = node
	} else {
		m.head = node
	}
	m.tail = node
	m.len += 1

	// Only kick the loop if it was empty. 
	// If not empty, the loop is already processing or has a pending kick.
	if was_empty {
		nbio.wake_up(m.loop)
	}

	return true
}

// try_receive_loop is the ONLY way the nbio thread gets data.
// It should be called in a loop until it returns nil.
try_receive_loop :: proc(m: ^Loop_Mailbox($T)) -> (node: ^T, ok: bool) {
	sync.mutex_lock(&m.mutex)
	defer sync.mutex_unlock(&m.mutex)

	if m.len == 0 do return nil, false

	node = m.head
	m.head = m.head.next
	if m.head == nil {
		m.tail = nil
	}
	m.len -= 1
	
	node.next = nil
	return node, true
}

// close prevents new messages from being sent to the loop.
close_loop :: proc(m: ^Loop_Mailbox($T)) {
	sync.mutex_lock(&m.mutex)
	m.closed = true
	sync.mutex_unlock(&m.mutex)
	
	// We wake the loop one last time so it can see it is closed 
	// and perform any final cleanup/draining.
	nbio.wake_up(m.loop)
}

// stats returns the current pressure on the engine.
stats :: proc(m: ^Loop_Mailbox($T)) -> int {
	// We don't lock here; an approximate value is usually enough for telemetry.
	return m.len
}