package game

import "core:fmt"
import "core:math/rand"

import platform "../platform"

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
	pos:            Coords,
	projection_pos: Coords,
	coords:         [4]Coords,
}

tetromino_init :: proc(tetromino: ^Tetromino, kind: TetrominoKind, sp: ^Singleplayer) {
	tetromino.kind = kind
	tetromino.coords = tetromino_coords[kind]
	tetromino.pos = Coords{3, 0}
	#partial switch kind {
	case .O:
		tetromino.pos = Coords{4, 0}
	}

	tetromino_project(tetromino, sp)
}

tetromino_project :: proc(tetromino: ^Tetromino, sp: ^Singleplayer) {
	pos := tetromino.pos

	outer: for {
		for c in tetromino.coords {
			abs_col, abs_row := c.col + pos.col, c.row + pos.row

			if abs_row >= sp.rows {
				pos.row -= 1
				break outer
			}

			idx := abs_row * sp.cols + abs_col
			cell := sp.filled_cells[idx]

			if cell != .None {
				pos.row -= 1
				break outer
			}
		}

		pos.row += 1
	}

	tetromino.projection_pos = pos
}

tetromino_abs_coords :: proc(tetromino: ^Tetromino) -> (coords: [4]Coords) {
	for c, i in tetromino.coords {
		coords[i].col = c.col + tetromino.pos.col
		coords[i].row = c.row + tetromino.pos.row
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
	// ui
	using rect:   Rect,
	game_rect:    Rect,
	time_rect:    Rect,
	queue_rect:   Rect,

	//
	clock:        Clock,
	last_update:  f64,
	timestep:     f64,
	state:        SingleplayerState,
	countdown:    int,

	// game
	cols, rows:   int,
	queue:        SP_Queue,
	tetromino:    Tetromino,
	filled_cells: [dynamic]Cube,
}

singleplayer_init :: proc(sp: ^Singleplayer, window_size: Vec2, allocator := context.allocator) {
	// sizes

	sp.cols = 10
	sp.rows = 20
	sp.filled_cells = make([dynamic]Cube, sp.cols * sp.rows, allocator = allocator)

	// full rect

	sp.rect.z = f32((sp.cols + 2) * CUBE_SIZE) * 4
	sp.rect.w = f32((sp.rows + 2) * CUBE_SIZE) * 1.5

	// game

	sp.game_rect.z = f32(sp.cols + 2) * CUBE_SIZE
	sp.game_rect.w = f32(sp.rows + 2) * CUBE_SIZE

	sp.state = .Countdown
	sp.countdown = 3

	// time

	sp.timestep = 1
	clock_init(&sp.clock)

	time_text_size: Vec2
	platform.measure_text(&time_text_size, "999:99:99.99")
	sp.time_rect.zw = time_text_size

	// queue

	sp.queue_rect.zw = 4 * CUBE_SIZE

	singleplayer_layout(sp, window_size)

	// tetromino and queue

	sp_queue_init(&sp.queue)
	tetromino_init(&sp.tetromino, sp_queue_next(&sp.queue), sp)
}

singleplayer_layout :: proc(sp: ^Singleplayer, window_size: Vec2) {
	sp.rect.xy = window_size / 2 - sp.rect.zw / 2
	sp.game_rect.xy = sp.rect.xy + sp.rect.zw / 2 - sp.game_rect.zw / 2

	game_end := sp.game_rect.x + sp.game_rect.z
	padding :: 40

	sp.time_rect.x = game_end + padding
	sp.time_rect.y = sp.game_rect.y

	// align to the end of time rect
	sp.queue_rect.x = sp.time_rect.x + sp.time_rect.z - sp.queue_rect.z
	sp.queue_rect.y = sp.time_rect.y + padding
}

is_cell_filled :: proc(coords: Coords, sp: ^Singleplayer) -> (collided: bool) {
	row_idx := coords.row * sp.cols
	row_cells := sp.filled_cells[row_idx:row_idx + sp.cols]

	for rc, i in row_cells do if rc != .None && i == coords.col {
		collided = true
		break
	}

	return
}

singleplayer_update :: proc(sp: ^Singleplayer) {
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

			sp.tetromino.pos.row += 1

			tetromino := &sp.tetromino
			collided := false

			// check collision with bottom and filled cells
			for c in tetromino_abs_coords(tetromino) do if c.row > sp.rows - 1 || is_cell_filled(c, sp) {
				collided = true
				break
			}

			if collided {
				// put cells to the filled cells
				tetromino.pos.row -= 1

				for c in tetromino_abs_coords(tetromino) {
					idx := c.row * sp.cols + c.col
					sp.filled_cells[idx] = tetromino_cubes[tetromino.kind]
				}

				// delete current tetromino
				tetromino.kind = .None

				// delete filled rows
				for row in 0 ..< sp.rows {
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
						copy(sp.filled_cells[sp.cols:to_idx], sp.filled_cells[:from_idx])
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

singleplayer_draw :: proc(sp: ^Singleplayer) {
	// bg
	platform.fill_rect(&sp.rect, &Color{0.15, 0.15, 0.3, 1})

	switch sp.state {
	case .None:
	case .Countdown:
		countdown_text := fmt.tprintf("%d", sp.countdown)
		countdown_text_size: Vec2
		platform.measure_text(&countdown_text_size, countdown_text)

		pos := sp.rect.xy + sp.rect.zw / 2 - countdown_text_size.xy / 2
		platform.fill_text(&pos, &Color{1, 1, 1, 1}, countdown_text)
	case .Game:
		{ 	// padding horizontal
			for i in 0 ..< 2 + sp.cols {
				x := sp.game_rect.x + f32(i * CUBE_SIZE)

				// upper
				y := sp.game_rect.y
				draw_cube(.Gray, Vec2{x, y})

				// lower
				y += f32(sp.rows + 1) * CUBE_SIZE
				draw_cube(.Gray, Vec2{x, y})
			}
		}

		// padding vertical
		for i in 0 ..< sp.rows {
			y := sp.game_rect.y + CUBE_SIZE + f32(i) * CUBE_SIZE

			// left
			x := sp.game_rect.x
			draw_cube(.Gray, Vec2{x, y})

			x += f32(sp.cols + 1) * CUBE_SIZE
			draw_cube(.Gray, Vec2{x, y})
		}

		{ 	// tetromino and projection
			tetromino := sp.tetromino

			if tetromino.kind != .None {
				start_pos := sp.game_rect.xy + CUBE_SIZE
				tetromino_pos := start_pos + coords_vec(tetromino.pos) * CUBE_SIZE

				for c in sp.tetromino.coords {
					cv := coords_vec(c)
					pos := tetromino_pos + cv * CUBE_SIZE
					draw_cube(tetromino_cubes[tetromino.kind], pos)
				}

				projection_pos := start_pos + coords_vec(tetromino.projection_pos) * CUBE_SIZE

				for c in sp.tetromino.coords {
					cv := coords_vec(c)
					pos := projection_pos + cv * CUBE_SIZE
					platform.draw_rect(
						&Rect{pos.x, pos.y, CUBE_SIZE, CUBE_SIZE},
						&Color{0.6, 0.6, 0.6, 1},
					)
				}
			}
		}

		{ 	// filled cells
			start := sp.game_rect.xy + CUBE_SIZE

			for fc, i in sp.filled_cells do if fc != .None {
				col := i % sp.cols
				row := i / sp.cols

				x := start.x + f32(col) * CUBE_SIZE
				y := start.y + f32(row) * CUBE_SIZE
				draw_cube(fc, Vec2{x, y})
			}
		}

		{ 	// time
			total := int(sp.clock.time) - 3

			hours := total / 3600
			minutes := (total / 60) % 60
			seconds := (sp.clock.time - 3) - f64(total) + f64(total % 60)

			text := fmt.tprintf("%02d:%02d:%05.2f", hours, minutes, seconds)

			text_size: Vec2
			platform.measure_text(&text_size, text)

			pos := sp.time_rect.xy + sp.time_rect.zw - text_size
			platform.fill_text(&pos, &Color{0.8, 0.8, 0.8, 1}, text)
		}

		{ 	// queue
			platform.draw_rect(&sp.queue_rect, &Color{0.8, 0.8, 0.8, 1})

			next := sp.queue.bag[sp.queue.index]
			coords := tetromino_coords[next]

			for c in coords {
				dst := coords_vec(c) * CUBE_SIZE + sp.queue_rect.xy
				draw_cube(tetromino_cubes[next], dst)
			}
		}
	}
}

singleplayer_process_event :: proc(sp: ^Singleplayer, event: ^platform.Event) {
	tetromino_rotate :: proc(tetromino: ^Tetromino) -> (rotated: bool) {
		#partial switch tetromino.kind {
		case .None:
		case .O:
		// no rotation
		case .I:
			rotated = true

			for c, i in tetromino.coords {
				// double
				x := 2 * c.col
				y := 2 * c.row

				// translate
				x -= 3
				y -= 3

				// rotate
				x2 := y
				y2 := -x

				// translate back
				x2 += 3
				y2 += 3

				tetromino.coords[i] = {x2 / 2, y2 / 2}
			}
		case:
			rotated = true
			c := tetromino.coords

			tetromino.coords[0].col = 2 - tetromino.coords[0].row
			tetromino.coords[1].col = 2 - tetromino.coords[1].row
			tetromino.coords[2].col = 2 - tetromino.coords[2].row
			tetromino.coords[3].col = 2 - tetromino.coords[3].row

			tetromino.coords[0].row = c[0].col
			tetromino.coords[1].row = c[1].col
			tetromino.coords[2].row = c[2].col
			tetromino.coords[3].row = c[3].col
		}

		return
	}

	if sp.state == .Game {
		#partial switch event.kind {
		case .Keydown:
			#partial switch event.keyboard.key {
			case .DOWN:
				sp.clock.multiplier = 20
			case .UP:
				if sp.tetromino.kind != .None {
					rotated := tetromino_rotate(&sp.tetromino)

					if rotated {
						// check collision and do kicks

						// project
						tetromino_project(&sp.tetromino, sp)
					}
				}
			case .LEFT:
				if sp.tetromino.kind != .None {
					t := &sp.tetromino
					t.pos.col -= 1
					collision := false

					// check collision with left side and filled cells
					for c in tetromino_abs_coords(t) do if c.col < 0 || is_cell_filled(c, sp) {
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
					for c in tetromino_abs_coords(t) do if c.col >= sp.cols || is_cell_filled(c, sp) {
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
