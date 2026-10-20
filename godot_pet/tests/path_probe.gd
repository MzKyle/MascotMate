extends SceneTree


func _init() -> void:
	var config = preload("res://scripts/ConfigStore.gd").new()
	config.configure()
	if config.app_config()["skin_id"] != "classic_shinchan":
		quit(1)
		return
	var state = preload("res://scripts/StateStore.gd").new()
	var screenshots = preload("res://scripts/ScreenshotPins.gd").new()
	print("DATA_PATHS:" + JSON.stringify({"config": config._config_dir(), "state": state._state_path().get_base_dir(), "screenshots": screenshots._config_dir()}))
	config.free()
	state.free()
	screenshots.free()
	quit()
