/*
Package nbio_mbox provides a non-blocking mailbox for nbio event loops.

It wraps loop_mbox.Mbox with a wakeup mechanism that signals the nbio event loop
when a message is sent from another thread.

Two wake mechanisms are available via Nbio_Wakeuper_Kind:

  .UDP (default) — A loopback UDP socket. The sender writes 1 byte; nbio wakes on receipt.
      No queue capacity limit.

  .Timeout — A zero-duration nbio timeout. Works on all platforms.
      Throttled with a CAS flag to prevent 128-slot cross-thread queue overflow.

Thread model:

  init_nbio_mbox : any thread
  send (loop_mbox.send) : any thread — lock-free MPSC enqueue + wake signal
  try_receive    : event-loop thread only (MPSC single-consumer rule)
  close          : event-loop thread only (nbio.remove panics cross-thread)
  destroy        : event-loop thread (after close)

"Event-loop thread" is the single thread calling nbio.tick for the given loop.

Quick start:

	loop := nbio.current_thread_event_loop()
	m, err := nbio_mbox.init_nbio_mbox(Msg, loop)
	defer {
		loop_mbox.close(m)
		loop_mbox.destroy(m)
	}

	// sender thread:
	loop_mbox.send(m, msg)

	// event-loop thread:
	for {
		nbio.tick(timeout)
		batch := loop_mbox.try_receive_batch(m)
		for node := list.pop_front(&batch); node != nil; node = list.pop_front(&batch) {
			msg := (^Msg)(node)
			_ = msg // handle — free or return to pool
		}
	}


*/
package nbio_mbox
