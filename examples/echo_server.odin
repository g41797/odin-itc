package examples

import mbox "../mbox"
import mpsc "../mpsc"
import pool_pkg "../pool"
import list "core:container/intrusive/list"
import "core:mem"
import "core:sync"
import "core:thread"

// Echo_Msg is a message with a reply address.
// Sent from a client to the server; server echoes it back via reply_to.
Echo_Msg :: struct {
	node:      list.Node,
	allocator: mem.Allocator,
	data:      int,
	reply_to:  ^mbox.Mailbox(Echo_Msg),
}

// _Echo_Server_Ctx holds state for the server thread.
@(private)
_Echo_Server_Ctx :: struct {
	q:       ^mpsc.Queue(Echo_Msg),
	sema:    ^sync.Sema,
	count:   int, // number of messages to process before exiting
}

// echo_server_example shows raw mpsc.Queue + sync.Sema — building blocks of loop_mbox.
//
// N_CLIENTS client threads share a pool with M_MSGS tokens (M_MSGS < N_CLIENTS).
// This forces backpressure: clients block in pool.get until the server echoes a message back.
// The server runs a manual loop — the same pattern that loop_mbox uses internally.
echo_server_example :: proc() -> bool {
	N_CLIENTS :: 8
	M_MSGS    :: 4 // fewer tokens than clients — forces backpressure

	// Shared pool of Echo_Msg.
	p: pool_pkg.Pool(Echo_Msg)
	if ok, _ := pool_pkg.init(&p, initial_msgs = M_MSGS, max_msgs = M_MSGS, reset = nil); !ok {
		return false
	}
	defer pool_pkg.destroy(&p)

	// Server queue and wake semaphore.
	// raw mpsc.Queue + sync.Sema — building blocks of loop_mbox
	server_q: mpsc.Queue(Echo_Msg)
	mpsc.init(&server_q)
	server_sema: sync.Sema

	// Server thread: process exactly N_CLIENTS messages, then exit.
	srv_ctx := _Echo_Server_Ctx{
		q     = &server_q,
		sema  = &server_sema,
		count = N_CLIENTS,
	}
	server_thread := thread.create_and_start_with_data(
		&srv_ctx,
		proc(data: rawptr) {
			c := (^_Echo_Server_Ctx)(data)
			processed := 0
			for processed < c.count {
				sync.sema_wait(c.sema)
				// Drain all available messages on each wake.
				for {
					node := mpsc.pop(c.q)
					if node == nil {break}
					msg := (^Echo_Msg)(node)
					reply_to := msg.reply_to
					reply: Maybe(^Echo_Msg) = msg
					mbox.send(reply_to, &reply)
					processed += 1
				}
			}
		},
	)

	// Client threads: get token, send to server, wait for echo, verify, return token.
	_Client_Ctx :: struct {
		pool:        ^pool_pkg.Pool(Echo_Msg),
		server_q:    ^mpsc.Queue(Echo_Msg),
		server_sema: ^sync.Sema,
		my_id:       int,
		ok:          bool,
	}
	client_threads := make([]^thread.Thread, N_CLIENTS)
	defer delete(client_threads)
	ctxs := make([]_Client_Ctx, N_CLIENTS)
	defer delete(ctxs)

	for i in 0 ..< N_CLIENTS {
		ctxs[i] = _Client_Ctx{
			pool        = &p,
			server_q    = &server_q,
			server_sema = &server_sema,
			my_id       = i,
		}
		client_threads[i] = thread.create_and_start_with_data(
			&ctxs[i],
			proc(data: rawptr) {
				c := (^_Client_Ctx)(data)

				// Get a token (blocks if all tokens are in flight — backpressure).
				msg, status := pool_pkg.get(c.pool, .Pool_Only, -1)
				if status != .Ok || msg == nil {
					return
				}

				// Per-client reply mailbox (stack-allocated — valid for this thread's lifetime).
				my_inbox: mbox.Mailbox(Echo_Msg)
				msg.data = c.my_id
				msg.reply_to = &my_inbox

				// Push to server queue and wake the server.
				m: Maybe(^Echo_Msg) = msg // [itc: maybe-container]
				if !mpsc.push(c.server_q, &m) {
					// push failed — return token to pool
					m2: Maybe(^Echo_Msg) = msg
					_, _ = pool_pkg.put(c.pool, &m2)
					return
				}
				sync.sema_post(c.server_sema)

				// Wait for the echo reply.
				reply, err := mbox.wait_receive(&my_inbox)
				if err != .None || reply == nil {
					return
				}
				c.ok = reply.data == c.my_id

				// Return the token to the pool.
				reply_opt: Maybe(^Echo_Msg) = reply
				_, _ = pool_pkg.put(c.pool, &reply_opt) // [itc: defer-put]
			},
		)
	}

	// Wait for all clients and the server to finish.
	thread.join(server_thread)
	thread.destroy(server_thread)

	for i in 0 ..< N_CLIENTS {
		thread.join(client_threads[i])
		thread.destroy(client_threads[i])
	}

	// Check all clients got correct echoes.
	all_ok := true
	for i in 0 ..< N_CLIENTS {
		if !ctxs[i].ok {
			all_ok = false
		}
	}
	return all_ok
}
