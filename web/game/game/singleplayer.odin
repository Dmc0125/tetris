package game

import "base:runtime"
import "core:fmt"
import "core:math/rand"
import "core:time"

import platform "../platform"
import ui "../ui"

Clock :: struct {
	time:            f64,
	base_multiplier: f64,
	multiplier:      f64,
	last_update:     f64,
	time_step:       f64,
}

clock_init :: proc(clock: ^Clock, base_multiplier: f64, time_step: f64) {
	clock.time = 0
	clock.base_multiplier = base_multiplier
	clock.multiplier = base_multiplier
	clock.time_step = time_step
	clock.last_update = 0
}

clock_pause :: proc(clock: ^Clock) {
	clock.multiplier = 0
}

clock_resume :: proc(clock: ^Clock) {
	clock.multiplier = clock.base_multiplier
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
	Countdown,
	Game,
	Paused,
	GameOver,
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

SP_LAYOUT_SMALL_BP :: 700

SP_Queue_Ui :: struct {
	container:                 ui.Block,
	header:                    ui.Text,
	tetromino_block_container: ui.Block,
	tetromino_container:       ui.Block,
}

sp_queue_ui_init :: proc(
	q: ^SP_Queue_Ui,
	board_width, time_width: f32,
	window_size: Vec2,
	allocator: runtime.Allocator,
) {
	q.header = ui.Text {
		text = "Next",
	}

	size :: 4 * CUBE_SIZE

	ui.block_init(&q.tetromino_container, .Vertical, Rect{0, 0, size, size}, allocator = allocator)
	ui.block_init(&q.tetromino_block_container, .Vertical, allocator = allocator)

	ui.block_add_child(&q.tetromino_block_container, &q.tetromino_container)

	ui.block_init(&q.container, .Vertical, alignment = .Start, allocator = allocator)
	ui.block_add_child(&q.container, &q.header)
	ui.block_add_child(&q.container, &q.tetromino_block_container)

	sp_queue_ui_layout(q, board_width, time_width, window_size)
}

sp_queue_ui_layout :: proc(q: ^SP_Queue_Ui, board_width, time_width: f32, window_size: Vec2) {
	switch {
	case window_size.x < SP_LAYOUT_SMALL_BP:
		q.header.font_size = .Small
		ui.text_layout(&q.header)

		size :: 4 * CUBE_SIZE

		spacing :: 10
		padding :: 10

		q.container.spacing = spacing
		q.container.padding = padding

		q.container.rect.z = board_width
		q.container.rect.w =
			q.header.rect.w + spacing + q.tetromino_block_container.rect.w + padding * 2

		q.tetromino_block_container.rect.z = board_width - padding * 2
	case:
		q.header.font_size = .Medium
		ui.text_layout(&q.header)

		size :: 4 * CUBE_SIZE

		padding :: 20
		spacing :: 10

		q.container.spacing = spacing
		q.container.padding = padding

		q.container.rect.zw = Vec2{time_width, 120}
		q.tetromino_block_container.rect.z = time_width - padding * 2
	}
}

Singleplayer :: struct {
	perm_allocator:  runtime.Allocator,
	temp_allocator:  runtime.Allocator,


	// ui
	header:          ui.Text,
	countdown_texts: [3]ui.Text,
	game_over_text:  ui.Text,
	pause_button:    ui.Button,
	arrows:          [4]ui.Button,
	time_text:       ui.Text_Mono,
	board:           ui.Block,
	// score
	score_block:     ui.Block,
	score_header:    ui.Text,
	score_text:      ui.Text_Mono,
	// queue
	queue_ui:        SP_Queue_Ui,

	// ui clrs
	clr_card_bg:     Color,
	clr_card_border: Color,
	clr_text_light:  Color,
	clr_text_dark:   Color,
	clr_accent:      Color,

	//
	clock:           Clock,
	state:           SingleplayerState,
	countdown:       int,
	cols, rows:      int,
	queue:           SP_Queue,
	tetromino:       Tetromino,
	filled_cells:    [dynamic]Cube,
	rows_score:      f64,
	score:           f64,
}

sp_init :: proc(
	sp: ^Singleplayer,
	window_size: Vec2,
	clr_card_bg: Color,
	clr_card_border: Color,
	clr_text_light: Color,
	clr_text_dark: Color,
	clr_accent: Color,
	perm_allocator := context.allocator,
	temp_allocator := context.temp_allocator,
) {
	sp.perm_allocator = perm_allocator
	sp.temp_allocator = temp_allocator

	sp.cols = 10
	sp.rows = 20
	sp.filled_cells = make([dynamic]Cube, sp.cols * sp.rows, perm_allocator)

	sp.state = .Countdown
	sp.countdown = 3

	sp_queue_init(&sp.queue)
	tetromino_init(&sp.tetromino, sp_queue_next(&sp.queue), sp)

	clock_init(&sp.clock, 1, 1)

	sp.clr_card_bg = clr_card_bg
	sp.clr_card_border = clr_card_border
	sp.clr_text_light = clr_text_light
	sp.clr_text_dark = clr_text_dark
	sp.clr_accent = clr_accent

	//
	// UI
	//

	ui.text_init(&sp.header, "Tetris classic", .Large)

	ui.text_init(&sp.countdown_texts[0], "1", .Large)
	ui.text_init(&sp.countdown_texts[1], "2", .Large)
	ui.text_init(&sp.countdown_texts[2], "3", .Large)

	ui.text_init(&sp.game_over_text, "Game over", .Large)

	board_width := f32(sp.cols + 2) * CUBE_SIZE
	board_height := f32(sp.rows + 2) * CUBE_SIZE
	ui.block_init(&sp.board, .Vertical, Rect{0, 0, board_width, board_height})

	score_font_size: platform.Font_Size
	pause_btn_size: Vec2

	switch {
	case window_size.x < SP_LAYOUT_SMALL_BP:
		score_font_size = .Small
		pause_btn_size = Vec2{board_width, 30}

		ui.text_mono_init(&sp.time_text, "00:00:00.00", .Small)
	case:
		score_font_size = .Medium

		ui.text_mono_init(&sp.time_text, "00:00:00.00", .Medium)
		pause_btn_size = Vec2{sp.time_text.rect.z, 40}
	}

	ui.button_init(&sp.pause_button, pause_btn_size, "Pause")

	// score

	ui.block_init(
		&sp.score_block,
		.Vertical,
		Rect{0, 0, 120, 120},
		padding = 20,
		spacing = 10,
		alignment = .Start,
		allocator = perm_allocator,
	)

	ui.text_init(&sp.score_header, "Score", .Medium)
	ui.block_add_child(&sp.score_block, &sp.score_header)

	ui.text_mono_init(&sp.score_text, "000000", score_font_size)
	ui.block_add_child(&sp.score_block, &sp.score_text)

	sp_queue_ui_init(
		&sp.queue_ui,
		board_width,
		sp.time_text.rect.z,
		window_size,
		allocator = perm_allocator,
	)

	{ 	// arrows
		arrows := [?]string{"u", "l", "r", "d"}
		for a, i in arrows {
			size :: 40
			ui.button_init(&sp.arrows[i], Vec2{size, size}, a)
		}
	}
}

sp_reset :: proc(sp: ^Singleplayer, window_size: Vec2) {
	for _, i in sp.filled_cells {
		sp.filled_cells[i] = .None
	}

	sp.state = .Countdown
	sp.countdown = 3

	sp_queue_init(&sp.queue)
	tetromino_init(&sp.tetromino, sp_queue_next(&sp.queue), sp)
	clock_init(&sp.clock, 1, 1)

	sp.rows_score = 0
	sp.score = 0
}

sp_layout :: proc(sp: ^Singleplayer, window_size: Vec2) {
	switch {
	case window_size.x < 700:
		{ 	// heading
			h := &sp.header
			ui.text_init(h, "Tetris classic", .Large)
			ui.center_horizontal_in_size(window_size, &h.rect)
			h.rect.y = 20
		}

		// game container
		container: ui.Block
		ui.block_init(
			&container,
			.Vertical,
			Rect{0, 80, 0, 0},
			spacing = 20,
			alignment = .Center,
			allocator = sp.temp_allocator,
		)

		sp_queue_ui_layout(&sp.queue_ui, sp.board.rect.z, 0, window_size)
		ui.block_add_child(&container, &sp.queue_ui.container)

		{ 	// time and score
			sp.time_text.font_size = .Small
			ui.text_mono_layout(&sp.time_text)

			sp.score_text.font_size = .Small
			ui.text_mono_layout(&sp.score_text)

			spacing := sp.board.rect.z - sp.time_text.rect.z - sp.score_text.rect.z

			c: ui.Block
			ui.block_init(
				&c,
				.Horizontal,
				Rect{},
				spacing = spacing,
				allocator = sp.temp_allocator,
			)

			ui.block_add_child(&c, &sp.score_text)
			ui.block_add_child(&c, &sp.time_text)

			ui.block_add_child(&container, &c)
		}

		// board

		ui.block_add_child(&container, &sp.board)

		defer {
			for _, i in sp.countdown_texts {
				ui.center(sp.board.rect, &sp.countdown_texts[i].rect)
			}
			ui.center(sp.board.rect, &sp.game_over_text.rect)
		}


		{ 	// arrows
			arrow_block_size :: 40
			spacing := (sp.board.rect.z - arrow_block_size * 4) / 3

			arrows_container: ui.Block
			ui.block_init(
				&arrows_container,
				.Horizontal,
				Rect{0, 0, sp.board.rect.z, arrow_block_size},
				spacing = spacing,
				allocator = sp.temp_allocator,
			)

			for &a in sp.arrows {
				ui.block_add_child(&arrows_container, &a)
			}

			ui.block_add_child(&container, &arrows_container)
		}

		// pause button
		// TODO: Fix
		ui.button_init(&sp.pause_button, Vec2{sp.board.rect.z, 30}, "Pause")
		ui.block_add_child(&container, &sp.pause_button)

		ui.center_horizontal(window_size, &container.rect)
		ui.block_layout(&container)

	case:
		// left side

		sp.score_text.font_size = .Medium
		ui.text_mono_layout(&sp.score_text)

		left_side_layout: ui.Block
		ui.block_init(
			&left_side_layout,
			.Vertical,
			spacing = 30,
			alignment = .Start,
			allocator = sp.temp_allocator,
		)
		ui.block_add_child(&left_side_layout, &sp.score_block)

		// right side

		sp.time_text.font_size = .Medium
		ui.text_mono_layout(&sp.time_text)

		right_side_layout: ui.Block
		ui.block_init(
			&right_side_layout,
			.Vertical,
			spacing = 30,
			alignment = .End,
			allocator = sp.temp_allocator,
		)
		ui.block_add_child(&right_side_layout, &sp.time_text)
		ui.block_add_child(&right_side_layout, &sp.queue_ui.container)


		ui.block_add_child(&right_side_layout, &sp.pause_button)

		// layout

		layout: ui.Block
		ui.block_init(
			&layout,
			.Horizontal,
			spacing = 30,
			alignment = .Start,
			allocator = sp.temp_allocator,
		)

		ui.block_add_child(&layout, &left_side_layout)
		ui.block_add_child(&layout, &sp.board)
		ui.block_add_child(&layout, &right_side_layout)

		ui.center(window_size, &layout.rect)
		ui.block_layout(&layout)

		// countdown
		ui.center(sp.board.rect, &sp.countdown_texts[0].rect)
		ui.center(sp.board.rect, &sp.countdown_texts[1].rect)
		ui.center(sp.board.rect, &sp.countdown_texts[2].rect)

		ui.center(sp.board.rect, &sp.game_over_text.rect)
	}
}

is_cell_filled :: proc(coords: Coords, sp: ^Singleplayer) -> (filled: bool) {
	idx := coords.row * sp.cols + coords.col
	filled = sp.filled_cells[idx] != .None
	return
}

sp_update :: proc(sp: ^Singleplayer) {
	updated := false

	#partial switch sp.state {
	case .Countdown:
		// update every second
		if clock := &sp.clock; clock.last_update + clock.time_step < clock.time {
			sp.countdown -= 1
			updated = true
		}

		if sp.countdown == 0 {
			sp.state = .Game
		}
	case .Game:
		update_game :: proc(sp: ^Singleplayer) -> (updated: bool) {
			if clock := &sp.clock; clock.last_update + clock.time_step > clock.time {
				return
			}

			updated = true

			// spawn tetromino
			if sp.tetromino.kind == .None {
				t := &sp.tetromino

				next_kind := sp_queue_next(&sp.queue)
				tetromino_init(t, next_kind, sp)

				for c in tetromino_abs_coords(t.coords, t.pos) do if is_cell_filled(c, sp) {
					t.kind = .None
					sp.state = .GameOver
					clock_pause(&sp.clock)
					break
				}

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

						sp.rows_score += 10
						sp.clock.base_multiplier = clamp(sp.clock.base_multiplier + 0.1, 1, 4)
						sp.clock.multiplier = sp.clock.base_multiplier
					}
				}
			}


			sp.score = max(0, sp.rows_score + sp.clock.time - 3)
			return
		}

		updated = update_game(sp)
	case .GameOver:
		sp.pause_button.text = "Play again"
	}

	if updated {
		sp.clock.last_update = sp.clock.time
	}
}

sp_draw :: proc(sp: ^Singleplayer, window_size: Vec2) {
	// header
	ui.text_draw(&sp.header, clr_bg = sp.clr_text_light)

	{ 	// board
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

		if sp.state != .Countdown {
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
		}

		// filled cells
		for cell, i in sp.filled_cells do if cell != .None {
			col := i % sp.cols
			row := i / sp.cols
			pos := game_coords_to_world_pos(Coords{col, row}, sp)
			draw_cube(cell, pos)
		}

		if sp.state == .Countdown {
			text := &sp.countdown_texts[sp.countdown - 1]
			ui.text_draw(text, clr_bg = sp.clr_text_light)
		}
	}

	{ 	// time
		#partial switch sp.state {
		case .Countdown:
			sp.time_text.text = "00:00:00.00"
		case .Game, .Paused, .GameOver:
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

		ui.text_mono_draw(&sp.time_text, clr_bg = sp.clr_text_light)
	}

	{ 	// pause button
		clr_bg, clr_text: Color
		#partial switch sp.state {
		case .Paused, .GameOver:
			clr_bg = sp.clr_accent
			clr_text = sp.clr_text_dark
		case:
			clr_bg = sp.clr_card_border
			clr_text = sp.clr_text_light

		}
		ui.button_draw(&sp.pause_button, .Medium, clr_btn_bg = clr_bg, clr_text_bg = clr_text)
	}

	{ 	// score
		if window_size.x > SP_LAYOUT_SMALL_BP {
			ui.draw_rect(
				sp.score_block.rect,
				ui.Modifiers_Flags{.Background, .Border},
				clr_bg = sp.clr_card_bg,
				clr_border = sp.clr_card_border,
			)
			ui.text_draw(&sp.score_header, clr_bg = sp.clr_text_light)
		}

		sp.score_text.text = fmt.aprintf("%06.0f", sp.score, allocator = sp.temp_allocator)
		ui.text_mono_draw(&sp.score_text, clr_bg = sp.clr_accent)
	}

	{ 	// queue
		ui.draw_rect(
			sp.queue_ui.container.rect,
			ui.Modifiers_Flags{.Background, .Border},
			clr_bg = sp.clr_card_bg,
			clr_border = sp.clr_card_border,
		)

		ui.text_draw(&sp.queue_ui.header, clr_bg = sp.clr_text_light)

		if sp.state != .Countdown {
			next := sp.queue.bag[sp.queue.index]
			for c in tetromino_coords[next][0] {
				pos := sp.queue_ui.tetromino_container.rect.xy + coords_vec(c) * CUBE_SIZE
				draw_cube(tetromino_cubes[next], pos)
			}
		}
	}

	if sp.state == .GameOver {
		ui.text_draw(
			&sp.game_over_text,
			ui.Modifiers_Flags{.Border, .Background},
			clr_bg = sp.clr_text_light,
			clr_border = sp.clr_card_bg,
		)
	}

	// arrows
	for &a in sp.arrows {
		ui.button_draw(
			&a,
			.Medium,
			btn_modifiers = ui.Modifiers_Flags{.Border, .Background},
			clr_btn_bg = sp.clr_card_bg,
			clr_btn_border = sp.clr_card_border,
			clr_text_bg = sp.clr_text_light,
		)
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
				sp.clock.multiplier = sp.clock.base_multiplier
			}
		}
	}

}

sp_pause_button_click :: proc(sp: ^Singleplayer, window_size: Vec2) {
	#partial switch sp.state {
	case .Game:
		sp.pause_button.text = "resume"
		sp.state = .Paused
		clock_pause(&sp.clock)
	case .Paused:
		sp.pause_button.text = "pause"
		sp.state = .Game
		clock_resume(&sp.clock)
	case .GameOver:
		sp.pause_button.text = "pause"
		sp_reset(sp, window_size)
	}
}
