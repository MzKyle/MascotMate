extends Node2D

var repo_root := ""
var pet_sprite
var rng := RandomNumberGenerator.new()
var transient_nodes := []
var bubble: Label
var bubble_timer: Timer


func _ready() -> void:
	rng.randomize()
	bubble = Label.new()
	bubble.visible = false
	bubble.add_theme_font_size_override("font_size", 15)
	bubble.add_theme_color_override("font_color", Color(0.12, 0.1, 0.08))
	bubble.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.8))
	bubble.add_theme_constant_override("shadow_offset_x", 1)
	bubble.add_theme_constant_override("shadow_offset_y", 1)
	add_child(bubble)

	bubble_timer = Timer.new()
	bubble_timer.one_shot = true
	bubble_timer.timeout.connect(func(): bubble.visible = false)
	add_child(bubble_timer)


func configure(root: String, pet) -> void:
	repo_root = root
	pet_sprite = pet


func show_bubble(text: String, seconds := 1.8) -> void:
	bubble.text = text
	bubble.visible = true
	bubble_timer.start(seconds)


func set_bubble_position(pos: Vector2) -> void:
	if bubble != null:
		bubble.position = pos


func spawn_heart() -> void:
	var heart = _temporary_sprite("effects/heart.png", 38)
	if heart != null and pet_sprite != null:
		heart.position = pet_sprite.position + Vector2(rng.randf_range(-35, 35), -76)


func spawn_note() -> void:
	var label = Label.new()
	label.text = "小新路过：嘿嘿。"
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.18, 0.15, 0.08))
	label.position = Vector2(rng.randi_range(18, 220), rng.randi_range(36, 170))
	add_child(label)
	transient_nodes.append(label)
	_auto_remove(label, 5.0)


func spawn_footprint() -> void:
	var label = Label.new()
	label.text = "・ ・ ・"
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0.12, 0.1, 0.08, 0.45))
	label.position = Vector2(rng.randi_range(20, 330), rng.randi_range(160, 220))
	add_child(label)
	transient_nodes.append(label)
	_auto_remove(label, 3.6)


func clear_mischief() -> void:
	for node in transient_nodes:
		if is_instance_valid(node):
			node.queue_free()
	transient_nodes.clear()
	show_bubble("清理完成。")


func _temporary_sprite(relative_path: String, size: int):
	var path = repo_root.path_join("assets").path_join(relative_path)
	if not FileAccess.file_exists(path):
		return null
	var image = Image.new()
	if image.load(path) != OK:
		return null
	var texture = ImageTexture.create_from_image(image)
	var sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.scale = Vector2(size / texture.get_size().x, size / texture.get_size().y)
	add_child(sprite)
	transient_nodes.append(sprite)
	_auto_remove(sprite, 1.2)
	return sprite


func _auto_remove(node: Node, seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	if is_instance_valid(node):
		transient_nodes.erase(node)
		node.queue_free()
