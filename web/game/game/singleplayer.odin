package game

import "base:runtime"
import "core:fmt"
import "core:math/rand"

import platform "../platform"
import ui "../ui"

Clock :: struct {
	time:       f64,
	multiplier: f64,
}

clock_init :: proc(clock: ^Clock) {
	clock.time = 0
	clock.multiplier = 1
}

clock_frame_start :: proc(clock: ^Clock, delta_time: f64) {
	clock.time += delta_time * clock.multiplier
}

Coords :: struct {
	col, row: int,
}

coords_vec :: proc(coords: Coords) -> (v: Vec2) {
	v.x = f32(coords.col)
	v.y = f32(coords.row)
	return
}

Tetromino :: struct {
	kind:           TetrominoKind,
	rotation:       int,
	pos:            Coords,
	projection_pos: Coords,
	coords:         [4]Coords,
}

tetromino_init :: proc(tetromino: ^Tetromino, kind: TetrominoKind, sp: ^Singleplayer) {
	tetromino.kind = kind
	tetromino.rotation = 0
	tetromino.coords = tetromino_coords[kind][0]

	tetromino.pos.row = 19

	#partial switch kind {
	case .O:
		tetromino.pos.col = 4
	case:
		tetromino.pos.col = 3
	}

	tetromino_project(tetromino, sp)
}

tetromino_project :: proc(tetromino: ^Tetromino, sp: ^Singleplayer) {
	pos := tetromino.pos

	outer: for {
		for c in tetromino_abs_coords(tetromino.coords, pos) {
			if c.row < 0 {
				pos.row += 1
				break outer
			}

			idx := c.row * sp.cols + c.col
			cell := sp.filled_cells[idx]

			if cell != .None {
				pos.row += 1
				break outer
			}
		}

		pos.row -= 1
	}

	tetromino.projection_pos = pos
}

tetromino_rotate :: proc(t: ^Tetromino, sp: ^Singleplayer) {
	nrotation := (t.rotation + 1) % 4
	ncoords := tetromino_coords[t.kind][nrotation]

	if t.kind != .O {
		npos: Coords
		retries := 0

		for ; retries < 5; retries += 1 {
			offsets: Coords
			#partial switch t.kind {
			case .I:
				offsets = tetromino_i_rotations_offsets[t.rotation][retries]
			case:
				offsets = tetromino_rotations_offsets[t.rotation][retries]
			}

			npos.col = t.pos.col + offsets.col
			npos.row = t.pos.row + offsets.row

			collision := false

			for c in tetromino_abs_coords(ncoords, npos) {
				if (c.col < 0 || c.col >= sp.cols) ||
				   (c.row < 0 || c.row >= sp.rows) ||
				   is_cell_filled(c, sp) {
					collision = true
					break
				}
			}

			if !collision {
				t.pos = npos
				t.coords = ncoords
				t.rotation = nrotation

				tetromino_project(t, sp)
				break
			}
		}
	}

	return
}

tetromino_abs_coords :: proc(coords: [4]Coords, pos: Coords) -> (abs_coords: [4]Coords) {
	for c, i in coords {
		abs_coords[i].col = pos.col + c.col
		abs_coords[i].row = pos.row - c.row
	}
	return
}

SingleplayerState :: enum {
	None,
	Countdown,
	Game,
}

SP_Queue :: struct {
	index: int,
	bag:   [7]TetrominoKind,
}

sp_queue_init :: proc(queue: ^SP_Queue) {
	queue.index = 0
	queue.bag = [7]TetrominoKind{.I, .O, .L, .J, .S, .Z, .T}
	rand.shuffle(queue.bag[:])
}

sp_queue_next :: proc(queue: ^SP_Queue) -> TetrominoKind {
	if queue.index == 6 {
		kind := queue.bag[6]
		sp_queue_init(queue)
		return kind
	}

	k := queue.index
	queue.index += 1
	return queue.bag[k]
}

Singleplayer :: struct {
	perm_allocator:  runtime.Allocator,
	temp_allocator:  runtime.Allocator,

	// ui
	countdown_texts: [3]ui.Text,
	board:           ui.Card,
	score_card:      ui.Card,
	time_text:       ui.Text_Mono,
	queue_stack:     ui.Vertical_Stack,
	queue_header:    ui.Text,
	queue_card:      ui.Card,

	//
	clock:           Clock,
	last_update:     f64,
	timestep:        f64,
	state:           SingleplayerState,
	countdown:       int,

	// game
	cols, rows:      int,
	queue:           SP_Queue,
	tetromino:       Tetromino,
	filled_cells:    [dynamic]Cube,
}

sp_init :: proc(
	sp: ^Singleplayer,
	window_size: Vec2,
	clr_text: Color,
	perm_allocator := context.allocator,
	temp_allocator := context.temp_allocator,
) {
	sp.perm_allocator = perm_allocator
	sp.temp_allocator = temp_allocator

	sp.cols = 10
	sp.rows = 20
	sp.filled_cells = make([dynamic]Cube, sp.cols * sp.rows, perm_allocator)

	sp.state = .Countdown

	sp_queue_init(&sp.queue)
	tetromino_init(&sp.tetromino, sp_queue_next(&sp.queue), sp)

	// left side
	ui.card_init(&sp.score_card, Rect{0, 0, 100, 100}, Color{0, 1, 0, 1})

	// board

	board_width := f32(sp.cols + 2) * CUBE_SIZE
	board_height := f32(sp.rows + 2) * CUBE_SIZE
	ui.card_init(&sp.board, Rect{0, 0, board_width, board_height}, Color{1, 0, 0, 1})

	//
	// right side

	// countdown

	sp.countdown = 3

	ui.text_init(&sp.countdown_texts[0], "1", clr_text)
	ui.text_init(&sp.countdown_texts[1], "2", clr_text)
	ui.text_init(&sp.countdown_texts[2], "3", clr_text)

	// time

	sp.timestep = 1
	clock_init(&sp.clock)

	ui.text_mono_init(&sp.time_text, "00:00:00.00", clr_text)

	{ 	// queue
		ui.vertical_stack_init(&sp.queue_stack, Vec2{}, 10, .Start, perm_allocator)

		ui.text_init(&sp.queue_header, "Next", clr_text)
		ui.vertical_stack_add(&sp.queue_stack, &sp.queue_header)

		size :: 4 * CUBE_SIZE
		ui.card_init(&sp.queue_card, Rect{0, 0, size, size}, Color{1, 0, 0, 1})
		ui.vertical_stack_add(&sp.queue_stack, &sp.queue_card)
	}
}

sp_layout :: proc(sp: ^Singleplayer, window_size: Vec2) {
	// left side

	left_side_layout: ui.Vertical_Stack
	ui.vertical_stack_init(&left_side_layout, Vec2{}, 30, .Start, sp.temp_allocator)
	ui.vertical_stack_add(&left_side_layout, &sp.score_card)

	// right side

	right_side_layout: ui.Vertical_Stack
	ui.vertical_stack_init(&right_side_layout, Vec2{}, 30, .End, sp.temp_allocator)
	ui.vertical_stack_add(&right_side_layout, &sp.time_text)
	ui.vertical_stack_add(&right_side_layout, &sp.queue_stack)

	// layout

	layout: ui.Horizontal_Stack
	ui.horizontal_stack_init(&layout, Vec2{}, 30, .Start, sp.temp_allocator)

	ui.horizontal_stack_add(&layout, &left_side_layout)
	ui.horizontal_stack_add(&layout, &sp.board)
	ui.horizontal_stack_add(&layout, &right_side_layout)

	ui.center(window_size, &layout.rect)
	ui.horizontal_stack_layout(&layout)

	// countdown
	ui.center(sp.board.rect, &sp.countdown_texts[0].rect)
	ui.center(sp.board.rect, &sp.countdown_texts[1].rect)
	ui.center(sp.board.rect, &sp.countdown_texts[2].rect)
}

is_cell_filled :: proc(coords: Coords, sp: ^Singleplayer) -> (filled: bool) {
	idx := coords.row * sp.cols + coords.col
	filled = sp.filled_cells[idx] != .None
	return
}

sp_update :: proc(sp: ^Singleplayer) {
	updated := false

	switch sp.state {
	case .None:
	case .Countdown:
		// update every second
		if sp.last_update + sp.timestep < sp.clock.time {
			sp.countdown -= 1
			updated = true
		}

		if sp.countdown == 0 {
			sp.state = .Game
		}
	case .Game:
		update_game :: proc(sp: ^Singleplayer) -> (updated: bool) {
			if sp.last_update + sp.timestep > sp.clock.time {
				return
			}

			updated = true

			// spawn tetromino
			if sp.tetromino.kind == .None {
				next_kind := sp_queue_next(&sp.queue)
				tetromino_init(&sp.tetromino, next_kind, sp)
				return
			}

			// move tetromino

			sp.tetromino.pos.row -= 1

			tetromino := &sp.tetromino
			collided := false

			// check collision with bottom and filled cells
			for c in tetromino_abs_coords(tetromino.coords, tetromino.pos) do if c.row < 0 || is_cell_filled(c, sp) {
				collided = true
				break
			}

			if collided {
				// put cells to the filled cells
				tetromino.pos.row += 1

				for c in tetromino_abs_coords(tetromino.coords, tetromino.pos) {
					idx := c.row * sp.cols + c.col
					sp.filled_cells[idx] = tetromino_cubes[tetromino.kind]
				}

				// delete current tetromino
				tetromino.kind = .None

				// delete filled rows
				//
				// 2: ---xx--x-x -> checked
				// 1: xxxxxxxxxx -> found filled; row = 1 => dst: [row * sp.cols:], src: [row * sp.cols + sp.cols:]
				// 0: xx--xx-x--
				for row := sp.rows - 1; row >= 0; row -= 1 {
					from_idx := row * sp.cols
					to_idx := from_idx + sp.cols
					row_cells := sp.filled_cells[from_idx:to_idx]
					filled := true

					for rc in row_cells do if rc == .None {
						filled = false
						break
					}

					if filled {
						// this row is filled, need to move all the prev elements
						// to this row
						copy(sp.filled_cells[from_idx:], sp.filled_cells[to_idx:])
						for i in len(sp.filled_cells) - sp.cols ..< len(sp.filled_cells) {
							sp.filled_cells[i] = .None
						}
					}
				}
			}

			return
		}

		updated = update_game(sp)
	}

	if updated {
		sp.last_update = sp.clock.time
	}
}

sp_draw :: proc(sp: ^Singleplayer) {
	ui.card_draw(&sp.score_card)

	{ 	// draw board
		// horizontal walls
		for i in 0 ..< sp.cols + 2 {
			p := sp.board.rect.xy
			p.x += f32(i) * CUBE_SIZE
			draw_cube(.Gray, p)

			p.y += f32(sp.rows + 1) * CUBE_SIZE
			draw_cube(.Gray, p)
		}

		{ 	// vertical walls
			p := sp.board.rect.xy
			p.y += CUBE_SIZE
			for _ in 0 ..< sp.rows {
				draw_cube(.Gray, p)
				draw_cube(.Gray, Vec2{p.x + f32(sp.cols + 1) * CUBE_SIZE, p.y})

				p.y += CUBE_SIZE
			}
		}

		game_coords_to_world_pos :: proc(c: Coords, sp: ^Singleplayer) -> (p: Vec2) {
			p = sp.board.rect.xy
			p.x += f32(c.col + 1) * CUBE_SIZE
			p.y += f32(sp.rows - c.row) * CUBE_SIZE
			return
		}

		if sp.state == .Game {
			if sp.tetromino.kind != .None {
				// tetromino
				t := &sp.tetromino
				for c in tetromino_abs_coords(t.coords, t.pos) {
					p := game_coords_to_world_pos(c, sp)
					draw_cube(tetromino_cubes[t.kind], p)
				}

				// projection
				clr_projection := Color{0.6, 0.6, 0.6, 1}
				for c in tetromino_abs_coords(t.coords, t.projection_pos) {
					p := game_coords_to_world_pos(c, sp)
					platform.draw_rect(&Rect{p.x, p.y, CUBE_SIZE, CUBE_SIZE}, &clr_projection)
				}


			}

			// filled cells
			for cell, i in sp.filled_cells do if cell != .None {
				col := i % sp.cols
				row := i / sp.cols
				pos := game_coords_to_world_pos(Coords{col, row}, sp)
				draw_cube(cell, pos)
			}
		}

		if sp.state == .Countdown {
			text := &sp.countdown_texts[sp.countdown - 1]
			ui.text_draw(text)
		}
	}

	// right side

	#partial switch sp.state {
	case .Countdown:
		sp.time_text.text = "00:00:00.00"
	case .Game:
		total := int(sp.clock.time) - 3
		hours := total / 3600
		minutes := (total / 60) % 60
		seconds := (sp.clock.time - 3) - f64(total) + f64(total % 60)
		text := fmt.aprintf(
			"%02d:%02d:%05.2f",
			hours,
			minutes,
			seconds,
			allocator = sp.temp_allocator,
		)
		sp.time_text.text = text
	}

	ui.text_mono_draw(&sp.time_text)

	{ 	// queue
		ui.text_draw(&sp.queue_header)

		if sp.state == .Game {
			next := sp.queue.bag[sp.queue.index]
			for c in tetromino_coords[next][0] {
				pos := sp.queue_card.rect.xy + coords_vec(c) * CUBE_SIZE
				draw_cube(tetromino_cubes[next], pos)
			}
		}
	}
}

sp_process_event :: proc(sp: ^Singleplayer, event: ^platform.Event) {
	if sp.state == .Game {
		#partial switch event.kind {
		case .Keydown:
			#partial switch event.keyboard.key {
			case .DOWN:
				sp.clock.multiplier = 20
			case .UP:
				if sp.tetromino.kind != .None {
					tetromino_rotate(&sp.tetromino, sp)
				}
			case .LEFT:
				if sp.tetromino.kind != .None {
					t := &sp.tetromino
					t.pos.col -= 1
					collision := false

					// check collision with left side and filled cells
					for c in tetromino_abs_coords(t.coords, t.pos) do if c.col < 0 || is_cell_filled(c, sp) {
						collision = true
						break
					}

					// revert if collision
					if collision {
						t.pos.col += 1
					} else {
						tetromino_project(t, sp)
					}
				}
			case .RIGHT:
				if sp.tetromino.kind != .None {
					t := &sp.tetromino
					t.pos.col += 1
					collision := false

					// check collision with right side and filled cells
					for c in tetromino_abs_coords(t.coords, t.pos) do if c.col >= sp.cols || is_cell_filled(c, sp) {
						collision = true
						break
					}

					// revert if collision
					if collision {
						t.pos.col -= 1
					} else {
						tetromino_project(t, sp)
					}
				}
			}
		case .Keyup:
			#partial switch event.keyboard.key {
			case .DOWN:
				sp.clock.multiplier = 1
			}
		}
	}
}
