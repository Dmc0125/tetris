package ui

import "base:runtime"
import "core:fmt"
import "core:unicode/utf8"

import platform "../platform"

Vec2 :: platform.Vec2
Rect :: platform.Rect
Color :: platform.Color

Alignment :: enum {
	Start,
	Center,
	End,
}

center_screen_left_top_origin :: proc(container: Vec2, child: ^Rect) {
	child.xy = container / 2 - child.zw / 2
}

center_in_container :: proc(container: Rect, child: ^Rect) {
	child.xy = container.xy + container.zw / 2 - child.zw / 2
}

center :: proc {
	center_screen_left_top_origin,
	center_in_container,
}

Element :: union {
	^Vertical_Stack,
	^Horizontal_Stack,
	^Button,
	^Text,
	^Text_Mono,
	^Card,
}

element_rect :: proc(element: Element) -> (r: ^Rect) {
	switch c in element {
	case ^Vertical_Stack:
		r = &c.rect
	case ^Horizontal_Stack:
		r = &c.rect
	case ^Button:
		r = &c.rect
	case ^Text:
		r = &c.rect
	case ^Text_Mono:
		r = &c.rect
	case ^Card:
		r = &c.rect
	}
	return
}

element_layout :: proc(element: Element) {
	#partial switch c in element {
	case ^Vertical_Stack:
		vertical_stack_layout(c)
	case ^Horizontal_Stack:
		horizontal_stack_layout(c)
	}
}

Child :: struct {
	element: Element,
	next:    ^Child,
}

// vertically stacked elements centered around x axis
Vertical_Stack :: struct {
	allocator:  runtime.Allocator,

	// absolute position on the screen and size of children
	rect:       Rect,
	// verical spacing between elements
	spacing:    f32,
	// horizontal alignment of children
	alignment:  Alignment,

	//
	last_child: ^Child,
	children:   ^Child,
}

vertical_stack_init :: proc(
	stack: ^Vertical_Stack,
	pos: Vec2,
	spacing: f32,
	alignment: Alignment,
	allocator := context.allocator,
) {
	stack.rect.xy = pos
	stack.spacing = spacing
	stack.alignment = alignment
	stack.allocator = allocator
}

vertical_stack_add :: proc(stack: ^Vertical_Stack, element: Element) {
	// save child
	c := new(Child, allocator = stack.allocator)
	c.element = element

	if stack.last_child == nil {
		stack.last_child = c
		stack.children = c
	} else {
		stack.last_child.next = c
		stack.last_child = c
	}

	// update size
	el_rect := element_rect(element)
	stack.rect.z = max(stack.rect.z, el_rect.z)
	stack.rect.w += el_rect.w + stack.spacing
}

// sets the absolute position on the screen of all children
// !! expects the stack position to be set
vertical_stack_layout :: proc(stack: ^Vertical_Stack) {
	// calc screen position of children
	child := stack.children
	cursor := stack.rect.xy

	for child != nil {
		el_rect := element_rect(child.element)

		// calc position
		el_rect.xy = cursor
		switch stack.alignment {
		case .Start:
		case .Center:
			el_rect.x += stack.rect.z / 2 - el_rect.z / 2
		case .End:
			el_rect.x += stack.rect.z - el_rect.z
		}

		// advance
		cursor.y += el_rect.w + stack.spacing
		child = child.next
	}

	// calc layout for children
	child = stack.children
	for child != nil {
		element_layout(child.element)
		child = child.next
	}
}

Horizontal_Stack :: struct {
	allocator:  runtime.Allocator,

	// absolute position on the screen and size of children
	rect:       Rect,
	// verical spacing between elements
	spacing:    f32,
	// vertical alignment of children
	alignment:  Alignment,

	//
	last_child: ^Child,
	children:   ^Child,
}

horizontal_stack_init :: proc(
	stack: ^Horizontal_Stack,
	pos: Vec2,
	spacing: f32,
	alignment: Alignment,
	allocator := context.allocator,
) {
	stack.allocator = allocator
	stack.rect.xy = pos
	stack.spacing = spacing
	stack.alignment = alignment
}

horizontal_stack_add :: proc(stack: ^Horizontal_Stack, element: Element) {
	// save child
	c := new(Child, allocator = stack.allocator)
	c.element = element

	if stack.last_child == nil {
		stack.last_child = c
		stack.children = c
	} else {
		stack.last_child.next = c
		stack.last_child = c
	}

	// update size
	el_rect := element_rect(element)
	stack.rect.z += el_rect.z + stack.spacing
	stack.rect.w = max(stack.rect.w, el_rect.w)
}

// sets the absolute position on the screen of all children
// !! expects the stack position to be set
horizontal_stack_layout :: proc(stack: ^Horizontal_Stack) {
	// calc positions
	child := stack.children
	cursor := stack.rect.xy

	for child != nil {
		el_rect := element_rect(child.element)

		// calc position
		el_rect.xy = cursor
		switch stack.alignment {
		case .Start:
		case .Center:
			el_rect.y += stack.rect.w / 2 - el_rect.w / 2
		case .End:
			el_rect.y += stack.rect.w - el_rect.w
		}

		// advance
		cursor.x += el_rect.z + stack.spacing
		child = child.next
	}

	// calc layouts
	child = stack.children
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

	// clrs
	clr_fill:  Color,
	clr_text:  Color,
}

button_init :: proc(button: ^Button, size: Vec2, text: string, clr_fill, clr_text: Color) {
	button.rect.zw = size

	text_size: Vec2
	platform.measure_text(&text_size, text)
	assert(text_size.x < size.x)
	assert(text_size.y < size.y)
	button.text = text

	button.text_rect.zw = text_size
	button.text_rect.xy = size / 2 - text_size / 2

	button.clr_fill = clr_fill
	button.clr_text = clr_text
}

button_draw :: proc(button: ^Button) {
	platform.fill_rect(&button.rect, &button.clr_fill)

	text_pos := button.rect.xy + button.text_rect.xy
	platform.fill_text(&text_pos, &button.clr_text, button.text)

	// 	platform.draw_rect(
	// 		&Rect{text_pos.x, text_pos.y, button.text_rect.z, button.text_rect.w},
	// 		&Color{1, 0, 0, 1},
	// 	)
}

Text :: struct {
	rect: Rect,
	text: string,
	clr:  Color,
}

text_init :: proc(text: ^Text, str: string, clr: Color) {
	text_size: Vec2
	platform.measure_text(&text_size, str)
	text.rect.zw = text_size
	text.text = str
	text.clr = clr
}

text_draw :: proc(text: ^Text) {
	pos := text.rect.xy
	platform.fill_text(&pos, &text.clr, text.text)
}

Text_Mono :: struct {
	rect:       Rect,
	text:       string,
	char_width: f32,
	clr:        Color,
}

text_mono_init :: proc(text_mono: ^Text_Mono, text: string, clr: Color) {
	{
		char_size: Vec2
		platform.font_metrics_max(&char_size)
		text_mono.char_width = char_size.x
		text_mono.rect = Rect{0, 0, f32(len(text)) * char_size.x, char_size.y}
	}

	text_mono.text = text
	text_mono.clr = clr
}

text_mono_draw :: proc(text_mono: ^Text_Mono) {
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
		platform.measure_text(&char_size, char)

		char_rect: Rect
		char_rect.zw = char_size
		center(cell_rect, &char_rect)

		pos := char_rect.xy
		platform.fill_text(&pos, &text_mono.clr, char)
	}
}

Card :: struct {
	rect:     Rect,
	clr_fill: Color,
}

card_init :: proc(card: ^Card, rect: Rect, clr_fill: Color) {
	card.rect = rect
	card.clr_fill = clr_fill
}

card_draw :: proc(card: ^Card) {
	platform.fill_rect(&card.rect, &card.clr_fill)
}
