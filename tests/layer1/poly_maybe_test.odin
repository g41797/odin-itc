//+test
package tests_layer1

import "core:testing"
import ex "../../examples/layer1"

@test
test_smallest_example :: proc(t: ^testing.T) {
	testing.expect(t, ex.run_poly_maybe_example(), "Smallest possible example (PolyNode + MayItem) failed.")
}
