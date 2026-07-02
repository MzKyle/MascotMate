extends Node2D

signal stop_requested

const MISCHIEF_GRAB_SECONDS := 4.0
const MISCHIEF_STOP_SIZE := Vector2(44, 30)

var pet_sprite
var physics
var animation_resolver
var play_area_source: Callable
var active := false
var elapsed := 0.0
var cursor_local := Vector2.ZERO
var timer: Timer
var stop_button: Button


func _ready() -> void:
	timer = Timer.new()
	timer.one_shot = true
	timer.timeout.connect(func(): emit_signal("stop_requested"))
	add_child(timer)

	stop_button = Button.new()
	stop_button.text = "停"
	stop_button.visible = false
	stop_button.focus_mode = Control.FOCUS_NONE
	stop_button.pressed.connect(func(): emit_signal("stop_requested"))
	add_child(stop_button)


func configure(pet, pet_physics, play_area_callable: Callable, resolver = null) -> void:
	pet_sprite = pet
	physics = pet_physics
	play_area_source = play_area_callable
	animation_resolver = resolver


func start() -> bool:
	active = true
	elapsed = 0.0
	cursor_local = get_viewport().get_mouse_position()
	physics.idle()
	var action_id = "mischief_grab"
	if animation_resolver != null:
		action_id = animation_resolver.resolve("mischief", {"preferred": "mischief_grab"})
	if action_id == "" or not pet_sprite.play(action_id):
		if animation_resolver != null:
			pet_sprite.play(animation_resolver.resolve("resting"))
		else:
			pet_sprite.play("idle")
	stop_button.visible = true
	timer.start(MISCHIEF_GRAB_SECONDS)
	queue_redraw()
	return true


func stop() -> void:
	active = false
	timer.stop()
	stop_button.visible = false
	queue_redraw()


func tick(delta: float, window: Window) -> void:
	if not active:
		return
	elapsed += delta
	var window_size = Vector2(window.size)
	var mouse = Vector2(DisplayServer.mouse_get_position())
	var offset = Vector2(-window_size.x * 0.28, window_size.y * 0.22)
	var shake = Vector2(sin(elapsed * 34.0) * 4.0, cos(elapsed * 29.0) * 3.0)
	physics.position = _clamp_window_position(mouse - window_size * 0.5 + offset + shake, window_size)
	window.position = Vector2i(round(physics.position.x), round(physics.position.y))
	cursor_local = mouse - physics.position
	position_stop_button(window.size)
	queue_redraw()


func apply_pose(window_size: Vector2) -> void:
	if not active:
		return
	var base = window_size * 0.5
	var shake = Vector2(sin(elapsed * 42.0) * 4.5, cos(elapsed * 37.0) * 2.5)
	pet_sprite.position = base + shake
	pet_sprite.sprite.rotation = -0.08 + sin(elapsed * 24.0) * 0.075
	pet_sprite.sprite.scale = pet_sprite._base_sprite_scale() * Vector2(1.04, 0.98)


func position_stop_button(window_size: Vector2i) -> void:
	if stop_button == null:
		return
	var size = Vector2(window_size)
	stop_button.size = MISCHIEF_STOP_SIZE
	stop_button.position = Vector2(size.x - MISCHIEF_STOP_SIZE.x - 12.0, 12.0)


func stop_rect() -> Rect2:
	if stop_button == null:
		return Rect2(Vector2.ZERO, MISCHIEF_STOP_SIZE)
	return Rect2(stop_button.position, stop_button.size)


func _draw() -> void:
	if not active or pet_sprite == null or pet_sprite.sprite == null:
		return
	var hand_a = pet_sprite.position + Vector2(28, -8).rotated(pet_sprite.sprite.rotation)
	var hand_b = pet_sprite.position + Vector2(46, 10).rotated(pet_sprite.sprite.rotation)
	var pull = cursor_local
	var wobble = Vector2(sin(elapsed * 31.0) * 3.0, cos(elapsed * 27.0) * 2.0)
	draw_line(hand_a, pull + wobble, Color(0.98, 0.72, 0.18, 0.92), 3.0)
	draw_line(hand_b, pull - wobble, Color(0.95, 0.42, 0.18, 0.8), 2.0)
	draw_arc(pull, 13.0 + sin(elapsed * 18.0) * 2.0, -0.8, 2.9, 18, Color(0.2, 0.22, 0.25, 0.65), 2.0)
	for i in range(3):
		var phase = elapsed * 4.4 + float(i) * 1.7
		var drop = pet_sprite.position + Vector2(-38 + i * 16, -62 - abs(sin(phase)) * 12)
		draw_circle(drop, 3.5 + float(i) * 0.4, Color(0.35, 0.72, 1.0, 0.82))


func _clamp_window_position(pos: Vector2, window_size: Vector2) -> Vector2:
	var area: Rect2 = play_area_source.call()
	var max_x = area.position.x + area.size.x - window_size.x
	var max_y = area.position.y + area.size.y - window_size.y
	if max_x < area.position.x:
		max_x = area.position.x
	if max_y < area.position.y:
		max_y = area.position.y
	return Vector2(
		clamp(pos.x, area.position.x, max_x),
		clamp(pos.y, area.position.y, max_y)
	)
