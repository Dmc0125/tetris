package main

import "base:runtime"
import "core:fmt"
import "core:mem"

Vec2 :: [2]f32
Vec4 :: [4]f32
Rect :: Vec4
Color :: Vec4

rect_collides :: proc(r: Rect, other: Vec2) -> bool {
	inside_x := r.x <= other.x && r.x + r.z >= other.x
	inside_y := r.y <= other.y && r.y + r.w >= other.y
	return inside_x && inside_y
}

EventKind :: enum u8 {
	None,
	Resize,
	Keydown,
	Keyup,
}

ResizeEvent :: struct {
	kind: EventKind,
	size: Vec2,
}

Key :: enum u16 {
	None,
	UP,
	DOWN,
	LEFT,
	RIGHT,
	ESCAPE,
	// a = 65,
	// b = 66,
	// c = 67,
	// d = 68,
	// e = 69,
	// f = 70,
	// g = 71,
	// h = 72,
	// i = 73,
	// j = 74,
	// k = 75,
	// l = 76,
	// m = 77,
	// n = 78,
	// o = 79,
	// p = 80,
	// q = 81,
	// r = 82,
	// s = 83,
	// t = 84,
	// u = 85,
	// v = 86,
	// w = 87,
	// x = 88,
	// y = 89,
	// z = 90,
}

KeyboardEvent :: struct {
	kind: EventKind,
	key:  Key,
}

Event :: struct #raw_union {
	kind:     EventKind,
	resize:   ResizeEvent,
	keyboard: KeyboardEvent,
}

foreign import "env"
@(default_calling_convention = "contextless")
foreign env {
	set_target_fps :: proc(fps: f32) ---
	get_actual_fps :: proc(fps: ^f32) ---

	window_size :: proc(_: ^Vec2) ---
	draw_image :: proc(src_rect: ^Rect, dst_rect: ^Rect) ---
	draw_rect :: proc(rect: ^Rect, color: ^Color) ---
	fill_rect :: proc(rect: ^Rect, color: ^Color) ---

	// font
	measure_text :: proc(size: ^Vec2, text: string) ---
	fill_text :: proc(pos: ^Vec2, color: ^Color, text: string) ---

	// events
	get_mouse_state :: proc(mx, my: ^f32, btn: ^u8) ---
	poll_event :: proc(event: ^Event) ---
}

Cube :: enum u8 {
	None,
	Yellow,
	Lime,
	Purple,
	Blue,
	Orange,
	Pink,
	Cyan,
	Stone,
	Sand,
	Mint,
	Gray,
}

CUBE_TEXTURE_SIZE :: 16
CUBE_SIZE :: CUBE_TEXTURE_SIZE

draw_cube :: proc(cube: Cube, dst: Vec2, size := CUBE_SIZE) {
	assert(cube != .None)

	idx := int(cube) - 1
	src := Rect{f32(idx * CUBE_TEXTURE_SIZE), 0, CUBE_TEXTURE_SIZE, CUBE_TEXTURE_SIZE}
	draw_image(&src, &Rect{dst.x, dst.y, f32(size), f32(size)})
}

MOUSE_BTN_PRIMARY: u8 : 1 << 0
MOUSE_BTN_SECONDARY: u8 : 1 << 1
MOUSE_BTN_AUXILIARY: u8 : 1 << 2
MOUSE_BTN_BROWSER_BACK: u8 : 1 << 3
MOUSE_BTN_BROWSER_FORWARD: u8 : 1 << 4

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
	measure_text(&text_size, button.text)
	button.text_rect.zw = text_size
	button.text_rect.xy = button.rect.zw / 2 - button.text_rect.zw / 2
}

button_render :: proc(button: ^Button) {
	fill_rect(&button.rect, &button.bg_color)
	text_pos := button.rect.xy + button.text_rect.xy
	fill_text(&text_pos, &button.text_color, button.text)
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
	singleplayer: Singleplayer,
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

	set_target_fps(144)
	window_size(&ctx.window_size)

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
		singleplayer_layout(ctx)
	}

	{ 	// fps
		fps := &ui.fps

		text_size: Vec2
		measure_text(&text_size, fps.text)

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
		singleplayer_draw(ctx)
	}

	{ 	// fps
		pos := ui.fps.rect.xy
		fill_text(&pos, &Color{1, 0.9, 0.2, 1}, ui.fps.text)
	}
}

@(export)
step :: proc(delta_time: f64) -> bool {
	context.allocator = mem.arena_allocator(&allocator_arena)
	context.temp_allocator = mem.arena_allocator(&temp_allocator_arena)
	free_all(context.temp_allocator)

	context.random_generator = runtime.default_random_generator()

	if ctx.screen == .Singleplayer {
		clock_frame_start(&ctx.singleplayer.clock, delta_time)
	}

	ui := &ctx.ui

	{
		fps: f32
		get_actual_fps(&fps)
		ui.fps.text = fmt.tprintf("%.0f", fps)
	}

	{
		event: Event
		for {
			poll_event(&event)
			if event.kind == .None {
				break
			}

			#partial switch ctx.screen {
			case .Singleplayer:
				singleplayer_process_event(&ctx, &event)
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
		get_mouse_state(&mouse.pos.x, &mouse.pos.y, &mouse.btn)
		defer {
			ctx.mouse = mouse
		}

		switch {
		case mouse.btn & MOUSE_BTN_PRIMARY != 0 && ctx.mouse.btn & MOUSE_BTN_PRIMARY == 0:
			// click

			switch ctx.screen {
			case .Begin:
				if rect_collides(ui.play_sp_btn, mouse) {
					ctx.screen = .Singleplayer
					singleplayer_init(&ctx)
				}
			case .Singleplayer:
			}
		}
	}

	{ 	// update
		switch ctx.screen {
		case .Begin:
		case .Singleplayer:
			singleplayer_update(&ctx)
		}

	}

	draw(&ctx)

	return true
}
