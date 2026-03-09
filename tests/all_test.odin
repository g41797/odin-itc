package tests

import "core:testing"
import examples "../examples"

@(test)
test_negotiation :: proc(t: ^testing.T) {
	testing.expect(t, examples.negotiation_example())
}

@(test)
test_stress :: proc(t: ^testing.T) {
	testing.expect(t, examples.stress_example())
}
