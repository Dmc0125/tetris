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

CLR_BLACK_100 :: Color{0.02, 0.02, 0.05, 1}
CLR_BLACK_200 :: Color{0.03, 0.03, 0.10, 1}
CLR_BLACK_300 :: Color{0.17, 0.18, 0.22, 1}
CLR_WHITE_100 :: Color{0.9, 0.9, 0.9, 1}
CLR_GREEN_100 :: Color{0.15, 0.73, 0.3, 1}

Screen :: enum {
	Menu,
	Singleplayer,
}

Menu :: struct {
	window_size: Vec2,
	container:   ui.Container,
	header:      ui.Text,
	sp_btn:      ui.Button,
	mp_btn:      ui.Button,
}

menu_init :: proc(
	menu: ^Menu,
	window_size: Vec2,
	perm_allocator, temp_allocator: runtime.Allocator,
) {
	menu.window_size = window_size

	menu.header = ui.Text {
		value = "Tetris",
		appearance = ui.Appearance{flags = ui.Appearance_Flags{.Background}, bg = CLR_WHITE_100},
	}

	menu.sp_btn = ui.Button {
		rect = Rect{0, 0, 200, 40},
		text = "Tetris classic",
		button_appearance = ui.Appearance {
			flags = ui.Appearance_Flags{.Background},
			bg = CLR_GREEN_100,
		},
		text_appearance = ui.Appearance {
			flags = ui.Appearance_Flags{.Background},
			bg = CLR_BLACK_100,
		},
	}

	menu.mp_btn = ui.Button {
		rect = Rect{0, 0, 200, 40},
		text = "Coming soon",
		button_appearance = ui.Appearance {
			flags = ui.Appearance_Flags{.Background},
			bg = CLR_GREEN_100,
		},
		text_appearance = ui.Appearance {
			flags = ui.Appearance_Flags{.Background},
			bg = CLR_BLACK_100,
		},
	}

	menu.container = ui.Container {
		perm_allocator = perm_allocator,
		temp_allocator = temp_allocator,
		sizing         = [2]ui.Sizing{.Full, .Auto},
		direction      = .Vertical,
		alignment      = .Center,
	}

	//

	container := ui.container_init(
		perm_allocator,
		temp_allocator,
		sizing = [2]ui.Sizing{.Auto, .Auto},
		direction = .Vertical,
		alignment = .Center,
		padding = Vec2{0, 100},
		spacing = 100,
	)

	buttons := ui.container_init(
		perm_allocator,
		temp_allocator,
		sizing = [2]ui.Sizing{.Auto, .Auto},
		direction = .Vertical,
		spacing = 20,
	)

	ui.container_add_child(buttons, &menu.sp_btn)
	ui.container_add_child(buttons, &menu.mp_btn)

	ui.container_add_child(container, &menu.header)
	ui.container_add_child(container, buttons)

	ui.container_add_child(&menu.container, container)

	menu_layout(menu)
}

menu_layout :: proc(menu: ^Menu) {
	menu.header.font_size = .Large
	menu.sp_btn.font_size = .Medium
	menu.mp_btn.font_size = .Medium

	ui.container_layout(&menu.container, menu.window_size)
}

Menu_Result :: enum {
	None,
	Singleplayer,
}

menu_update_and_draw :: proc(
	menu: ^Menu,
	events: [dynamic]platform.Event,
	mouse: platform.Mouse,
) -> (
	result: Menu_Result,
) {
	for event in events {
		if event.kind == .Resize {
			menu.window_size = event.resize.size
			menu_layout(menu)
		}
	}

	if mouse.state == .Click && ui.rect_collides(menu.sp_btn.rect, mouse.pos) {
		result = .Singleplayer
		return
	}

	clr_bg := CLR_BLACK_100
	platform.fill_rect(&Rect{0, 0, menu.window_size.x, menu.window_size.y}, &clr_bg)

	ui.container_draw(&menu.container)

	return
}

Context :: struct {
	time:         f64,
	mouse:        platform.Mouse,
	screen:       Screen,
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
	platform.load_fonts(&ui.fonts[.Small], &ui.fonts[.Medium], &ui.fonts[.Large])
	window_size: Vec2
	platform.window_size(&window_size)

	menu_init(&ctx.menu, window_size, context.allocator, context.temp_allocator)
	game.sp_init(
		&ctx.singleplayer,
		window_size,
		clr_screen = CLR_BLACK_100,
		clr_card_bg = CLR_BLACK_200,
		clr_card_border = CLR_BLACK_300,
		clr_text_light = CLR_WHITE_100,
		clr_text_dark = CLR_BLACK_100,
		clr_accent = CLR_GREEN_100,
		perm_allocator = context.allocator,
		temp_allocator = context.temp_allocator,
	)
}

@(export)
step :: proc(delta_time: f64) -> bool {
	ctx.time += delta_time

	context.allocator = mem.arena_allocator(&allocator_arena)
	context.temp_allocator = mem.arena_allocator(&temp_allocator_arena)
	free_all(context.temp_allocator)
	context.random_generator = runtime.default_random_generator()

	events := make([dynamic]platform.Event, allocator = context.temp_allocator)
	{
		event: platform.Event
		for {
			platform.poll_event(&event)
			if event.kind == .None {
				break
			}

			append(&events, event)
		}
	}

	{ 	// mouse
		mouse_pos: Vec2
		mouse_btn: u8
		platform.get_mouse_state(&mouse_pos.x, &mouse_pos.y, &mouse_btn)
		defer {
			ctx.mouse.pos = mouse_pos
			ctx.mouse.btn = mouse_btn
		}

		switch ctx.mouse.state {
		case .None:
			if mouse_btn & platform.MOUSE_BTN_PRIMARY != 0 &&
			   ctx.mouse.btn & platform.MOUSE_BTN_PRIMARY == 0 {
				ctx.mouse.state = .Click
				ctx.mouse.clicked_at = ctx.time
			}
		case .Click:
			if mouse_btn & platform.MOUSE_BTN_PRIMARY != 0 &&
			   ctx.mouse.btn & platform.MOUSE_BTN_PRIMARY != 0 {
				ctx.mouse.state = .Holding
			} else if mouse_btn == 0 {
				ctx.mouse.state = .None
			}
		case .Holding:
			if ctx.mouse.clicked_at + 0.250 < ctx.time {
				ctx.mouse.state = .Pressed
			} else if mouse_btn == 0 {
				ctx.mouse.state = .None
			}
		case .Pressed:
			if mouse_btn == 0 {
				ctx.mouse.state = .None
			}
		}
	}

	switch ctx.screen {
	case .Menu:
		if menu_update_and_draw(&ctx.menu, events, ctx.mouse) == .Singleplayer {
			ctx.screen = .Singleplayer
			game.sp_start(&ctx.singleplayer, ctx.menu.window_size)
		}
	case .Singleplayer:
		game.sp_update_and_draw(&ctx.singleplayer, events, ctx.mouse, delta_time)
	}

	// { 	// fps
	// 	fps: f32
	// 	platform.get_actual_fps(&fps)
	// 	text := fmt.tprintf("%.0f", fps)
	// 	pos := Vec2{ctx.window_size.x - 50, 20}
	// 	platform.fill_text(&pos, &Color{1, 0.9, 0.2, 1}, text)
	// }

	return true
}
