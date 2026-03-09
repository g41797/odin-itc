package examples

import mbox ".."

stress_example :: proc() -> bool {
	_ = mbox.Mailbox(Msg){}
	return true
}
