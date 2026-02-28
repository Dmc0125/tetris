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

Cell :: struct {
	col, row: i32,
}

game_cell_to_world_pos :: proc(game: ^Game, cell: Cell) -> (world: Vec2) {
	world.xy = game.pos + Vec2{f32(cell.col), f32(cell.row)} * f32(game.cell_size)
	return
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

Tetromino :: struct {
	using _:        Cell,
	projection_pos: Cell,
	rotation:       u8,
	type:           TetrominoType,
	cells:          [16]u8,
	color:          SDL.Color,
}

tetromino_init :: proc(tetromino: ^Tetromino) {
	tetromino.col = 0
	tetromino.row = 0
	tetromino.projection_pos = Cell{}
	tetromino.rotation = 0

	choices := [?]TetrominoType{.I, .O, .T, .J, .L, .S, .Z}
	tetromino.type = rand.choice(choices[:])

	switch tetromino.type {
	case .None:
	case .I:
		tetromino.color = SDL.Color{100, 100, 200, 255}
	case .O:
		tetromino.color = SDL.Color{255, 220, 50, 255}
	case .T:
		tetromino.color = SDL.Color{215, 43, 251, 255}
	case .J:
		tetromino.color = SDL.Color{43, 131, 251, 255}
	case .L:
		tetromino.color = SDL.Color{251, 177, 43, 255}
	case .S:
		tetromino.color = SDL.Color{43, 251, 97, 255}
	case .Z:
		tetromino.color = SDL.Color{251, 43, 63, 255}
	}

	tetromino_set_cells(tetromino)
}

tetromino_rotate_r :: proc(tetromino: ^Tetromino) {
	tetromino.rotation += 1
	tetromino.rotation %= 4
	tetromino_set_cells(tetromino)
}

tetromino_rotate_l :: proc(tetromino: ^Tetromino) {
	tetromino.rotation -= 1
	tetromino.rotation %= 4
	tetromino_set_cells(tetromino)
}

tetromino_game_cell :: proc(cell: Cell, i: int) -> (c: Cell) {
	c.col = cell.col + i32(i) % 4
	c.row = cell.row + i32(i) / 4
	return
}

tetromino_projection :: proc(game: ^Game, tetromino: ^Tetromino) {
	tetromino.projection_pos = tetromino
	for !game_check_collision(game, tetromino.projection_pos, tetromino.cells) {
		tetromino.projection_pos.row += 1
	}
}

cell_to_game_cell_idx :: proc(game: ^Game, cell: Cell) -> int {
	return int(cell.row * i32(game.cols) + cell.col)
}

tetromino_set_cells :: proc(tetromino: ^Tetromino) {
	t := &tetromino.cells
	rotation := tetromino.rotation

	switch tetromino.type {
	case .I:
		switch rotation {
		case 0, 2:
			t[+0], t[+1], t[+2], t[+3] = 1, 1, 1, 1
			t[+4], t[+5], t[+6], t[+7] = 0, 0, 0, 0
			t[+8], t[+9], t[10], t[11] = 0, 0, 0, 0
			t[12], t[13], t[14], t[15] = 0, 0, 0, 0
		case 1, 3:
			t[+0], t[+1], t[+2], t[+3] = 0, 1, 0, 0
			t[+4], t[+5], t[+6], t[+7] = 0, 1, 0, 0
			t[+8], t[+9], t[10], t[11] = 0, 1, 0, 0
			t[12], t[13], t[14], t[15] = 0, 1, 0, 0
		}
	case .O:
		t[+0], t[+1], t[+2], t[+3] = 1, 1, 0, 0
		t[+4], t[+5], t[+6], t[+7] = 1, 1, 0, 0
		t[+8], t[+9], t[10], t[11] = 0, 0, 0, 0
		t[12], t[13], t[14], t[15] = 0, 0, 0, 0
	case .T:
		switch rotation {
		case 0:
			t[+0], t[+1], t[+2], t[+3] = 0, 1, 0, 0
			t[+4], t[+5], t[+6], t[+7] = 1, 1, 1, 0
			t[+8], t[+9], t[10], t[11] = 0, 0, 0, 0
			t[12], t[13], t[14], t[15] = 0, 0, 0, 0
		case 1:
			t[+0], t[+1], t[+2], t[+3] = 0, 1, 0, 0
			t[+4], t[+5], t[+6], t[+7] = 1, 1, 0, 0
			t[+8], t[+9], t[10], t[11] = 0, 1, 0, 0
			t[12], t[13], t[14], t[15] = 0, 0, 0, 0
		case 2:
			t[+0], t[+1], t[+2], t[+3] = 0, 0, 0, 0
			t[+4], t[+5], t[+6], t[+7] = 1, 1, 1, 0
			t[+8], t[+9], t[10], t[11] = 0, 1, 0, 0
			t[12], t[13], t[14], t[15] = 0, 0, 0, 0
		case 3:
			t[+0], t[+1], t[+2], t[+3] = 0, 1, 0, 0
			t[+4], t[+5], t[+6], t[+7] = 0, 1, 1, 0
			t[+8], t[+9], t[10], t[11] = 0, 1, 0, 0
			t[12], t[13], t[14], t[15] = 0, 0, 0, 0
		}
	case .J:
		switch rotation {
		case 0:
			t[+0], t[+1], t[+2], t[+3] = 0, 1, 0, 0
			t[+4], t[+5], t[+6], t[+7] = 0, 1, 0, 0
			t[+8], t[+9], t[10], t[11] = 1, 1, 0, 0
			t[12], t[13], t[14], t[15] = 0, 0, 0, 0
		case 1:
			t[+0], t[+1], t[+2], t[+3] = 1, 0, 0, 0
			t[+4], t[+5], t[+6], t[+7] = 1, 1, 1, 0
			t[+8], t[+9], t[10], t[11] = 0, 0, 0, 0
			t[12], t[13], t[14], t[15] = 0, 0, 0, 0
		case 2:
			t[+0], t[+1], t[+2], t[+3] = 0, 1, 1, 0
			t[+4], t[+5], t[+6], t[+7] = 0, 1, 0, 0
			t[+8], t[+9], t[10], t[11] = 0, 1, 0, 0
			t[12], t[13], t[14], t[15] = 0, 0, 0, 0
		case 3:
			t[+0], t[+1], t[+2], t[+3] = 0, 0, 0, 0
			t[+4], t[+5], t[+6], t[+7] = 1, 1, 1, 0
			t[+8], t[+9], t[10], t[11] = 0, 0, 1, 0
			t[12], t[13], t[14], t[15] = 0, 0, 0, 0
		}
	case .L:
		switch rotation {
		case 0:
			t[+0], t[+1], t[+2], t[+3] = 0, 1, 0, 0
			t[+4], t[+5], t[+6], t[+7] = 0, 1, 0, 0
			t[+8], t[+9], t[10], t[11] = 0, 1, 1, 0
			t[12], t[13], t[14], t[15] = 0, 0, 0, 0
		case 1:
			t[+0], t[+1], t[+2], t[+3] = 0, 0, 0, 0
			t[+4], t[+5], t[+6], t[+7] = 1, 1, 1, 0
			t[+8], t[+9], t[10], t[11] = 1, 0, 0, 0
			t[12], t[13], t[14], t[15] = 0, 0, 0, 0
		case 2:
			t[+0], t[+1], t[+2], t[+3] = 1, 1, 0, 0
			t[+4], t[+5], t[+6], t[+7] = 0, 1, 0, 0
			t[+8], t[+9], t[10], t[11] = 0, 1, 0, 0
			t[12], t[13], t[14], t[15] = 0, 0, 0, 0
		case 3:
			t[+0], t[+1], t[+2], t[+3] = 0, 0, 1, 0
			t[+4], t[+5], t[+6], t[+7] = 1, 1, 1, 0
			t[+8], t[+9], t[10], t[11] = 0, 0, 0, 0
			t[12], t[13], t[14], t[15] = 0, 0, 0, 0
		}
	case .S:
		switch rotation {
		case 0, 2:
			t[+0], t[+1], t[+2], t[+3] = 0, 0, 0, 0
			t[+4], t[+5], t[+6], t[+7] = 0, 1, 1, 0
			t[+8], t[+9], t[10], t[11] = 1, 1, 0, 0
			t[12], t[13], t[14], t[15] = 0, 0, 0, 0
		case 1, 3:
			t[+0], t[+1], t[+2], t[+3] = 1, 0, 0, 0
			t[+4], t[+5], t[+6], t[+7] = 1, 1, 0, 0
			t[+8], t[+9], t[10], t[11] = 0, 1, 0, 0
			t[12], t[13], t[14], t[15] = 0, 0, 0, 0
		}
	case .Z:
		switch rotation {
		case 0, 2:
			t[+0], t[+1], t[+2], t[+3] = 0, 0, 0, 0
			t[+4], t[+5], t[+6], t[+7] = 1, 1, 0, 0
			t[+8], t[+9], t[10], t[11] = 0, 1, 1, 0
			t[12], t[13], t[14], t[15] = 0, 0, 0, 0
		case 1, 3:
			t[+0], t[+1], t[+2], t[+3] = 0, 1, 0, 0
			t[+4], t[+5], t[+6], t[+7] = 1, 1, 0, 0
			t[+8], t[+9], t[10], t[11] = 1, 0, 0, 0
			t[12], t[13], t[14], t[15] = 0, 0, 0, 0
		}
	case .None:
	}
}

GameCell :: struct {
	color:  SDL.Color,
	filled: bool,
}

Game :: struct {
	using _:        Rect,
	cols, rows:     int,
	cell_size:      i32,

	//
	last_update_at: f64,
	tetromino:      Tetromino,
	cells:          []GameCell,
}

game_init :: proc(ctx: ^Context, game: ^Game, allocator := context.allocator) {
	cols, rows :: 10, 20
	cell_size :: 20

	game.cols = cols
	game.rows = rows
	game.cell_size = cell_size
	game.size = Vec2{cols, rows} * Vec2{cell_size, cell_size}

	game.cells = make([]GameCell, cols * rows, allocator = allocator)
}

game_layout :: proc(ctx: ^Context, game: ^Game) {
	pos := ctx.window_size / 2 - game.size / 2
	game.pos = pos
}

game_check_collision :: proc(game: ^Game, pos: Cell, tetromino_cells: [16]u8) -> bool {
	for c, i in tetromino_cells do if c == 1 {
		cell := tetromino_game_cell(pos, i)
		cell.row += 1

		if cell.row >= i32(game.rows) {
			return true
		}

		game_cell_idx := cell_to_game_cell_idx(game, cell)
		game_cell := game.cells[game_cell_idx]
		if game_cell.filled {
			return true
		}
	}

	return false
}

game_remove_filled_rows :: proc(game: ^Game) {
	for rowIdx in 0 ..< game.rows {
		begin := rowIdx * game.cols
		end := begin + game.cols
		row := game.cells[begin:end]

		is_filled := true
		for cell in row do if !cell.filled {
			is_filled = false
			break
		}

		if is_filled {
			copy(game.cells[game.cols:end], game.cells[:begin])
			for i in 0 ..< game.cols {
				game.cells[i].filled = false
			}
		}
	}
}

update :: proc(ctx: ^Context, game: ^Game) {
	update_timeout :: 0.5

	if game.last_update_at + update_timeout >= ctx.clock.sim_time {
		return
	}

	if game.tetromino.type == .None {
		tetromino_init(&game.tetromino)
		tetromino_projection(game, &game.tetromino)

		game.last_update_at = ctx.clock.sim_time
	} else {
		if game_check_collision(game, game.tetromino, game.tetromino.cells) {
			for filled, i in game.tetromino.cells do if filled == 1 {
				cell := tetromino_game_cell(&game.tetromino, i)
				game_cell_idx := cell_to_game_cell_idx(game, cell)
				game.cells[game_cell_idx] = GameCell {
					filled = true,
					color  = game.tetromino.color,
				}
			}

			game_remove_filled_rows(game)
			game.tetromino.type = .None
		} else {
			game.tetromino.row += 1
		}

		game.last_update_at = ctx.clock.sim_time
	}
}


render :: proc(ctx: ^Context, game: ^Game) -> (err: Error) {
	set_color(ctx.renderer, SDL.Color{0, 0, 0, 255}) or_return
	sdl_proc(SDL.RenderClear(ctx.renderer)) or_return

	switch ctx.mode {
	case .Menu:
	case .Game:
		set_color(ctx.renderer, SDL.Color{150, 150, 150, 255}) or_return
		draw_rect(ctx.renderer, game.size, game.pos) or_return

		set_color(ctx.renderer, SDL.Color{50, 50, 50, 255}) or_return

		// vertical lines
		for col in 1 ..< game.cols {
			pos := game_cell_to_world_pos(game, Cell{i32(col), 0})
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
		for row in 1 ..< game.rows {
			pos := game_cell_to_world_pos(game, Cell{0, i32(row)})
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

		render_cube :: proc(
			ctx: ^Context,
			game: ^Game,
			cell: Cell,
			color: SDL.Color,
			fill := true,
		) -> (
			err: Error,
		) {
			set_color(ctx.renderer, color) or_return

			pos := game_cell_to_world_pos(game, cell)
			pos += 1
			r := SDL.FRect {
				x = pos.x,
				y = pos.y,
				w = f32(game.cell_size) - 2,
				h = f32(game.cell_size) - 2,
			}
			if fill {
				return sdl_proc(SDL.RenderFillRectF(ctx.renderer, &r))
			} else {
				return sdl_proc(SDL.RenderDrawRectF(ctx.renderer, &r))
			}
		}

		if game.tetromino.type != .None {
			for cell, i in game.tetromino.cells do if cell == 1 {
				game_cell := tetromino_game_cell(&game.tetromino, i)
				render_cube(ctx, game, game_cell, game.tetromino.color) or_return
			}
			for cell, i in game.tetromino.cells do if cell == 1 {
				game_cell := tetromino_game_cell(game.tetromino.projection_pos, i)
				render_cube(ctx, game, game_cell, game.tetromino.color, false) or_return
			}
		}

		for cell, i in game.cells do if cell.filled {
			row := i / game.cols
			col := i % game.cols
			render_cube(ctx, game, Cell{i32(col), i32(row)}, cell.color) or_return
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
					if game.tetromino.type != .None {
						can_shift := true
						for filled, i in game.tetromino.cells do if filled == 1 {
							cell := tetromino_game_cell(&game.tetromino, i)
							can_shift = can_shift && cell.col > 0
							if !can_shift {
								break
							}
							cell.col -= 1
							idx := cell_to_game_cell_idx(&game, cell)
							can_shift = !game.cells[idx].filled
							if !can_shift {
								break
							}
						}
						if can_shift {
							game.tetromino.col -= 1
							tetromino_projection(&game, &game.tetromino)
						}
					}
				case .RIGHT:
					if game.tetromino.type != .None {
						can_shift := true
						for filled, i in game.tetromino.cells do if filled == 1 {
							cell := tetromino_game_cell(&game.tetromino, i)
							can_shift = can_shift && cell.col < i32(game.cols) - 1
							if !can_shift {
								break
							}
							cell.col += 1
							idx := cell_to_game_cell_idx(&game, cell)
							can_shift = !game.cells[idx].filled
							if !can_shift {
								break
							}
						}
						if can_shift {
							game.tetromino.col += 1
							tetromino_projection(&game, &game.tetromino)
						}
					}
				case .UP:
					if game.tetromino.type != .None {
						tetromino_rotate_r(&game.tetromino)

						valid := true
						for filled, i in game.tetromino.cells do if filled == 1 {
							cell := tetromino_game_cell(&game.tetromino, i)

							if cell.col < 0 {
								game.tetromino.col -= cell.col
							} else if cell.col >= i32(game.cols) {
								game.tetromino.col -= cell.col - i32(game.cols) + 1
							} else {
								game_cell_idx := cell_to_game_cell_idx(&game, cell)
								if game.cells[game_cell_idx].filled {
									valid = false
								}
							}
						}

						if !valid {
							tetromino_rotate_l(&game.tetromino)
						} else {
							tetromino_projection(&game, &game.tetromino)
						}
					}
				case .DOWN:
					if game.tetromino.type != .None &&
					   !game_check_collision(&game, game.tetromino, game.tetromino.cells) {
						game.tetromino.row += 1
						game.last_update_at = ctx.clock.sim_time
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
