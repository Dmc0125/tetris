#+test
package tests

import "core:fmt"
import "core:log"
import "core:testing"

import game "../game"

@(test)
test_sp_queue :: proc(t: ^testing.T) {
	queue: game.SP_Queue
	game.sp_queue_init(&queue)

	kinds := [game.TetrominoKind]int{}
	for _ in 0 ..< 7 {
		current_kind := game.sp_queue_next(&queue)
		kinds[current_kind] += 1
	}

	log.info("Each kind should be drawn only once")
	for k in game.TetrominoKind {
		#partial switch k {
		case .None:
			if !testing.expect_value(t, kinds[k], 0) {
				log.error("None should not be drawn")
			}
		case:
			if !testing.expect_value(t, kinds[k], 1) {
				log.errorf("%s was not drawn exactly once: %d", k, kinds[k])
			}
		}
	}

	log.info("After each kind is drawn, queue should be reset")
	testing.expect_value(t, queue.index, 0)
}
