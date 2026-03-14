package examples

import list "core:container/intrusive/list"
import "core:mem"

// Msg is the shared message type for all examples.
// "node" is required by mbox (and pool). The name is fixed. The type is list.Node.
// "allocator" is required by pool — set by pool.get on every retrieval.
Msg :: struct {
	node:      list.Node,
	allocator: mem.Allocator,
	data:      int,
}
