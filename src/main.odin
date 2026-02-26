package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:time"

import SDL "vendor:sdl3"

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

sdl_proc :: proc(r: bool, msg := "", location := #caller_location) -> (err: Error) {
	if !r {
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

main :: proc() {
	if err := sdl_proc(SDL.Init(SDL.INIT_VIDEO)); err != nil {
		fmt.eprintln(error_string(err))
		return
	}

	window_width :: 1280
	window_height :: 800

	window: ^SDL.Window
	renderer: ^SDL.Renderer

	if err := sdl_proc(
		SDL.CreateWindowAndRenderer(
			"tetris",
			window_width,
			window_height,
			nil,
			&window,
			&renderer,
		),
	); err != nil {
		fmt.eprintln(error_string(err))
		return
	}

	for {
		fmt.println("YO")
		event: SDL.Event
		for SDL.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				return
			}
		}

		time.sleep(time.Millisecond * 16)
	}
}
