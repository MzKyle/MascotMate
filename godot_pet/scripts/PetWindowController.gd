extends Node

const INITIAL_WINDOW_MARGIN := 40

var target_window: Window
var target_viewport: Viewport
var transparent_window := false
var mouse_passthrough_enabled := false
var last_mouse_passthrough_polygon := PackedVector2Array()


func configure(window: Window, viewport: Viewport) -> void:
	target_window = window
	target_viewport = viewport
	var safe_window = _env_flag("CRAYON_PET_SAFE_WINDOW", false)
	transparent_window = _env_flag("CRAYON_PET_TRANSPARENT", true) and not safe_window
	mouse_passthrough_enabled = _env_flag("CRAYON_PET_MOUSE_PASSTHROUGH", true)
	if target_window != null:
		target_window.borderless = _env_flag("CRAYON_PET_BORDERLESS", transparent_window)
		target_window.always_on_top = _env_flag("CRAYON_PET_ALWAYS_ON_TOP", transparent_window)
		target_window.transparent = transparent_window
		target_window.unresizable = true
	if target_viewport != null:
		target_viewport.transparent_bg = transparent_window
	if transparent_window:
		RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	else:
		RenderingServer.set_default_clear_color(Color(0.96, 0.94, 0.88, 1))


func is_transparent() -> bool:
	return transparent_window


func is_mouse_passthrough_enabled() -> bool:
	return mouse_passthrough_enabled


func size() -> Vector2i:
	if target_window == null:
		return Vector2i.ZERO
	return target_window.size


func set_size(value: Vector2i) -> void:
	if target_window != null and target_window.size != value:
		target_window.size = value


func position() -> Vector2i:
	if target_window == null:
		return Vector2i.ZERO
	return target_window.position


func apply_position(value: Vector2) -> void:
	if target_window == null:
		return
	var next_position = Vector2i(round(value.x), round(value.y))
	if target_window.position != next_position:
		target_window.position = next_position


func play_area() -> Rect2:
	var screen = DisplayServer.window_get_current_screen()
	return Rect2(
		Vector2(DisplayServer.screen_get_position(screen)),
		Vector2(DisplayServer.screen_get_size(screen))
	)


func ensure_on_screen() -> void:
	if target_window == null:
		return
	var window_rect = Rect2(Vector2(target_window.position), Vector2(target_window.size))
	if _window_rect_is_on_screen(window_rect):
		return
	var area = play_area()
	var min_pos = area.position + Vector2(INITIAL_WINDOW_MARGIN, INITIAL_WINDOW_MARGIN)
	var max_pos = area.position + area.size - Vector2(target_window.size) - Vector2(INITIAL_WINDOW_MARGIN, INITIAL_WINDOW_MARGIN)
	if max_pos.x < min_pos.x:
		max_pos.x = area.position.x
		min_pos.x = area.position.x
	if max_pos.y < min_pos.y:
		max_pos.y = area.position.y
		min_pos.y = area.position.y
	apply_position(Vector2(max_pos.x, max_pos.y))


func set_mouse_passthrough_polygon(polygon: PackedVector2Array) -> void:
	var next_polygon = polygon
	if not transparent_window or not mouse_passthrough_enabled:
		next_polygon = PackedVector2Array()
	if _polygons_equal(last_mouse_passthrough_polygon, next_polygon):
		return
	last_mouse_passthrough_polygon = next_polygon
	if target_window != null:
		target_window.mouse_passthrough_polygon = next_polygon


func mouse_passthrough_polygon() -> PackedVector2Array:
	return last_mouse_passthrough_polygon


func debug_state() -> Dictionary:
	var result := {
		"transparent_window": transparent_window,
		"mouse_passthrough_enabled": mouse_passthrough_enabled,
		"borderless": false,
		"always_on_top": false,
		"window_transparent": false,
		"viewport_transparent_bg": false,
		"position": [],
		"size": [],
	}
	if target_window != null:
		result["borderless"] = target_window.borderless
		result["always_on_top"] = target_window.always_on_top
		result["window_transparent"] = target_window.transparent
		result["position"] = [target_window.position.x, target_window.position.y]
		result["size"] = [target_window.size.x, target_window.size.y]
	if target_viewport != null:
		result["viewport_transparent_bg"] = target_viewport.transparent_bg
	return result


func _window_rect_is_on_screen(rect: Rect2) -> bool:
	for screen in range(DisplayServer.get_screen_count()):
		var screen_rect = Rect2(
			Vector2(DisplayServer.screen_get_position(screen)),
			Vector2(DisplayServer.screen_get_size(screen))
		)
		if screen_rect.intersects(rect, true):
			return true
	return false


func _polygons_equal(left: PackedVector2Array, right: PackedVector2Array) -> bool:
	if left.size() != right.size():
		return false
	for i in range(left.size()):
		if left[i] != right[i]:
			return false
	return true


func _env_flag(name: String, default_value: bool) -> bool:
	var value = OS.get_environment(name).strip_edges().to_lower()
	if value == "":
		return default_value
	return value in ["1", "true", "yes", "on"]
