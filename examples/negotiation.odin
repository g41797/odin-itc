package examples

import ilist "core:container/intrusive/list"
import "core:nbio"
import mbox ".."

// Msg is the shared node type used in all examples.
// Field "node" is required by mbox — fixed name, type ilist.Node.
Msg :: struct {
	node: ilist.Node,
	data: int,
}

negotiation_example :: proc() -> bool {
	_ = mbox.Mailbox(Msg){}
	_ = mbox.Loop_Mailbox(Msg){}
	_ = nbio.Event_Loop{}
	return true
}
