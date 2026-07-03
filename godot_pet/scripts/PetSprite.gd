extends Node2D

signal action_finished(next_action)

const MAX_CACHED_ACTIONS := 10
const MAX_CACHED_FRAMES := 360
const COMPACT_WINDOW_PADDING := Vector2(48, 48)
const COMPACT_WINDOW_MIN := Vector2(96, 96)
const PADDED_WINDOW_PADDING := Vector2(96, 84)
const PADDED_WINDOW_MIN := Vector2(180, 160)

var repo_root := ""
var frame_root := ""
var skin := {}
var actions := {}
var display_scale := 1.0
var current_action := "idle"
var current_config := {}
var textures := []
var frame_anchors := []
var frame_durations := []
var frame_used_rects := []
var frame_texture_sizes := []
var frame_index := 0
var elapsed := 0.0
var sprite: Sprite2D
var base_size := Vector2(130, 130)
var window_extent_size := Vector2(130, 130)
var action_visible_bounds := Rect2(Vector2(-65, -65), Vector2(130, 130))
var current_texture_size := Vector2.ZERO
var current_used_rect := Rect2()
var current_anchor := Vector2.ZERO
var action_cache := {}
var cache_order := []
var cache_frame_count := 0
var cache_hits := 0
var cache_misses := 0


func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.centered = true
	add_child(sprite)


func configure(root: String, manifest: Dictionary) -> void:
	repo_root = root
	frame_root = repo_root.path_join("resource_hd")
	skin = {}
	actions = manifest.get("actions", {})
	_clear_cache()


func configure_skin(skin_manifest: Dictionary, frame_root_path: String) -> void:
	skin = skin_manifest.duplicate(true)
	actions = skin.get("actions", {})
	frame_root = frame_root_path
	_clear_cache()


func set_display_scale(value: float) -> void:
	display_scale = clamp(value, 1.0, 1.5)
	_apply_current_frame()


func play(action_id: String) -> bool:
	if not actions.has(action_id):
		return false
	var config = actions[action_id]
	var entry = _cache_entry_for_action(action_id, config)
	if entry.is_empty():
		return false
	current_action = action_id
	current_config = config
	textures = entry["textures"]
	frame_anchors = entry["anchors"]
	frame_durations = entry["durations_ms"]
	frame_used_rects = entry["used_rects"]
	frame_texture_sizes = entry["texture_sizes"]
	frame_index = 0
	elapsed = 0.0
	base_size = entry["base_size"]
	window_extent_size = entry["window_extent"]
	action_visible_bounds = entry["visible_bounds"]
	_apply_current_frame()
	return true


func cache_info() -> Dictionary:
	return {
		"actions": action_cache.size(),
		"frames": cache_frame_count,
		"hits": cache_hits,
		"misses": cache_misses,
	}


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
	return compact_window_size()


func compact_window_size() -> Vector2i:
	var bounds = action_visible_rect()
	var padded = bounds.size + COMPACT_WINDOW_PADDING
	return Vector2i(
		max(int(COMPACT_WINDOW_MIN.x), int(ceil(padded.x))),
		max(int(COMPACT_WINDOW_MIN.y), int(ceil(padded.y)))
	)


func padded_window_size() -> Vector2i:
	var padded = window_extent_size * display_scale + PADDED_WINDOW_PADDING
	return Vector2i(
		max(int(PADDED_WINDOW_MIN.x), int(ceil(padded.x))),
		max(int(PADDED_WINDOW_MIN.y), int(ceil(padded.y)))
	)


func action_visible_rect() -> Rect2:
	return Rect2(action_visible_bounds.position * display_scale, action_visible_bounds.size * display_scale)


func compact_pet_position(window_size: Vector2) -> Vector2:
	var bounds = action_visible_rect()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return window_size * 0.5
	return window_size * 0.5 - (bounds.position + bounds.size * 0.5)


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


func _cache_entry_for_action(action_id: String, config: Dictionary) -> Dictionary:
	if action_cache.has(action_id):
		cache_hits += 1
		_touch_cache_key(action_id)
		return action_cache[action_id]
	cache_misses += 1
	var entry = _load_action_entry(config)
	if entry.is_empty():
		return {}
	action_cache[action_id] = entry
	cache_frame_count += int(entry.get("frame_count", 0))
	_touch_cache_key(action_id)
	_evict_cache(action_id)
	return entry


func _load_action_entry(config: Dictionary) -> Dictionary:
	var loaded := []
	var loaded_anchors := []
	var durations := []
	var used_rects := []
	var texture_sizes := []
	var frames = config.get("frames", [])
	var anchors = config.get("anchors", [])
	var durations_ms = config.get("durations_ms", [])
	var precomputed_used_rects = config.get("used_rects", [])
	if typeof(frames) != TYPE_ARRAY:
		return {}
	var valid_anchor_count := 0
	var valid_duration_count := 0
	for i in range(frames.size()):
		var rel_path = str(frames[i])
		var loaded_frame = _load_frame(rel_path, precomputed_used_rects, i)
		if loaded_frame.is_empty():
			continue
		loaded.append(loaded_frame["texture"])
		texture_sizes.append(loaded_frame["texture_size"])
		used_rects.append(loaded_frame["used_rect"])
		if typeof(anchors) == TYPE_ARRAY and i < anchors.size() and _valid_anchor(anchors[i]):
			loaded_anchors.append(Vector2(float(anchors[i][0]), float(anchors[i][1])))
			valid_anchor_count += 1
		if typeof(durations_ms) == TYPE_ARRAY and i < durations_ms.size():
			durations.append(max(1, int(durations_ms[i])))
			valid_duration_count += 1
	if loaded.is_empty():
		return {}
	var size_value = config.get("size", [130, 130])
	var entry_base_size = Vector2(float(size_value[0]), float(size_value[1]))
	var entry_anchors = loaded_anchors if valid_anchor_count == loaded.size() else []
	return {
		"textures": loaded,
		"anchors": entry_anchors,
		"durations_ms": durations if valid_duration_count == loaded.size() else [],
		"used_rects": used_rects,
		"texture_sizes": texture_sizes,
		"base_size": entry_base_size,
		"window_extent": _window_extent_for_entry(texture_sizes, entry_anchors, entry_base_size),
		"visible_bounds": _visible_bounds_for_entry(used_rects, texture_sizes, entry_anchors, entry_base_size, bool(config.get("mirror_x", false))),
		"frame_count": loaded.size(),
	}


func _load_frame(relative_path: String, precomputed_used_rects, index: int) -> Dictionary:
	var path = frame_root.path_join(relative_path) if frame_root != "" else repo_root.path_join("resource_hd").path_join(relative_path)
	if not FileAccess.file_exists(path):
		return {}
	var image = Image.new()
	if image.load(path) != OK:
		return {}
	var texture_size = Vector2(image.get_width(), image.get_height())
	var used_rect = _precomputed_used_rect(precomputed_used_rects, index, texture_size)
	if used_rect.size.x <= 0.0 or used_rect.size.y <= 0.0:
		var image_used = image.get_used_rect()
		used_rect = Rect2(
			Vector2(float(image_used.position.x), float(image_used.position.y)),
			Vector2(float(image_used.size.x), float(image_used.size.y))
		)
	if used_rect.size.x <= 0.0 or used_rect.size.y <= 0.0:
		used_rect = Rect2(Vector2.ZERO, texture_size)
	return {
		"texture": ImageTexture.create_from_image(image),
		"texture_size": texture_size,
		"used_rect": used_rect,
	}


func _precomputed_used_rect(precomputed_used_rects, index: int, texture_size: Vector2) -> Rect2:
	if typeof(precomputed_used_rects) != TYPE_ARRAY or index < 0 or index >= precomputed_used_rects.size():
		return Rect2()
	var value = precomputed_used_rects[index]
	if not _valid_used_rect(value, texture_size):
		return Rect2()
	return Rect2(
		Vector2(float(value[0]), float(value[1])),
		Vector2(float(value[2]), float(value[3]))
	)


func _valid_used_rect(value, texture_size: Vector2) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() < 4:
		return false
	var x = float(value[0])
	var y = float(value[1])
	var width = float(value[2])
	var height = float(value[3])
	return x >= 0.0 and y >= 0.0 and width > 0.0 and height > 0.0 and x + width <= texture_size.x and y + height <= texture_size.y


func _touch_cache_key(action_id: String) -> void:
	cache_order.erase(action_id)
	cache_order.append(action_id)


func _evict_cache(protected_action_id: String) -> void:
	while (cache_order.size() > MAX_CACHED_ACTIONS or cache_frame_count > MAX_CACHED_FRAMES) and cache_order.size() > 1:
		var victim = str(cache_order[0])
		if victim == protected_action_id or victim == current_action:
			cache_order.remove_at(0)
			cache_order.append(victim)
			if cache_order.size() <= 1:
				return
			continue
		cache_order.remove_at(0)
		var entry = action_cache.get(victim, {})
		cache_frame_count -= int(entry.get("frame_count", 0)) if typeof(entry) == TYPE_DICTIONARY else 0
		action_cache.erase(victim)


func _clear_cache() -> void:
	action_cache = {}
	cache_order = []
	cache_frame_count = 0
	cache_hits = 0
	cache_misses = 0
	textures = []
	frame_anchors = []
	frame_durations = []
	frame_used_rects = []
	frame_texture_sizes = []
	action_visible_bounds = Rect2(-base_size * 0.5, base_size)


func _apply_current_frame() -> void:
	if textures.is_empty() or sprite == null:
		return
	sprite.texture = textures[frame_index]
	current_texture_size = frame_texture_sizes[frame_index] if frame_index < frame_texture_sizes.size() else sprite.texture.get_size()
	current_used_rect = frame_used_rects[frame_index] if frame_index < frame_used_rects.size() else Rect2(Vector2.ZERO, current_texture_size)
	current_anchor = _current_frame_anchor()
	if _uses_frame_anchors():
		sprite.centered = false
		sprite.offset = -current_anchor
	else:
		sprite.centered = true
		sprite.offset = Vector2.ZERO
	sprite.scale = _base_sprite_scale()


func _base_sprite_scale() -> Vector2:
	if current_texture_size.x <= 0.0 or current_texture_size.y <= 0.0:
		return Vector2.ONE
	var scale = Vector2(
		(base_size.x * display_scale) / current_texture_size.x,
		(base_size.y * display_scale) / current_texture_size.y
	)
	if bool(current_config.get("mirror_x", false)):
		scale.x *= -1.0
	return scale


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


func _current_frame_duration() -> float:
	if frame_index >= 0 and frame_index < frame_durations.size():
		return max(0.001, float(frame_durations[frame_index]) / 1000.0)
	var fps = float(current_config.get("fps", 10.0))
	return 1.0 / max(1.0, fps)


func _uses_frame_anchors() -> bool:
	return frame_anchors.size() == textures.size() and frame_anchors.size() > 0


func _current_frame_anchor() -> Vector2:
	if _uses_frame_anchors() and frame_index >= 0 and frame_index < frame_anchors.size():
		return frame_anchors[frame_index]
	return current_texture_size * 0.5


func _valid_anchor(value) -> bool:
	return typeof(value) == TYPE_ARRAY and value.size() >= 2


func _window_extent_for_entry(texture_sizes: Array, anchors: Array, entry_base_size: Vector2) -> Vector2:
	if anchors.size() != texture_sizes.size() or texture_sizes.is_empty():
		return entry_base_size
	var left := 0.0
	var right := 0.0
	var top := 0.0
	var bottom := 0.0
	for i in range(texture_sizes.size()):
		var texture_size: Vector2 = texture_sizes[i]
		if texture_size.x <= 0.0 or texture_size.y <= 0.0:
			continue
		var scale = Vector2(entry_base_size.x / texture_size.x, entry_base_size.y / texture_size.y)
		var anchor: Vector2 = anchors[i]
		left = max(left, anchor.x * scale.x)
		right = max(right, (texture_size.x - anchor.x) * scale.x)
		top = max(top, anchor.y * scale.y)
		bottom = max(bottom, (texture_size.y - anchor.y) * scale.y)
	return Vector2(max(left, right) * 2.0, max(top, bottom) * 2.0)


func _visible_bounds_for_entry(used_rects: Array, texture_sizes: Array, anchors: Array, entry_base_size: Vector2, mirror_x: bool) -> Rect2:
	var result := Rect2()
	var has_bounds := false
	var uses_anchors = anchors.size() == texture_sizes.size() and not texture_sizes.is_empty()
	for i in range(texture_sizes.size()):
		if i >= used_rects.size():
			continue
		var texture_size: Vector2 = texture_sizes[i]
		var used_rect: Rect2 = used_rects[i]
		if texture_size.x <= 0.0 or texture_size.y <= 0.0 or used_rect.size.x <= 0.0 or used_rect.size.y <= 0.0:
			continue
		var anchor: Vector2 = anchors[i] if uses_anchors else texture_size * 0.5
		var frame_rect = _local_rect_for_frame(used_rect, texture_size, anchor, entry_base_size, mirror_x)
		if has_bounds:
			result = result.merge(frame_rect)
		else:
			result = frame_rect
			has_bounds = true
	if has_bounds:
		return result
	return Rect2(-entry_base_size * 0.5, entry_base_size)


func _local_rect_for_frame(used_rect: Rect2, texture_size: Vector2, anchor: Vector2, entry_base_size: Vector2, mirror_x: bool) -> Rect2:
	var scale = Vector2(entry_base_size.x / texture_size.x, entry_base_size.y / texture_size.y)
	if mirror_x:
		scale.x *= -1.0
	var min_source = used_rect.position - anchor
	var max_source = used_rect.position + used_rect.size - anchor
	var min_scaled = Vector2(min_source.x * scale.x, min_source.y * scale.y)
	var max_scaled = Vector2(max_source.x * scale.x, max_source.y * scale.y)
	return Rect2(
		Vector2(min(min_scaled.x, max_scaled.x), min(min_scaled.y, max_scaled.y)),
		Vector2(abs(max_scaled.x - min_scaled.x), abs(max_scaled.y - min_scaled.y))
	)
