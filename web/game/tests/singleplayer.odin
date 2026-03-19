package tests

import sp "../game"
import "core:testing"

@(test)
test_sp_queue :: proc(t: ^testing.T) {
	queue: sp.SP_Queue
	_ = queue


	testing.expect_value(t, 5, 5)
}
