package examples_block1

import matryoshka "../.."

// Alias for matryoshka.PolyNode — shortens usage across this package.
PolyNode :: matryoshka.PolyNode

// Alias for matryoshka.MayItem — ownership handle.
MayItem :: matryoshka.MayItem

// Alias for matryoshka.PolyTag — tag type for item identity.
PolyTag :: matryoshka.PolyTag

@(private)
event_tag: PolyTag = {}

@(private)
sensor_tag: PolyTag = {}

// EVENT_TAG is the unique tag for Event items.
EVENT_TAG: rawptr = &event_tag

// SENSOR_TAG is the unique tag for Sensor items.
SENSOR_TAG: rawptr = &sensor_tag

// event_is_it_you reports whether tag belongs to an Event.
event_is_it_you :: #force_inline proc(tag: rawptr) -> bool {return tag == EVENT_TAG}

// sensor_is_it_you reports whether tag belongs to a Sensor.
sensor_is_it_you :: #force_inline proc(tag: rawptr) -> bool {return tag == SENSOR_TAG}

// Event carries a numeric code and a human-readable message.
Event :: struct {
	using poly: PolyNode, // offset 0 — required for safe cast
	code:       int,
	message:    string,
}

// Sensor carries a name and a floating-point measurement.
Sensor :: struct {
	using poly: PolyNode, // offset 0 — required for safe cast
	name:       string,
	value:      f64,
}
