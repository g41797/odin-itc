package examples_layer1

import matryoshka "../.."

// Ctor_Dtor provides functions to construct and destruct PolyNodes.
// These are typically used by pools or other resource managers.
Ctor_Dtor :: struct {
	ctor: proc(id: int) -> Maybe(^matryoshka.PolyNode),
	dtor: proc(m: ^Maybe(^matryoshka.PolyNode)),
}

// item_ctor allocates the correct type for id and sets id.
// Returns nil for unknown ids.
item_ctor :: proc(id: int) -> Maybe(^matryoshka.PolyNode) {
	switch ItemId(id) {
	case .Event:
		ev := new(Event)
		ev.poly.id = id
		return Maybe(^matryoshka.PolyNode)(&ev.poly)
	case .Sensor:
		s := new(Sensor)
		s.poly.id = id
		return Maybe(^matryoshka.PolyNode)(&s.poly)
	case:
		return nil
	}
}

// item_dtor frees internal resources and the node, then sets m^ = nil.
// Safe to call with m == nil or m^ == nil (no-op).
item_dtor :: proc(m: ^Maybe(^matryoshka.PolyNode)) {
	if m == nil {
		return
	}
	ptr, ok := m.?
	if !ok {
		return
	}
	switch ItemId(ptr.id) {
	case .Event:
		free((^Event)(ptr))
	case .Sensor:
		free((^Sensor)(ptr))
	case:
		// Unknown id — still free the raw allocation to avoid leaks.
		free(ptr)
	}
	m^ = nil
}

// make_ctor_dtor returns a Ctor_Dtor for Event + Sensor.
make_ctor_dtor :: proc() -> Ctor_Dtor {
	return Ctor_Dtor{ctor = item_ctor, dtor = item_dtor}
}
