# mbox — Examples and Patterns

mbox is intrusive. The message struct is the node. No extra allocation per message.

---

## 1. Basic send and receive

```odin
import mbox "path/to/odin-mbox"
import list "core:container/intrusive/list"

Msg :: struct {
    node: list.Node,  // required
    data: int,
}

// Sender:
msg := Msg{data = 42}
ok := mbox.send(&mb, &msg)

// Receiver (non-blocking):
got, ok := mbox.try_receive(&mb)

// Receiver (blocking, infinite wait):
got, err := mbox.wait_receive(&mb)

// Receiver (blocking, with timeout):
got, err := mbox.wait_receive(&mb, 100 * time.Millisecond)
```

---

## 2. Tagged envelope pattern (multiple message types)

One mailbox. Multiple message types. Use a common base struct with a kind field.

```odin
import mbox "path/to/odin-mbox"
import list "core:container/intrusive/list"
import "core:fmt"

Msg_Kind :: enum {
    Process_Image,
    Save_File,
    Shutdown,
}

// Base struct. All message types start with this.
Envelope :: struct {
    node: list.Node,  // required — must be first or at known offset
    kind: Msg_Kind,
}

// Specific message type. Embeds Envelope.
Image_Msg :: struct {
    using base: Envelope,
    width:      int,
    height:     int,
}

// Send:
img := new(Image_Msg)
img.kind = .Process_Image
img.width = 1920
mbox.send(&mb, &img.base)  // send the base Envelope

// Receive and dispatch:
got, err := mbox.wait_receive(&mb)
if err == .None {
    switch got.kind {
    case .Process_Image:
        full := (^Image_Msg)(got)
        fmt.printf("Processing %d wide image\n", full.width)
        free(full)
    case .Save_File:
        // ...
    case .Shutdown:
        // ...
    }
}
```

Note: for this pattern, `mb` is `mbox.Mailbox(Envelope)`.

---

## 3. Graceful shutdown

```odin
// Sender signals shutdown:
mbox.close(&mb)

// Receiver checks for it:
msg, err := mbox.wait_receive(&mb)
switch err {
case .None:
    // process msg
case .Closed:
    // mailbox is closed, stop receiving
case .Timeout:
    // timed out, check other conditions
case .Interrupted:
    // interrupted, stop or retry
}
```

---

## 4. Interrupt for cancellation

```odin
// From any thread, cancel all waiters:
mbox.interrupt(&mb)

// Each waiting thread gets .Interrupted:
msg, err := mbox.wait_receive(&mb)
if err == .Interrupted {
    // stop work
}

// After interrupt, reset to allow reuse:
mbox.reset(&mb)
```

---

## 5. nbio loop mailbox — request-reply

Worker thread sends a request to the nbio loop. The loop replies via a regular mailbox.

```odin
// Setup (on the loop thread):
loop_mb: mbox.Loop_Mailbox(Req)
loop_mb.loop = nbio.current_thread_event_loop()

reply_mb: mbox.Mailbox(Reply)

// Worker thread:
req := Req{data = 10}
mbox.send_to_loop(&loop_mb, &req)

reply, err := mbox.wait_receive(&reply_mb)

// nbio loop — drain on wake:
for {
    req, ok := mbox.try_receive_loop(&loop_mb)
    if !ok { break }
    r := Reply{data = req.data + 1}
    mbox.send(&reply_mb, &r)
}
```

See `examples/negotiation.odin` for a working version of this pattern.

---

## 6. High-throughput stress pattern

Many producers, one consumer.

```odin
// Consumer thread:
for {
    msg, err := mbox.wait_receive(&mb)
    if err == .Closed { break }
    // process msg
}

// Each producer thread:
for i in 0 ..< N {
    mbox.send(&mb, &msgs[i])
}

// After all producers finish:
mbox.close(&mb)
```

See `examples/stress.odin` for a working version of this pattern.
