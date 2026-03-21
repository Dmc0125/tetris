package main

import "base:runtime"
import "core:fmt"
import "core:math/linalg"
import "core:mem"

import game "game"
import platform "platform"
import ui "ui"

Vec2 :: linalg.Vector2f32
Rect :: linalg.Vector4f32
Color :: linalg.Vector4f32

CLR_BG :: Color{0.02, 0.02, 0.05, 1}
CLR_BG_SECONDARY :: Color{0.03, 0.03, 0.10, 1}
CLR_BORDER :: Color{0.17, 0.18, 0.22, 1}
CLR_BTN_BG :: Color{0.15, 0.73, 0.3, 1}
CLR_BTN_TEXT :: CLR_BG
CLR_TEXT :: Color{0.9, 0.9, 0.9, 1}

rect_collides :: proc(r: Rect, other: Vec2) -> bool {
	inside_x := r.x <= other.x && r.x + r.z >= other.x
	inside_y := r.y <= other.y && r.y + r.w >= other.y
	return inside_x && inside_y
}

Mouse :: struct {
	using pos: Vec2,
	btn:       u8,
}

Screen :: enum {
	Menu,
	Singleplayer,
}

Menu :: struct {
	header: ui.Text,
	sp_btn: ui.Button,
	mp_btn: ui.Button,
}

menu_layout :: proc(ui_menu: ^Menu, screen_size: Vec2, allocator := context.temp_allocator) {
	clr_fill := CLR_BTN_BG
	clr_btn_text := CLR_BTN_TEXT

	// buttons

	ui.button_init(&ui_menu.sp_btn, Vec2{200, 40}, "Play singleplayer", clr_fill, clr_btn_text)
	ui.button_init(&ui_menu.mp_btn, Vec2{200, 40}, "Play multiplayer", clr_fill, clr_btn_text)

	buttons: ui.Block
	ui.block_init(&buttons, .Vertical, spacing = 20, alignment = .Center, allocator = allocator)

	ui.block_add_child(&buttons, &ui_menu.sp_btn)
	ui.block_add_child(&buttons, &ui_menu.mp_btn)

	// screen

	ui.text_init(&ui_menu.header, "Tetris showdown", CLR_TEXT)

	screen_layout: ui.Block
	ui.block_init(
		&screen_layout,
		.Vertical,
		spacing = 100,
		alignment = .Center,
		allocator = allocator,
	)

	ui.block_add_child(&screen_layout, &ui_menu.header)
	ui.block_add_child(&screen_layout, &buttons)

	ui.center(screen_size, &screen_layout.rect)
	ui.block_layout(&screen_layout)
}

Context :: struct {
	window_size:  Vec2,
	screen:       Screen,
	mouse:        Mouse,
	menu:         Menu,
	singleplayer: game.Singleplayer,
}

ctx: Context

allocator_data: [mem.Kilobyte * 4]byte
allocator_arena: mem.Arena

temp_allocator_data: [mem.Kilobyte * 4]byte
temp_allocator_arena: mem.Arena

@(export)
init :: proc() {
	mem.arena_init(&allocator_arena, allocator_data[:])
	context.allocator = mem.arena_allocator(&allocator_arena)

	mem.arena_init(&temp_allocator_arena, temp_allocator_data[:])
	context.temp_allocator = mem.arena_allocator(&temp_allocator_arena)

	platform.set_target_fps(144)
	platform.window_size(&ctx.window_size)

	menu_layout(&ctx.menu, ctx.window_size)
}

@(export)
step :: proc(delta_time: f64) -> bool {
	context.allocator = mem.arena_allocator(&allocator_arena)
	context.temp_allocator = mem.arena_allocator(&temp_allocator_arena)
	free_all(context.temp_allocator)

	context.random_generator = runtime.default_random_generator()

	if ctx.screen == .Singleplayer {
		game.clock_frame_start(&ctx.singleplayer.clock, delta_time)
	}

	{
		event: platform.Event
		for {
			platform.poll_event(&event)
			if event.kind == .None {
				break
			}

			#partial switch ctx.screen {
			case .Singleplayer:
				game.sp_process_event(&ctx.singleplayer, &event)
			}

			// global

			#partial switch event.kind {
			case .Resize:
				ctx.window_size = event.resize.size
				menu_layout(&ctx.menu, ctx.window_size)
				game.sp_layout(&ctx.singleplayer, ctx.window_size)
			}
		}
	}

	{ 	// mouse
		mouse: Mouse
		platform.get_mouse_state(&mouse.pos.x, &mouse.pos.y, &mouse.btn)
		defer {
			ctx.mouse = mouse
		}

		switch {
		case mouse.btn & platform.MOUSE_BTN_PRIMARY != 0 &&
		     ctx.mouse.btn & platform.MOUSE_BTN_PRIMARY == 0:
			// click

			switch ctx.screen {
			case .Menu:
				if rect_collides(ctx.menu.sp_btn.rect, mouse) {
					ctx.screen = .Singleplayer
					game.sp_init(
						&ctx.singleplayer,
						ctx.window_size,
						clr_text = CLR_TEXT,
						clr_card_bg = CLR_BG_SECONDARY,
						clr_card_border = CLR_BORDER,
					)
					game.sp_layout(&ctx.singleplayer, ctx.window_size)
				}
			case .Singleplayer:
			}
		}
	}

	{ 	// update
		switch ctx.screen {
		case .Menu:
		case .Singleplayer:
			game.sp_update(&ctx.singleplayer)
		}

	}

	{ 	// draw
		clr_bg := CLR_BG
		platform.fill_rect(&Rect{0, 0, ctx.window_size.x, ctx.window_size.y}, &clr_bg)

		switch ctx.screen {
		case .Menu:
			ui.text_draw(&ctx.menu.header)
			ui.button_draw(&ctx.menu.sp_btn)
			ui.button_draw(&ctx.menu.mp_btn)
		case .Singleplayer:
			game.sp_draw(&ctx.singleplayer)
		}

		{ 	// fps
			fps: f32
			platform.get_actual_fps(&fps)
			text := fmt.tprintf("%.0f", fps)
			pos := Vec2{ctx.window_size.x - 50, 20}
			platform.fill_text(&pos, &Color{1, 0.9, 0.2, 1}, text)
		}
	}

	return true
}
