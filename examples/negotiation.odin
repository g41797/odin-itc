package examples

import mbox ".."
import list "core:container/intrusive/list"
import "core:nbio"
import "core:thread"

// Msg is the shared message type for all examples.
// Field "node" is required by mbox. The name is fixed. The type is list.Node.
Msg :: struct {
	node: list.Node,
	data: int,
}

// _Worker holds pointers to both mailboxes, the request, and the result.
// Lives on the main thread stack. thread.join ensures it outlives the worker thread.
@(private)
_Worker :: struct {
	loop_mb:  ^mbox.Loop_Mailbox(Msg),
	reply_mb: ^mbox.Mailbox(Msg),
	request:  ^Msg,
	ok:       bool,
}

// negotiation_example shows request-reply between a worker thread and an nbio event loop.
//
// Flow:
//   worker  →  Loop_Mailbox  →  nbio loop
//   nbio loop →  Mailbox  →  worker
//
// The worker sends a Msg with data=10.
// The loop increments data by 1 and sends the reply.
// The worker verifies data == 11.
negotiation_example :: proc() -> bool {
	err := nbio.acquire_thread_event_loop()
	if err != nil {
		return false
	}
	defer nbio.release_thread_event_loop()

	loop := nbio.current_thread_event_loop()

	// loop_mb receives requests from the worker.
	loop_mb: mbox.Loop_Mailbox(Msg)
	loop_mb.loop = loop

	// reply_mb sends replies back to the worker.
	reply_mb: mbox.Mailbox(Msg)

	// request and reply live on the main thread stack.
	// thread.join below ensures they outlive the worker thread.
	request := Msg{data = 10}
	reply := Msg{}

	// w lives on the main thread stack too.
	w := _Worker{&loop_mb, &reply_mb, &request, false}

	// Start worker: sends request to loop, waits for reply.
	t := thread.create_and_start_with_poly_data(&w, proc(w: ^_Worker) {
		mbox.send_to_loop(w.loop_mb, w.request)
		msg, recv_err := mbox.wait_receive(w.reply_mb)
		w.ok = recv_err == .None && msg != nil && msg.data == w.request.data + 1
	})

	// Event loop: tick until the request is processed and reply is sent.
	for {
		tick_err := nbio.tick()
		if tick_err != nil {
			break
		}
		msg, ok := mbox.try_receive_loop(&loop_mb)
		if ok {
			reply.data = msg.data + 1
			mbox.send(&reply_mb, &reply)
			break
		}
	}

	thread.join(t)
	thread.destroy(t)

	return w.ok
}
