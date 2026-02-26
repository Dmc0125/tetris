package main

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:math/linalg"
import "core:os"
import "core:time"

import SDL "vendor:sdl2"

ErrorSDL :: struct {
	loc: runtime.Source_Code_Location,
	msg: string,
}

Error :: union {
	ErrorSDL,
}

error_string :: proc(err: Error) -> string {
	switch e in err {
	case ErrorSDL:
		return fmt.aprintf("%s: SDL Error: %s", e.loc, e.msg)
	}

	return ""
}

sdl_proc :: proc(r: c.int, msg := "", location := #caller_location) -> (err: Error) {
	if r != 0 {
		m: string
		if len(msg) > 0 {
			m = fmt.aprintf("%s: %s", msg, SDL.GetError())
		} else {
			m = string(SDL.GetError())
		}
		err = ErrorSDL {
			loc = location,
			msg = m,
		}
	}
	return
}

Vec2 :: linalg.Vector2f64

Mode :: enum {
	Menu,
	Game,
}

Menu :: struct {
	button_size: Vec2,
	button_pos:  Vec2,
}

menu_layout :: proc(ctx: ^Context, menu: ^Menu) {
	menu.button_size = Vec2{200, 40}
}

Context :: struct {
	window:      ^SDL.Window,
	renderer:    ^SDL.Renderer,
	window_size: Vec2,
	mode:        Mode,
}


render :: proc(ctx: ^Context) {
	switch ctx.mode {
	case .Menu:

	case .Game:
	}

}

main :: proc() {
	if err := sdl_proc(SDL.Init(SDL.INIT_VIDEO)); err != nil {
		fmt.eprintln(error_string(err))
		return
	}

	TARGET_FPS: f64 : 144
	FRAME_TIME: f64 : 1000 / 1000 / TARGET_FPS

	window_width :: 1280
	window_height :: 800

	window: ^SDL.Window
	renderer: ^SDL.Renderer

	if err := sdl_proc(
		SDL.CreateWindowAndRenderer(window_width, window_height, nil, &window, &renderer),
	); err != nil {
		fmt.eprintln(error_string(err))
		return
	}

	SDL.SetWindowTitle(window, "Tetris")

	ctx := Context {
		window      = window,
		renderer    = renderer,
		window_size = Vec2{f64(window_width), f64(window_height)},
		mode        = .Menu,
	}
	err: Error

	for {
		frame_start := time.tick_now()

		// input

		event: SDL.Event
		for SDL.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				return
			}
		}

		// update

		// render


		frame_duration := time.tick_since(frame_start)
		remaining := FRAME_TIME - time.duration_seconds(frame_duration)
		if remaining > 0 {
			time.sleep(time.Duration(remaining * f64(time.Second)))
		}

		// sdl_proc(SDL.SetWindowTitle(window, fmt.tprintf("Tetris: ")))

		free_all(context.temp_allocator)
	}

	fmt.eprintln(error_string(err))
}
