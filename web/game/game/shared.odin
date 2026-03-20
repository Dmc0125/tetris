package game

import "core:math/linalg"

import platform "../platform"

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

Vec2 :: linalg.Vector2f32
Rect :: linalg.Vector4f32
Color :: linalg.Vector4f32

CUBE_TEXTURE_SIZE :: 16
CUBE_SIZE :: CUBE_TEXTURE_SIZE

draw_cube :: proc(cube: Cube, dst: Vec2, size := CUBE_SIZE) {
	assert(cube != .None)

	idx := int(cube) - 1
	src := Rect{f32(idx * CUBE_TEXTURE_SIZE), 0, CUBE_TEXTURE_SIZE, CUBE_TEXTURE_SIZE}
	platform.draw_image(&src, &Rect{dst.x, dst.y, f32(size), f32(size)})
}

TetrominoKind :: enum u8 {
	None,
	I,
	O,
	L,
	J,
	S,
	Z,
	T,
}

// NOTE: Cube coordinates inside 4x4 cube
// with origin at the top left corner
tetromino_coords := [TetrominoKind][4][4]Coords {
	.None = {},
	.I    = {
		{{0, 1}, {1, 1}, {2, 1}, {3, 1}},
		{{2, 0}, {2, 1}, {2, 2}, {2, 3}},
		{{0, 2}, {1, 2}, {2, 2}, {3, 2}},
		{{1, 0}, {1, 1}, {1, 2}, {1, 3}},
	},
	.O    = {
		{{1, 0}, {1, 1}, {2, 0}, {2, 1}},
		{{1, 0}, {1, 1}, {2, 0}, {2, 1}},
		{{1, 0}, {1, 1}, {2, 0}, {2, 1}},
		{{1, 0}, {1, 1}, {2, 0}, {2, 1}},
	},
	.L    = {
		{{0, 1}, {1, 1}, {2, 1}, {2, 0}},
		{{1, 0}, {1, 1}, {1, 2}, {2, 2}},
		{{0, 1}, {1, 1}, {2, 1}, {0, 2}},
		{{0, 0}, {1, 0}, {1, 1}, {1, 2}},
	},
	.J    = {
		{{0, 0}, {0, 1}, {1, 1}, {2, 1}},
		{{1, 0}, {2, 0}, {1, 1}, {1, 2}},
		{{0, 1}, {1, 1}, {2, 1}, {2, 2}},
		{{1, 0}, {1, 1}, {0, 2}, {1, 2}},
	},
	.S    = {
		{{0, 1}, {1, 1}, {1, 0}, {2, 0}},
		{{1, 0}, {1, 1}, {2, 1}, {2, 2}},
		{{0, 2}, {1, 2}, {1, 1}, {2, 1}},
		{{0, 0}, {0, 1}, {1, 1}, {1, 2}},
	},
	.Z    = {
		{{0, 0}, {1, 0}, {1, 1}, {2, 1}},
		{{1, 2}, {1, 1}, {2, 1}, {2, 0}},
		{{0, 1}, {1, 1}, {1, 2}, {2, 2}},
		{{2, 0}, {0, 1}, {1, 1}, {1, 0}},
	},
	.T    = {
		{{1, 0}, {1, 1}, {0, 1}, {2, 1}},
		{{1, 0}, {1, 1}, {2, 1}, {1, 2}},
		{{0, 1}, {1, 1}, {2, 1}, {1, 2}},
		{{1, 0}, {1, 1}, {0, 1}, {1, 2}},
	},
}

tetromino_cubes := [TetrominoKind]Cube {
	.None = {},
	.I    = .Cyan,
	.O    = .Yellow,
	.L    = .Blue,
	.J    = .Orange,
	.S    = .Pink,
	.Z    = .Sand,
	.T    = .Purple,
}

tetromino_rotations_offsets := [4][5]Coords {
	{{0, 0}, {-1, 0}, {-1, +1}, {0, -2}, {-1, -2}},
	{{0, 0}, {+1, 0}, {+1, -1}, {0, +2}, {+1, +2}},
	{{0, 0}, {+1, 0}, {+1, +1}, {0, -2}, {+1, -2}},
	{{0, 0}, {-1, 0}, {-1, -1}, {0, +2}, {-1, +2}},
}

tetromino_i_rotations_offsets := [4][5]Coords {
	{{0, 0}, {-2, 0}, {+1, 0}, {-2, -1}, {+1, +2}},
	{{0, 0}, {-1, 0}, {+2, 0}, {-1, +2}, {+2, -1}},
	{{0, 0}, {+2, 0}, {-1, 0}, {+2, +1}, {-1, -2}},
	{{0, 0}, {+1, 0}, {-2, 0}, {+1, -2}, {-2, +1}},
}
