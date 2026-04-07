package examples_block3

import matryoshka "../.."
import ex1 "../block1"
import ex2 "../block2"

// Aliases for matryoshka core types.
PolyNode :: matryoshka.PolyNode
MayItem   :: matryoshka.MayItem
Mailbox   :: matryoshka.Mailbox
Pool      :: matryoshka.Pool
PoolHooks :: matryoshka.PoolHooks

// Aliases for Layer 1 items, builder, and tags.
Event   :: ex1.Event
Sensor  :: ex1.Sensor
Builder :: ex1.Builder

make_builder     :: ex1.make_builder
ctor             :: ex1.ctor
dtor             :: ex1.dtor
event_is_it_you  :: ex1.event_is_it_you
sensor_is_it_you :: ex1.sensor_is_it_you

EVENT_TAG: rawptr = ex1.EVENT_TAG
SENSOR_TAG: rawptr = ex1.SENSOR_TAG

// Aliases for Layer 2 Master.
Master     :: ex2.Master
newMaster  :: ex2.newMaster
freeMaster :: ex2.freeMaster
