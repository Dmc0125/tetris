package platform

import "core:math/linalg"

Vec2 :: linalg.Vector2f32
Rect :: linalg.Vector4f32
Color :: linalg.Vector4f32

Font_Size :: enum u8 {
	Small,
	Medium,
	Large,
}

// events

EventKind :: enum u8 {
	None,
	Resize,
	Keydown,
	Keyup,
}

ResizeEvent :: struct {
	kind: EventKind,
	size: linalg.Vector2f32,
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

// mouse

MOUSE_BTN_PRIMARY: u8 : 1 << 0
MOUSE_BTN_SECONDARY: u8 : 1 << 1
MOUSE_BTN_AUXILIARY: u8 : 1 << 2
MOUSE_BTN_BROWSER_BACK: u8 : 1 << 3
MOUSE_BTN_BROWSER_FORWARD: u8 : 1 << 4
