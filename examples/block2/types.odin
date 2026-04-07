package examples_block2

import matryoshka "../.."
import ex1 "../block1"

// Aliases for matryoshka core types.
PolyNode :: matryoshka.PolyNode
MayItem   :: matryoshka.MayItem
Mailbox   :: matryoshka.Mailbox

// Aliases for Layer 1 items, builder, and tags.
Event   :: ex1.Event
Sensor  :: ex1.Sensor
Builder :: ex1.Builder

make_builder    :: ex1.make_builder
ctor            :: ex1.ctor
dtor            :: ex1.dtor
event_is_it_you  :: ex1.event_is_it_you
sensor_is_it_you :: ex1.sensor_is_it_you

EVENT_TAG: rawptr = ex1.EVENT_TAG
SENSOR_TAG: rawptr = ex1.SENSOR_TAG

// Tag alias and helper for infrastructure identity checks.
MAILBOX_TAG: rawptr = matryoshka.MAILBOX_TAG
mailbox_is_it_you :: matryoshka.mailbox_is_it_you
