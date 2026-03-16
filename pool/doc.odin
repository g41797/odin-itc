/*
Package pool is a thread-safe free-list for reusable message objects.

Use it with mbox when you send many messages.

How it works:
- Call init to set up the pool and pre-allocate messages.
- Call get to take a message from the pool (or allocate a new one).
- Send the message via mbox.
- After receiving, call put to return the message to the pool.
- Call destroy when done. It frees all remaining pool messages.

The pool reuses the same "node" field that mbox requires.
A message is never in both the pool and a mailbox at the same time.

Your struct must have two fields:
  - "node" of type list.Node
  - "allocator" of type mem.Allocator  (set by pool.get on every retrieval)

	import list "core:container/intrusive/list"
	import "core:mem"

	My_Msg :: struct {
	    node:      list.Node,      // required by both pool and mbox
	    allocator: mem.Allocator,  // required by pool
	    data:      int,
	}

Idiom reference: design/idioms.md

Status returns:
- init returns (bool, Pool_Status): (true, .Ok) on success; (false, .Out_Of_Memory) on pre-allocation failure.
- get returns (^T, Pool_Status): .Ok, .Pool_Empty, .Out_Of_Memory, or .Closed.
  With .Pool_Only strategy and timeout parameter:
  - timeout==0 (default): return immediately if empty (.Pool_Empty). Non-blocking.
  - timeout<0: wait forever until put or destroy.
  - timeout>0: wait up to that duration; returns (nil, .Pool_Empty) on expiry.
  - Returns (nil, .Closed) if pool is destroyed while waiting.
- put returns ^T: nil if recycled or freed. Returns the original pointer if the message is foreign (msg.allocator != pool allocator) — caller must free or dispose it.

Lifecycle:
- Pool_State.Uninit: zero value, init not yet called.
- Pool_State.Active: pool is running.
- Pool_State.Closed: destroyed or init failed.

T_Procs — optional hooks for message lifecycle:
- Pass a ^T_Procs(T) to init to register hooks. Pass nil to use all defaults.
- All three fields are optional independently. nil field = default behavior.
- factory: called for every fresh allocation (pre-alloc in init, .Always path in get).
  - nil: new(T, allocator) is used. get sets msg.allocator.
  - not nil: must allocate the struct, initialize internal resources, set msg.allocator.
  - On failure: must clean up everything itself, return (nil, false).
- reset: called with .Get when a recycled message is returned from the free-list.
  - Called with .Put before a message is returned to the free-list (or permanently freed).
  - nil: no reset (current behavior).
  - NOT called for fresh allocations.
  - Called outside the pool mutex.
- dispose: called instead of free when permanently destroying a message.
  - Sites: destroy loop, put when pool is full or closed, destroy_msg.
  - nil: free(msg, allocator) is used.
  - not nil: must free all internal resources, free the struct itself, set msg^ = nil.
*/
package pool

/*
Note: Some test procedures may appear in the generated documentation.
This is because they are part of the same package to allow for white-box testing.
*/
