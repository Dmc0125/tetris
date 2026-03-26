package ui

import "base:runtime"
import "core:fmt"
import "core:unicode/utf8"

import platform "../platform"

Vec2 :: platform.Vec2
Rect :: platform.Rect
Color :: platform.Color

fonts := [platform.Font_Size]Vec2 {
	.Small  = Vec2{},
	.Medium = Vec2{},
	.Large  = Vec2{},
}

Alignment :: enum {
	Start,
	Center,
	End,
}

center_in_size :: proc(container: Vec2, child: ^Rect) {
	child.xy = container / 2 - child.zw / 2
}

center_in_container :: proc(container: Rect, child: ^Rect) {
	child.xy = container.xy + container.zw / 2 - child.zw / 2
}

center :: proc {
	center_in_size,
	center_in_container,
}

center_horizontal_in_size :: proc(container: Vec2, child: ^Rect) {
	child.x = container.x / 2 - child.z / 2
}

center_horizontal_in_container :: proc(container: Rect, child: ^Rect) {
	child.x = container.x + container.z / 2 - child.z / 2
}

center_horizontal :: proc {
	center_horizontal_in_size,
	center_horizontal_in_container,
}


Element :: union {
	^Block,
	^Button,
	^Text,
	^Text_Mono,
}

element_rect :: proc(element: Element) -> (r: ^Rect) {
	switch c in element {
	case ^Block:
		r = &c.rect
	case ^Button:
		r = &c.rect
	case ^Text:
		r = &c.rect
	case ^Text_Mono:
		r = &c.rect
	}
	return
}

element_layout :: proc(element: Element) {
	#partial switch c in element {
	case ^Block:
		block_layout(c)
	}
}

Child :: struct {
	element: Element,
	next:    ^Child,
}

Modifiers :: enum {
	Background,
	Border,
}

Modifiers_Flags :: bit_set[Modifiers]

draw_rect :: proc(rect: Rect, flags: Modifiers_Flags, clr_bg := Color{}, clr_border := Color{}) {
	r := rect

	if .Background in flags {
		c := clr_bg
		platform.fill_rect(&r, &c)
	}

	if .Border in flags {
		c := clr_border
		platform.draw_rect(&r, &c)
	}
}

draw_text :: proc(
	pos: Vec2,
	text: string,
	flags: Modifiers_Flags,
	size: platform.Font_Size,
	clr_bg := Color{},
	clr_border := Color{},
) {
	p := pos

	if .Background in flags {
		c := clr_bg
		platform.fill_text_2(&p, &c, text, size)
	}

	if .Border in flags {
		c := clr_border
		platform.stroke_text_2(&p, &c, text, size)
	}
}

Block_Direction :: enum {
	Horizontal,
	Vertical,
}

Block :: struct {
	allocator:  runtime.Allocator,

	//
	rect:       Rect,
	fixed_size: bool,
	padding:    f32,
	// spacing between elements
	spacing:    f32,
	// placement of children
	direction:  Block_Direction,
	// alignment of children based on direction
	alignment:  Alignment,

	// children
	last_child: ^Child,
	children:   ^Child,
}

block_init :: proc(
	block: ^Block,
	direction: Block_Direction,
	rect := Rect{},
	padding: f32 = 0,
	spacing: f32 = 0,
	alignment: Alignment = .Start,
	allocator := context.allocator,
) {
	block.rect = rect
	block.fixed_size = rect.zw != 0

	if !block.fixed_size {
		block.rect.zw = padding * 2
	}

	block.padding = padding
	block.spacing = spacing

	block.direction = direction
	block.alignment = alignment

	block.allocator = allocator
}

block_add_child :: proc(block: ^Block, child: Element) {
	// save child
	c := new(Child, allocator = block.allocator)
	c.element = child
	first_child := block.last_child == nil

	if first_child {
		block.last_child = c
		block.children = c
	} else {
		block.last_child.next = c
		block.last_child = c
	}

	// calc block width
	if !block.fixed_size {
		c_rect := element_rect(child)

		if first_child {
			switch block.direction {
			case .Vertical:
				block.rect.z = max(block.rect.z, c_rect.z + block.padding * 2)
				block.rect.w += c_rect.w
			case .Horizontal:
				block.rect.z += c_rect.z
				block.rect.w = max(block.rect.w, c_rect.w + block.padding * 2)
			}
		} else {
			switch block.direction {
			case .Vertical:
				block.rect.z = max(block.rect.z, c_rect.z + block.padding * 2)
				block.rect.w += c_rect.w + block.spacing
			case .Horizontal:
				block.rect.z += c_rect.z + block.spacing
				block.rect.w = max(block.rect.w, c_rect.w + block.padding * 2)
			}
		}
	}
}

block_layout :: proc(block: ^Block) {
	cursor := block.rect.xy + block.padding
	child := block.children

	for child != nil {
		c_rect := element_rect(child.element)

		// child position
		c_rect.xy = cursor

		switch block.alignment {
		case .Start:
		case .Center:
			switch block.direction {
			case .Vertical:
				// center on x axis
				c_rect.x += block.rect.z / 2 - c_rect.z / 2
			case .Horizontal:
				// center on y axis
				c_rect.y += block.rect.w / 2 - c_rect.w / 2
			}
		case .End:
			switch block.direction {
			case .Vertical:
				// center on x axis
				c_rect.x += block.rect.z - c_rect.z
			case .Horizontal:
				// center on y axis
				c_rect.y += block.rect.w - c_rect.w
			}
		}

		// advance
		switch block.direction {
		case .Vertical:
			cursor.y += c_rect.w + block.spacing
		case .Horizontal:
			cursor.x += c_rect.z + block.spacing
		}
		child = child.next
	}

	// children layouts
	child = block.children

	for child != nil {
		element_layout(child.element)
		child = child.next
	}
}

// button text is always aligned to center
Button :: struct {
	// absolute position on the screen
	rect:      Rect,
	// button text
	text:      string,
	// button text rect relative to the button origin
	text_rect: Rect,
}

button_init :: proc(button: ^Button, size: Vec2, text: string) {
	button.rect.zw = size
	button.text = text
}

button_draw :: proc(
	button: ^Button,
	font_size: platform.Font_Size,
	btn_modifiers := Modifiers_Flags{.Background},
	clr_btn_bg := Color{},
	clr_btn_border := Color{},
	text_modifiers := Modifiers_Flags{.Background},
	clr_text_bg := Color{},
	clr_text_border := Color{},
) {
	draw_rect(button.rect, btn_modifiers, clr_bg = clr_btn_bg, clr_border = clr_btn_border)

	text_size: Vec2
	platform.measure_text_2(&text_size, button.text, font_size)
	text_pos := button.rect.xy + button.rect.zw / 2 - text_size / 2

	c := clr_text_bg
	platform.fill_text_2(&text_pos, &c, button.text, font_size)

	// draw_text(
	// 	text_pos,
	// 	button.text,
	// 	text_modifiers,
	// 	clr_bg = clr_text_bg,
	// 	clr_border = clr_text_border,
	// )
	// platform.draw_rect(&Rect{text_pos.x, text_pos.y, text_size.x, text_size.y}, &Color{1, 0, 0, 1})
}

Text :: struct {
	rect:      Rect,
	text:      string,
	font_size: platform.Font_Size,
}

text_init :: proc(text: ^Text, str: string, font_size: platform.Font_Size) {
	text.text = str
	text.font_size = font_size
	text_layout(text)
}

text_layout :: proc(text: ^Text) {
	text_size: Vec2
	platform.measure_text_2(&text_size, text.text, text.font_size)
	text.rect.zw = text_size
}

text_draw :: proc(
	text: ^Text,
	modifiers := Modifiers_Flags{.Background},
	clr_bg := Color{},
	clr_border := Color{},
) {
	draw_text(
		text.rect.xy,
		text.text,
		modifiers,
		text.font_size,
		clr_bg = clr_bg,
		clr_border = clr_border,
	)
}

Text_Mono :: struct {
	rect:       Rect,
	text:       string,
	char_width: f32,
	font_size:  platform.Font_Size,
}

text_mono_init :: proc(text_mono: ^Text_Mono, text: string, font_size: platform.Font_Size) {
	text_mono.text = text
	text_mono.font_size = font_size
	text_mono_layout(text_mono)
}

text_mono_layout :: proc(text_mono: ^Text_Mono) {
	char_size := fonts[text_mono.font_size]
	text_mono.char_width = char_size.x
	text_mono.rect = Rect{0, 0, f32(len(text_mono.text)) * char_size.x, char_size.y}
}

text_mono_draw :: proc(
	text_mono: ^Text_Mono,
	modifiers := Modifiers_Flags{.Background},
	clr_bg := Color{},
	clr_border := Color{},
) {
	for _, i in text_mono.text {
		offset := f32(i) * text_mono.char_width
		cell_rect := Rect {
			text_mono.rect.x + offset,
			text_mono.rect.y,
			text_mono.char_width,
			text_mono.rect.w,
		}

		char := text_mono.text[i:i + 1]
		char_size: Vec2
		platform.measure_text_2(&char_size, char, text_mono.font_size)

		char_rect: Rect
		char_rect.zw = char_size
		center(cell_rect, &char_rect)

		draw_text(
			char_rect.xy,
			char,
			modifiers,
			text_mono.font_size,
			clr_bg = clr_bg,
			clr_border = clr_border,
		)
	}
}
