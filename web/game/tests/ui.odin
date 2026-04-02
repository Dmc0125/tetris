#+test
package tests

import "base:runtime"
import "core:log"
import "core:testing"

import ui "../ui"

Rect :: ui.Rect
Vec2 :: ui.Vec2

@(test)
test_container_layout :: proc(t: ^testing.T) {
	// context = runtime.default_context()

	// width  = 5 * 16 = 80
	// height = 16
	header := ui.Text {
		value     = "Hello",
		font_size = .Medium,
	}

	{
		// width  = 10 + 80 + 10
		// height = 15 + 16 + 15
		container := ui.Container {
			perm_allocator = context.temp_allocator,
			sizing    = [2]ui.Sizing{.Auto, .Auto},
			padding   = Vec2{10, 15},
			spacing   = 5,
			direction = .Vertical,
			alignment = .Start,
		}
		log.info("container: ", container)
		ui.container_add_child(&container, &header)
		ui.container_layout(&container, Vec2{1920, 1080}, context.temp_allocator)

		log.info("Header has correct size")
		testing.expect_value(t, header.rect.z, 80)
		testing.expect_value(t, header.rect.w, 16)

		log.info("Header has correct position")
		testing.expect_value(t, header.rect.x, 10)
		testing.expect_value(t, header.rect.y, 15)

		log.info("Container has correct size")
		testing.expect_value(t, container.rect.z, 100)
		testing.expect_value(t, container.rect.w, 46)

		log.info("Container has correct position")
		testing.expect_value(t, container.rect.x, 0)
		testing.expect_value(t, container.rect.y, 0)
	}

	{
		container := ui.Container {
			perm_allocator = context.temp_allocator,
			sizing    = [2]ui.Sizing{.Full, .Full},
			padding   = Vec2{10, 15},
			spacing   = 5,
			direction = .Vertical,
			alignment = .Center,
		}

		log.info("container: ", container)
		ui.container_add_child(&container, &header)
		ui.container_layout(&container, Vec2{1920, 1080}, context.temp_allocator)

		log.info("container has correct size and pos")
		testing.expect_value(t, container.rect, Rect{0, 0, 1920, 1080})

		log.info("header has correct size")
		testing.expect_value(t, header.rect.zw, Vec2{80, 16})

		log.info("header has correct pos")
		testing.expect_value(t, header.rect.xy, Vec2{920, 15})
	}
}
