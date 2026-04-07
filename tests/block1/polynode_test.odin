//+test
package tests_block1

import matryoshka "../.."
import "core:testing"

@(test)
test_poly_node_zero_value :: proc(t: ^testing.T) {
	n: matryoshka.PolyNode
	testing.expect(t, n.tag == nil, "zero-value PolyNode must have tag == nil")
	testing.expect(t, n.prev == nil, "zero-value node.prev must be nil")
	testing.expect(t, n.next == nil, "zero-value node.next must be nil")
}

@(test)
test_maybe_nil_semantics :: proc(t: ^testing.T) {
	m: Maybe(^matryoshka.PolyNode)
	testing.expect(t, m == nil, "zero-value Maybe must be nil")
	n: matryoshka.PolyNode
	m = &n
	testing.expect(t, m != nil, "Maybe set to non-nil pointer must not be nil")
	testing.expect(t, m.? == &n, "Maybe.? must return the stored pointer")
}

@(test)
test_offset_zero_cast :: proc(t: ^testing.T) {
	// Verify that embedding PolyNode at offset 0 makes (^PolyNode)(item) safe.
	Item :: struct {
		using poly: matryoshka.PolyNode, // offset 0
		value:      int,
	}
	tag: matryoshka.PolyTag = {}
	item: Item
	item.tag = &tag
	item.value = 42
	// Cast to ^PolyNode — safe because PolyNode is at offset 0
	poly := (^matryoshka.PolyNode)(&item)
	testing.expect(t, poly.tag == &tag, "cast to ^PolyNode must preserve tag")
	// Cast back — safe because tag is known
	back := (^Item)(poly)
	testing.expect(t, back.value == 42, "cast back to ^Item must preserve value")
}

@(test)
test_tag_nil_is_uninitialized :: proc(t: ^testing.T) {
	// tag == nil means the node was never stamped.
	// Callers must check tag != nil before use.
	n: matryoshka.PolyNode
	testing.expect(t, n.tag == nil, "uninitialized PolyNode has tag == nil (invalid)")
	tag: matryoshka.PolyTag = {}
	n.tag = &tag
	testing.expect(t, n.tag != nil, "after stamping, tag must be != nil")
}
