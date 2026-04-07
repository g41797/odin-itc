//+test
package tests_block1

import matryoshka "../.."
import ex "../../examples/block1"
import "core:testing"

@(test)
test_factory_event :: proc(t: ^testing.T) {
	b := ex.make_builder(context.allocator)
	m := ex.ctor(&b, ex.EVENT_TAG)
	testing.expect(t, m != nil, "ctor(EVENT_TAG) must return non-nil")
	ptr, ok := m.?
	testing.expect(t, ok, "Maybe must unwrap")
	testing.expect(t, ex.event_is_it_you(ptr.tag), "ctor must set tag == EVENT_TAG")
	// Clean up.
	ex.dtor(&b, &m)
}

@(test)
test_factory_sensor :: proc(t: ^testing.T) {
	b := ex.make_builder(context.allocator)
	m := ex.ctor(&b, ex.SENSOR_TAG)
	testing.expect(t, m != nil, "ctor(SENSOR_TAG) must return non-nil")
	ptr, ok := m.?
	testing.expect(t, ok, "Maybe must unwrap")
	testing.expect(t, ex.sensor_is_it_you(ptr.tag), "ctor must set tag == SENSOR_TAG")
	ex.dtor(&b, &m)
}

@(test)
test_factory_unknown :: proc(t: ^testing.T) {
	b := ex.make_builder(context.allocator)
	m := ex.ctor(&b, nil)
	testing.expect(t, m == nil, "ctor(nil tag) must return nil")
}

@(test)
test_dispose :: proc(t: ^testing.T) {
	b := ex.make_builder(context.allocator)
	m := ex.ctor(&b, ex.EVENT_TAG)
	testing.expect(t, m != nil, "ctor must succeed before dtor test")
	ex.dtor(&b, &m)
	testing.expect(t, m == nil, "dtor must set handle to nil")
}

@(test)
test_roundtrip :: proc(t: ^testing.T) {
	b := ex.make_builder(context.allocator)

	// Event roundtrip
	m_ev := ex.ctor(&b, ex.EVENT_TAG)
	testing.expect(t, m_ev != nil, "Event ctor must succeed")
	ex.dtor(&b, &m_ev)
	testing.expect(t, m_ev == nil, "Event dtor must nil the handle")

	// Sensor roundtrip
	m_s := ex.ctor(&b, ex.SENSOR_TAG)
	testing.expect(t, m_s != nil, "Sensor ctor must succeed")
	ex.dtor(&b, &m_s)
	testing.expect(t, m_s == nil, "Sensor dtor must nil the handle")
}

@(test)
test_dispose_nil_handle :: proc(t: ^testing.T) {
	// dtor must be safe when called with a nil Maybe value (m^ == nil).
	b := ex.make_builder(context.allocator)
	m: Maybe(^matryoshka.PolyNode) = nil
	ex.dtor(&b, &m) // must not crash
	testing.expect(t, m == nil, "dtor on nil handle must leave it nil")
}

@(test)
test_example_builder :: proc(t: ^testing.T) {
	testing.expect(t, ex.example_builder(context.allocator), "example_builder must return true")
}
