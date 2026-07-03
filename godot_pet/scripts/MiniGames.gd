extends Node2D

signal feed_success
signal tease_success(count, direction)
signal game_finished(name)

const TEASE_SECONDS := 5.0
const TEASE_TRIGGER_MARGIN := 28.0
const TEASE_SPEED := 220.0
const TEASE_COOLDOWN := 0.45
const TEASE_TARGET_COUNT := 3

var repo_root := ""
var pet_sprite
var active := ""
var food: Sprite2D
var dragging_food := false
var tease_elapsed := 0.0
var tease_cooldown := 0.0
var tease_count := 0
var last_mouse_position := Vector2.ZERO
var has_mouse_sample := false


func configure(root: String, pet) -> void:
	repo_root = root
	pet_sprite = pet


func start_feed() -> void:
	clear()
	active = "feed"
	food = _make_sprite("games/rice_ball.png", 58)
	food.position = Vector2(300, 110)
	add_child(food)


func start_tease() -> void:
	clear()
	active = "tease"
	tease_elapsed = 0.0
	tease_cooldown = 0.0
	tease_count = 0
	last_mouse_position = get_viewport().get_mouse_position()
	has_mouse_sample = false


func clear() -> void:
	for child in get_children():
		child.queue_free()
	active = ""
	food = null
	dragging_food = false
	tease_elapsed = 0.0
	tease_cooldown = 0.0
	tease_count = 0
	has_mouse_sample = false


func handle_input(event: InputEvent) -> bool:
	if active != "feed":
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if food != null and food.get_rect().has_point(food.to_local(event.position)):
				dragging_food = true
				return true
		else:
			if dragging_food:
				dragging_food = false
				_check_food_hit()
				return true
	if event is InputEventMouseMotion:
		if dragging_food and food != null:
			food.position = event.position
			return true
	return false


func tick(delta: float) -> void:
	if active != "tease":
		return
	_tick_tease(delta, get_viewport().get_mouse_position())


func _tick_tease(delta: float, mouse_position: Vector2) -> void:
	tease_elapsed += delta
	tease_cooldown = max(0.0, tease_cooldown - delta)
	var velocity := Vector2.ZERO
	if has_mouse_sample:
		velocity = (mouse_position - last_mouse_position) / max(delta, 0.001)
	last_mouse_position = mouse_position
	has_mouse_sample = true
	_register_tease_sample(mouse_position, velocity)
	if active == "tease" and tease_elapsed >= TEASE_SECONDS:
		emit_signal("game_finished", "tease")
		clear()


func _register_tease_sample(mouse_position: Vector2, velocity: Vector2) -> bool:
	if active != "tease" or pet_sprite == null or tease_cooldown > 0.0:
		return false
	var pet_rect = pet_sprite.pet_rect()
	var near_rect = pet_rect.grow(TEASE_TRIGGER_MARGIN)
	var sweep_rect = pet_rect.grow(TEASE_TRIGGER_MARGIN * 2.0)
	var local_mouse = pet_sprite.to_local(mouse_position)
	var inside_near = near_rect.has_point(local_mouse)
	var fast_cross = sweep_rect.has_point(local_mouse) and velocity.length() >= TEASE_SPEED
	if not inside_near and not fast_cross:
		return false
	tease_count += 1
	tease_cooldown = TEASE_COOLDOWN
	var direction = Vector2.ZERO
	if velocity.length() > 0.001:
		direction = velocity.normalized()
	else:
		direction = (local_mouse - (pet_rect.position + pet_rect.size * 0.5)).normalized()
	emit_signal("tease_success", tease_count, direction)
	if tease_count >= TEASE_TARGET_COUNT:
		emit_signal("game_finished", "tease")
		clear()
	return true


func _check_food_hit() -> void:
	if food == null:
		return
	if pet_sprite.mouth_rect().has_point(pet_sprite.to_local(food.global_position)):
		emit_signal("feed_success")
		emit_signal("game_finished", "feed")
		clear()


func _make_sprite(relative_path: String, size: int) -> Sprite2D:
	var sprite = Sprite2D.new()
	var texture = _load_texture(relative_path)
	if texture != null:
		sprite.texture = texture
		var texture_size = texture.get_size()
		sprite.scale = Vector2(size / texture_size.x, size / texture_size.y)
	return sprite


func _load_texture(relative_path: String):
	var path = repo_root.path_join("assets").path_join(relative_path)
	if not FileAccess.file_exists(path):
		return null
	var image = Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)
