package game

import "base:runtime"
import "core:fmt"
import "core:math/rand"
import "core:mem"
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
	Ready,
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

Singleplayer :: struct {
	window_size:               Vec2,
	perm_allocator:            runtime.Allocator,
	temp_allocator:            runtime.Allocator,

	//
	score_arena:               mem.Arena,
	score_data:                [size_of(rune) * 6]u8,
	time_arena:                mem.Arena,
	time_data:                 [size_of(rune) * 11]u8,
	countdown_arena:           mem.Arena,
	// don't know why but using an array of size 1 does not work
	countdown_data:            [size_of(rune) * 2]u8,

	// ui
	layouts:                   [2]ui.Container,
	layout_active:             int,
	board:                     ui.Container,
	action_button:             ui.Button,
	arrows_buttons:            struct {
		u: ui.Button,
		d: ui.Button,
		l: ui.Button,
		r: ui.Button,
	},
	score_text, time_text:     ui.Text_Mono,
	queue_container:           ui.Container,
	queue_header:              ui.Text,
	queue_container_t_wrapper: ui.Container,
	queue_tetromino_block:     ui.Container,
	//
	board_text:                ui.Text,
	ready_screen_container:    ui.Container,
	clr_screen:                Color,

	//
	clock:                     Clock,
	state:                     SingleplayerState,
	countdown:                 int,
	cols, rows:                int,
	queue:                     SP_Queue,
	tetromino:                 Tetromino,
	filled_cells:              [dynamic]Cube,
	rows_score:                f64,
	score:                     f64,
}

sp_init :: proc(
	sp: ^Singleplayer,
	window_size: Vec2,
	clr_screen: Color,
	clr_card_bg: Color,
	clr_card_border: Color,
	clr_text_light: Color,
	clr_text_dark: Color,
	clr_accent: Color,
	perm_allocator, temp_allocator: runtime.Allocator,
) {
	sp.perm_allocator = perm_allocator
	sp.temp_allocator = temp_allocator

	sp.cols = 10
	sp.rows = 20
	sp.filled_cells = make([dynamic]Cube, sp.cols * sp.rows, perm_allocator)

	sp.state = .Ready
	sp.countdown = 3

	mem.arena_init(&sp.score_arena, sp.score_data[:])
	mem.arena_init(&sp.time_arena, sp.time_data[:])
	mem.arena_init(&sp.countdown_arena, sp.countdown_data[:])

	sp.clr_screen = clr_screen

	//
	// UI
	//

	board_size := Vec2{f32(sp.cols + 2) * CUBE_SIZE, f32(sp.rows + 2) * CUBE_SIZE}

	{ 	// ready screen
		sp.ready_screen_container = ui.Container {
			perm_allocator = perm_allocator,
			temp_allocator = temp_allocator,
			rect           = {0, 0, board_size.x, board_size.y},
			sizing         = {.Fixed, .Fixed},
			direction      = .Horizontal,
			alignment      = .Center,
		}

		c1 := ui.container_init(
			perm_allocator,
			temp_allocator,
			rect = {0, 0, board_size.x, 0},
			sizing = {.Fixed, .Auto},
			spacing = 5,
			direction = .Vertical,
			alignment = .Center,
		)
		ui.container_add_child(&sp.ready_screen_container, c1)

		header := new(ui.Text, perm_allocator)
		header.value = "Ready to play?"
		header.font_size = .Medium
		header.appearance = {
			flags = {.Background},
			bg    = clr_text_light,
		}

		subheader := new(ui.Text, perm_allocator)
		subheader.value = "Press Start"
		subheader.font_size = .Small
		subheader.appearance = {
			flags = {.Background},
			bg    = clr_text_light,
		}

		ui.container_add_child(c1, header)
		ui.container_add_child(c1, subheader)
	}

	// board text
	sp.board_text.font_size = .Medium
	sp.board_text.value = "3"
	sp.board_text.appearance = {
		flags  = {.Background, .Border},
		bg     = clr_text_light,
		border = clr_text_dark,
	}


	header := new(ui.Text, perm_allocator)
	header.value = "Tetris classic"
	header.font_size = .Large
	header.appearance = {
		flags = {.Background},
		bg    = clr_text_light,
	}

	sp.board = ui.Container {
		perm_allocator = perm_allocator,
		temp_allocator = temp_allocator,
		rect           = Rect{0, 0, board_size.x, board_size.y},
		sizing         = {.Fixed, .Fixed},
	}

	{ 	// queue
		sp.queue_container = ui.Container {
			perm_allocator = perm_allocator,
			temp_allocator = temp_allocator,
			sizing = {.Fixed, .Auto},
			direction = .Vertical,
			padding = Vec2{10, 5},
			spacing = 10,
			appearance = {
				flags = {.Border, .Background},
				border = clr_card_border,
				bg = clr_card_bg,
			},
		}

		sp.queue_header = ui.Text {
			value = "Next",
			appearance = {flags = {.Background}, bg = clr_text_light},
		}

		sp.queue_container_t_wrapper = ui.Container {
			perm_allocator = perm_allocator,
			temp_allocator = temp_allocator,
			sizing         = {.Fixed, .Auto},
			alignment      = .Center,
			direction      = .Vertical,
		}

		sp.queue_tetromino_block = ui.Container {
			perm_allocator = perm_allocator,
			temp_allocator = temp_allocator,
			rect           = Rect{0, 0, 4 * CUBE_SIZE, 3 * CUBE_SIZE},
			sizing         = {.Fixed, .Fixed},
		}
		ui.container_add_child(&sp.queue_container_t_wrapper, &sp.queue_tetromino_block)

		ui.container_add_child(&sp.queue_container, &sp.queue_header)
		ui.container_add_child(&sp.queue_container, &sp.queue_container_t_wrapper)
	}

	sp.score_text = ui.Text_Mono {
		value = "000000",
		appearance = {flags = {.Background}, bg = clr_accent},
	}

	sp.time_text = ui.Text_Mono {
		value = "00:00:00.00",
		appearance = {flags = {.Background}, bg = clr_text_light},
	}

	arrow_size :: 35
	arrows_texts := [?]string{"U", "L", "R", "D"}
	arrows := [?]^ui.Button {
		&sp.arrows_buttons.u,
		&sp.arrows_buttons.l,
		&sp.arrows_buttons.r,
		&sp.arrows_buttons.d,
	}
	for a, i in arrows_texts {
		arrows[i].text = a
		arrows[i].rect = Rect{0, 0, arrow_size, arrow_size}
		arrows[i].font_size = .Medium
		arrows[i].button_appearance = {
			flags  = {.Border, .Background},
			border = clr_card_border,
			bg     = clr_card_bg,
		}
		arrows[i].text_appearance = {
			flags = {.Background},
			bg    = clr_text_light,
		}
	}

	sp.action_button = ui.Button {
		rect = Rect{0, 0, board_size.x, 40},
		text = "Start",
		font_size = .Medium,
		button_appearance = {flags = {.Background}, bg = clr_accent},
		text_appearance = {flags = {.Background}, bg = clr_text_dark},
	}

	// SM

	sp.layouts[0] = ui.Container {
		perm_allocator = perm_allocator,
		temp_allocator = temp_allocator,
		sizing         = {.Full, .Auto},
		direction      = .Vertical,
		alignment      = .Center,
		spacing        = 10,
	}

	ui.container_add_child(&sp.layouts[0], header)
	ui.container_add_child(&sp.layouts[0], &sp.queue_container)

	{
		// score and time
		score_and_time_container := ui.container_init(
			perm_allocator,
			temp_allocator,
			rect = Rect{0, 0, board_size.x, 0},
			sizing = {.Fixed, .Auto},
			direction = .Horizontal,
		)

		score_container := ui.container_init(
			perm_allocator,
			temp_allocator,
			rect = {0, 0, board_size.x / 2, 0},
			sizing = {.Fixed, .Auto},
		)
		ui.container_add_child(score_container, &sp.score_text)

		time_container := ui.container_init(
			perm_allocator,
			temp_allocator,
			rect = {0, 0, board_size.x / 2, 0},
			sizing = {.Fixed, .Auto},
			direction = .Vertical,
			alignment = .End,
		)
		ui.container_add_child(time_container, &sp.time_text)

		ui.container_add_child(score_and_time_container, score_container)
		ui.container_add_child(score_and_time_container, time_container)

		ui.container_add_child(&sp.layouts[0], score_and_time_container)
	}

	ui.container_add_child(&sp.layouts[0], &sp.board)

	{
		arrows_container := ui.container_init(
			perm_allocator,
			temp_allocator,
			direction = .Horizontal,
			spacing = (sp.board.rect.z - arrow_size * 4) / 3,
		)

		ui.container_add_child(arrows_container, &sp.arrows_buttons.u)
		ui.container_add_child(arrows_container, &sp.arrows_buttons.l)
		ui.container_add_child(arrows_container, &sp.arrows_buttons.r)
		ui.container_add_child(arrows_container, &sp.arrows_buttons.d)

		ui.container_add_child(&sp.layouts[0], arrows_container)
	}

	ui.container_add_child(&sp.layouts[0], &sp.action_button)

	// LG

	sp.layouts[1] = ui.Container {
		perm_allocator = perm_allocator,
		temp_allocator = temp_allocator,
		sizing         = {.Full, .Auto},
		direction      = .Vertical,
		alignment      = .Center,
		spacing        = 50,
	}

	ui.container_add_child(&sp.layouts[1], header)

	game_container := ui.container_init(
		perm_allocator,
		temp_allocator,
		direction = .Horizontal,
		spacing = 40,
	)

	side_panel_init :: proc(perm_allocator, temp_allocator: runtime.Allocator) -> ^ui.Container {
		return ui.container_init(
			perm_allocator,
			temp_allocator,
			sizing = {.Auto, .Auto},
			direction = .Vertical,
			spacing = 20,
		)
	}

	left_side_container := side_panel_init(perm_allocator, temp_allocator)
	side_panel_width :: 150

	{
		score_container := ui.container_init(
			perm_allocator,
			temp_allocator,
			sizing = {.Fixed, .Auto},
			rect = {0, 0, side_panel_width, 0},
			direction = .Vertical,
			padding = {10, 10},
			spacing = 10,
			appearance = {
				flags = {.Background, .Border},
				bg = clr_card_bg,
				border = clr_card_border,
			},
		)

		score_header := new(ui.Text, allocator = perm_allocator)
		score_header.value = "Score"
		score_header.font_size = .Medium
		score_header.appearance = {
			flags = {.Background},
			bg    = clr_text_light,
		}

		ui.container_add_child(score_container, score_header)
		ui.container_add_child(score_container, &sp.score_text)

		ui.container_add_child(left_side_container, score_container)
	}

	{
		arrows_container := ui.container_init(
			perm_allocator,
			temp_allocator,
			sizing = {.Fixed, .Auto},
			rect = {0, 0, side_panel_width, 0},
			direction = .Vertical,
			alignment = .Center,
			spacing = 10,
		)

		ui.container_add_child(arrows_container, &sp.arrows_buttons.u)

		bottom_row := ui.container_init(
			perm_allocator,
			temp_allocator,
			sizing = {.Fixed, .Auto},
			rect = {0, 0, side_panel_width, 0},
			direction = .Horizontal,
			alignment = .Center,
			spacing = (side_panel_width - arrow_size * 3) / 2,
		)

		ui.container_add_child(bottom_row, &sp.arrows_buttons.l)
		ui.container_add_child(bottom_row, &sp.arrows_buttons.d)
		ui.container_add_child(bottom_row, &sp.arrows_buttons.r)

		ui.container_add_child(arrows_container, bottom_row)

		ui.container_add_child(left_side_container, arrows_container)
	}

	ui.container_add_child(game_container, left_side_container)
	ui.container_add_child(game_container, &sp.board)

	right_side_container := side_panel_init(perm_allocator, temp_allocator)
	right_side_container.alignment = .End

	ui.container_add_child(right_side_container, &sp.time_text)
	ui.container_add_child(right_side_container, &sp.queue_container)
	ui.container_add_child(right_side_container, &sp.action_button)

	ui.container_add_child(game_container, right_side_container)

	ui.container_add_child(&sp.layouts[1], game_container)

	sp_layout(sp)
}

sp_start :: proc(sp: ^Singleplayer, window_size: Vec2, state: SingleplayerState = .Ready) {
	for _, i in sp.filled_cells {
		sp.filled_cells[i] = .None
	}

	sp.state = state
	sp.countdown = 3

	sp_queue_init(&sp.queue)
	tetromino_init(&sp.tetromino, sp_queue_next(&sp.queue), sp)
	clock_init(&sp.clock, 1, 1)

	sp.rows_score = 0
	sp.score = 0

	sp.time_text.value = "00:00:00.00"
	sp.score_text.value = "000000"

	sp.window_size = window_size
	sp_layout(sp)
}

sp_layout :: proc(sp: ^Singleplayer) {
	switch {
	case sp.window_size.x < 700:
		sp.score_text.font_size = .Small
		sp.time_text.font_size = .Small

		sp.queue_header.font_size = .Small

		board_width := sp.board.rect.z
		sp.queue_container.rect.z = board_width
		sp.queue_container_t_wrapper.rect.z = board_width
		sp.action_button.rect.z = board_width

		sp.layout_active = 0
	case:
		sp.score_text.font_size = .Medium
		sp.time_text.font_size = .Medium

		sp.queue_header.font_size = .Medium

		sp.queue_container.rect.z = 150
		sp.queue_container_t_wrapper.rect.z = 150 - sp.queue_container.padding.x * 2
		sp.action_button.rect.z = 150

		sp.layout_active = 1
	}

	ui.container_layout(&sp.layouts[sp.layout_active], sp.window_size)

	sp.ready_screen_container.rect.xy =
		sp.board.rect.xy + sp.board.rect.zw / 2 - sp.ready_screen_container.rect.zw / 2
	ui.container_layout(&sp.ready_screen_container, Vec2{})

	ui.text_compute_size(&sp.board_text)
	sp.board_text.rect.xy = sp.board.rect.xy + sp.board.rect.zw / 2 - sp.board_text.rect.zw / 2
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

			countdown_arena := mem.arena_allocator(&sp.countdown_arena)
			free_all(countdown_arena)
			sp.board_text.value = fmt.aprintf("%d", sp.countdown, allocator = countdown_arena)

			sp_layout(sp)
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

					sp.board_text.value = "Game over"
					sp.action_button.text = "Play again"
					sp_layout(sp)

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

			score_allocator := mem.arena_allocator(&sp.score_arena)
			free_all(score_allocator)
			sp.score_text.value = fmt.aprintf("%06.0f", sp.score, allocator = score_allocator)

			return
		}

		{
			time_allocator := mem.arena_allocator(&sp.time_arena)
			free_all(time_allocator)

			total := int(sp.clock.time) - 3
			hours := total / 3600
			minutes := (total / 60) % 60
			seconds := (sp.clock.time - 3) - f64(total) + f64(total % 60)

			sp.time_text.value = fmt.aprintf(
				"%02d:%02d:%05.2f",
				hours,
				minutes,
				seconds,
				allocator = time_allocator,
			)
		}

		updated = update_game(sp)
	case .GameOver:
	}

	if updated {
		sp.clock.last_update = sp.clock.time
	}
}

sp_draw :: proc(sp: ^Singleplayer) {
	platform.fill_rect(&Rect{0, 0, sp.window_size.x, sp.window_size.y}, &sp.clr_screen)

	ui.container_draw(&sp.layouts[sp.layout_active])

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

		if sp.state == .Game || sp.state == .Paused || sp.state == .GameOver {
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
	}

	// queue
	if sp.state == .Game || sp.state == .Paused || sp.state == .GameOver {
		next := sp.queue.bag[sp.queue.index]
		for c in tetromino_coords[next][0] {
			pos := sp.queue_tetromino_block.rect.xy + coords_vec(c) * CUBE_SIZE
			draw_cube(tetromino_cubes[next], pos)
		}
	}

	if sp.state == .Ready {
		ui.container_draw(&sp.ready_screen_container)
	}

	if sp.state == .Countdown || sp.state == .Paused || sp.state == .GameOver {
		ui.text_draw(&sp.board_text)
	}
}


sp_update_and_draw :: proc(
	sp: ^Singleplayer,
	events: [dynamic]platform.Event,
	mouse: platform.Mouse,
	delta_time: f64,
) {
	if sp.state != .Ready && sp.state != .GameOver && sp.state != .Paused {
		clock_frame_start(&sp.clock, delta_time)
	}

	sp_handle_keydown_pressed :: proc(sp: ^Singleplayer) {
		sp.clock.multiplier = 20
	}

	sp_handle_keyleft :: proc(sp: ^Singleplayer) {
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
	}

	sp_handle_keyright :: proc(sp: ^Singleplayer) {
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

	sp_handle_keyup :: proc(sp: ^Singleplayer) {
		if sp.tetromino.kind != .None {
			tetromino_rotate(&sp.tetromino, sp)
		}
	}

	sp_process_event :: proc(sp: ^Singleplayer, event: platform.Event) {
		if event.kind == .Resize {
			sp.window_size = event.resize.size
			sp_layout(sp)
			return
		}

		if sp.state == .Game {
			#partial switch event.kind {
			case .Keydown:
				#partial switch event.keyboard.key {
				case .DOWN:
					sp_handle_keydown_pressed(sp)
				case .UP:
					sp_handle_keyup(sp)
				case .LEFT:
					sp_handle_keyleft(sp)
				case .RIGHT:
					sp_handle_keyright(sp)
				}
			case .Keyup:
				#partial switch event.keyboard.key {
				case .DOWN:
					sp.clock.multiplier = sp.clock.base_multiplier
				}
			}
		}
	}


	for event in events {
		sp_process_event(sp, event)
	}


	#partial switch mouse.state {
	case .Click:
		if ui.rect_collides(sp.action_button.rect, mouse.pos) {
			#partial switch sp.state {
			case .Ready:
				// ready -> game

				clock_init(&sp.clock, 1, 1)

				sp_queue_init(&sp.queue)
				tetromino_init(&sp.tetromino, sp_queue_next(&sp.queue), sp)

				sp.action_button.text = "Pause"

				sp.state = .Countdown
				sp.countdown = 3
				sp_layout(sp)
			case .Game:
				// game -> paused

				sp.action_button.text = "Resume"

				sp.state = .Paused
				sp.board_text.value = "Paused"
				sp_layout(sp)
			case .Paused:
				// paused -> game
				sp.state = .Game
				sp.action_button.text = "Pause"
				sp_layout(sp)
			case .GameOver:
				sp.action_button.text = "Pause"
				sp.board_text.value = "3"
				sp_layout(sp)
				sp_start(sp, sp.window_size, .Countdown)
			}
		}

		if sp.state == .Game {
			// switch {
			// case ui.rect_collides(sp.arrows_buttons.u.rect, mouse.pos):
			// 	sp_handle_keyup(sp)
			// case ui.rect_collides(sp.arrows_buttons.l.rect, mouse.pos):
			// 	sp_handle_keyleft(sp)
			// case ui.rect_collides(sp.arrows_buttons.d.rect, mouse.pos):
			// case ui.rect_collides(sp.arrows_buttons.r.rect, mouse.pos):
			// 	sp_handle_keyright(sp)
			// }
		}


	case .Pressed:
		if sp.state == .Game {
			// switch {
			// case ui.rect_collides(sp.arrows_buttons.u.rect, mouse.pos):
			// 	sp_handle_keyup(sp)
			// case ui.rect_collides(sp.arrows_buttons.l.rect, mouse.pos):
			// 	sp_handle_keyleft(sp)
			// case ui.rect_collides(sp.arrows_buttons.d.rect, mouse.pos):
			// case ui.rect_collides(sp.arrows_buttons.r.rect, mouse.pos):
			// 	sp_handle_keyright(sp)
			// }
		}
	}


	sp_update(sp)
	sp_draw(sp)
}
