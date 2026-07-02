extends Node2D

var repo_root := ""
var active := false
var edge := ""
var textures := {}
var sprite: Sprite2D


func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.visible = false
	add_child(sprite)


func configure(root: String) -> void:
	repo_root = root
	_load_textures()


func edge_for_release(global_pos: Vector2, play_area: Rect2, threshold: float) -> String:
	var left = global_pos.x <= play_area.position.x + threshold
	var right = global_pos.x >= play_area.position.x + play_area.size.x - threshold
	var top = global_pos.y <= play_area.position.y + threshold
	var bottom = global_pos.y >= play_area.position.y + play_area.size.y - threshold
	if top and left:
		return "top_left"
	if top and right:
		return "top_right"
	if bottom and left:
		return "bottom_left"
	if bottom and right:
		return "bottom_right"
	if left:
		return "left"
	if right:
		return "right"
	if top:
		return "top"
	if bottom:
		return "bottom"
	return ""


func enter(next_edge: String) -> void:
	active = true
	edge = next_edge
	visible = true
	apply_pose()


func exit() -> void:
	active = false
	edge = ""
	visible = false
	if sprite != null:
		sprite.visible = false


func window_position(target_edge: String, global_pos: Vector2, play_area: Rect2, window_size: Vector2) -> Vector2:
	var right = play_area.position.x + play_area.size.x
	var bottom = play_area.position.y + play_area.size.y
	var x = clamp(global_pos.x - window_size.x * 0.5, play_area.position.x, right - window_size.x)
	var y = clamp(global_pos.y - window_size.y * 0.5, play_area.position.y, bottom - window_size.y)
	if target_edge.contains("left"):
		x = play_area.position.x
	elif target_edge.contains("right"):
		x = right - window_size.x
	if target_edge.contains("top"):
		y = play_area.position.y
	elif target_edge.contains("bottom"):
		y = bottom - window_size.y
	return Vector2(x, y)


func apply_pose() -> void:
	if sprite == null:
		return
	sprite.visible = active
	sprite.texture = _texture_for_edge(edge)
	sprite.position = Vector2.ZERO
	sprite.scale = Vector2.ONE


func _load_textures() -> void:
	textures = {
		"left": _load_asset_texture("character/peek_left.png"),
		"right": _load_asset_texture("character/peek_right.png"),
		"top": _load_asset_texture("character/peek_top.png"),
		"bottom": _load_asset_texture("character/peek_bottom.png"),
	}


func _texture_for_edge(target_edge: String):
	var key = "bottom"
	if target_edge.contains("left"):
		key = "left"
	elif target_edge.contains("right"):
		key = "right"
	elif target_edge.contains("top"):
		key = "top"
	elif target_edge.contains("bottom"):
		key = "bottom"
	var texture = textures.get(key, null)
	if texture == null:
		texture = textures.get("right", null)
	return texture


func _load_asset_texture(relative_path: String):
	var path = repo_root.path_join("assets").path_join(relative_path)
	if not FileAccess.file_exists(path):
		return null
	var image = Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)
