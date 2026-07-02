extends Node2D

signal action_finished(next_action)

var repo_root := ""
var frame_root := ""
var skin := {}
var actions := {}
var display_scale := 1.0
var current_action := "idle"
var current_config := {}
var textures := []
var frame_anchors := []
var frame_index := 0
var elapsed := 0.0
var sprite: Sprite2D
var base_size := Vector2(130, 130)
var window_extent_size := Vector2(130, 130)
var current_texture_size := Vector2.ZERO
var current_used_rect := Rect2()
var current_anchor := Vector2.ZERO


func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.centered = true
	add_child(sprite)


func configure(root: String, manifest: Dictionary) -> void:
	repo_root = root
	frame_root = repo_root.path_join("resource_hd")
	skin = {}
	actions = manifest.get("actions", {})


func configure_skin(skin_manifest: Dictionary, frame_root_path: String) -> void:
	skin = skin_manifest.duplicate(true)
	actions = skin.get("actions", {})
	frame_root = frame_root_path


func set_display_scale(value: float) -> void:
	display_scale = clamp(value, 1.0, 1.5)
	_apply_current_frame()


func play(action_id: String) -> bool:
	if not actions.has(action_id):
		return false
	var config = actions[action_id]
	var loaded := []
	var loaded_anchors := []
	var frames = config.get("frames", [])
	var anchors = config.get("anchors", [])
	for i in range(frames.size()):
		var rel_path = frames[i]
		var texture = _load_texture(str(rel_path))
		if texture != null:
			loaded.append(texture)
			if typeof(anchors) == TYPE_ARRAY and i < anchors.size() and _valid_anchor(anchors[i]):
				loaded_anchors.append(Vector2(float(anchors[i][0]), float(anchors[i][1])))
	if loaded.is_empty():
		return false
	current_action = action_id
	current_config = config
	textures = loaded
	frame_anchors = loaded_anchors if loaded_anchors.size() == loaded.size() else []
	frame_index = 0
	elapsed = 0.0
	var size_value = config.get("size", [130, 130])
	base_size = Vector2(float(size_value[0]), float(size_value[1]))
	window_extent_size = _window_extent_for_loaded_frames()
	_apply_current_frame()
	return true


func update_animation(delta: float) -> void:
	if textures.is_empty():
		return
	elapsed += delta
	if elapsed < _current_frame_duration():
		return
	elapsed = 0.0
	if bool(current_config.get("loop", true)):
		var loop_start = int(current_config.get("loop_start", -1))
		if loop_start >= 0 and frame_index >= textures.size() - 1:
			frame_index = clamp(loop_start, 0, textures.size() - 1)
		else:
			frame_index = (frame_index + 1) % textures.size()
	else:
		if frame_index < textures.size() - 1:
			frame_index += 1
		else:
			emit_signal("action_finished", str(current_config.get("next_action", "")))
	_apply_current_frame()


func window_size() -> Vector2i:
	var padded = window_extent_size * display_scale + Vector2(96, 84)
	return Vector2i(max(180, int(padded.x)), max(160, int(padded.y)))


func pet_rect() -> Rect2:
	if sprite != null and sprite.texture != null and current_used_rect.size.x > 0.0 and current_used_rect.size.y > 0.0:
		return visible_rect_for_rotation(0.0)
	return _fallback_pet_rect()


func visible_rect() -> Rect2:
	if sprite == null:
		return pet_rect()
	return visible_rect_for_rotation(sprite.rotation)


func visible_rect_for_rotation(rotation: float) -> Rect2:
	if sprite == null or sprite.texture == null or current_used_rect.size.x <= 0.0 or current_used_rect.size.y <= 0.0:
		return _rotated_rect(_fallback_pet_rect(), rotation)

	var scale = sprite.scale
	var origin = current_anchor if _uses_frame_anchors() else current_texture_size * 0.5
	var min_source = current_used_rect.position - origin
	var max_source = current_used_rect.position + current_used_rect.size - origin
	var min_scaled = Vector2(min_source.x * scale.x, min_source.y * scale.y)
	var max_scaled = Vector2(max_source.x * scale.x, max_source.y * scale.y)
	var rect = Rect2(
		Vector2(min(min_scaled.x, max_scaled.x), min(min_scaled.y, max_scaled.y)),
		Vector2(abs(max_scaled.x - min_scaled.x), abs(max_scaled.y - min_scaled.y))
	)
	return _rotated_rect(rect, rotation)


func mouth_rect() -> Rect2:
	var rect = pet_rect()
	return Rect2(
		rect.position + Vector2(rect.size.x * 0.54, rect.size.y * 0.38),
		Vector2(rect.size.x * 0.34, rect.size.y * 0.26)
	)


func squash(amount: float) -> void:
	sprite.scale = Vector2(1.0 + amount, max(0.72, 1.0 - amount * 0.75)) * _base_sprite_scale()


func reset_transform() -> void:
	sprite.rotation = 0.0
	sprite.scale = _base_sprite_scale()


func lean_from_velocity(velocity: Vector2) -> void:
	sprite.rotation = clamp(velocity.x / 1800.0, -0.35, 0.35)


func _apply_current_frame() -> void:
	if textures.is_empty() or sprite == null:
		return
	sprite.texture = textures[frame_index]
	current_anchor = _current_frame_anchor()
	if _uses_frame_anchors():
		sprite.centered = false
		sprite.offset = -current_anchor
	else:
		sprite.centered = true
		sprite.offset = Vector2.ZERO
	_cache_current_used_rect()
	sprite.scale = _base_sprite_scale()


func _base_sprite_scale() -> Vector2:
	if sprite == null or sprite.texture == null:
		return Vector2.ONE
	var texture_size = sprite.texture.get_size()
	if texture_size.x <= 0 or texture_size.y <= 0:
		return Vector2.ONE
	var scale = Vector2(
		(base_size.x * display_scale) / texture_size.x,
		(base_size.y * display_scale) / texture_size.y
	)
	if bool(current_config.get("mirror_x", false)):
		scale.x *= -1.0
	return scale


func _cache_current_used_rect() -> void:
	if sprite == null or sprite.texture == null:
		current_texture_size = base_size
		current_used_rect = Rect2(Vector2.ZERO, base_size)
		return
	current_texture_size = sprite.texture.get_size()
	var image = sprite.texture.get_image()
	if image == null:
		current_used_rect = Rect2(Vector2.ZERO, current_texture_size)
		return
	var used = image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		current_used_rect = Rect2(Vector2.ZERO, current_texture_size)
	else:
		current_used_rect = Rect2(
			Vector2(float(used.position.x), float(used.position.y)),
			Vector2(float(used.size.x), float(used.size.y))
		)


func _rotated_rect(rect: Rect2, rotation: float) -> Rect2:
	var corners = [
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.position + rect.size,
		rect.position + Vector2(0, rect.size.y),
	]
	var min_pos = corners[0].rotated(rotation)
	var max_pos = min_pos
	for corner in corners:
		var point = corner.rotated(rotation)
		min_pos.x = min(min_pos.x, point.x)
		min_pos.y = min(min_pos.y, point.y)
		max_pos.x = max(max_pos.x, point.x)
		max_pos.y = max(max_pos.y, point.y)
	return Rect2(min_pos, max_pos - min_pos)


func _fallback_pet_rect() -> Rect2:
	var size = base_size * display_scale
	return Rect2(-size * 0.5, size)


func _load_texture(relative_path: String):
	var path = frame_root.path_join(relative_path) if frame_root != "" else repo_root.path_join("resource_hd").path_join(relative_path)
	if FileAccess.file_exists(path):
		var image = Image.new()
		if image.load(path) == OK:
			return ImageTexture.create_from_image(image)
	return null


func _current_frame_duration() -> float:
	var durations = current_config.get("durations_ms", [])
	if typeof(durations) == TYPE_ARRAY and frame_index >= 0 and frame_index < durations.size():
		return max(0.001, float(durations[frame_index]) / 1000.0)
	var fps = float(current_config.get("fps", 10.0))
	return 1.0 / max(1.0, fps)


func _uses_frame_anchors() -> bool:
	return frame_anchors.size() == textures.size() and frame_anchors.size() > 0


func _current_frame_anchor() -> Vector2:
	if _uses_frame_anchors() and frame_index >= 0 and frame_index < frame_anchors.size():
		return frame_anchors[frame_index]
	if sprite != null and sprite.texture != null:
		return sprite.texture.get_size() * 0.5
	return current_texture_size * 0.5


func _valid_anchor(value) -> bool:
	return typeof(value) == TYPE_ARRAY and value.size() >= 2


func _window_extent_for_loaded_frames() -> Vector2:
	if frame_anchors.size() != textures.size() or textures.is_empty():
		return base_size
	var left := 0.0
	var right := 0.0
	var top := 0.0
	var bottom := 0.0
	for i in range(textures.size()):
		var texture_size = textures[i].get_size()
		if texture_size.x <= 0.0 or texture_size.y <= 0.0:
			continue
		var scale = Vector2(base_size.x / texture_size.x, base_size.y / texture_size.y)
		var anchor: Vector2 = frame_anchors[i]
		left = max(left, anchor.x * scale.x)
		right = max(right, (texture_size.x - anchor.x) * scale.x)
		top = max(top, anchor.y * scale.y)
		bottom = max(bottom, (texture_size.y - anchor.y) * scale.y)
	return Vector2(max(left, right) * 2.0, max(top, bottom) * 2.0)
