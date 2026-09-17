extends Node

signal command_requested(command)

const MENU_WALK := 1
const MENU_FEED := 2
const MENU_SLEEP := 3
const MENU_WAKE := 4
const MENU_TEASE := 5
const MENU_SCALE_100 := 10
const MENU_SCALE_125 := 11
const MENU_SCALE_150 := 12
const MENU_QUIET := 20
const MENU_ACTIVE := 21
const MENU_MISCHIEF := 22
const MENU_TONE_GENTLE := 23
const MENU_TONE_SHORT_CUTE := 24
const MENU_TONE_CALM := 25
const MENU_CLEAR := 30
const MENU_TOGGLE_GRAVITY := 40
const MENU_EXIT_PEEK := 41
const MENU_SCREENSHOT_SETTINGS := 50
const MENU_SKINS := 60
const MENU_COMPANION_CONSOLE := 61
const MENU_HELP := 70
const MENU_EXIT := 99

var popup: PopupMenu
var current_behavior_mode := "安静"
var current_dialogue_tone := "gentle"


func _ready() -> void:
	popup = PopupMenu.new()
	add_child(popup)
	popup.id_pressed.connect(_on_menu_id_pressed)


func show_menu(gravity_enabled: bool, peek_mode: bool, behavior_mode: String, dialogue_tone := "gentle") -> void:
	current_behavior_mode = behavior_mode
	current_dialogue_tone = dialogue_tone
	popup.clear()
	popup.add_item("散步", MENU_WALK)
	popup.add_item("饭团投喂", MENU_FEED)
	popup.add_item("睡觉", MENU_SLEEP)
	popup.add_item("唤醒", MENU_WAKE)
	popup.add_item("逗一逗", MENU_TEASE)
	popup.add_item("怎么玩？", MENU_HELP)
	popup.add_separator()
	popup.add_item("显示大小 100%", MENU_SCALE_100)
	popup.add_item("显示大小 125%", MENU_SCALE_125)
	popup.add_item("显示大小 150%", MENU_SCALE_150)
	popup.add_separator()
	popup.add_item("关闭重力：悬浮" if gravity_enabled else "开启重力：落地", MENU_TOGGLE_GRAVITY)
	if peek_mode:
		popup.add_item("出来", MENU_EXIT_PEEK)
	popup.add_item("皮肤商店", MENU_SKINS)
	popup.add_item("陪伴控制台", MENU_COMPANION_CONSOLE)
	popup.add_item("截图贴图设置", MENU_SCREENSHOT_SETTINGS)
	popup.add_separator()
	popup.add_check_item("安静模式", MENU_QUIET)
	popup.add_check_item("活泼模式", MENU_ACTIVE)
	popup.add_check_item("捣乱模式", MENU_MISCHIEF)
	_sync_behavior_menu_checks()
	popup.add_separator()
	popup.add_check_item("温柔文案", MENU_TONE_GENTLE)
	popup.add_check_item("元气文案", MENU_TONE_SHORT_CUTE)
	popup.add_check_item("安静文案", MENU_TONE_CALM)
	_sync_tone_menu_checks()
	popup.add_item("清理捣乱物", MENU_CLEAR)
	popup.add_separator()
	popup.add_item("退出", MENU_EXIT)
	popup.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i(1, 1)))


func _sync_behavior_menu_checks() -> void:
	var modes = {
		MENU_QUIET: "安静",
		MENU_ACTIVE: "活泼",
		MENU_MISCHIEF: "捣乱",
	}
	for item_id in modes.keys():
		var index = popup.get_item_index(item_id)
		if index >= 0:
			popup.set_item_checked(index, modes[item_id] == current_behavior_mode)


func _sync_tone_menu_checks() -> void:
	var tones = {
		MENU_TONE_GENTLE: "gentle",
		MENU_TONE_SHORT_CUTE: "short_cute",
		MENU_TONE_CALM: "calm",
	}
	for item_id in tones.keys():
		var index = popup.get_item_index(item_id)
		if index >= 0:
			popup.set_item_checked(index, tones[item_id] == current_dialogue_tone)


func _on_menu_id_pressed(id: int) -> void:
	var commands = {
		MENU_WALK: "walk",
		MENU_FEED: "feed",
		MENU_SLEEP: "sleep",
		MENU_WAKE: "wake",
		MENU_TEASE: "tease",
		MENU_SCALE_100: "scale_100",
		MENU_SCALE_125: "scale_125",
		MENU_SCALE_150: "scale_150",
		MENU_TOGGLE_GRAVITY: "toggle_gravity",
		MENU_EXIT_PEEK: "exit_peek",
		MENU_SKINS: "skins",
		MENU_COMPANION_CONSOLE: "companion_console",
		MENU_SCREENSHOT_SETTINGS: "screenshot_settings",
		MENU_QUIET: "mode_quiet",
		MENU_ACTIVE: "mode_active",
		MENU_MISCHIEF: "mode_mischief",
		MENU_TONE_GENTLE: "tone_gentle",
		MENU_TONE_SHORT_CUTE: "tone_short_cute",
		MENU_TONE_CALM: "tone_calm",
		MENU_CLEAR: "clear_mischief",
		MENU_HELP: "help",
		MENU_EXIT: "exit",
	}
	if commands.has(id):
		emit_signal("command_requested", commands[id])
