package ui

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:unicode/utf8"

import platform "../platform"

when ODIN_ARCH == .wasm32 {
	measure_text :: platform.measure_text_2
} else {
	measure_text :: proc(size: ^Vec2, text: string, font_size: platform.Font_Size) {
		char_width: f32
		switch font_size {
		case .Small:
			char_width = 10
			size.y = 10
		case .Medium:
			char_width = 16
			size.y = 16
		case .Large:
			char_width = 24
			size.y = 24
		}

		size.x = f32(len(text)) * char_width
	}
}

Vec2 :: platform.Vec2
Rect :: platform.Rect
Color :: platform.Color

rect_collides :: proc(r: Rect, other: Vec2) -> bool {
	inside_x := r.x <= other.x && r.x + r.z >= other.x
	inside_y := r.y <= other.y && r.y + r.w >= other.y
	return inside_x && inside_y
}

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

Appearance_Modifiers :: enum {
	Background,
	Border,
}

Appearance_Flags :: bit_set[Appearance_Modifiers]

Appearance :: struct {
	flags:      Appearance_Flags,
	bg, border: Color,
}

draw_text :: proc(pos: Vec2, text: string, font_size: platform.Font_Size, appearance: Appearance) {
	pos := pos
	if .Background in appearance.flags {
		c := appearance.bg
		platform.fill_text_2(&pos, &c, text, font_size)
	}
	if .Border in appearance.flags {
		c := appearance.border
		platform.stroke_text_2(&pos, &c, text, font_size)
	}
}

draw_rect :: proc(rect: Rect, appearance: Appearance) {
	rect := rect
	if .Background in appearance.flags {
		c := appearance.bg
		platform.fill_rect(&rect, &c)
	}
	if .Border in appearance.flags {
		c := appearance.border
		platform.draw_rect(&rect, &c)
	}
}

Text :: struct {
	rect:       Rect,
	value:      string,
	font_size:  platform.Font_Size,
	appearance: Appearance,
}

text_compute_size :: proc(text: ^Text) {
	size: Vec2
	measure_text(&size, text.value, text.font_size)
	text.rect.zw = size
}

text_draw :: proc(text: ^Text) {
	draw_text(text.rect.xy, text.value, text.font_size, text.appearance)
}

Text_Mono :: struct {
	rect:       Rect,
	value:      string,
	font_size:  platform.Font_Size,
	appearance: Appearance,
}

text_mono_compute_size :: proc(t: ^Text_Mono) {
	char_size := fonts[t.font_size]
	t.rect.z = f32(len(t.value)) * char_size.x
	t.rect.w = char_size.y
}

text_mono_draw :: proc(t: ^Text_Mono) {
	max_char_size := fonts[t.font_size]
	pos := t.rect.xy

	for _, i in t.value {
		c := t.value[i:i + 1]
		char_size: Vec2
		measure_text(&char_size, c, t.font_size)

		c_pos := pos + max_char_size / 2 - char_size / 2
		draw_text(c_pos, c, t.font_size, t.appearance)

		pos.x += max_char_size.x
	}
}

Button :: struct {
	rect:              Rect,
	text_pos:          Vec2,
	text:              string,
	font_size:         platform.Font_Size,
	button_appearance: Appearance,
	text_appearance:   Appearance,
}

button_compute_layout :: proc(button: ^Button) {
	text_size: Vec2
	measure_text(&text_size, button.text, button.font_size)
	button.text_pos.xy = button.rect.xy + button.rect.zw / 2 - text_size.xy / 2
}

button_draw :: proc(button: ^Button) {
	draw_rect(button.rect, button.button_appearance)
	draw_text(button.text_pos, button.text, button.font_size, button.text_appearance)
}

Direction :: enum {
	Horizontal,
	Vertical,
}

Sizing :: enum {
	Auto,
	Full,
	Fixed,
}

Node :: union {
	^Container,
	^Text,
	^Text_Mono,
	^Button,
}

ChildNode :: struct {
	next: ^ChildNode,
	n:    Node,
}

Container :: struct {
	perm_allocator: runtime.Allocator,
	temp_allocator: runtime.Allocator,
	rect:           Rect,
	sizing:         [2]Sizing,
	padding:        Vec2,
	spacing:        f32,
	direction:      Direction,
	alignment:      Alignment,
	appearance:     Appearance,
	children:       ^ChildNode,
	last_child:     ^ChildNode,
	children_count: int,
}

container_init :: proc(
	perm_allocator, temp_allocator: runtime.Allocator,
	rect := Rect{},
	sizing := [2]Sizing{},
	padding := Vec2{},
	spacing: f32 = 0,
	direction: Direction = .Horizontal,
	alignment: Alignment = .Start,
	appearance := Appearance{},
) -> ^Container {
	container := new(Container, allocator = perm_allocator)
	container.perm_allocator = perm_allocator
	container.temp_allocator = temp_allocator
	container.rect = rect
	container.sizing = sizing
	container.padding = padding
	container.spacing = spacing
	container.direction = direction
	container.alignment = alignment
	container.appearance = appearance
	return container
}

container_add_child :: proc(container: ^Container, child: Node) {
	n := new(ChildNode, allocator = container.perm_allocator)
	n.n = child

	if container.last_child == nil {
		container.last_child = n
		container.children = container.last_child
	} else {
		container.last_child.next = n
		container.last_child = container.last_child.next
	}

	container.children_count += 1
}

node_compute_size :: proc(node: Node, parent_size: Vec2) -> (size: Vec2) {
	switch n in node {
	case ^Container:
		container_compute_size(n, parent_size)
		size = n.rect.zw
	case ^Text:
		text_compute_size(n)
		size = n.rect.zw
	case ^Text_Mono:
		text_mono_compute_size(n)
		size = n.rect.zw
	case ^Button:
		size = n.rect.zw
	}
	return
}

container_compute_size :: proc(container: ^Container, parent_size: Vec2) {
	child := container.children
	children_size: Vec2
	for child != nil {
		child_size := node_compute_size(child.n, parent_size)

		switch container.direction {
		case .Horizontal:
			children_size.x += child_size.x
			children_size.y = max(children_size.y, child_size.y)
		case .Vertical:
			children_size.x = max(children_size.x, child_size.x)
			children_size.y += child_size.y
		}

		child = child.next
	}

	size: Vec2
	if container.sizing.x == .Auto {
		size.x += container.padding.x * 2
	} else if container.sizing.x == .Full {
		size.x = parent_size.x
	}

	if container.sizing.y == .Auto {
		size.y += container.padding.y * 2
	} else if container.sizing.y == .Full {
		size.y = parent_size.y
	}

	if container.direction == .Horizontal {
		if container.sizing.x == .Auto {
			size.x += container.spacing * f32(container.children_count - 1) + children_size.x
		}
		if container.sizing.y == .Auto {
			size.y = children_size.y + container.padding.y * 2
		}
	}

	if container.direction == .Vertical {
		if container.sizing.x == .Auto {
			size.x = children_size.x + container.padding.x * 2
		}
		if container.sizing.y == .Auto {
			size.y += container.spacing * f32(container.children_count - 1) + children_size.y
		}
	}

	if container.sizing.x != .Fixed {
		container.rect.z = size.x
	}
	if container.sizing.y != .Fixed {
		container.rect.w = size.y
	}
}

container_layout :: proc(container: ^Container, parent_size: Vec2) {
	// collect all the nodes
	queue := make([dynamic]Node, allocator = container.temp_allocator)

	collect_nodes :: proc(container: ^Container, queue: ^[dynamic]Node) {
		append(queue, container)
		child := container.children

		for child != nil {
			append(queue, child.n)

			#partial switch n in child.n {
			case ^Container:
				collect_nodes(n, queue)
			}

			child = child.next
		}
	}

	collect_nodes(container, &queue)

	// compute size for each node
	// start from deepest children and bubble up

	#reverse for node in queue {
		node_compute_size(node, parent_size)
	}

	// compute layouts breadth first

	walk_container_breadth_first :: proc(container: ^Container, start_pos: Vec2) {
		set_position :: proc(start_pos: Vec2, container: ^Container, child_rect: ^Rect) {
			switch container.alignment {
			case .Start:
				child_rect.xy = start_pos
			case .Center:
				switch container.direction {
				case .Horizontal:
					child_rect.x = start_pos.x
					child_rect.y = container.rect.y + container.rect.w / 2 - child_rect.w / 2
				case .Vertical:
					child_rect.x = container.rect.x + container.rect.z / 2 - child_rect.z / 2
					child_rect.y = start_pos.y
				}
			case .End:
				switch container.direction {
				case .Horizontal:
					child_rect.x = start_pos.x
					child_rect.y = container.rect.y + container.rect.w - child_rect.w
				case .Vertical:
					child_rect.x = container.rect.x + container.rect.z - child_rect.z
					child_rect.y = start_pos.y
				}
			}
		}

		child := container.children
		pos := container.padding + start_pos

		for idx := 0; child != nil; idx += 1 {
			child_size: Vec2

			switch n in child.n {
			case ^Container:
				child_size = n.rect.zw
				set_position(pos, container, &n.rect)
				walk_container_breadth_first(n, n.rect.xy)
			case ^Text:
				child_size = n.rect.zw
				set_position(pos, container, &n.rect)
			case ^Text_Mono:
				child_size = n.rect.zw
				set_position(pos, container, &n.rect)
			case ^Button:
				child_size = n.rect.zw
				set_position(pos, container, &n.rect)
				button_compute_layout(n)
			}

			switch container.direction {
			case .Horizontal:
				pos.x += child_size.x
			case .Vertical:
				pos.y += child_size.y
			}

			if idx < container.children_count - 1 {
				switch container.direction {
				case .Horizontal:
					pos.x += container.spacing
				case .Vertical:
					pos.y += container.spacing
				}
			}

			child = child.next
		}
	}

	walk_container_breadth_first(container, container.rect.xy)
}

container_draw :: proc(container: ^Container) {
	draw_rect(container.rect, container.appearance)

	child := container.children
	for child != nil {
		switch n in child.n {
		case ^Container:
			container_draw(n)
		case ^Text:
			text_draw(n)
		case ^Text_Mono:
			text_mono_draw(n)
		case ^Button:
			button_draw(n)
		}

		child = child.next
	}
}
