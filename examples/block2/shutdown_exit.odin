package examples_block2

import "core:fmt"
import "core:thread"
import matryoshka "../.."

@(private)
exit_tag: matryoshka.PolyTag = {}
EXIT_TAG: rawptr = &exit_tag

// Worker waits for items.
worker_exit_proc :: proc(t: ^thread.Thread) {
	m := (^Master)(t.data)
	if m == nil {
		return
	}

	for {
		mi: MayItem
		if matryoshka.mbox_wait_receive(m.inbox, &mi) != .Ok {
			return
		}

		ptr, _ := mi.?
		if ptr.tag == EXIT_TAG {
			fmt.println("Worker: received EXIT message, shutting down")
			// Exit node is a raw PolyNode — free with the builder allocator.
			free(ptr, m.builder.alloc)
			mi = nil
			return
		}

		fmt.println("Worker: processed item")
		dtor(&m.builder, &mi)
	}
}

// example_shutdown_exit demonstrates shutdown via an exit message.
example_shutdown_exit :: proc() -> bool {
	alloc := context.allocator
	m := newMaster(alloc)
	if m == nil {
		return false
	}
	defer freeMaster(m)

	t := thread.create(worker_exit_proc)
	if t == nil {
		return false
	}
	t.data = m
	thread.start(t)
	defer thread.destroy(t)

	// Send normal data.
	mi_d := ctor(&m.builder, EVENT_TAG)
	if mi_d != nil {
		if matryoshka.mbox_send(m.inbox, &mi_d) != .Ok {
			dtor(&m.builder, &mi_d)
		}
	}

	// Send exit message.
	// Our builder doesn't know EXIT_TAG, so we create the node manually.
	exit_node := new(PolyNode, alloc)
	if exit_node != nil {
		exit_node.tag = EXIT_TAG
		mi_exit: MayItem = exit_node
		if matryoshka.mbox_send(m.inbox, &mi_exit) != .Ok {
			// Send failed — free manually since this is a raw PolyNode.
			free(exit_node, alloc)
		}
	}

	thread.join(t)
	return true
}
