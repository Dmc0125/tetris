#+build wasm32
package platform

foreign import "env"
@(default_calling_convention = "contextless")
foreign env {
	set_target_fps :: proc(fps: f32) ---
	get_actual_fps :: proc(fps: ^f32) ---

	window_size :: proc(_: ^Vec2) ---
	draw_image :: proc(src_rect: ^Rect, dst_rect: ^Rect) ---
	draw_rect :: proc(rect: ^Rect, color: ^Color) ---
	fill_rect :: proc(rect: ^Rect, color: ^Color) ---

	// font
	measure_text :: proc(size: ^Vec2, text: string) ---
	font_metrics_max :: proc(size: ^Vec2) ---
	fill_text :: proc(pos: ^Vec2, color: ^Color, text: string) ---
	stroke_text :: proc(pos: ^Vec2, color: ^Color, text: string) ---

	// events
	get_mouse_state :: proc(mx, my: ^f32, btn: ^u8) ---
	poll_event :: proc(event: ^Event) ---
}
