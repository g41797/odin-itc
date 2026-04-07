//+test
package tests_block1

import matryoshka "../.."
import ex "../../examples/block1"
import list "core:container/intrusive/list"
import "core:testing"

@(test)
test_produce_consume :: proc(t: ^testing.T) {
	testing.expect(
		t,
		ex.example_produce_consume(context.allocator),
		"produce_consume must return true",
	)
}

@(test)
test_ownership :: proc(t: ^testing.T) {
	testing.expect(t, ex.example_ownership(context.allocator), "ownership must return true")
}

@(test)
test_list_order :: proc(t: ^testing.T) {
	// Items pop in FIFO order; tags match what was pushed.
	l: list.List

	e1 := new(ex.Event)
	e1^.tag = ex.EVENT_TAG
	e1.code = 1
	list.push_back(&l, &e1.poly.node)

	s1 := new(ex.Sensor)
	s1^.tag = ex.SENSOR_TAG
	s1.value = 2.0
	list.push_back(&l, &s1.poly.node)

	// Pop first — must be Event
	raw1 := list.pop_front(&l)
	testing.expect(t, raw1 != nil, "first pop must not be nil")
	poly1 := (^matryoshka.PolyNode)(raw1)
	testing.expect(t, ex.event_is_it_you(poly1.tag), "first pop tag must be EVENT_TAG")
	got_e1 := (^ex.Event)(poly1)
	testing.expect(t, got_e1.code == 1, "first pop code must be 1")
	free(got_e1)

	// Pop second — must be Sensor
	raw2 := list.pop_front(&l)
	testing.expect(t, raw2 != nil, "second pop must not be nil")
	poly2 := (^matryoshka.PolyNode)(raw2)
	testing.expect(t, ex.sensor_is_it_you(poly2.tag), "second pop tag must be SENSOR_TAG")
	got_s1 := (^ex.Sensor)(poly2)
	testing.expect(t, got_s1.value == 2.0, "second pop value must be 2.0")
	free(got_s1)

	// List must be empty
	testing.expect(t, list.pop_front(&l) == nil, "list must be empty after consuming all")
}

@(test)
test_known_tags :: proc(t: ^testing.T) {
	// Every tag must be non-nil and distinct.
	testing.expect(t, ex.EVENT_TAG != nil, "EVENT_TAG must be non-nil")
	testing.expect(t, ex.SENSOR_TAG != nil, "SENSOR_TAG must be non-nil")
	testing.expect(t, ex.EVENT_TAG != ex.SENSOR_TAG, "EVENT_TAG and SENSOR_TAG must differ")
}
