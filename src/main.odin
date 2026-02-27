package main

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:math/linalg"
import "core:math/rand"
import "core:os"
import "core:time"

import SDL "vendor:sdl2"
import TTF "vendor:sdl2/ttf"

ErrorSDL :: struct {
	loc: runtime.Source_Code_Location,
	msg: string,
}

create_error_sdl :: proc(loc := #caller_location, msg := "") -> ErrorSDL {
	m: string
	if len(msg) > 0 {
		m = fmt.aprintf("%s: %s", msg, SDL.GetError())
	} else {
		m = string(SDL.GetError())
	}
	return ErrorSDL{loc = loc, msg = m}
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

Vec2 :: linalg.Vector2f32

Rect :: struct {
	size: Vec2,
	pos:  Vec2,
}

set_color :: proc(renderer: ^SDL.Renderer, color: SDL.Color) -> Error {
	return sdl_proc(SDL.SetRenderDrawColor(renderer, expand_values(color)))
}

draw_rect :: proc(
	renderer: ^SDL.Renderer,
	size, pos: Vec2,
	color: ^SDL.Color = nil,
) -> (
	err: Error,
) {
	if color != nil {
		set_color(renderer, color^) or_return
	}

	r := SDL.FRect {
		x = pos.x,
		y = pos.y,
		w = size.x,
		h = size.y,
	}
	return sdl_proc(SDL.RenderDrawRectF(renderer, &r))
}

fill_rect :: proc(
	renderer: ^SDL.Renderer,
	size, pos: Vec2,
	color: ^SDL.Color = nil,
) -> (
	err: Error,
) {
	if color != nil {
		set_color(renderer, color^) or_return
	}

	r := SDL.FRect {
		x = pos.x,
		y = pos.y,
		w = size.x,
		h = size.y,
	}
	return sdl_proc(SDL.RenderFillRectF(renderer, &r))
}

GLYPH_START :: 32
GLYPH_END :: 127
GLYPH_COUNT :: GLYPH_END - GLYPH_START

Font :: struct {
	font:   ^TTF.Font,
	atlas:  ^SDL.Texture,
	glyphs: [GLYPH_COUNT]Rect,
}

load_font :: proc(renderer: ^SDL.Renderer, font: ^Font, size: i32) -> (err: Error) {
	path :: "assets/PixelPurl.ttf"
	font.font = TTF.OpenFont(path, size)
	if font.font == nil {
		err = create_error_sdl()
		return
	}

	s: [GLYPH_COUNT]^SDL.Surface
	w, h: i32

	for ch in GLYPH_START ..< GLYPH_END {
		i := ch - 32
		surface := TTF.RenderGlyph_Blended(font.font, u16(ch), SDL.Color{255, 255, 255, 255})
		if surface == nil {
			err = create_error_sdl()
			return
		}

		w += surface.w
		h = max(h, surface.h)

		s[i] = surface
	}

	font.atlas = SDL.CreateTexture(renderer, .ARGB8888, .STATIC, w, h)
	if font.atlas == nil {
		err = create_error_sdl()
		return
	}

	x: f32

	for surface, i in s {
		r := Rect {
			size = Vec2{f32(surface.w), f32(surface.h)},
			pos  = Vec2{x, 0},
		}
		font.glyphs[i] = r

		sr := SDL.Rect {
			w = i32(r.size.x),
			h = i32(r.size.y),
			x = i32(r.pos.x),
			y = i32(r.pos.y),
		}
		sdl_proc(SDL.UpdateTexture(font.atlas, &sr, surface.pixels, surface.pitch)) or_return

		x += f32(surface.w)
	}

	return
}

Clock :: struct {
	frame_start: time.Tick,
	// dt in seconds
	dt:          f64,
	// sim dt in seconds
	sim_dt:      f64,
	// sim time in seconds
	sim_time:    f64,
}

clock_init :: proc(clock: ^Clock) {
	clock.frame_start = time.tick_now()
}

clock_frame_start :: proc(clock: ^Clock) {
	n := time.tick_now()

	dt := time.tick_since(clock.frame_start)
	clock.dt = time.duration_seconds(dt)
	clock.sim_dt = clock.dt
	clock.sim_time += clock.dt

	clock.frame_start = n
}

Context :: struct {
	window:      ^SDL.Window,
	renderer:    ^SDL.Renderer,
	window_size: Vec2,
	mode:        Mode,
	font:        ^Font,
	clock:       Clock,
}

Mode :: enum {
	Menu,
	Game,
}

Menu :: struct {
	button: Rect,
}

menu_layout :: proc(ctx: ^Context, menu: ^Menu) {
	menu.button.size = Vec2{200, 40}
	menu.button.pos = Vec2{200, 40}
}

TetrominoType :: enum {
	None,
	I,
	O,
	T,
	J,
	L,
	S,
	Z,
}

Game :: struct {
	using _:         Rect,
	cell_size:       Vec2,
	cells:           Vec2,
	//
	last_update_at:  f64,
	tetromino:       TetrominoType,
	projection:      [4]Vec2,
	tetromino_cells: [4]Vec2,
	filled_cells:    [][]bool,
}

game_init :: proc(ctx: ^Context, game: ^Game) {
	game.cells = Vec2{10, 20}
	game.cell_size = Vec2{20, 20}
	game.size = game.cells * game.cell_size

	game.filled_cells = make([][]bool, int(game.cells.y))
	for &row in game.filled_cells {
		row = make([]bool, int(game.cells.x))
	}
}

game_layout :: proc(ctx: ^Context, game: ^Game) {
	pos := ctx.window_size / 2 - game.size / 2
	game.pos = pos
}

game_check_collision :: proc(game: ^Game, tcells: []Vec2) -> bool {
	for tcell in tcells {
		next_y := int(tcell.y + 1)

		if next_y == int(game.cells.y) {
			return true
		} else if next_y >= 0 && next_y < int(game.cells.y) {
			filled_row := game.filled_cells[next_y]

			for filled, i in filled_row do if filled {
				if i == int(tcell.x) {
					return true
				}
			}
		}
	}

	return false
}

game_move_down :: proc(tcells: []Vec2) {
	tcells[0].y += 1
	tcells[1].y += 1
	tcells[2].y += 1
	tcells[3].y += 1
}

game_projection :: proc(game: ^Game) {
	copy(game.projection[:], game.tetromino_cells[:])

	for !game_check_collision(game, game.projection[:]) {
		game_move_down(game.projection[:])
	}
}

update :: proc(ctx: ^Context, game: ^Game) {
	update_timeout :: 0.5

	if game.last_update_at + update_timeout >= ctx.clock.sim_time {
		return
	}

	if game.tetromino == .None {
		choices := [?]TetrominoType{.I, .O, .T, .J, .L, .S, .Z}
		game.tetromino = rand.choice(choices[:])

		switch game.tetromino {
		case .I:
			x := f32(rand.int_range(0, int(game.cells.x - 4)))
			game.tetromino_cells = [4]Vec2{{x, -2}, {x + 1, -2}, {x + 2, -2}, {x + 3, -2}}
		case .O:
			x := f32(rand.int_range(0, int(game.cells.x - 2)))
			game.tetromino_cells = [4]Vec2{{x, -2}, {x + 1, -2}, {x, -1}, {x + 1, -1}}
		case .T:
			x := f32(rand.int_range(0, int(game.cells.x - 3)))
			game.tetromino_cells = [4]Vec2{{x, -2}, {x + 1, -2}, {x + 2, -2}, {x + 1, -1}}
		case .J:
			x := f32(rand.int_range(0, int(game.cells.x - 2)))
			game.tetromino_cells = [4]Vec2{{x + 1, -3}, {x + 1, -2}, {x + 1, -1}, {x, -1}}
		case .L:
			x := f32(rand.int_range(0, int(game.cells.x - 2)))
			game.tetromino_cells = [4]Vec2{{x, -3}, {x, -2}, {x, -1}, {x + 1, -1}}
		case .S:
			x := f32(rand.int_range(0, int(game.cells.x - 3)))
			game.tetromino_cells = [4]Vec2{{x, -1}, {x + 1, -1}, {x + 1, -2}, {x + 2, -2}}
		case .Z:
			x := f32(rand.int_range(0, int(game.cells.x - 3)))
			game.tetromino_cells = [4]Vec2{{x, -2}, {x + 1, -2}, {x + 1, -1}, {x + 2, -1}}
		case .None:
			assert(false)
		}

		game_projection(game)
		game.last_update_at = ctx.clock.sim_time
	} else {
		fill := proc(game: ^Game, i: int) {
			r := game.tetromino_cells[i].y
			c := game.tetromino_cells[i].x
			game.filled_cells[int(r)][int(c)] = true
		}

		if game_check_collision(game, game.tetromino_cells[:]) {
			fill(game, 0)
			fill(game, 1)
			fill(game, 2)
			fill(game, 3)
			game.tetromino = .None
		} else {
			game_move_down(game.tetromino_cells[:])
		}

		game.last_update_at = ctx.clock.sim_time
	}
}

render :: proc(ctx: ^Context, game: ^Game) -> (err: Error) {
	set_color(ctx.renderer, SDL.Color{0, 0, 0, 255}) or_return
	sdl_proc(SDL.RenderClear(ctx.renderer)) or_return

	game_cell_to_pixel_pos :: proc(game: ^Game, cell: Vec2) -> Vec2 {
		return game.pos + cell * game.cell_size
	}

	switch ctx.mode {
	case .Menu:
	case .Game:
		set_color(ctx.renderer, SDL.Color{150, 150, 150, 255}) or_return
		draw_rect(ctx.renderer, game.size, game.pos) or_return

		set_color(ctx.renderer, SDL.Color{50, 50, 50, 255}) or_return

		// vertical lines
		for col in 1 ..< game.cells.x {
			pos := game.pos + Vec2{col, 0} * game.cell_size
			pos.y += 1
			sdl_proc(
				SDL.RenderDrawLineF(
					ctx.renderer,
					expand_values(pos),
					pos.x,
					pos.y + game.size.y - 3, // 1px left border, 1px right border, 1px shift the to the right,
				),
			) or_return
		}

		// horizontal
		for row in 1 ..< game.cells.y {
			pos := game.pos + Vec2{0, row} * game.cell_size
			pos.x += 1
			sdl_proc(
				SDL.RenderDrawLineF(
					ctx.renderer,
					expand_values(pos),
					pos.x + game.size.x - 3,
					pos.y,
				),
			) or_return
		}

		// tetromino

		render_tetromino_cell :: proc(
			ctx: ^Context,
			game: ^Game,
			cell: Vec2,
			fill := true,
		) -> (
			err: Error,
		) {
			// if cell.y < 0 {
			// 	return
			// }

			pos := game_cell_to_pixel_pos(game, cell)
			pos += Vec2{1, 1}
			size := game.cell_size - Vec2{2, 2}
			if fill {
				fill_rect(ctx.renderer, size, pos, &SDL.Color{100, 100, 255, 255}) or_return
			} else {
				draw_rect(ctx.renderer, size, pos, &SDL.Color{100, 100, 255, 255}) or_return
			}
			return
		}

		if game.tetromino != .None {
			render_tetromino_cell(ctx, game, game.projection[0], false) or_return
			render_tetromino_cell(ctx, game, game.projection[1], false) or_return
			render_tetromino_cell(ctx, game, game.projection[2], false) or_return
			render_tetromino_cell(ctx, game, game.projection[3], false) or_return

			render_tetromino_cell(ctx, game, game.tetromino_cells[0]) or_return
			render_tetromino_cell(ctx, game, game.tetromino_cells[1]) or_return
			render_tetromino_cell(ctx, game, game.tetromino_cells[2]) or_return
			render_tetromino_cell(ctx, game, game.tetromino_cells[3]) or_return
		}

		for columns, row in game.filled_cells {
			for valid, col in columns {
				if valid {
					render_tetromino_cell(ctx, game, Vec2{f32(col), f32(row)})
				}
			}
		}
	}

	SDL.RenderPresent(ctx.renderer)

	return
}

main :: proc() {
	if err := sdl_proc(SDL.Init(SDL.INIT_VIDEO)); err != nil {
		fmt.eprintln(error_string(err))
		return
	}
	if err := sdl_proc(TTF.Init()); err != nil {
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

	font: Font
	if err := load_font(renderer, &font, 16); err != nil {
		fmt.eprintln(error_string(err))
		return
	}

	ctx := Context {
		window      = window,
		renderer    = renderer,
		window_size = Vec2{f32(window_width), f32(window_height)},
		mode        = .Game,
		font        = &font,
	}
	clock_init(&ctx.clock)

	game: Game
	game_init(&ctx, &game)
	game_layout(&ctx, &game)

	err: Error

	loop: for {
		clock_frame_start(&ctx.clock)

		frame_start := time.tick_now()

		// input

		event: SDL.Event
		for SDL.PollEvent(&event) {
			#partial switch event.type {
			case .KEYDOWN:
				#partial switch event.key.keysym.sym {
				case .LEFT:
					if game.tetromino != .None {
						most_left := min(
							game.tetromino_cells[0].x,
							game.tetromino_cells[1].x,
							game.tetromino_cells[2].x,
							game.tetromino_cells[3].x,
						)
						if most_left > 0 {
							game.tetromino_cells[0].x -= 1
							game.tetromino_cells[1].x -= 1
							game.tetromino_cells[2].x -= 1
							game.tetromino_cells[3].x -= 1

							game_projection(&game)
						}
					}
				case .RIGHT:
					if game.tetromino != .None {
						most_right := max(
							game.tetromino_cells[0].x,
							game.tetromino_cells[1].x,
							game.tetromino_cells[2].x,
							game.tetromino_cells[3].x,
						)
						if most_right < game.cells.x - 1 {
							game.tetromino_cells[0].x += 1
							game.tetromino_cells[1].x += 1
							game.tetromino_cells[2].x += 1
							game.tetromino_cells[3].x += 1

							game_projection(&game)
						}
					}
				case .DOWN:
					if game.tetromino != .None &&
					   !game_check_collision(&game, game.tetromino_cells[:]) {
						game_move_down(game.tetromino_cells[:])
					}
				}
			case .QUIT:
				return
			}
		}

		// update

		update(&ctx, &game)

		// render

		if err = render(&ctx, &game); err != nil {
			break loop
		}

		frame_duration := time.tick_since(frame_start)
		remaining := FRAME_TIME - time.duration_seconds(frame_duration)
		if remaining > 0 {
			time.sleep(time.Duration(remaining * f64(time.Second)))
		}

		SDL.SetWindowTitle(window, fmt.ctprintf("Tetris - frame duration: %s", frame_duration))

		free_all(context.temp_allocator)
	}

	fmt.eprintln(error_string(err))
}
