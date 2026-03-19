package main

import "base:runtime"
import "core:fmt"
import "core:math/linalg"
import "core:mem"

import game "game"
import platform "platform"

Vec2 :: linalg.Vector2f32
Rect :: linalg.Vector4f32
Color :: linalg.Vector4f32

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
	Begin,
	Singleplayer,
}

Button :: struct {
	using rect: Rect,
	text:       string,
	text_rect:  Rect,
	bg_color:   Color,
	text_color: Color,
}

button_init :: proc(
	button: ^Button,
	size: Vec2,
	text: string,
	bg_color: Color,
	text_color: Color,
) {
	button.rect.zw = size

	button.bg_color = bg_color
	button.text_color = text_color

	button.text = text
	text_size: Vec2
	platform.measure_text(&text_size, button.text)
	button.text_rect.zw = text_size
	button.text_rect.xy = button.rect.zw / 2 - button.text_rect.zw / 2
}

button_render :: proc(button: ^Button) {
	platform.fill_rect(&button.rect, &button.bg_color)
	text_pos := button.rect.xy + button.text_rect.xy
	platform.fill_text(&text_pos, &button.text_color, button.text)
}

Fps :: struct {
	using rect: Rect,
	text:       string,
}

UI :: struct {
	fps:         Fps,
	play_sp_btn: Button,
	play_mp_btn: Button,
}

ui_init :: proc(ctx: ^Context) {
	ui := &ctx.ui

	button_init(
		&ui.play_sp_btn,
		Vec2{200, 40},
		"Play singleplayer",
		Color{0.4, 0.4, 0.4, 1},
		Color{1, 1, 1, 1},
	)

	button_init(
		&ui.play_mp_btn,
		Vec2{200, 40},
		"Play multiplayer",
		Color{0.4, 0.4, 0.4, 1},
		Color{1, 1, 1, 1},
	)
}

Context :: struct {
	window_size:  Vec2,
	screen:       Screen,
	mouse:        Mouse,
	ui:           UI,
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

	ui_init(&ctx)

	layout(&ctx)
}

layout :: proc(ctx: ^Context) {
	ui := &ctx.ui

	switch ctx.screen {
	case .Begin:
		// play button
		ui.play_sp_btn.rect.xy = ctx.window_size / 2 - ui.play_sp_btn.rect.zw / 2
		ui.play_sp_btn.rect.y -= 30

		ui.play_mp_btn.rect.xy = ctx.window_size / 2 - ui.play_sp_btn.rect.zw / 2
		ui.play_mp_btn.rect.y += 30
	case .Singleplayer:
		game.singleplayer_layout(&ctx.singleplayer, ctx.window_size)
	}

	{ 	// fps
		fps := &ui.fps

		text_size: Vec2
		platform.measure_text(&text_size, fps.text)

		fps.rect.zw = text_size
		fps.rect.x = ctx.window_size.x - text_size.x - 20
		fps.rect.y = 20
	}
}

draw :: proc(ctx: ^Context) {
	ui := &ctx.ui

	switch ctx.screen {
	case .Begin:
		button_render(&ui.play_sp_btn)
		button_render(&ui.play_mp_btn)
	case .Singleplayer:
		game.singleplayer_draw(&ctx.singleplayer)
	}

	{ 	// fps
		pos := ui.fps.rect.xy
		platform.fill_text(&pos, &Color{1, 0.9, 0.2, 1}, ui.fps.text)
	}
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

	ui := &ctx.ui

	{
		fps: f32
		platform.get_actual_fps(&fps)
		ui.fps.text = fmt.tprintf("%.0f", fps)
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
				game.singleplayer_process_event(&ctx.singleplayer, &event)
			}

			// global

			#partial switch event.kind {
			case .Resize:
				ctx.window_size = event.resize.size
				layout(&ctx)
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
			case .Begin:
				if rect_collides(ui.play_sp_btn, mouse) {
					ctx.screen = .Singleplayer
					game.singleplayer_init(&ctx.singleplayer, ctx.window_size)
				}
			case .Singleplayer:
			}
		}
	}

	{ 	// update
		switch ctx.screen {
		case .Begin:
		case .Singleplayer:
			game.singleplayer_update(&ctx.singleplayer)
		}

	}

	draw(&ctx)

	return true
}
