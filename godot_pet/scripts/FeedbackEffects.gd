extends Node2D

signal temporary_window_extent_requested(seconds)

const BUBBLE_EXTRA_SECONDS := 0.2
const HEART_DURATION := 1.2


class StickerBubble:
	extends Control

	const PAD_X := 12.0
	const PAD_Y := 8.0
	const TAIL_HEIGHT := 9.0
	const MIN_CONTENT_WIDTH := 76.0
	const MAX_CONTENT_HEIGHT := 62.0

	var label: Label
	var body_size := Vector2(112, 42)


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		label = Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.clip_text = true
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(0.16, 0.11, 0.08))
		add_child(label)
		visible = false


	func show_message(text: String, max_width: float) -> void:
		if label == null:
			return
		var available_width = max(MIN_CONTENT_WIDTH, max_width - PAD_X * 2.0)
		var estimated_width = clamp(float(text.length()) * 13.0, MIN_CONTENT_WIDTH, available_width)
		label.text = text
		label.size = Vector2(estimated_width, 96)
		var content_size = label.get_combined_minimum_size()
		var content_width = clamp(max(content_size.x, estimated_width), MIN_CONTENT_WIDTH, available_width)
		label.size = Vector2(content_width, 96)
		content_size = label.get_combined_minimum_size()
		var content_height = clamp(content_size.y, 20.0, MAX_CONTENT_HEIGHT)
		body_size = Vector2(content_width + PAD_X * 2.0, content_height + PAD_Y * 2.0)
		size = body_size + Vector2(0, TAIL_HEIGHT)
		custom_minimum_size = size
		label.position = Vector2(PAD_X, PAD_Y)
		label.size = Vector2(body_size.x - PAD_X * 2.0, body_size.y - PAD_Y * 2.0)
		visible = true
		queue_redraw()


	func _draw() -> void:
		if not visible:
			return
		var body_rect = Rect2(Vector2.ZERO, body_size)
		var tail_x = clamp(body_size.x * 0.28, 26.0, body_size.x - 28.0)
		var tail = PackedVector2Array([
			Vector2(tail_x - 8.0, body_size.y - 1.0),
			Vector2(tail_x + 13.0, body_size.y - 1.0),
			Vector2(tail_x + 2.0, body_size.y + TAIL_HEIGHT),
		])
		var shadow_tail = _offset_points(tail, Vector2(2.0, 3.0))
		var shadow_rect = Rect2(body_rect.position + Vector2(2.0, 3.0), body_rect.size - Vector2(0.0, 1.0))
		draw_colored_polygon(shadow_tail, Color(0.16, 0.09, 0.05, 0.18))
		draw_style_box(_bubble_box(Color(0.16, 0.09, 0.05, 0.18), Color(0, 0, 0, 0), 0), shadow_rect)
		draw_colored_polygon(tail, Color(1.0, 0.965, 0.875, 0.98))
		draw_style_box(_bubble_box(Color(1.0, 0.965, 0.875, 0.98), Color(0.34, 0.20, 0.12, 0.82), 1), body_rect)
		draw_arc(Vector2(body_size.x * 0.28, 9.0), body_size.x * 0.20, 2.95, 3.98, 18, Color(1, 1, 1, 0.42), 2.0, true)
		draw_polyline(PackedVector2Array([tail[0], tail[2], tail[1]]), Color(0.34, 0.20, 0.12, 0.82), 1.0, true)


	func _bubble_box(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
		var box = StyleBoxFlat.new()
		box.bg_color = fill
		box.border_color = border
		box.border_width_left = border_width
		box.border_width_top = border_width
		box.border_width_right = border_width
		box.border_width_bottom = border_width
		box.corner_radius_top_left = 12
		box.corner_radius_top_right = 10
		box.corner_radius_bottom_left = 11
		box.corner_radius_bottom_right = 13
		return box


	func _offset_points(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
		var result := PackedVector2Array()
		for point in points:
			result.append(point + offset)
		return result


class HeartParticle:
	extends Node2D

	var age := 0.0
	var duration := 1.2
	var velocity := Vector2.ZERO
	var heart_size := 14.0
	var body_color := Color(0.95, 0.29, 0.38)
	var spin := 0.0
	var phase := 0.0


	func configure(size_value: float, velocity_value: Vector2, color_value: Color, duration_value: float, spin_value: float, phase_value: float) -> void:
		heart_size = size_value
		velocity = velocity_value
		body_color = color_value
		duration = duration_value
		spin = spin_value
		phase = phase_value


	func _process(delta: float) -> void:
		age += delta
		position += velocity * delta
		velocity *= pow(0.965, delta * 60.0)
		rotation += spin * delta
		queue_redraw()
		if age >= duration:
			queue_free()


	func _draw() -> void:
		var t = clamp(age / max(0.001, duration), 0.0, 1.0)
		var alpha = 1.0
		if t > 0.70:
			alpha = 1.0 - clamp((t - 0.70) / 0.30, 0.0, 1.0)
		var pulse = 0.82 + 0.18 * sin((t + phase) * PI)
		var shadow = Color(0.18, 0.08, 0.07, 0.18 * alpha)
		var fill = Color(body_color.r, body_color.g, body_color.b, body_color.a * alpha)
		var outline = Color(0.38, 0.12, 0.15, 0.70 * alpha)
		draw_colored_polygon(_heart_points(heart_size * pulse, Vector2(1.6, 2.0)), shadow)
		var heart = _heart_points(heart_size * pulse, Vector2.ZERO)
		draw_colored_polygon(heart, fill)
		draw_polyline(_closed_points(heart), outline, 1.4, true)
		draw_circle(Vector2(-heart_size * 0.28, -heart_size * 0.28), heart_size * 0.12, Color(1.0, 0.88, 0.86, 0.75 * alpha))
		_draw_star(Vector2(heart_size * 0.64, -heart_size * 0.42), heart_size * 0.18, Color(1.0, 0.88, 0.48, 0.72 * alpha))


	func _heart_points(size_value: float, offset: Vector2) -> PackedVector2Array:
		var points := PackedVector2Array()
		for i in range(36):
			var theta = TAU * float(i) / 36.0
			var s = sin(theta)
			var x = 16.0 * s * s * s
			var y = -(13.0 * cos(theta) - 5.0 * cos(2.0 * theta) - 2.0 * cos(3.0 * theta) - cos(4.0 * theta))
			points.append(Vector2(x, y) * (size_value / 18.0) + offset)
		return points


	func _closed_points(points: PackedVector2Array) -> PackedVector2Array:
		var result := PackedVector2Array(points)
		if not points.is_empty():
			result.append(points[0])
		return result


	func _draw_star(center: Vector2, radius: float, color: Color) -> void:
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(0, -radius),
			center + Vector2(radius * 0.32, -radius * 0.32),
			center + Vector2(radius, 0),
			center + Vector2(radius * 0.32, radius * 0.32),
			center + Vector2(0, radius),
			center + Vector2(-radius * 0.32, radius * 0.32),
			center + Vector2(-radius, 0),
			center + Vector2(-radius * 0.32, -radius * 0.32),
		]), color)


var repo_root := ""
var pet_sprite
var rng := RandomNumberGenerator.new()
var transient_nodes := []
var bubble: StickerBubble
var bubble_timer: Timer
var bubble_anchor := Vector2(14, 12)
var window_size := Vector2(226, 214)


func _ready() -> void:
	rng.randomize()
	bubble = StickerBubble.new()
	add_child(bubble)

	bubble_timer = Timer.new()
	bubble_timer.one_shot = true
	bubble_timer.timeout.connect(func(): bubble.visible = false)
	add_child(bubble_timer)


func configure(root: String, pet) -> void:
	repo_root = root
	pet_sprite = pet


func set_window_size(value: Vector2) -> void:
	window_size = value
	_layout_bubble()


func show_bubble(text: String, seconds := 1.8) -> void:
	emit_signal("temporary_window_extent_requested", seconds + BUBBLE_EXTRA_SECONDS)
	bubble.show_message(text, _bubble_max_width())
	_layout_bubble()
	bubble_timer.start(seconds)


func set_bubble_position(pos: Vector2) -> void:
	bubble_anchor = pos
	_layout_bubble()


func spawn_heart() -> void:
	emit_signal("temporary_window_extent_requested", HEART_DURATION + 0.15)
	if pet_sprite == null:
		return
	var count = rng.randi_range(2, 3)
	for i in range(count):
		var heart = HeartParticle.new()
		var spread = float(i) - float(count - 1) * 0.5
		var start = pet_sprite.position + Vector2(spread * 22.0 + rng.randf_range(-7, 7), -72.0 + rng.randf_range(-10, 6))
		heart.position = _clamped_effect_position(start, Vector2(36, 36))
		heart.configure(
			rng.randf_range(10.0, 15.5),
			Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-42.0, -24.0)),
			Color(0.92 + rng.randf_range(-0.04, 0.04), 0.30 + rng.randf_range(-0.03, 0.04), 0.38 + rng.randf_range(-0.02, 0.05), 0.96),
			HEART_DURATION + rng.randf_range(-0.08, 0.12),
			rng.randf_range(-0.55, 0.55),
			rng.randf()
		)
		add_child(heart)
		_track_transient(heart)


func spawn_note() -> void:
	var label = Label.new()
	label.text = "小新路过：嘿嘿。"
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.18, 0.15, 0.08))
	label.position = _clamped_effect_position(Vector2(rng.randi_range(18, 220), rng.randi_range(36, 170)), Vector2(128, 26))
	add_child(label)
	_track_transient(label)
	_auto_remove(label, 5.0)


func spawn_footprint() -> void:
	var label = Label.new()
	label.text = "・ ・ ・"
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0.12, 0.1, 0.08, 0.45))
	label.position = _clamped_effect_position(Vector2(rng.randi_range(20, 330), rng.randi_range(160, 220)), Vector2(90, 36))
	add_child(label)
	_track_transient(label)
	_auto_remove(label, 3.6)


func clear_mischief() -> void:
	for node in transient_nodes:
		if is_instance_valid(node):
			node.queue_free()
	transient_nodes.clear()
	show_bubble("清理完成。")


func _layout_bubble() -> void:
	if bubble == null:
		return
	var margin := 6.0
	var max_x = max(margin, window_size.x - bubble.size.x - margin)
	var max_y = max(margin, window_size.y - bubble.size.y - margin)
	bubble.position = Vector2(
		clamp(bubble_anchor.x, margin, max_x),
		clamp(bubble_anchor.y, margin, max_y)
	)


func _bubble_max_width() -> float:
	return max(118.0, min(300.0, window_size.x - 12.0))


func _clamped_effect_position(pos: Vector2, approx_size: Vector2) -> Vector2:
	var margin := 6.0
	return Vector2(
		clamp(pos.x, margin, max(margin, window_size.x - approx_size.x - margin)),
		clamp(pos.y, margin, max(margin, window_size.y - approx_size.y - margin))
	)


func _track_transient(node: Node) -> void:
	transient_nodes.append(node)
	node.tree_exiting.connect(func(): transient_nodes.erase(node))


func _auto_remove(node: Node, seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	if is_instance_valid(node):
		transient_nodes.erase(node)
		node.queue_free()
