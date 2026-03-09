package tests

import "core:testing"
import "core:thread"
import "core:time"
import list "core:container/intrusive/list"
import examples "../examples"
import mbox ".."

// --- example tests ---

@(test)
test_negotiation :: proc(t: ^testing.T) {
	testing.expect(t, examples.negotiation_example(), "negotiation_example failed")
}

@(test)
test_stress :: proc(t: ^testing.T) {
	testing.expect(t, examples.stress_example(), "stress_example failed")
}

// --- Mailbox edge-case tests ---

// Msg is the local test message type.
Msg :: struct {
	node: list.Node,
	data: int,
}

@(test)
test_send_and_try_receive :: proc(t: ^testing.T) {
	mb: mbox.Mailbox(Msg)
	m := Msg{data = 42}

	ok := mbox.send(&mb, &m)
	testing.expect(t, ok, "send should return true")

	got, ok2 := mbox.try_receive(&mb)
	testing.expect(t, ok2, "try_receive should return ok")
	testing.expect(t, got != nil && got.data == 42, "try_receive wrong data")
}

@(test)
test_try_receive_empty :: proc(t: ^testing.T) {
	mb: mbox.Mailbox(Msg)
	got, ok := mbox.try_receive(&mb)
	testing.expect(t, !ok, "try_receive on empty mailbox should return ok=false")
	testing.expect(t, got == nil, "try_receive on empty mailbox should return nil")
}

@(test)
test_timeout_on_empty :: proc(t: ^testing.T) {
	mb: mbox.Mailbox(Msg)
	_, err := mbox.wait_receive(&mb, 10 * time.Millisecond)
	testing.expect(t, err == .Timeout, "wait_receive on empty mailbox should timeout")
}

@(test)
test_zero_timeout :: proc(t: ^testing.T) {
	mb: mbox.Mailbox(Msg)
	_, err := mbox.wait_receive(&mb, 0)
	testing.expect(t, err == .Timeout, "wait_receive with timeout=0 should return .Timeout immediately")
}

@(test)
test_close_blocks_send :: proc(t: ^testing.T) {
	mb: mbox.Mailbox(Msg)
	m := Msg{data = 1}

	mbox.close(&mb)

	ok := mbox.send(&mb, &m)
	testing.expect(t, !ok, "send to closed mailbox should return false")
}

@(test)
test_close_wakes_waiter :: proc(t: ^testing.T) {
	mb: mbox.Mailbox(Msg)
	result: mbox.Mailbox_Error

	// Start a waiter thread.
	thread.run_with_poly_data2(&mb, &result, proc(mb: ^mbox.Mailbox(Msg), result: ^mbox.Mailbox_Error) {
		_, err := mbox.wait_receive(mb)
		result^ = err
	})

	time.sleep(10 * time.Millisecond)
	mbox.close(&mb)
	time.sleep(20 * time.Millisecond)

	testing.expect(t, result == .Closed, "waiter should get .Closed after close()")
}

@(test)
test_interrupt_wakes_waiter :: proc(t: ^testing.T) {
	mb: mbox.Mailbox(Msg)
	result: mbox.Mailbox_Error

	// Start a waiter thread.
	thread.run_with_poly_data2(&mb, &result, proc(mb: ^mbox.Mailbox(Msg), result: ^mbox.Mailbox_Error) {
		_, err := mbox.wait_receive(mb)
		result^ = err
	})

	time.sleep(10 * time.Millisecond)
	mbox.interrupt(&mb)
	time.sleep(20 * time.Millisecond)

	testing.expect(t, result == .Interrupted, "waiter should get .Interrupted after interrupt()")
}

@(test)
test_reset_allows_reuse :: proc(t: ^testing.T) {
	mb: mbox.Mailbox(Msg)
	m := Msg{data = 7}

	mbox.close(&mb)
	mbox.reset(&mb)

	ok := mbox.send(&mb, &m)
	testing.expect(t, ok, "send after reset should succeed")

	got, ok2 := mbox.try_receive(&mb)
	testing.expect(t, ok2 && got != nil && got.data == 7, "try_receive after reset should return message")
}

@(test)
test_fifo_order :: proc(t: ^testing.T) {
	mb: mbox.Mailbox(Msg)
	a := Msg{data = 1}
	b := Msg{data = 2}
	c := Msg{data = 3}

	mbox.send(&mb, &a)
	mbox.send(&mb, &b)
	mbox.send(&mb, &c)

	got1, _ := mbox.try_receive(&mb)
	got2, _ := mbox.try_receive(&mb)
	got3, _ := mbox.try_receive(&mb)

	testing.expect(t, got1 != nil && got1.data == 1, "first message should be 1")
	testing.expect(t, got2 != nil && got2.data == 2, "second message should be 2")
	testing.expect(t, got3 != nil && got3.data == 3, "third message should be 3")
}

@(test)
test_wait_receive_gets_message :: proc(t: ^testing.T) {
	mb: mbox.Mailbox(Msg)
	m := Msg{data = 99}

	// Send from a separate thread after a short delay.
	thread.run_with_poly_data2(&mb, &m, proc(mb: ^mbox.Mailbox(Msg), m: ^Msg) {
		time.sleep(5 * time.Millisecond)
		mbox.send(mb, m)
	})

	got, err := mbox.wait_receive(&mb)
	testing.expect(t, err == .None, "wait_receive should not error")
	testing.expect(t, got != nil && got.data == 99, "wait_receive should get the sent message")
}
