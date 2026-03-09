package examples

import mbox ".."
import "core:sync"
import "core:thread"

// stress_example shows high-throughput multi-producer single-consumer messaging.
//
// 10 producer threads each send 1000 messages.
// 1 consumer thread receives all 10,000 messages via wait_receive.
// The example returns true if all messages were received.
//
// Messages are pre-allocated on the heap. Producers index into their slice.
// After the consumer counts all 10,000, it signals done.
// Main waits for done, then closes the mailbox.
stress_example :: proc() -> bool {
	N :: 10_000
	P :: 10

	// Pre-allocate all messages. Producers only write their node links.
	// Safe to free after consumer counts all N.
	msgs := make([]Msg, N)
	defer delete(msgs)

	mb: mbox.Mailbox(Msg)
	done: sync.Sema

	// Consumer: counts N messages then signals done.
	thread.run_with_poly_data2(&mb, &done, proc(mb: ^mbox.Mailbox(Msg), done: ^sync.Sema) {
		count := 0
		for count < N {
			_, err := mbox.wait_receive(mb)
			if err == .None {
				count += 1
			}
		}
		sync.sema_post(done)
	})

	// P producers: each sends its slice of messages.
	for p in 0 ..< P {
		slice := msgs[p * (N / P) : (p + 1) * (N / P)]
		thread.run_with_poly_data2(&mb, slice, proc(mb: ^mbox.Mailbox(Msg), slice: []Msg) {
			for i in 0 ..< len(slice) {
				mbox.send(mb, &slice[i])
			}
		})
	}

	// Wait for consumer to count all N messages.
	sync.sema_wait(&done)
	mbox.close(&mb)

	return true
}
