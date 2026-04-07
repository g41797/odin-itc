// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

package matryoshka

// matryoshka_dispose is the only way to teardown infrastructure items.
//
// Entry:
//   - m == nil  → no-op
//   - m^ == nil → no-op
//
// The item must be closed before disposal (mbox_close / pool_close).
// Panics if the item is still open, or if the tag is not a known system tag.
//
// Exit:
//   - m^ = nil on success
matryoshka_dispose :: proc(m: ^MayItem) {
	if m == nil || m^ == nil {
		return
	}
	ptr, _ := m^.?
	if mailbox_is_it_you(ptr.tag) {
		_mbox_dispose(m)
	} else if pool_is_it_you(ptr.tag) {
		_pool_dispose(m)
	} else {
		panic("matryoshka_dispose: unknown tag or not an infrastructure item")
	}
}
