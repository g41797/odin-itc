package examples_block1

import "core:mem"

// Builder provides functions to construct and destruct
// PolyNode-based items with different types.
// Very naive - don't use in produnction
Builder :: struct {
	alloc: mem.Allocator,
}

// make_builder creates a Builder with the given allocator.
make_builder :: proc(alloc: mem.Allocator) -> Builder {
	return Builder{alloc = alloc}
}

// ctor allocates the correct type for tag and sets tag.
// Returns nil for unknown tags.
ctor :: proc(b: ^Builder, tag: rawptr) -> MayItem {
	if event_is_it_you(tag) {
		ev := new(Event, b.alloc)
		if ev == nil {
			return nil
		}
		ev^.tag = EVENT_TAG
		return MayItem(&ev.poly)
	} else if sensor_is_it_you(tag) {
		s := new(Sensor, b.alloc)
		if s == nil {
			return nil
		}
		s^.tag = SENSOR_TAG
		return MayItem(&s.poly)
	}
	return nil
}

// dtor frees internal resources and the node, then sets m^ = nil.
// Safe to call with m == nil or m^ == nil (no-op).
dtor :: proc(b: ^Builder, m: ^MayItem) {
	if m == nil {
		return
	}
	ptr, ok := m^.?
	if !ok {
		return
	}
	if event_is_it_you(ptr.tag) {
		free((^Event)(ptr), b.alloc)
	} else if sensor_is_it_you(ptr.tag) {
		free((^Sensor)(ptr), b.alloc)
	} else {
		panic("unknown tag")
	}
	m^ = nil
}
